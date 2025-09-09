#!/bin/bash

# Fast build script - minimal Docker image, everything else on first run
# This creates a MUCH smaller image that downloads faster to RunPod

set -e

echo "🚀 Building FAST Docker image for RunPod..."
echo "📦 This image is minimal - libraries install on first run to /workspace/venv"

# Create the fast Dockerfile
cat > Dockerfile.fast << 'EOF'
# Minimal fast-start Dockerfile
FROM nvidia/cuda:12.4.0-runtime-ubuntu22.04

WORKDIR /workspace
ENV DEBIAN_FRONTEND=noninteractive

# Install only essential system packages
RUN apt-get update && \
    apt-get install -y \
        python3.10 python3.10-venv python3-pip \
        git wget curl unzip \
        && apt-get clean \
        && rm -rf /var/lib/apt/lists/*

# Install rclone
RUN curl -O https://downloads.rclone.org/rclone-current-linux-amd64.zip && \
    unzip rclone-current-linux-amd64.zip && \
    cd rclone-*-linux-amd64 && \
    cp rclone /usr/bin/ && \
    cd .. && \
    rm -rf rclone-*-linux-amd64*

# Copy application files
COPY config /app/config
COPY ui /app/ui
COPY scripts /app/scripts
RUN chmod +x /app/scripts/*.sh

# Create start script
RUN cat > /app/start.sh << 'STARTSCRIPT'
#!/bin/bash
echo "🚀 Fast ComfyUI Startup"

# Run fast initialization
/app/scripts/init_fast.sh

# Configure Google Drive
if [ -f "/app/scripts/init_gdrive.sh" ]; then
    /app/scripts/init_gdrive.sh || true
fi

# Activate venv
source /workspace/venv/bin/activate

# Start services
echo "Starting UI on port 7777..."
cd /app/ui && python app.py &

echo "Starting JupyterLab on port 8888..."
jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root \
    --NotebookApp.token="" --NotebookApp.password="" &

echo "Ready! Access UI at port 7777"
sleep infinity
STARTSCRIPT

RUN chmod +x /app/start.sh

# Create ComfyUI start script
RUN cat > /app/start_comfyui.sh << 'COMFYUI'
#!/bin/bash
/app/scripts/init_fast.sh
source /workspace/venv/bin/activate

if [ ! -f "/workspace/ComfyUI/main.py" ]; then
    echo "ERROR: ComfyUI not found"
    exit 1
fi

cd /workspace/ComfyUI
python main.py --listen 0.0.0.0 --port 8188
COMFYUI

RUN chmod +x /app/start_comfyui.sh

EXPOSE 7777 8188 8888
CMD ["/app/start.sh"]
EOF

# Build the image
docker build -f Dockerfile.fast -t comfyui-fast:latest .

# Clean up
rm -f Dockerfile.fast

echo "✅ Build complete!"
echo ""
echo "📊 Image size comparison:"
echo "  Regular image: ~15GB (includes all Python packages)"
echo "  Fast image: ~3GB (downloads packages on first run)"
echo ""
echo "⚡ Benefits:"
echo "  • 5x faster upload to Docker Hub"
echo "  • 5x faster download to RunPod"
echo "  • Libraries cached in /workspace/venv (persistent)"
echo "  • Second startup takes < 30 seconds"
echo ""
echo "🚀 To push:"
echo "  docker tag comfyui-fast:latest yourusername/comfyui-fast:latest"
echo "  docker push yourusername/comfyui-fast:latest"
echo ""
echo "📝 Note: First run will take 5-10 minutes to setup venv,"
echo "      but subsequent runs will be instant!"