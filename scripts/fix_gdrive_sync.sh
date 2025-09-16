#!/bin/bash

echo "===================================="
echo "Google Drive Sync Fix Tool"
echo "===================================="
echo "This script fixes common sync issues, especially after installing custom nodes"
echo

# Step 1: Stop existing sync process
echo "1. Stopping existing sync process..."
pkill -f "rclone_sync_loop" 2>/dev/null || true
echo "   ✅ Stopped"
echo

# Step 2: Fix output directory structure
echo "2. Fixing output directory structure..."

# Check if ComfyUI/output is a real directory (created by custom nodes)
if [ -d "/workspace/ComfyUI/output" ] && [ ! -L "/workspace/ComfyUI/output" ]; then
    echo "   Found real output directory in ComfyUI folder"

    # Move any files to workspace/output
    if [ "$(ls -A /workspace/ComfyUI/output 2>/dev/null)" ]; then
        echo "   Moving existing files to /workspace/output..."
        mkdir -p /workspace/output
        # Move files preserving user structure
        for item in /workspace/ComfyUI/output/*; do
            if [ -e "$item" ]; then
                basename_item=$(basename "$item")
                if [ -d "$item" ]; then
                    # It's a user directory
                    echo "     Moving user folder: $basename_item"
                    mkdir -p "/workspace/output/$basename_item"
                    mv "$item"/* "/workspace/output/$basename_item/" 2>/dev/null || true
                else
                    # It's a file in root
                    echo "     Moving file: $basename_item"
                    mv "$item" "/workspace/output/" 2>/dev/null || true
                fi
            fi
        done
    fi

    # Remove the real directory
    rm -rf /workspace/ComfyUI/output
    echo "   ✅ Removed real directory"
fi

# Create proper symlink
if [ ! -e "/workspace/ComfyUI/output" ]; then
    ln -sf /workspace/output /workspace/ComfyUI/output
    echo "   ✅ Created symlink: /workspace/ComfyUI/output → /workspace/output"
elif [ -L "/workspace/ComfyUI/output" ]; then
    echo "   ✅ Symlink already correct"
fi
echo

# Step 3: Verify rclone configuration
echo "3. Verifying rclone configuration..."

# Check if config exists
if [ ! -f "/root/.config/rclone/rclone.conf" ]; then
    if [ -f "/workspace/.config/rclone/rclone.conf" ]; then
        echo "   Restoring config from workspace backup..."
        mkdir -p /root/.config/rclone
        cp /workspace/.config/rclone/rclone.conf /root/.config/rclone/
        if [ -f "/workspace/.config/rclone/service_account.json" ]; then
            cp /workspace/.config/rclone/service_account.json /root/.config/rclone/
        fi
        echo "   ✅ Config restored"
    else
        echo "   ❌ No rclone config found. Please run /app/init.sh first"
        exit 1
    fi
else
    echo "   ✅ Rclone config exists"
fi

# Test connection
if rclone lsd gdrive: >/dev/null 2>&1; then
    echo "   ✅ Google Drive connection working"
else
    echo "   ❌ Cannot connect to Google Drive"
    echo "   Please check your RunPod secret configuration"
    exit 1
fi
echo

# Step 4: Create improved sync script
echo "4. Creating improved sync script..."

cat > /tmp/rclone_sync_loop.sh << 'SYNC_SCRIPT'
#!/bin/bash

echo "[$(date)] Google Drive sync started (symlink-aware version)" >> /tmp/rclone_sync.log

# Function to resolve directory path (follows symlinks)
resolve_dir() {
    local path="$1"
    if [ -L "$path" ]; then
        # It's a symlink, follow it
        readlink -f "$path"
    elif [ -d "$path" ]; then
        # It's a real directory
        echo "$path"
    else
        # Doesn't exist
        echo ""
    fi
}

while true; do
    sleep 60  # Sync every minute
    echo "[$(date)] Starting sync cycle..." >> /tmp/rclone_sync.log

    # Sync OUTPUT directory - ALWAYS use /workspace/output (the real location)
    OUTPUT_DIR="/workspace/output"

    if [ -d "$OUTPUT_DIR" ]; then
        echo "  Copying output from: $OUTPUT_DIR" >> /tmp/rclone_sync.log

        # Count files to sync
        FILE_COUNT=$(find "$OUTPUT_DIR" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) 2>/dev/null | wc -l)
        [ "$FILE_COUNT" -gt 0 ] && echo "  Found $FILE_COUNT image files" >> /tmp/rclone_sync.log

        # Use COPY not SYNC - never delete from Drive!
        rclone copy "$OUTPUT_DIR" "gdrive:ComfyUI-Output/output" \
            --exclude "*.tmp" \
            --exclude "*.partial" \
            --exclude "**/temp_*" \
            --transfers 4 \
            --checkers 2 \
            --bwlimit 50M \
            --min-age 30s \
            --no-update-modtime \
            --ignore-existing \
            --log-level ERROR >> /tmp/rclone_sync.log 2>&1

        [ "$FILE_COUNT" -gt 0 ] && echo "  Output copy completed" >> /tmp/rclone_sync.log
    else
        echo "  Warning: No output directory found" >> /tmp/rclone_sync.log
    fi

    # Sync INPUT directory - ALWAYS use /workspace/input (the real location)
    INPUT_DIR="/workspace/input"

    if [ -d "$INPUT_DIR" ]; then
        echo "  Syncing input from: $INPUT_DIR" >> /tmp/rclone_sync.log
        # Use copy for inputs (don't delete from Drive)
        rclone copy "$INPUT_DIR" "gdrive:ComfyUI-Output/input" \
            --transfers 4 \
            --checkers 2 \
            --bwlimit 50M \
            --no-update-modtime \
            --log-level ERROR >> /tmp/rclone_sync.log 2>&1
    fi

    # Sync WORKFLOWS directory - ALWAYS use /workspace/workflows (the real location)
    WORKFLOWS_DIR="/workspace/workflows"

    if [ -d "$WORKFLOWS_DIR" ]; then
        echo "  Syncing workflows from: $WORKFLOWS_DIR" >> /tmp/rclone_sync.log
        rclone sync "$WORKFLOWS_DIR" "gdrive:ComfyUI-Output/workflows" \
            --transfers 4 \
            --checkers 2 \
            --bwlimit 50M \
            --no-update-modtime \
            --log-level ERROR >> /tmp/rclone_sync.log 2>&1
    fi

    # Sync loras folder
    if [ -d "/workspace/models/loras" ]; then
        LORA_COUNT=$(find "/workspace/models/loras" -type f -name "*.safetensors" 2>/dev/null | wc -l)
        if [ "$LORA_COUNT" -gt 0 ]; then
            echo "  Syncing $LORA_COUNT LoRA files" >> /tmp/rclone_sync.log
            rclone sync /workspace/models/loras "gdrive:ComfyUI-Output/loras" \
                --transfers 4 \
                --checkers 2 \
                --bwlimit 50M \
                --no-update-modtime \
                --log-level ERROR >> /tmp/rclone_sync.log 2>&1
        fi
    fi

    echo "  Sync cycle completed" >> /tmp/rclone_sync.log
done
SYNC_SCRIPT

chmod +x /tmp/rclone_sync_loop.sh
echo "   ✅ Created improved sync script"
echo

# Step 5: Start sync process
echo "5. Starting sync process..."
/tmp/rclone_sync_loop.sh &
SYNC_PID=$!
sleep 2

if kill -0 $SYNC_PID 2>/dev/null; then
    echo "   ✅ Sync process started (PID: $SYNC_PID)"
    echo "   Log file: /tmp/rclone_sync.log"
else
    echo "   ❌ Failed to start sync process"
    exit 1
fi
echo

# Step 6: Test sync
echo "6. Testing sync..."
echo "test_$(date +%s)" > /workspace/output/sync_test.txt
echo "   Created test file, waiting for sync..."
sleep 5

if rclone ls gdrive:ComfyUI-Output/output/sync_test.txt >/dev/null 2>&1; then
    echo "   ✅ Test file synced successfully!"
    rm /workspace/output/sync_test.txt
    rclone delete gdrive:ComfyUI-Output/output/sync_test.txt 2>/dev/null
else
    echo "   ⚠️ Test file not synced yet (may take up to 60 seconds)"
fi
echo

echo "===================================="
echo "✅ Google Drive sync has been fixed!"
echo "===================================="
echo
echo "Sync is now running in the background."
echo "Files will sync every 60 seconds from:"
echo "  /workspace/output → gdrive:ComfyUI-Output/output"
echo
echo "Monitor sync activity with:"
echo "  tail -f /tmp/rclone_sync.log"
echo
echo "Check sync status with:"
echo "  ./debug_gdrive_sync.sh"