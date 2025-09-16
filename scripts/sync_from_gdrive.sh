#!/bin/bash

# Download models, workflows FROM Google Drive to ComfyUI
# Note: Using 'copy' instead of 'sync' to prevent deletion of local files
echo "=========================================="
echo "📥 Downloading from Google Drive"
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

# Create user-based directories (matching your system)
mkdir -p /workspace/output
mkdir -p /workspace/input
mkdir -p /workspace/workflows

# Optimized rclone settings for RunPod
# --transfers: Number of parallel transfers (reduced from default 4)
# --checkers: Number of checkers running in parallel (reduced from default 8)
# --bwlimit: Bandwidth limit to prevent network saturation
# --buffer-size: Per-transfer buffer size (reduced for memory efficiency)
# --use-mmap: Use memory mapping for better memory efficiency
# --ignore-existing: Skip files that already exist locally
# --retries: Number of retries for failed transfers
# --low-level-retries: Number of retries for low level errors

RCLONE_FLAGS="--transfers 2 --checkers 2 --bwlimit 30M --buffer-size 16M --use-mmap --ignore-existing --retries 3 --low-level-retries 10 --progress"

echo "📥 Downloading checkpoints (large files, limited bandwidth)..."
rclone copy gdrive:ComfyUI/models/checkpoints /workspace/ComfyUI/models/checkpoints $RCLONE_FLAGS --bwlimit 20M

echo "📥 Downloading LoRAs..."
rclone copy gdrive:ComfyUI/models/loras /workspace/ComfyUI/models/loras $RCLONE_FLAGS

echo "📥 Downloading VAE..."
rclone copy gdrive:ComfyUI/models/vae /workspace/ComfyUI/models/vae $RCLONE_FLAGS

echo "📥 Downloading embeddings..."
rclone copy gdrive:ComfyUI/models/embeddings /workspace/ComfyUI/models/embeddings $RCLONE_FLAGS

echo "📥 Downloading ControlNet..."
rclone copy gdrive:ComfyUI/models/controlnet /workspace/ComfyUI/models/controlnet $RCLONE_FLAGS

echo "📥 Downloading upscale models..."
rclone copy gdrive:ComfyUI/models/upscale_models /workspace/ComfyUI/models/upscale_models $RCLONE_FLAGS

echo "📥 Downloading workflows..."
# Download per-user workflows
if rclone lsd gdrive:ComfyUI/workflows/ 2>/dev/null | grep -q " "; then
    for username in $(rclone lsd gdrive:ComfyUI/workflows/ 2>/dev/null | awk '{print $NF}'); do
        echo "  📁 Downloading $username workflows..."
        mkdir -p "/workspace/workflows/$username"
        rclone copy "gdrive:ComfyUI/workflows/$username" "/workspace/workflows/$username" --transfers 4 --checkers 2 --buffer-size 8M --ignore-existing --progress
    done
fi

echo "📥 Downloading input images..."
# Download per-user inputs
if rclone lsd gdrive:ComfyUI/inputs/ 2>/dev/null | grep -q " "; then
    for username in $(rclone lsd gdrive:ComfyUI/inputs/ 2>/dev/null | awk '{print $NF}'); do
        echo "  📁 Downloading $username inputs..."
        mkdir -p "/workspace/input/$username"
        rclone copy "gdrive:ComfyUI/inputs/$username" "/workspace/input/$username" --transfers 4 --checkers 2 --buffer-size 8M --ignore-existing --progress
    done
fi

# Optional: download previous outputs (might be large)
read -p "Download previous outputs from Google Drive? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "📥 Downloading outputs..."
    # Download per-user outputs
    if rclone lsd gdrive:ComfyUI/outputs/ 2>/dev/null | grep -q " "; then
        for username in $(rclone lsd gdrive:ComfyUI/outputs/ 2>/dev/null | awk '{print $NF}'); do
            echo "  📁 Downloading $username outputs..."
            mkdir -p "/workspace/output/$username"
            rclone copy "gdrive:ComfyUI/outputs/$username" "/workspace/output/$username" --transfers 2 --checkers 2 --bwlimit 20M --buffer-size 16M --use-mmap --ignore-existing --progress
        done
    fi
fi

echo ""
echo "✅ Download complete!"
echo "📊 Storage used:"
du -sh /workspace/ComfyUI/models/
du -sh /workspace/ComfyUI/user/default/workflows/