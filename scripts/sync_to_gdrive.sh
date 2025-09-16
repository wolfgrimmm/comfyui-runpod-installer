#!/bin/bash

# Sync outputs and workflows TO Google Drive
# Note: Using 'sync' to make Google Drive match local exactly (will delete extra files on Drive)
echo "=========================================="
echo "📤 Syncing to Google Drive (Full Clone)"
echo "=========================================="

# Check if rclone is configured
if ! rclone listremotes | grep -q "gdrive:"; then
    echo "❌ Google Drive not configured!"
    echo "Run: rclone config"
    echo "Then set up 'gdrive' remote"
    exit 1
fi

# Optimized rclone settings for RunPod uploads
# Lower bandwidth and parallel transfers to avoid saturating the connection
# --min-age: Only upload files older than 10s (avoid uploading files being written)
# --exclude: Skip temporary and partial files
# Note: Removed --ignore-existing since sync handles this better
RCLONE_FLAGS="--transfers 2 --checkers 2 --bwlimit 15M --buffer-size 16M --use-mmap --min-age 10s --exclude '*.tmp' --exclude '*.partial' --progress"

echo "📤 Syncing outputs to Google Drive (bandwidth limited)..."
rclone sync /workspace/ComfyUI/output gdrive:ComfyUI/output $RCLONE_FLAGS

echo "📤 Syncing workflows to Google Drive..."
rclone sync /workspace/ComfyUI/user/default/workflows gdrive:ComfyUI/workflows --transfers 4 --buffer-size 8M --progress

echo "📤 Syncing input images to Google Drive..."
rclone sync /workspace/ComfyUI/input gdrive:ComfyUI/input $RCLONE_FLAGS

echo ""
echo "✅ Sync complete!"
echo "📊 Files synced:"
echo "Outputs: $(find /workspace/ComfyUI/output -type f | wc -l) files"
echo "Workflows: $(find /workspace/ComfyUI/user/default/workflows -name "*.json" | wc -l) workflows"