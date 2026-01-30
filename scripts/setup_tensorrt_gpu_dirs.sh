#!/bin/bash
# Setup GPU-specific TensorRT directories
# This allows multiple GPUs (4090, 5090, B200) to share the same network volume
# without TensorRT engine conflicts

set -e

echo "Setting up GPU-specific TensorRT directories..."

# Get current GPU compute capability
COMPUTE_CAP=$(python3 -c "
import torch
if torch.cuda.is_available():
    cap = torch.cuda.get_device_capability(0)
    print(f'{cap[0]}{cap[1]}')
else:
    print('unknown')
" 2>/dev/null || echo "unknown")

if [ "$COMPUTE_CAP" = "unknown" ]; then
    echo "Warning: Could not detect GPU compute capability"
    exit 0
fi

echo "Detected GPU compute capability: sm_$COMPUTE_CAP"

# Create GPU-specific cache directory
CACHE_BASE="/workspace/.tensorrt_cache"
GPU_CACHE_DIR="$CACHE_BASE/sm_$COMPUTE_CAP"

mkdir -p "$GPU_CACHE_DIR/upscaler"
mkdir -p "$GPU_CACHE_DIR/engines"

echo "Created cache directory: $GPU_CACHE_DIR"

# Setup symlink for TensorRT upscaler
TENSORRT_UPSCALER="/workspace/ComfyUI/models/tensorrt/upscaler"
TENSORRT_DIR="/workspace/ComfyUI/models/tensorrt"

# Ensure parent directory exists
mkdir -p "$TENSORRT_DIR"

# Remove existing upscaler dir/symlink if it exists
if [ -L "$TENSORRT_UPSCALER" ]; then
    rm -f "$TENSORRT_UPSCALER"
    echo "Removed existing symlink"
elif [ -d "$TENSORRT_UPSCALER" ]; then
    # Move existing engines to GPU-specific cache if they match our compute cap
    if [ "$(ls -A $TENSORRT_UPSCALER 2>/dev/null)" ]; then
        echo "Moving existing engines to GPU cache..."
        mv "$TENSORRT_UPSCALER"/* "$GPU_CACHE_DIR/upscaler/" 2>/dev/null || true
    fi
    rm -rf "$TENSORRT_UPSCALER"
    echo "Removed existing directory"
fi

# Create symlink to GPU-specific directory
ln -s "$GPU_CACHE_DIR/upscaler" "$TENSORRT_UPSCALER"
echo "Created symlink: $TENSORRT_UPSCALER -> $GPU_CACHE_DIR/upscaler"

echo "TensorRT GPU directories setup complete!"
echo "  - GPU: sm_$COMPUTE_CAP"
echo "  - Cache: $GPU_CACHE_DIR"
echo "  - Upscaler: $TENSORRT_UPSCALER -> $GPU_CACHE_DIR/upscaler"
