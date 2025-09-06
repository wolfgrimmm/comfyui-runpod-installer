#!/bin/bash

# Sync outputs and workflows TO Google Drive
echo "=========================================="
echo "📤 Syncing to Google Drive"
echo "=========================================="

# Check if rclone is configured
if ! rclone listremotes | grep -q "gdrive:"; then
    echo "❌ Google Drive not configured!"
    echo "Run: rclone config"
    echo "Then set up 'gdrive' remote"
    exit 1
fi

echo "🔄 Uploading outputs to Google Drive..."
rclone sync /workspace/ComfyUI/output gdrive:ComfyUI/output --progress

echo "🔄 Uploading workflows to Google Drive..."
rclone sync /workspace/ComfyUI/user/default/workflows gdrive:ComfyUI/workflows --progress

echo "🔄 Uploading input images to Google Drive..."
rclone sync /workspace/ComfyUI/input gdrive:ComfyUI/input --progress

echo ""
echo "✅ Upload complete!"
echo "📊 Files uploaded:"
echo "Outputs: $(find /workspace/ComfyUI/output -type f | wc -l) files"
echo "Workflows: $(find /workspace/ComfyUI/user/default/workflows -name "*.json" | wc -l) workflows"