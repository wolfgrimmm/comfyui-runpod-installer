#!/bin/bash

# This script ensures Google Drive sync is always running
# Should be called on pod start and periodically

echo "[$(date)] Ensuring Google Drive sync is running..."

# Check if sync is already running
if pgrep -f "rclone_sync_loop" >/dev/null 2>&1; then
    echo "✅ Sync already running"
    exit 0
fi

echo "⚠️ Sync not running, attempting to start..."

# Check if rclone config exists
if [ ! -f "/root/.config/rclone/rclone.conf" ]; then
    echo "Restoring rclone config from workspace..."
    if [ -f "/workspace/.config/rclone/rclone.conf" ]; then
        mkdir -p /root/.config/rclone
        cp /workspace/.config/rclone/rclone.conf /root/.config/rclone/
        if [ -f "/workspace/.config/rclone/service_account.json" ]; then
            cp /workspace/.config/rclone/service_account.json /root/.config/rclone/
        fi
        echo "✅ Config restored"
    else
        echo "❌ No rclone config found. Google Drive not configured."
        exit 1
    fi
fi

# Test rclone connection
if ! rclone lsd gdrive: >/dev/null 2>&1; then
    echo "❌ Cannot connect to Google Drive"
    exit 1
fi

# Create sync script in persistent location
SYNC_SCRIPT="/workspace/.sync/rclone_sync_loop.sh"
mkdir -p /workspace/.sync

cat > "$SYNC_SCRIPT" << 'EOF'
#!/bin/bash

echo "[$(date)] Google Drive sync started (persistent version)" >> /tmp/rclone_sync.log

while true; do
    sleep 60  # Sync every minute

    # COPY output files (never delete from Drive!)
    if [ -d "/workspace/output" ]; then
        FILE_COUNT=$(find /workspace/output -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.webp" \) 2>/dev/null | wc -l)
        if [ "$FILE_COUNT" -gt 0 ]; then
            echo "[$(date)] Copying $FILE_COUNT images from /workspace/output" >> /tmp/rclone_sync.log

            rclone copy "/workspace/output" "gdrive:ComfyUI-Output/output" \
                --exclude "*.tmp" \
                --exclude "*.partial" \
                --exclude "**/temp_*" \
                --exclude "**/.DS_Store" \
                --transfers 4 \
                --checkers 2 \
                --bwlimit 50M \
                --min-age 30s \
                --ignore-existing \
                --no-update-modtime >> /tmp/rclone_sync.log 2>&1
        fi
    fi

    # COPY input files
    if [ -d "/workspace/input" ]; then
        rclone copy "/workspace/input" "gdrive:ComfyUI-Output/input" \
            --transfers 4 \
            --checkers 2 \
            --bwlimit 50M \
            --ignore-existing \
            --no-update-modtime >> /tmp/rclone_sync.log 2>&1
    fi

    # SYNC workflows (OK to sync)
    if [ -d "/workspace/workflows" ]; then
        rclone sync "/workspace/workflows" "gdrive:ComfyUI-Output/workflows" \
            --transfers 4 \
            --checkers 2 \
            --bwlimit 50M \
            --no-update-modtime >> /tmp/rclone_sync.log 2>&1
    fi

    # COPY loras
    if [ -d "/workspace/models/loras" ]; then
        rclone copy "/workspace/models/loras" "gdrive:ComfyUI-Output/loras" \
            --transfers 4 \
            --checkers 2 \
            --bwlimit 50M \
            --ignore-existing \
            --no-update-modtime >> /tmp/rclone_sync.log 2>&1
    fi
done
EOF

chmod +x "$SYNC_SCRIPT"

# Also create copy in /tmp for immediate use
cp "$SYNC_SCRIPT" /tmp/rclone_sync_loop.sh
chmod +x /tmp/rclone_sync_loop.sh

# Start the sync
"$SYNC_SCRIPT" &
SYNC_PID=$!

sleep 2

if kill -0 $SYNC_PID 2>/dev/null; then
    echo "✅ Sync started successfully (PID: $SYNC_PID)"
    echo "Sync script saved to: $SYNC_SCRIPT"
    echo "Log file: /tmp/rclone_sync.log"
else
    echo "❌ Failed to start sync"
    exit 1
fi