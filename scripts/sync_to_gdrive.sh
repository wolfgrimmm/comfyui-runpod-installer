#!/bin/bash

# Sync outputs and workflows TO Google Drive
# Note: Using 'sync' to make Google Drive match local exactly (will delete extra files on Drive)
echo "=========================================="
echo "📤 Syncing to Google Drive (Full Clone)"
echo "=========================================="

# Restore config from workspace if needed
if [ -f "/workspace/.config/rclone/rclone.conf" ] && [ ! -f "/root/.config/rclone/rclone.conf" ]; then
    echo "📋 Restoring rclone config from workspace..."
    mkdir -p /root/.config/rclone
    cp /workspace/.config/rclone/rclone.conf /root/.config/rclone/
fi

# Check if rclone is configured
if ! rclone listremotes | grep -q "gdrive:"; then
    echo "❌ Google Drive not configured!"
    echo "Run: rclone config"
    echo "Then set up 'gdrive' remote"
    exit 1
fi

# Backup config to workspace for persistence
if [ -f "/root/.config/rclone/rclone.conf" ] && [ ! -f "/workspace/.config/rclone/rclone.conf" ]; then
    mkdir -p /workspace/.config/rclone
    cp /root/.config/rclone/rclone.conf /workspace/.config/rclone/
    echo "💾 Config backed up to workspace"
fi

# Optimized rclone settings for RunPod uploads
# Lower bandwidth and parallel transfers to avoid saturating the connection
# --min-age: Only upload files older than 10s (avoid uploading files being written)
# --exclude: Skip temporary and partial files
# Note: Removed --ignore-existing since sync handles this better
RCLONE_FLAGS="--transfers 2 --checkers 2 --bwlimit 15M --buffer-size 16M --use-mmap --min-age 10s --exclude '*.tmp' --exclude '*.partial' --progress"

echo "📤 Syncing user outputs to Google Drive..."
# Sync each user's folder from /workspace/output
for user_dir in /workspace/output/*/; do
    if [ -d "$user_dir" ]; then
        username=$(basename "$user_dir")
        echo "  📁 Syncing $username..."
        rclone sync "$user_dir" "gdrive:ComfyUI/output/$username" $RCLONE_FLAGS
    fi
done

echo "📤 Syncing workflows to Google Drive..."
# Check both possible workflow locations
if [ -d "/workspace/workflows" ]; then
    for user_dir in /workspace/workflows/*/; do
        if [ -d "$user_dir" ]; then
            username=$(basename "$user_dir")
            echo "  📁 Syncing $username workflows..."
            rclone sync "$user_dir" "gdrive:ComfyUI/workflows/$username" --transfers 4 --buffer-size 8M --progress
        fi
    done
elif [ -d "/workspace/ComfyUI/user/default/workflows" ]; then
    rclone sync /workspace/ComfyUI/user/default/workflows gdrive:ComfyUI/workflows --transfers 4 --buffer-size 8M --progress
fi

echo "📤 Syncing input images to Google Drive..."
# Sync each user's input folder
for user_dir in /workspace/input/*/; do
    if [ -d "$user_dir" ]; then
        username=$(basename "$user_dir")
        echo "  📁 Syncing $username inputs..."
        rclone sync "$user_dir" "gdrive:ComfyUI/input/$username" $RCLONE_FLAGS
    fi
done

echo ""
echo "✅ Sync complete!"
echo "📊 Files synced:"
echo "Outputs: $(find /workspace/output -type f 2>/dev/null | wc -l) files"
echo "Workflows: $(find /workspace/workflows -name "*.json" 2>/dev/null | wc -l) workflows"