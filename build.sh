#!/bin/bash

# Universal build script - creates image that works both ways:
# 1. Traditional: Pre-installed packages (larger image, instant start)
# 2. Fast: Creates venv on first run (smaller image, 5-10 min first start)

set -e

echo "🔧 Building Universal Docker image for RunPod..."
echo ""
echo "This image supports two modes:"
echo "1. Traditional build: Include all packages (use --traditional flag)"
echo "2. Fast build: Minimal image, downloads on first run (default)"
echo ""

if [ "$1" == "--traditional" ]; then
    echo "📦 Building TRADITIONAL image with pre-installed packages..."
    echo "   Image size: ~15GB"
    echo "   First start: Instant"
    echo ""
    
    # Build with pre-installed packages
    docker build --build-arg INSTALL_PACKAGES=true -t comfyui-runpod:latest .
else
    echo "🚀 Building FAST image (minimal, downloads on demand)..."
    echo "   Image size: ~3GB"
    echo "   First start: 5-10 minutes (then instant)"
    echo ""
    
    # Build minimal image
    docker build -t comfyui-runpod:latest .
fi

echo "✅ Build complete!"
echo ""
echo "The image will automatically:"
echo "• Check for venv in /workspace/venv"
echo "• Use it if found (instant start)"
echo "• Create it if needed (5-10 min first time)"
echo "• Install ComfyUI Manager"
echo ""
echo "Next steps:"
echo "1. Tag: docker tag comfyui-runpod:latest yourusername/comfyui-runpod:latest"
echo "2. Push: docker push yourusername/comfyui-runpod:latest"
echo "3. Add GOOGLE_SERVICE_ACCOUNT secret in RunPod dashboard"
echo "4. Deploy pod with persistent /workspace volume"