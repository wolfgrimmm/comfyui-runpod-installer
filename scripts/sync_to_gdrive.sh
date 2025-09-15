#!/bin/bash

# Upload outputs and workflows TO Google Drive
# Note: Using 'copy' instead of 'sync' to prevent deletion of files on Google Drive
echo "=========================================="
echo "📤 Uploading to Google Drive"
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
RCLONE_FLAGS="--transfers 2 --checkers 2 --bwlimit 15M --buffer-size 16M --use-mmap --ignore-existing --min-age 10s --exclude '*.tmp' --exclude '*.partial' --progress"

echo "📤 Uploading outputs to Google Drive (bandwidth limited)..."
rclone copy /workspace/ComfyUI/output gdrive:ComfyUI/output $RCLONE_FLAGS

echo "📤 Uploading workflows to Google Drive..."
rclone copy /workspace/ComfyUI/user/default/workflows gdrive:ComfyUI/workflows --transfers 4 --buffer-size 8M --ignore-existing --progress

echo "📤 Uploading input images to Google Drive..."
rclone copy /workspace/ComfyUI/input gdrive:ComfyUI/input $RCLONE_FLAGS

echo ""
echo "✅ Upload complete!"
echo "📊 Files uploaded:"
echo "Outputs: $(find /workspace/ComfyUI/output -type f | wc -l) files"
echo "Workflows: $(find /workspace/ComfyUI/user/default/workflows -name "*.json" | wc -l) workflows"