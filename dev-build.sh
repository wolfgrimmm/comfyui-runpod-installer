#!/bin/bash
# Fast local development build script

echo "ComfyUI Development Build Script"
echo "================================"
echo ""

# Check what changed
UI_CHANGED=$(git diff --name-only HEAD^ HEAD | grep -c "ui/")
DOCKERFILE_CHANGED=$(git diff --name-only HEAD^ HEAD | grep -c "Dockerfile")

if [ "$1" == "ui" ] || ([ $UI_CHANGED -gt 0 ] && [ $DOCKERFILE_CHANGED -eq 0 ]); then
    echo "🚀 Building UI-only (fast mode)..."
    echo "This will take ~1-2 minutes"
    
    # Build using dev dockerfile (super fast)
    docker build -f Dockerfile.dev -t wolfgrimmm/comfyui-runpod:dev .
    
    if [ $? -eq 0 ]; then
        echo "✅ Build successful!"
        echo ""
        echo "To test locally:"
        echo "docker run -p 7777:7777 -p 8188:8188 -p 8888:8888 wolfgrimmm/comfyui-runpod:dev"
        echo ""
        echo "To push to Docker Hub:"
        echo "docker tag wolfgrimmm/comfyui-runpod:dev wolfgrimmm/comfyui-runpod:latest"
        echo "docker push wolfgrimmm/comfyui-runpod:latest"
    fi
    
elif [ "$1" == "full" ]; then
    echo "🔨 Building full image..."
    echo "This will take ~10-15 minutes"
    
    # Build using optimized dockerfile with cache
    docker build -f Dockerfile.optimized \
        --cache-from wolfgrimmm/comfyui-runpod:latest \
        --cache-from wolfgrimmm/comfyui-runpod:base \
        -t wolfgrimmm/comfyui-runpod:latest .
        
    if [ $? -eq 0 ]; then
        echo "✅ Build successful!"
        echo ""
        echo "To push base image for future builds:"
        echo "docker build -f Dockerfile.optimized --target comfyui -t wolfgrimmm/comfyui-runpod:base ."
        echo "docker push wolfgrimmm/comfyui-runpod:base"
    fi
    
else
    echo "Usage:"
    echo "  ./dev-build.sh ui     # Fast UI-only build (~1 min)"
    echo "  ./dev-build.sh full   # Full rebuild (~10-15 min)"
    echo ""
    echo "Auto-detect mode (based on git changes):"
    echo "  ./dev-build.sh"
    
    if [ $UI_CHANGED -gt 0 ] && [ $DOCKERFILE_CHANGED -eq 0 ]; then
        echo ""
        echo "Detected UI changes only. Run with 'ui' flag for fast build."
    fi
fi