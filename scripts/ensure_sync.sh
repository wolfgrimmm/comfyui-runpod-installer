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

    cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive =
root_folder_id = 0ABFT2ECfnjL3Uk9PVA
EOF

    # Auto-detect shared drive
    DRIVES_JSON=$(rclone backend drives gdrive: 2>/dev/null || echo "[]")
    if [ "$DRIVES_JSON" != "[]" ] && [ -n "$DRIVES_JSON" ]; then
        TEAM_DRIVE_ID=$(echo "$DRIVES_JSON" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
        if [ -n "$TEAM_DRIVE_ID" ]; then
            echo "[ENSURE SYNC] Found shared drive: $TEAM_DRIVE_ID"
            sed -i "s/team_drive =$/team_drive = $TEAM_DRIVE_ID/" /root/.config/rclone/rclone.conf
        fi
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

    cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive =
root_folder_id = 0ABFT2ECfnjL3Uk9PVA
EOF

    # Auto-detect shared drive
    DRIVES_JSON=$(rclone backend drives gdrive: 2>/dev/null || echo "[]")
    if [ "$DRIVES_JSON" != "[]" ] && [ -n "$DRIVES_JSON" ]; then
        TEAM_DRIVE_ID=$(echo "$DRIVES_JSON" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
        if [ -n "$TEAM_DRIVE_ID" ]; then
            echo "[ENSURE SYNC] Found shared drive: $TEAM_DRIVE_ID"
            sed -i "s/team_drive =$/team_drive = $TEAM_DRIVE_ID/" /root/.config/rclone/rclone.conf
        fi
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

    # Use the permanent sync script if it exists
    if [ -f "/workspace/.permanent_sync/sync_loop.sh" ]; then
        /workspace/.permanent_sync/sync_loop.sh > /tmp/sync.log 2>&1 &
    else
        # Create a simple sync loop
        cat > /tmp/emergency_sync.sh << 'SYNC'
#!/bin/bash
while true; do
    sleep 60
    if [ -d /workspace/output ]; then
        for user_dir in /workspace/output/*/; do
            if [ -d "$user_dir" ]; then
                username=$(basename "$user_dir")
                rclone copy "$user_dir" "gdrive:ComfyUI-Output/output/$username" \
                    --exclude "*.tmp" --exclude "*.partial" \
                    --min-age 30s --transfers 2 2>&1
            fi
        done
    fi
done
SYNC
        chmod +x /tmp/emergency_sync.sh
        /tmp/emergency_sync.sh > /tmp/sync.log 2>&1 &
    fi

    SYNC_PID=$!
    sleep 2

    if kill -0 $SYNC_PID 2>/dev/null; then
        echo "[ENSURE SYNC] ✅ Sync started (PID: $SYNC_PID)"
    else
        echo "[ENSURE SYNC] ❌ Failed to start sync"
        exit 1
    fi
fi

echo "[ENSURE SYNC] ✅ Google Drive sync is running and working!"