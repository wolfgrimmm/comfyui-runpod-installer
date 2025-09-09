#!/bin/bash

# Build script optimized for RunPod using their official base image
# Much faster builds since PyTorch/CUDA are pre-installed!

set -e

echo "🚀 Building RunPod-Optimized Docker Image"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Using RunPod base image with:"
echo "• PyTorch 2.4.0 pre-installed"
echo "• CUDA 12.4 pre-installed"
echo "• Python 3.11 pre-installed"
echo "• Common ML libraries included"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Enable BuildKit for better caching
export DOCKER_BUILDKIT=1

# Build the optimized image
echo "Building image..."
docker build \
    -f Dockerfile.runpod \
    --platform linux/amd64 \
    -t comfyui-runpod-optimized:latest \
    .

# Calculate size difference
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Build Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Show image size
docker images comfyui-runpod-optimized:latest --format "Image size: {{.Size}}"

echo ""
echo "🎯 Advantages of RunPod base:"
echo "• Faster builds (PyTorch pre-installed)"
echo "• Smaller final image (no duplicate packages)"
echo "• Optimized for RunPod's infrastructure"
echo "• Cached on RunPod servers (faster pulls)"
echo ""
echo "📤 To push:"
echo "docker tag comfyui-runpod-optimized:latest yourusername/comfyui:runpod"
echo "docker push yourusername/comfyui:runpod"
echo ""
echo "⚡ This image starts INSTANTLY on RunPod!"