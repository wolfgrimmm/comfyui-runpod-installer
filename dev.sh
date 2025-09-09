#!/bin/bash

# Development build script - optimized for fast iteration
# Reuses Docker cache layers intelligently

set -e

echo "🚀 Fast Development Build"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Use BuildKit for better caching
export DOCKER_BUILDKIT=1

# Detect what changed
CHANGED_UI=false
CHANGED_SCRIPTS=false
CHANGED_CONFIG=false

# Check git diff if available
if command -v git &> /dev/null; then
    if git diff --quiet HEAD -- ui/; then
        echo "✅ UI unchanged (using cache)"
    else
        echo "🔄 UI changed (will rebuild)"
        CHANGED_UI=true
    fi
    
    if git diff --quiet HEAD -- scripts/; then
        echo "✅ Scripts unchanged (using cache)"
    else
        echo "🔄 Scripts changed (will rebuild)"
        CHANGED_SCRIPTS=true
    fi
    
    if git diff --quiet HEAD -- config/; then
        echo "✅ Config unchanged (using cache)"
    else
        echo "🔄 Config changed (will rebuild)"
        CHANGED_CONFIG=true
    fi
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Build with cache mount for pip packages
docker build \
    -f Dockerfile.layered \
    --cache-from comfyui-dev:cache \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    -t comfyui-dev:latest \
    -t comfyui-dev:cache \
    .

# Show build time
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Build complete!"
echo ""

# Optionally run locally for testing
if [ "$1" = "--run" ]; then
    echo "🏃 Starting container for testing..."
    docker run --rm -it \
        -p 7777:7777 \
        -p 8188:8188 \
        -p 8888:8888 \
        -v $(pwd)/ui:/app/ui:ro \
        --name comfyui-dev \
        comfyui-dev:latest
elif [ "$1" = "--push" ]; then
    echo "📤 Pushing to registry..."
    docker tag comfyui-dev:latest ${DOCKER_REGISTRY:-yourusername}/comfyui-runpod:dev
    docker push ${DOCKER_REGISTRY:-yourusername}/comfyui-runpod:dev
else
    echo "💡 Tips:"
    echo "  ./dev.sh --run   # Run locally with live UI mount"
    echo "  ./dev.sh --push  # Push to registry"
fi