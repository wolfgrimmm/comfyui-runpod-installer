#!/bin/bash

# Ensure Google Drive sync is always running
# This script can be called on every pod start to guarantee sync works

echo "[ENSURE SYNC] Checking Google Drive sync status..."

# Function to check if sync is running
is_sync_running() {
    pgrep -f "sync_loop\|permanent_sync\|rclone_sync" > /dev/null 2>&1
}

# Function to check if rclone works
is_rclone_working() {
    rclone lsd gdrive: >/dev/null 2>&1
}

# Check if sync is already running
if is_sync_running; then
    echo "[ENSURE SYNC] Sync process already running"

    # But verify rclone is actually working
    if is_rclone_working; then
        echo "[ENSURE SYNC] ✅ Everything is working!"
        exit 0
    else
        echo "[ENSURE SYNC] ⚠️ Sync running but rclone not working, fixing..."
        pkill -f "sync_loop\|permanent_sync\|rclone_sync"
        sleep 2
    fi
else
    echo "[ENSURE SYNC] No sync process found"
fi

# Try different methods to get sync working

# Method 1: Check for saved credentials in permanent sync
if [ -f "/workspace/.permanent_sync/service_account.json" ] || [ -f "/workspace/.permanent_sync/runpod_secret.json" ]; then
    echo "[ENSURE SYNC] Found saved credentials, restoring..."

    mkdir -p /root/.config/rclone

    if [ -f "/workspace/.permanent_sync/service_account.json" ]; then
        cp /workspace/.permanent_sync/service_account.json /root/.config/rclone/service_account.json
    elif [ -f "/workspace/.permanent_sync/runpod_secret.json" ]; then
        cp /workspace/.permanent_sync/runpod_secret.json /root/.config/rclone/service_account.json
    fi

    if [ -f "/workspace/.permanent_sync/rclone.conf" ]; then
        cp /workspace/.permanent_sync/rclone.conf /root/.config/rclone/rclone.conf
    fi

    if is_rclone_working; then
        echo "[ENSURE SYNC] ✅ Restored from permanent backup"
    fi
fi

# Method 2: Use environment variables
if ! is_rclone_working && [ -n "$GOOGLE_SERVICE_ACCOUNT" ]; then
    echo "[ENSURE SYNC] Setting up from GOOGLE_SERVICE_ACCOUNT environment..."

    mkdir -p /root/.config/rclone
    echo "$GOOGLE_SERVICE_ACCOUNT" > /root/.config/rclone/service_account.json
    chmod 600 /root/.config/rclone/service_account.json

    # Create initial config without team_drive to enable auto-detection
    cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive =

EOF

    # Auto-detect shared drive (this runs every time)
    echo "[ENSURE SYNC] Auto-detecting Shared Drive..."
    DRIVES_JSON=$(rclone backend drives gdrive: 2>/dev/null || echo "[]")
    if [ "$DRIVES_JSON" != "[]" ] && [ -n "$DRIVES_JSON" ]; then
        TEAM_DRIVE_ID=$(echo "$DRIVES_JSON" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
        if [ -n "$TEAM_DRIVE_ID" ]; then
            echo "[ENSURE SYNC] Found Shared Drive: $TEAM_DRIVE_ID"
            sed -i "s/team_drive =$/team_drive = $TEAM_DRIVE_ID/" /root/.config/rclone/rclone.conf
        else
            echo "[ENSURE SYNC] Warning: Could not extract Shared Drive ID"
        fi
    else
        echo "[ENSURE SYNC] Warning: No Shared Drives found"
    fi

    # Save for next time
    mkdir -p /workspace/.permanent_sync
    cp /root/.config/rclone/service_account.json /workspace/.permanent_sync/
    cp /root/.config/rclone/rclone.conf /workspace/.permanent_sync/
fi

# Method 3: Check for RunPod secret
if ! is_rclone_working && [ -n "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" ]; then
    echo "[ENSURE SYNC] Setting up from RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT..."

    mkdir -p /root/.config/rclone
    echo "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" > /root/.config/rclone/service_account.json
    chmod 600 /root/.config/rclone/service_account.json

    # Create initial config without team_drive to enable auto-detection
    cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive =

EOF

    # Auto-detect shared drive (this runs every time)
    echo "[ENSURE SYNC] Auto-detecting Shared Drive..."
    DRIVES_JSON=$(rclone backend drives gdrive: 2>/dev/null || echo "[]")
    if [ "$DRIVES_JSON" != "[]" ] && [ -n "$DRIVES_JSON" ]; then
        TEAM_DRIVE_ID=$(echo "$DRIVES_JSON" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
        if [ -n "$TEAM_DRIVE_ID" ]; then
            echo "[ENSURE SYNC] Found Shared Drive: $TEAM_DRIVE_ID"
            sed -i "s/team_drive =$/team_drive = $TEAM_DRIVE_ID/" /root/.config/rclone/rclone.conf
        else
            echo "[ENSURE SYNC] Warning: Could not extract Shared Drive ID"
        fi
    else
        echo "[ENSURE SYNC] Warning: No Shared Drives found"
    fi

    # Save for next time
    mkdir -p /workspace/.permanent_sync
    cp /root/.config/rclone/service_account.json /workspace/.permanent_sync/
    cp /root/.config/rclone/rclone.conf /workspace/.permanent_sync/
fi

# Final check
if ! is_rclone_working; then
    echo "[ENSURE SYNC] ❌ Could not setup rclone - no credentials available"
    exit 1
fi

# Start the sync loop
if ! is_sync_running; then
    echo "[ENSURE SYNC] Starting sync loop..."

    # Create the sync script if it doesn't exist
    if [ ! -f "/workspace/.permanent_sync/sync_loop.sh" ]; then
        echo "[ENSURE SYNC] Creating sync_loop.sh..."
        mkdir -p /workspace/.permanent_sync

        cat > /workspace/.permanent_sync/sync_loop.sh << 'SYNC_SCRIPT'
#!/bin/bash

echo "[SYNC] Starting permanent sync loop..."

while true; do
    # Ensure rclone is configured
    if ! rclone lsd gdrive: >/dev/null 2>&1; then
        echo "[SYNC] Rclone not working, attempting to restore..."

        if [ -f /workspace/.permanent_sync/service_account.json ]; then
            mkdir -p /root/.config/rclone
            cp /workspace/.permanent_sync/service_account.json /root/.config/rclone/service_account.json
            cp /workspace/.permanent_sync/rclone.conf /root/.config/rclone/rclone.conf 2>/dev/null || true
        fi

        if ! rclone lsd gdrive: >/dev/null 2>&1; then
            echo "[SYNC] Still not working, waiting..."
            sleep 60
            continue
        fi
    fi

    # Perform the sync
    if [ -d "/workspace/output" ]; then
        FILE_COUNT=$(find /workspace/output -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) 2>/dev/null | wc -l)
        if [ "$FILE_COUNT" -gt 0 ]; then
            rclone sync "/workspace/output" "gdrive:ComfyUI-Output/output" \
                --exclude "*.tmp" --exclude "*.partial" \
                --min-age 30s \
                --transfers 2 --checkers 2 \
                --no-update-modtime >> /tmp/rclone_sync.log 2>&1
        fi
    fi

    # Sync input and workflows
    [ -d "/workspace/input" ] && \
        rclone copy "/workspace/input" "gdrive:ComfyUI-Output/input" \
            --transfers 2 --ignore-existing --no-update-modtime >/dev/null 2>&1

    [ -d "/workspace/workflows" ] && \
        rclone copy "/workspace/workflows" "gdrive:ComfyUI-Output/workflows" \
            --transfers 2 --no-update-modtime >/dev/null 2>&1

    sleep 60
done
SYNC_SCRIPT
        chmod +x /workspace/.permanent_sync/sync_loop.sh
    fi

    # Start the sync loop
    /workspace/.permanent_sync/sync_loop.sh > /tmp/sync.log 2>&1 &
    SYNC_PID=$!
    sleep 2

    if kill -0 $SYNC_PID 2>/dev/null; then
        echo "[ENSURE SYNC] ✅ Sync started (PID: $SYNC_PID)"
        echo $SYNC_PID > /workspace/.permanent_sync/sync.pid
    else
        echo "[ENSURE SYNC] ❌ Failed to start sync"
        exit 1
    fi
fi

echo "[ENSURE SYNC] ✅ Google Drive sync is running and working!"