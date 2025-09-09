#!/bin/bash

# Simple build script for RunPod deployment with Secrets
# No credentials are embedded - they're provided via RunPod Secrets

set -e

echo "🔧 Building Docker image for RunPod..."
echo "📝 Note: Google Drive credentials will be provided via RunPod Secrets"

# Build Docker image without embedded credentials
docker build -t comfyui-runpod:latest .

echo "✅ Build complete!"
echo ""
echo "🚀 To push to Docker Hub:"
echo "   docker tag comfyui-runpod:latest yourusername/comfyui-runpod:latest"
echo "   docker push yourusername/comfyui-runpod:latest"
echo ""
echo "📋 RunPod Setup Instructions:"
echo "   1. Go to RunPod Dashboard → Secrets"
echo "   2. Create a new secret named: GOOGLE_SERVICE_ACCOUNT"
echo "   3. Paste your entire service account JSON as the value"
echo "   4. When creating a pod, the secret will be available as:"
echo "      \$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT"
echo ""
echo "🔒 This approach is more secure - credentials are never in the image!"