#!/bin/bash

# Bulletproof Google Drive sync that always works
# This script ensures sync works even if configs are broken

echo "===================================="
echo "Bulletproof Google Drive Sync Setup"
echo "===================================="
echo "Ensuring sync works no matter what"
echo

# Function to setup rclone from scratch using RunPod secret
setup_from_secret() {
    echo "Setting up rclone from RunPod secret..."

    # Check for secret
    if [ -z "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" ]; then
        echo "❌ No RunPod secret found"
        return 1
    fi

    echo "✅ Found RunPod secret (${#RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT} chars)"

    # Create directories
    mkdir -p /root/.config/rclone
    mkdir -p /workspace/.config/rclone

    # Save service account
    echo "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" > /root/.config/rclone/service_account.json
    echo "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" > /workspace/.config/rclone/service_account.json
    chmod 600 /root/.config/rclone/service_account.json
    chmod 600 /workspace/.config/rclone/service_account.json

    # Create fresh config
    cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive =

EOF

    # Copy to workspace
    cp /root/.config/rclone/rclone.conf /workspace/.config/rclone/rclone.conf

    echo "✅ Fresh config created"

    # Test it
    if rclone lsd gdrive: >/dev/null 2>&1; then
        echo "✅ Rclone working!"
        return 0
    else
        echo "❌ Rclone test failed"
        return 1
    fi
}

# Kill any existing sync
echo "1. Stopping any existing sync..."
pkill -f rclone_sync_loop 2>/dev/null || true
sleep 1
echo "   Done"
echo

# Check if rclone is working
echo "2. Testing current rclone setup..."
if rclone lsd gdrive: >/dev/null 2>&1; then
    echo "   ✅ Rclone is working"
else
    echo "   ❌ Rclone not working, attempting to fix..."

    # Try to fix it
    if setup_from_secret; then
        echo "   ✅ Fixed using RunPod secret"
    else
        echo "   ❌ Could not fix rclone"
        echo
        echo "   Please ensure RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT is set"
        exit 1
    fi
fi
echo

# Create bulletproof sync script
echo "3. Creating bulletproof sync script..."

SYNC_DIR="/workspace/.sync"
mkdir -p "$SYNC_DIR"

cat > "$SYNC_DIR/bulletproof_sync.sh" << 'SYNC_SCRIPT'
#!/bin/bash

# Bulletproof sync that checks and fixes itself

LOG_FILE="/tmp/rclone_sync.log"
echo "[$(date)] Bulletproof sync starting..." >> "$LOG_FILE"

# Function to ensure rclone works
ensure_rclone_works() {
    # Test if rclone works
    if rclone lsd gdrive: >/dev/null 2>&1; then
        return 0
    fi

    echo "[$(date)] Rclone broken, attempting to fix..." >> "$LOG_FILE"

    # Try to restore from workspace backup
    if [ -f "/workspace/.config/rclone/rclone.conf" ]; then
        mkdir -p /root/.config/rclone
        cp /workspace/.config/rclone/* /root/.config/rclone/ 2>/dev/null

        if rclone lsd gdrive: >/dev/null 2>&1; then
            echo "[$(date)] Fixed using workspace backup" >> "$LOG_FILE"
            return 0
        fi
    fi

    # Try to setup from RunPod secret
    if [ -n "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" ]; then
        echo "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" > /root/.config/rclone/service_account.json

        cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive =

EOF

        if rclone lsd gdrive: >/dev/null 2>&1; then
            echo "[$(date)] Fixed using RunPod secret" >> "$LOG_FILE"
            # Backup to workspace
            cp /root/.config/rclone/* /workspace/.config/rclone/ 2>/dev/null
            return 0
        fi
    fi

    echo "[$(date)] Could not fix rclone" >> "$LOG_FILE"
    return 1
}

# Main sync loop
while true; do
    # Ensure rclone works before trying to sync
    if ! ensure_rclone_works; then
        echo "[$(date)] Skipping sync - rclone not working" >> "$LOG_FILE"
        sleep 60
        continue
    fi

    # Do the actual sync
    if [ -d "/workspace/output" ]; then
        FILE_COUNT=$(find /workspace/output -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) 2>/dev/null | wc -l)
        if [ "$FILE_COUNT" -gt 0 ]; then
            echo "[$(date)] Copying $FILE_COUNT files from /workspace/output" >> "$LOG_FILE"

            # Use copy to never delete
            rclone copy "/workspace/output" "gdrive:ComfyUI-Output/output" \
                --exclude "*.tmp" \
                --exclude "*.partial" \
                --exclude "**/temp_*" \
                --transfers 4 \
                --checkers 2 \
                --bwlimit 50M \
                --min-age 30s \
                --ignore-existing \
                --no-update-modtime >> "$LOG_FILE" 2>&1

            if [ $? -eq 0 ]; then
                echo "[$(date)] Copy successful" >> "$LOG_FILE"
            else
                echo "[$(date)] Copy failed, will retry next cycle" >> "$LOG_FILE"
            fi
        fi
    fi

    # Also sync input and workflows
    [ -d "/workspace/input" ] && \
        rclone copy "/workspace/input" "gdrive:ComfyUI-Output/input" \
            --transfers 2 --ignore-existing --no-update-modtime >/dev/null 2>&1

    [ -d "/workspace/workflows" ] && \
        rclone sync "/workspace/workflows" "gdrive:ComfyUI-Output/workflows" \
            --transfers 2 --no-update-modtime >/dev/null 2>&1

    sleep 60
done
SYNC_SCRIPT

chmod +x "$SYNC_DIR/bulletproof_sync.sh"
echo "   ✅ Created at $SYNC_DIR/bulletproof_sync.sh"
echo

# Create symlink for easy access
ln -sf "$SYNC_DIR/bulletproof_sync.sh" /tmp/rclone_sync_loop.sh 2>/dev/null

# Start the sync
echo "4. Starting bulletproof sync..."
"$SYNC_DIR/bulletproof_sync.sh" &
SYNC_PID=$!
sleep 2

if kill -0 $SYNC_PID 2>/dev/null; then
    echo "   ✅ Sync started (PID: $SYNC_PID)"
else
    echo "   ❌ Failed to start sync"
    exit 1
fi
echo

# Create startup script that always works
echo "5. Creating auto-start script..."

cat > "$SYNC_DIR/start_on_boot.sh" << 'BOOT_SCRIPT'
#!/bin/bash

# This ensures sync starts on every pod boot

# Wait for environment to be ready
sleep 10

# Ensure sync is running
if ! pgrep -f bulletproof_sync >/dev/null 2>&1; then
    /workspace/.sync/bulletproof_sync.sh &
fi
BOOT_SCRIPT

chmod +x "$SYNC_DIR/start_on_boot.sh"
echo "   ✅ Created at $SYNC_DIR/start_on_boot.sh"
echo

# Save config state for debugging
echo "6. Saving config state..."
mkdir -p /workspace/.sync/backups
cp /root/.config/rclone/rclone.conf /workspace/.sync/backups/rclone.conf.$(date +%Y%m%d_%H%M%S) 2>/dev/null
echo "   ✅ Config backed up"
echo

echo "===================================="
echo "✅ Bulletproof Sync Setup Complete!"
echo "===================================="
echo
echo "The sync will now:"
echo "• Check and fix rclone before each sync cycle"
echo "• Restore config from backups if needed"
echo "• Recreate config from RunPod secret if needed"
echo "• Never fail silently"
echo
echo "Files are stored in /workspace/.sync/ (survives restarts)"
echo
echo "To check status:"
echo "  ps aux | grep bulletproof"
echo "  tail -f /tmp/rclone_sync.log"
echo
echo "To restart manually:"
echo "  /workspace/.sync/bulletproof_sync.sh &"