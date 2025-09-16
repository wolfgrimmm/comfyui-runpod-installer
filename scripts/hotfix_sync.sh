#!/bin/bash

echo "===================================="
echo "Google Drive Sync Hotfix"
echo "===================================="
echo "Fixing sync to use COPY instead of SYNC (prevents deletion)"
echo

# Kill existing sync process
echo "1. Stopping current sync process..."
pkill -f "rclone_sync_loop" 2>/dev/null || true
sleep 2
echo "   ✅ Stopped"
echo

# Create new sync script with COPY for outputs
echo "2. Creating fixed sync script..."

cat > /tmp/rclone_sync_loop.sh << 'SYNC_SCRIPT'
#!/bin/bash

echo "[$(date)] Google Drive sync started (COPY mode - no deletions)" >> /tmp/rclone_sync.log

while true; do
    sleep 60  # Sync every minute
    echo "[$(date)] Starting sync cycle..." >> /tmp/rclone_sync.log

    # COPY output files (never delete from Drive!)
    if [ -d "/workspace/output" ]; then
        FILE_COUNT=$(find /workspace/output -type f -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.webp" 2>/dev/null | wc -l)
        if [ "$FILE_COUNT" -gt 0 ]; then
            echo "  Copying $FILE_COUNT images from /workspace/output" >> /tmp/rclone_sync.log

            # Use COPY with --ignore-existing to skip files already in Drive
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

            echo "  Copy completed at $(date)" >> /tmp/rclone_sync.log
        fi
    fi

    # COPY input files (also no deletion)
    if [ -d "/workspace/input" ]; then
        INPUT_COUNT=$(find /workspace/input -type f 2>/dev/null | wc -l)
        if [ "$INPUT_COUNT" -gt 0 ]; then
            echo "  Copying $INPUT_COUNT input files" >> /tmp/rclone_sync.log
            rclone copy "/workspace/input" "gdrive:ComfyUI-Output/input" \
                --transfers 4 \
                --checkers 2 \
                --bwlimit 50M \
                --ignore-existing \
                --no-update-modtime >> /tmp/rclone_sync.log 2>&1
        fi
    fi

    # SYNC workflows (OK to sync since we want Drive to match local)
    if [ -d "/workspace/workflows" ]; then
        echo "  Syncing workflows" >> /tmp/rclone_sync.log
        rclone sync "/workspace/workflows" "gdrive:ComfyUI-Output/workflows" \
            --transfers 4 \
            --checkers 2 \
            --bwlimit 50M \
            --no-update-modtime >> /tmp/rclone_sync.log 2>&1
    fi

    # COPY loras (also no deletion)
    if [ -d "/workspace/models/loras" ]; then
        LORA_COUNT=$(find /workspace/models/loras -type f -name "*.safetensors" 2>/dev/null | wc -l)
        if [ "$LORA_COUNT" -gt 0 ]; then
            echo "  Copying $LORA_COUNT LoRA files" >> /tmp/rclone_sync.log
            rclone copy "/workspace/models/loras" "gdrive:ComfyUI-Output/loras" \
                --transfers 4 \
                --checkers 2 \
                --bwlimit 50M \
                --ignore-existing \
                --no-update-modtime >> /tmp/rclone_sync.log 2>&1
        fi
    fi

    echo "  Sync cycle completed" >> /tmp/rclone_sync.log
done
SYNC_SCRIPT

chmod +x /tmp/rclone_sync_loop.sh
echo "   ✅ Created fixed sync script"
echo

# Start new sync process
echo "3. Starting fixed sync process..."
/tmp/rclone_sync_loop.sh &
SYNC_PID=$!
sleep 2

if kill -0 $SYNC_PID 2>/dev/null; then
    echo "   ✅ Sync started (PID: $SYNC_PID)"
else
    echo "   ❌ Failed to start sync"
    exit 1
fi
echo

# Clear the log and add marker
echo "4. Resetting sync log..."
echo "==== SYNC RESTARTED WITH COPY MODE $(date) ====" > /tmp/rclone_sync.log
echo "   ✅ Log reset"
echo

echo "===================================="
echo "✅ Hotfix Applied!"
echo "===================================="
echo
echo "Changes:"
echo "• Output files: Now using 'rclone copy' (won't delete from Drive)"
echo "• Input files: Now using 'rclone copy' (won't delete from Drive)"
echo "• Workflows: Still using 'rclone sync' (Drive matches local)"
echo "• LoRAs: Now using 'rclone copy' (won't delete from Drive)"
echo
echo "Key differences:"
echo "• COPY: Only adds new files, never deletes"
echo "• SYNC: Makes destination match source exactly (can delete)"
echo
echo "Files wait 30 seconds before uploading (ensures they're complete)"
echo "Already uploaded files are skipped (--ignore-existing)"
echo
echo "Monitor with: tail -f /tmp/rclone_sync.log"