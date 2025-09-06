#!/bin/bash

# Sync models, workflows FROM Google Drive to ComfyUI
echo "=========================================="
echo "📥 Syncing from Google Drive"
echo "=========================================="

# Check if rclone is configured
if ! rclone listremotes | grep -q "gdrive:"; then
    echo "❌ Google Drive not configured!"
    echo "Run: rclone config"
    echo "Then set up 'gdrive' remote"
    exit 1
fi

# Create model directories if they don't exist
mkdir -p /workspace/ComfyUI/models/checkpoints
mkdir -p /workspace/ComfyUI/models/loras
mkdir -p /workspace/ComfyUI/models/vae
mkdir -p /workspace/ComfyUI/models/embeddings
mkdir -p /workspace/ComfyUI/models/controlnet
mkdir -p /workspace/ComfyUI/models/upscale_models
mkdir -p /workspace/ComfyUI/user/default/workflows
mkdir -p /workspace/ComfyUI/output
mkdir -p /workspace/ComfyUI/input

echo "🔄 Syncing checkpoints..."
rclone sync gdrive:ComfyUI/models/checkpoints /workspace/ComfyUI/models/checkpoints --progress

echo "🔄 Syncing LoRAs..."
rclone sync gdrive:ComfyUI/models/loras /workspace/ComfyUI/models/loras --progress

echo "🔄 Syncing VAE..."
rclone sync gdrive:ComfyUI/models/vae /workspace/ComfyUI/models/vae --progress

echo "🔄 Syncing embeddings..."
rclone sync gdrive:ComfyUI/models/embeddings /workspace/ComfyUI/models/embeddings --progress

echo "🔄 Syncing ControlNet..."
rclone sync gdrive:ComfyUI/models/controlnet /workspace/ComfyUI/models/controlnet --progress

echo "🔄 Syncing upscale models..."
rclone sync gdrive:ComfyUI/models/upscale_models /workspace/ComfyUI/models/upscale_models --progress

echo "🔄 Syncing workflows..."
rclone sync gdrive:ComfyUI/workflows /workspace/ComfyUI/user/default/workflows --progress

echo "🔄 Syncing input images..."
rclone sync gdrive:ComfyUI/input /workspace/ComfyUI/input --progress

# Optional: sync previous outputs (might be large)
read -p "Sync previous outputs from Google Drive? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🔄 Syncing outputs..."
    rclone sync gdrive:ComfyUI/output /workspace/ComfyUI/output --progress
fi

echo ""
echo "✅ Sync complete!"
echo "📊 Storage used:"
du -sh /workspace/ComfyUI/models/
du -sh /workspace/ComfyUI/user/default/workflows/