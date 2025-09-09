#!/bin/bash

# Build script for RunPod deployment with Secrets
# Credentials are provided via RunPod Secrets, not embedded in image

set -e

echo "🔧 Building Docker image for RunPod..."

# Build Docker image
docker build -t comfyui-runpod:latest .

echo "✅ Build complete!"
echo ""
echo "Next steps:"
echo "1. Push to Docker Hub: docker push yourusername/comfyui-runpod:latest"
echo "2. Add GOOGLE_SERVICE_ACCOUNT secret in RunPod dashboard"
echo "3. Deploy pod with the image"