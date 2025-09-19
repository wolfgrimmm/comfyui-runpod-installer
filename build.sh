#!/bin/bash

# Build script optimized for RunPod using their official base image
# Much faster builds since PyTorch/CUDA are pre-installed!

set -e

echo "🚀 Building RunPod-Optimized Docker Image"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Using RunPod base image with:"
echo "• PyTorch 2.4.1 pre-installed"
echo "• CUDA 12.9 (upgrading from 12.4)"
echo "• Python 3.11 pre-installed"
echo "• Common ML libraries included"
echo "• cuDNN 9 for optimal performance"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Enable BuildKit for better caching
export DOCKER_BUILDKIT=1

# Build the optimized image
echo "Building image..."
docker build \
    --platform linux/amd64 \
    -t comfyui-runpod:latest \
    .

# Calculate size difference
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Build Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Show image size
docker images comfyui-runpod:latest --format "Image size: {{.Size}}"

echo ""
echo "🎯 How it works:"
echo "• Control Panel starts automatically on port 7777"
echo "• Use Control Panel to install/start ComfyUI on port 8188"
echo "• JupyterLab available on port 8888"
echo "• All data persists in /workspace"
echo ""
echo "📤 To push to Docker Hub:"
echo "docker tag comfyui-runpod:latest wolfgrimmm/comfyui-runpod:latest"
echo "docker push wolfgrimmm/comfyui-runpod:latest"
echo ""
echo "🏃 To run locally:"
echo "docker run -it --gpus all -p 7777:7777 -p 8188:8188 -p 8888:8888 -v ./workspace:/workspace comfyui-runpod:latest"
echo ""
echo "⚡ This image is optimized for RunPod pods!"