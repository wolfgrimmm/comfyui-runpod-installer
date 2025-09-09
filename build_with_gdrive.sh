#!/bin/bash

# Build script that embeds Google Drive credentials securely
# Usage: ./build_with_gdrive.sh /path/to/service-account.json

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 /path/to/service-account.json"
    echo "Example: $0 ~/Downloads/ageless-answer-466112-s1-f9cd403e242b.json"
    exit 1
fi

SERVICE_ACCOUNT_FILE="$1"

if [ ! -f "$SERVICE_ACCOUNT_FILE" ]; then
    echo "Error: Service account file not found: $SERVICE_ACCOUNT_FILE"
    exit 1
fi

echo "🔧 Building Docker image with embedded Google Drive credentials..."

# Read the service account JSON
SERVICE_ACCOUNT_JSON=$(cat "$SERVICE_ACCOUNT_FILE")

# Extract key components
PRIVATE_KEY_ID=$(echo "$SERVICE_ACCOUNT_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('private_key_id', ''))")
PRIVATE_KEY=$(echo "$SERVICE_ACCOUNT_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('private_key', ''))")

# Create a temporary init script with real credentials
cp scripts/init_gdrive_embedded.sh scripts/init_gdrive_temp.sh

# Replace placeholders with actual values (using Python for safe escaping)
python3 << EOF
import json

with open('scripts/init_gdrive_temp.sh', 'r') as f:
    content = f.read()

# Read service account
with open('$SERVICE_ACCOUNT_FILE', 'r') as f:
    sa = json.load(f)

# Replace placeholders
content = content.replace('PLACEHOLDER_PRIVATE_KEY_ID', sa['private_key_id'])
content = content.replace('PLACEHOLDER_PRIVATE_KEY', sa['private_key'])

with open('scripts/init_gdrive_temp.sh', 'w') as f:
    f.write(content)
EOF

# Build Docker image with the real credentials
echo "📦 Building Docker image..."
docker build -t comfyui-gdrive:latest .

# Clean up temporary file immediately
rm -f scripts/init_gdrive_temp.sh

echo "✅ Build complete!"
echo ""
echo "🚀 To run locally:"
echo "   docker run -p 7777:7777 -p 8188:8188 --gpus all comfyui-gdrive:latest"
echo ""
echo "📤 To push to Docker Hub:"
echo "   docker tag comfyui-gdrive:latest yourusername/comfyui-gdrive:latest"
echo "   docker push yourusername/comfyui-gdrive:latest"
echo ""
echo "🔒 Security: Credentials are embedded in the image. Only share with trusted users."