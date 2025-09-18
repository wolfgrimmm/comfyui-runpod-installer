#!/bin/bash

# Quick fix for Google Drive sync on second run
# This directly addresses the issue where GOOGLE_SERVICE_ACCOUNT exists but sync fails

echo "==========================================="
echo "QUICK FIX FOR GOOGLE DRIVE SYNC"
echo "==========================================="
echo

# 1. Setup rclone properly from GOOGLE_SERVICE_ACCOUNT
if [ -n "$GOOGLE_SERVICE_ACCOUNT" ]; then
    echo "✅ Found GOOGLE_SERVICE_ACCOUNT in environment"

    # Create all necessary directories
    mkdir -p /root/.config/rclone
    mkdir -p /workspace/.permanent_sync

    # Save the service account JSON
    echo "$GOOGLE_SERVICE_ACCOUNT" > /root/.config/rclone/service_account.json
    echo "$GOOGLE_SERVICE_ACCOUNT" > /workspace/.permanent_sync/service_account.json
    chmod 600 /root/.config/rclone/service_account.json
    chmod 600 /workspace/.permanent_sync/service_account.json

    # Create rclone config
    cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive =
EOF

    # Auto-detect and add shared drive
    echo "Detecting shared drives..."
    DRIVES_JSON=$(rclone backend drives gdrive: 2>/dev/null || echo "[]")
    if [ "$DRIVES_JSON" != "[]" ] && [ -n "$DRIVES_JSON" ]; then
        TEAM_DRIVE_ID=$(echo "$DRIVES_JSON" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
        if [ -n "$TEAM_DRIVE_ID" ]; then
            echo "✅ Found shared drive: $TEAM_DRIVE_ID"
            sed -i "s/team_drive =$/team_drive = $TEAM_DRIVE_ID/" /root/.config/rclone/rclone.conf
        else
            echo "⚠️ No shared drive ID found in response"
        fi
    else
        echo "⚠️ No shared drives detected - service account may not have access"
        echo "   Make sure to add the service account to your shared drive with Content Manager permission"
    fi

    # Save config to workspace for next run
    cp /root/.config/rclone/rclone.conf /workspace/.permanent_sync/rclone.conf

    echo "✅ Rclone configured"
else
    echo "❌ No GOOGLE_SERVICE_ACCOUNT found"
    exit 1
fi

# 2. Test rclone
echo
echo "Testing rclone connection..."
if rclone lsd gdrive: 2>/dev/null | head -2; then
    echo "✅ Rclone working!"
else
    echo "❌ Rclone test failed"
    exit 1
fi

# 3. Kill any existing sync processes
echo
echo "Stopping existing sync processes..."
pkill -f "auto_sync_gdrive|emergency_sync|rclone_sync" 2>/dev/null || true
sleep 2

# 4. Start new sync
echo
echo "Starting new sync process..."

cat > /workspace/.permanent_sync/sync.sh << 'SYNC'
#!/bin/bash

echo "[SYNC] Starting permanent sync..."

while true; do
    # Ensure rclone still works
    if ! rclone lsd gdrive: >/dev/null 2>&1; then
        # Try to restore
        if [ -f /workspace/.permanent_sync/service_account.json ]; then
            mkdir -p /root/.config/rclone
            cp /workspace/.permanent_sync/service_account.json /root/.config/rclone/
            cp /workspace/.permanent_sync/rclone.conf /root/.config/rclone/ 2>/dev/null
        fi
    fi

    # Sync files
    if [ -d "/workspace/output" ]; then
        FILE_COUNT=$(find /workspace/output -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) 2>/dev/null | wc -l)
        if [ "$FILE_COUNT" -gt 0 ]; then
            echo "[$(date)] Syncing $FILE_COUNT files"

            rclone copy /workspace/output gdrive:ComfyUI-Output/output \
                --exclude "*.tmp" \
                --exclude "*.partial" \
                --min-age 30s \
                --ignore-existing \
                --transfers 2 \
                --no-update-modtime >> /tmp/sync.log 2>&1
        fi
    fi

    sleep 60
done
SYNC

chmod +x /workspace/.permanent_sync/sync.sh
nohup /workspace/.permanent_sync/sync.sh > /tmp/sync.log 2>&1 &
SYNC_PID=$!

sleep 2
if kill -0 $SYNC_PID 2>/dev/null; then
    echo "✅ Sync started (PID: $SYNC_PID)"
else
    echo "❌ Failed to start sync"
fi

echo
echo "==========================================="
echo "QUICK FIX COMPLETE"
echo "==========================================="
echo
echo "Files saved to /workspace/.permanent_sync/:"
ls -la /workspace/.permanent_sync/
echo
echo "To verify sync is working:"
echo "  ps aux | grep sync"
echo "  tail -f /tmp/sync.log"
echo
echo "This fix will survive pod restarts!"