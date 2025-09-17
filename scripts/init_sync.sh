#!/bin/bash

# Initialize Google Drive sync with bulletproof persistence
# This runs on every pod start and ensures sync always works

echo "[SYNC INIT] Starting Google Drive sync initialization..."

# Function to setup rclone from any available source
setup_rclone_config() {
    # Check if rclone already works
    if rclone lsd gdrive: >/dev/null 2>&1; then
        echo "[SYNC INIT] Rclone already working"
        return 0
    fi

    echo "[SYNC INIT] Setting up rclone configuration..."

    # Create necessary directories
    mkdir -p /root/.config/rclone
    mkdir -p /workspace/.permanent_sync

    # Try different sources in order of preference

    # 1. Try workspace backup first (most reliable for second run)
    if [ -f /workspace/.permanent_sync/service_account.json ] || [ -f /workspace/.permanent_sync/runpod_secret.json ]; then
        echo "[SYNC INIT] Found saved credentials in workspace"

        if [ -f /workspace/.permanent_sync/service_account.json ]; then
            cp /workspace/.permanent_sync/service_account.json /root/.config/rclone/service_account.json
        elif [ -f /workspace/.permanent_sync/runpod_secret.json ]; then
            cp /workspace/.permanent_sync/runpod_secret.json /root/.config/rclone/service_account.json
        fi

        if [ -f /workspace/.permanent_sync/rclone.conf ]; then
            cp /workspace/.permanent_sync/rclone.conf /root/.config/rclone/rclone.conf
        else
            cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive =
EOF
        fi

        if rclone lsd gdrive: >/dev/null 2>&1; then
            echo "[SYNC INIT] Successfully restored from workspace backup"
            return 0
        fi
    fi

    # 2. Try GOOGLE_SERVICE_ACCOUNT environment variable (may be set directly or from RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT)
    if [ -n "$GOOGLE_SERVICE_ACCOUNT" ]; then
        echo "[SYNC INIT] Found GOOGLE_SERVICE_ACCOUNT environment variable"
        echo "$GOOGLE_SERVICE_ACCOUNT" > /root/.config/rclone/service_account.json
        chmod 600 /root/.config/rclone/service_account.json

        cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive =
EOF

        # Save to workspace for next run
        cp /root/.config/rclone/service_account.json /workspace/.permanent_sync/service_account.json
        cp /root/.config/rclone/rclone.conf /workspace/.permanent_sync/rclone.conf

        if rclone lsd gdrive: >/dev/null 2>&1; then
            echo "[SYNC INIT] Successfully configured from GOOGLE_SERVICE_ACCOUNT"
            return 0
        fi
    fi

    # 3. Try RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT
    if [ -n "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" ]; then
        echo "[SYNC INIT] Found RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT"
        echo "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" > /root/.config/rclone/service_account.json

        cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive =
EOF

        # Save to workspace for next run
        cp /root/.config/rclone/service_account.json /workspace/.permanent_sync/service_account.json
        cp /root/.config/rclone/rclone.conf /workspace/.permanent_sync/rclone.conf

        if rclone lsd gdrive: >/dev/null 2>&1; then
            echo "[SYNC INIT] Successfully configured from RUNPOD_SECRET"
            return 0
        fi
    fi

    echo "[SYNC INIT] ERROR: No valid credentials found"
    return 1
}

# Function to start the sync loop
start_sync_loop() {
    # Kill any existing sync processes
    pkill -f "rclone_sync_loop|permanent_sync" 2>/dev/null || true
    sleep 1

    # Create the sync script in workspace
    cat > /workspace/.permanent_sync/sync_loop.sh << 'SYNC_SCRIPT'
#!/bin/bash

echo "[SYNC] Starting permanent sync loop..."

while true; do
    # Ensure rclone is configured (in case it gets lost)
    if ! rclone lsd gdrive: >/dev/null 2>&1; then
        echo "[SYNC] Rclone not working, attempting to restore..."

        # Try to restore from workspace backup
        if [ -f /workspace/.permanent_sync/service_account.json ]; then
            mkdir -p /root/.config/rclone
            cp /workspace/.permanent_sync/service_account.json /root/.config/rclone/service_account.json
            cp /workspace/.permanent_sync/rclone.conf /root/.config/rclone/rclone.conf 2>/dev/null

            # Create config if missing
            if [ ! -f /root/.config/rclone/rclone.conf ]; then
                cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive =
EOF
            fi
        fi

        # Test again
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
            echo "[SYNC] Syncing $FILE_COUNT files to Google Drive..."

            rclone copy "/workspace/output" "gdrive:ComfyUI-Output/output" \
                --exclude "*.tmp" \
                --exclude "*.partial" \
                --min-age 30s \
                --ignore-existing \
                --transfers 2 \
                --checkers 2 \
                --no-update-modtime >> /tmp/rclone_sync.log 2>&1

            if [ $? -eq 0 ]; then
                echo "[SYNC] Sync completed successfully"
            else
                echo "[SYNC] Sync had errors (see /tmp/rclone_sync.log)"
            fi
        fi
    fi

    # Also sync input and workflows if they exist
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

    # Start the sync loop
    echo "[SYNC INIT] Starting sync loop..."
    /workspace/.permanent_sync/sync_loop.sh &
    SYNC_PID=$!

    sleep 2
    if kill -0 $SYNC_PID 2>/dev/null; then
        echo "[SYNC INIT] Sync loop started successfully (PID: $SYNC_PID)"
        echo $SYNC_PID > /workspace/.permanent_sync/sync.pid
        return 0
    else
        echo "[SYNC INIT] Failed to start sync loop"
        return 1
    fi
}

# Main execution
echo "[SYNC INIT] Checking Google Drive sync status..."

# Setup rclone configuration
if setup_rclone_config; then
    echo "[SYNC INIT] Rclone configured successfully"

    # Start the sync loop
    if start_sync_loop; then
        echo "[SYNC INIT] Google Drive sync initialized successfully"
        echo "INITIALIZED" > /workspace/.permanent_sync/status
    else
        echo "[SYNC INIT] Failed to start sync loop"
        echo "FAILED" > /workspace/.permanent_sync/status
        exit 1
    fi
else
    echo "[SYNC INIT] Failed to configure rclone"
    echo "NO_CREDENTIALS" > /workspace/.permanent_sync/status
    exit 1
fi

echo "[SYNC INIT] Initialization complete"