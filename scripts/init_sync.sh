#!/bin/bash

# Initialize Google Drive sync with bulletproof persistence
# This runs on every pod start and ensures sync always works

# Check if sync is disabled via environment variable
if [ "$ENABLE_SYNC" = "false" ] && [ -z "$GOOGLE_SERVICE_ACCOUNT" ] && [ -z "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" ]; then
    echo "[SYNC] Sync disabled via ENABLE_SYNC environment variable"
    echo "[SYNC] To enable sync, set GOOGLE_SERVICE_ACCOUNT secret or remove ENABLE_SYNC=false"
    exit 0
fi

echo "[SYNC INIT] Starting Google Drive sync initialization..."

# Function to setup rclone from any available source
setup_rclone_config() {
    # Check rclone version first
    echo "[SYNC INIT] Rclone version: $(rclone version | head -1)"

    # Check if rclone already works
    if rclone lsd gdrive: >/dev/null 2>&1; then
        echo "[SYNC INIT] Rclone already working"
        return 0
    fi

    # Log any existing error
    echo "[SYNC INIT] Testing connection failed with: $(rclone lsd gdrive: 2>&1 | head -5)"

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
            # Auto-detect shared drive
        echo "[SYNC INIT] Detecting shared drives..."
        TEAM_DRIVE_ID=""

        # Create basic config first
        cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive =
EOF

        # Try to detect shared drive
        DRIVES_JSON=$(rclone backend drives gdrive: 2>/dev/null || echo "[]")
        if [ "$DRIVES_JSON" != "[]" ] && [ -n "$DRIVES_JSON" ]; then
            # Extract first shared drive ID
            TEAM_DRIVE_ID=$(echo "$DRIVES_JSON" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
            if [ -n "$TEAM_DRIVE_ID" ]; then
                echo "[SYNC INIT] Found shared drive: $TEAM_DRIVE_ID"
                # Update config with team drive
                sed -i "s/team_drive =$/team_drive = $TEAM_DRIVE_ID/" /root/.config/rclone/rclone.conf
            fi
        fi
        fi

        if rclone lsd gdrive: >/dev/null 2>&1; then
            echo "[SYNC INIT] Successfully restored from workspace backup"
            return 0
        else
            echo "[SYNC INIT] Workspace backup failed: $(rclone lsd gdrive: 2>&1 | head -3)"
        fi
    fi

    # 2. Try GOOGLE_SERVICE_ACCOUNT environment variable (may be set directly or from RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT)
    if [ -n "$GOOGLE_SERVICE_ACCOUNT" ]; then
        echo "[SYNC INIT] Found GOOGLE_SERVICE_ACCOUNT environment variable"
        echo "$GOOGLE_SERVICE_ACCOUNT" > /root/.config/rclone/service_account.json
        chmod 600 /root/.config/rclone/service_account.json

        # Auto-detect shared drive
        echo "[SYNC INIT] Detecting shared drives..."
        TEAM_DRIVE_ID=""

        # Create basic config first
        cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive =
EOF

        # Try to detect shared drive
        DRIVES_JSON=$(rclone backend drives gdrive: 2>/dev/null || echo "[]")
        if [ "$DRIVES_JSON" != "[]" ] && [ -n "$DRIVES_JSON" ]; then
            # Extract first shared drive ID
            TEAM_DRIVE_ID=$(echo "$DRIVES_JSON" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
            if [ -n "$TEAM_DRIVE_ID" ]; then
                echo "[SYNC INIT] Found shared drive: $TEAM_DRIVE_ID"
                # Update config with team drive
                sed -i "s/team_drive =$/team_drive = $TEAM_DRIVE_ID/" /root/.config/rclone/rclone.conf
            fi
        fi

        # Save to workspace for next run
        cp /root/.config/rclone/service_account.json /workspace/.permanent_sync/service_account.json
        cp /root/.config/rclone/rclone.conf /workspace/.permanent_sync/rclone.conf

        if rclone lsd gdrive: >/dev/null 2>&1; then
            echo "[SYNC INIT] Successfully configured from GOOGLE_SERVICE_ACCOUNT"
            return 0
        else
            echo "[SYNC INIT] Service account auth failed: $(rclone lsd gdrive: 2>&1 | head -3)"
        fi
    fi

    # 3. Try OAuth token refresh if available
    if [ -f /workspace/.permanent_sync/oauth_token.json ]; then
        echo "[SYNC INIT] Found OAuth token, checking if refresh needed"

        # Create OAuth config
        cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
token_json = {"access_token":"ACCESS_TOKEN","token_type":"Bearer","refresh_token":"REFRESH_TOKEN","expiry":"EXPIRY"}
client_id = YOUR_CLIENT_ID
client_secret = YOUR_CLIENT_SECRET
EOF

        # Replace with actual token
        TOKEN_JSON=$(cat /workspace/.permanent_sync/oauth_token.json)
        sed -i "s|token_json = .*|token_json = $TOKEN_JSON|" /root/.config/rclone/rclone.conf

        # Try to refresh token
        if rclone lsd gdrive: --refresh >/dev/null 2>&1; then
            echo "[SYNC INIT] OAuth token refreshed successfully"
            # Save refreshed token
            NEW_TOKEN=$(rclone config dump | grep -A1 'token' | tail -1)
            echo "$NEW_TOKEN" > /workspace/.permanent_sync/oauth_token.json
            return 0
        else
            echo "[SYNC INIT] OAuth token refresh failed, will try service account"
        fi
    fi

    # 4. Try RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT
    if [ -n "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" ]; then
        echo "[SYNC INIT] Found RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT"
        echo "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" > /root/.config/rclone/service_account.json

        # Auto-detect shared drive
        echo "[SYNC INIT] Detecting shared drives..."
        TEAM_DRIVE_ID=""

        # Create basic config first
        cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive =
EOF

        # Try to detect shared drive
        DRIVES_JSON=$(rclone backend drives gdrive: 2>/dev/null || echo "[]")
        if [ "$DRIVES_JSON" != "[]" ] && [ -n "$DRIVES_JSON" ]; then
            # Extract first shared drive ID
            TEAM_DRIVE_ID=$(echo "$DRIVES_JSON" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
            if [ -n "$TEAM_DRIVE_ID" ]; then
                echo "[SYNC INIT] Found shared drive: $TEAM_DRIVE_ID"
                # Update config with team drive
                sed -i "s/team_drive =$/team_drive = $TEAM_DRIVE_ID/" /root/.config/rclone/rclone.conf
            fi
        fi

        # Save to workspace for next run
        cp /root/.config/rclone/service_account.json /workspace/.permanent_sync/service_account.json
        cp /root/.config/rclone/rclone.conf /workspace/.permanent_sync/rclone.conf

        if rclone lsd gdrive: >/dev/null 2>&1; then
            echo "[SYNC INIT] Successfully configured from RUNPOD_SECRET"
            return 0
        fi
    fi

    echo "[SYNC INIT] ERROR: No valid credentials found"
    echo "[SYNC INIT] Please provide one of:"
    echo "  - GOOGLE_SERVICE_ACCOUNT or RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT env variable"
    echo "  - Service account JSON file in /workspace/.permanent_sync/service_account.json"
    echo "  - OAuth token in /workspace/.permanent_sync/oauth_token.json"
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
                # Auto-detect shared drive
        echo "[SYNC INIT] Detecting shared drives..."
        TEAM_DRIVE_ID=""

        # Create basic config first
        cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive =
EOF

        # Try to detect shared drive
        DRIVES_JSON=$(rclone backend drives gdrive: 2>/dev/null || echo "[]")
        if [ "$DRIVES_JSON" != "[]" ] && [ -n "$DRIVES_JSON" ]; then
            # Extract first shared drive ID
            TEAM_DRIVE_ID=$(echo "$DRIVES_JSON" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
            if [ -n "$TEAM_DRIVE_ID" ]; then
                echo "[SYNC INIT] Found shared drive: $TEAM_DRIVE_ID"
                # Update config with team drive
                sed -i "s/team_drive =$/team_drive = $TEAM_DRIVE_ID/" /root/.config/rclone/rclone.conf
            fi
        fi
            fi
        fi

        # Test again
        if ! rclone lsd gdrive: >/dev/null 2>&1; then
            echo "[SYNC] Still not working, waiting..."
            sleep 60
            continue
        fi
    fi

    # Perform the sync - sync each user folder separately to avoid mixing files
    if [ -d "/workspace/output" ]; then
        for user_dir in /workspace/output/*/; do
            if [ -d "$user_dir" ]; then
                username=$(basename "$user_dir")
                FILE_COUNT=$(find "$user_dir" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) 2>/dev/null | wc -l)

                if [ "$FILE_COUNT" -gt 0 ]; then
                    echo "[SYNC] Syncing $FILE_COUNT files for user $username..."

                    rclone sync "$user_dir" "gdrive:ComfyUI-Output/output/$username" \
                        --exclude "*.tmp" \
                        --exclude "*.partial" \
                        --min-age 30s \
                        --transfers 8 \
                        --checkers 8 \
                        --tpslimit 10 \
                        --no-update-modtime >> /tmp/rclone_sync.log 2>&1

                    if [ $? -eq 0 ]; then
                        echo "[SYNC] Sync completed successfully for $username"
                    else
                        ERROR_MSG=$(tail -10 /tmp/rclone_sync.log 2>/dev/null | grep -i "error\|fail" | head -3)
                        echo "[SYNC] Sync failed for $username: $ERROR_MSG"
                    fi
                fi
            fi
        done
    fi

    # Also sync input and workflows if they exist - per user
    if [ -d "/workspace/input" ]; then
        for user_dir in /workspace/input/*/; do
            if [ -d "$user_dir" ]; then
                username=$(basename "$user_dir")
                rclone copy "$user_dir" "gdrive:ComfyUI-Output/input/$username" \
                    --transfers 8 --tpslimit 10 --ignore-existing --no-update-modtime >/dev/null 2>&1
            fi
        done
    fi

    if [ -d "/workspace/workflows" ]; then
        for user_dir in /workspace/workflows/*/; do
            if [ -d "$user_dir" ]; then
                username=$(basename "$user_dir")
                rclone copy "$user_dir" "gdrive:ComfyUI-Output/workflows/$username" \
                    --transfers 8 --tpslimit 10 --no-update-modtime >/dev/null 2>&1
            fi
        done
    fi

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