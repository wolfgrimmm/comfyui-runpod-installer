# Optimized for RunPod Pods - Uses RunPod's PyTorch base
FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

WORKDIR /

# Install system dependencies including Python build tools
RUN apt-get update && apt-get install -y \
    git wget curl psmisc lsof unzip \
    python3.11-dev python3.11-venv python3-pip \
    build-essential \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create and activate a virtual environment to avoid conflicts
ENV VIRTUAL_ENV=/opt/venv
RUN python3.11 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Upgrade pip in virtual environment
RUN pip install --upgrade pip wheel setuptools

# Install Python packages in virtual environment
# Core ComfyUI requirements
RUN pip install --no-cache-dir \
    einops \
    torchsde \
    "kornia>=0.7.1" \
    spandrel \
    "safetensors>=0.4.2"

# Web and async packages
RUN pip install --no-cache-dir \
    aiohttp \
    pyyaml \
    Pillow \
    tqdm \
    scipy

# ML packages
RUN pip install --no-cache-dir \
    transformers \
    diffusers \
    accelerate

# ONNX and CV
RUN pip install --no-cache-dir onnxruntime-gpu || \
    pip install --no-cache-dir onnxruntime

RUN pip install --no-cache-dir opencv-python

# Core Web UI requirements
RUN pip install --no-cache-dir \
    flask==3.0.0 \
    psutil \
    requests

# Git integration (for ComfyUI Manager)
RUN pip install --no-cache-dir \
    GitPython \
    PyGithub==1.59.1

# Jupyter
RUN pip install --no-cache-dir \
    jupyterlab \
    ipywidgets \
    notebook

# Create app directory
RUN mkdir -p /app

# Copy application files
COPY scripts /app/scripts
COPY config /app/config
COPY ui /app/ui
RUN chmod +x /app/scripts/*.sh 2>/dev/null || true

# Create init script
RUN cat > /app/init.sh << 'EOF'
#!/bin/bash
set -e

echo "🚀 RunPod ComfyUI Installer Initializing..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Configure git
git config --global --add safe.directory '*'
git config --global user.email "comfyui@runpod.local" 2>/dev/null || true
git config --global user.name "ComfyUI" 2>/dev/null || true

# Create necessary directories
mkdir -p /workspace/models/{checkpoints,loras,vae,controlnet,clip,clip_vision,diffusers,embeddings,upscale_models}
mkdir -p /workspace/output /workspace/input /workspace/workflows

echo "✅ Environment prepared"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
EOF

RUN chmod +x /app/init.sh

# Create startup script
RUN cat > /start.sh << 'EOF'
#!/bin/bash
set -e

echo "🚀 Starting RunPod Services..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Activate virtual environment
source /opt/venv/bin/activate

# Initialize environment
/app/init.sh

# Start Control Panel UI
echo "🌐 Starting Control Panel on port 7777..."
cd /app/ui && python app.py > /workspace/ui.log 2>&1 &

# Start JupyterLab
echo "📊 Starting JupyterLab on port 8888..."
jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root \
    --NotebookApp.token="" --NotebookApp.password="" \
    --ServerApp.allow_origin="*" > /workspace/jupyter.log 2>&1 &

# Wait for services
sleep 3

# Check status
if lsof -i:7777 > /dev/null 2>&1; then
    echo "✅ Control Panel running on http://localhost:7777"
    echo "   Use the Control Panel to install and start ComfyUI"
else
    echo "⚠️ Control Panel failed to start. Check /workspace/ui.log"
    tail -20 /workspace/ui.log 2>/dev/null || true
fi

if lsof -i:8888 > /dev/null 2>&1; then
    echo "✅ JupyterLab running on http://localhost:8888"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Ready! Visit port 7777 to manage ComfyUI"

# Keep container running
sleep infinity
EOF

RUN chmod +x /start.sh

# Create ComfyUI start script
RUN cat > /app/start_comfyui.sh << 'EOF'
#!/bin/bash

echo "🎨 Starting ComfyUI..."

# Activate virtual environment
source /opt/venv/bin/activate

# Check if ComfyUI is installed
if [ ! -f "/workspace/ComfyUI/main.py" ]; then
    echo "📦 Installing ComfyUI first..."
    cd /workspace
    rm -rf ComfyUI
    
    if ! git clone https://github.com/comfyanonymous/ComfyUI.git; then
        echo "⚠️ Git clone failed, trying shallow clone..."
        git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git
    fi
    
    if [ ! -f "/workspace/ComfyUI/main.py" ]; then
        echo "❌ Failed to install ComfyUI"
        exit 1
    fi
fi

# Setup model symlink
if [ -e /workspace/ComfyUI/models ]; then
    rm -rf /workspace/ComfyUI/models
fi
ln -sf /workspace/models /workspace/ComfyUI/models

# Install Manager if needed
if [ ! -d "/workspace/ComfyUI/custom_nodes/ComfyUI-Manager" ]; then
    echo "📦 Installing ComfyUI Manager..."
    mkdir -p /workspace/ComfyUI/custom_nodes
    cd /workspace/ComfyUI/custom_nodes
    if git clone https://github.com/ltdrdata/ComfyUI-Manager.git; then
        if [ -f "ComfyUI-Manager/requirements.txt" ]; then
            pip install -r ComfyUI-Manager/requirements.txt 2>/dev/null || true
        fi
    fi
fi

# Start ComfyUI
cd /workspace/ComfyUI
echo "Starting ComfyUI on port 8188..."
exec python main.py --listen 0.0.0.0 --port 8188
EOF

RUN chmod +x /app/start_comfyui.sh

# Verify critical packages are installed
RUN python -c "import flask; print(f'Flask {flask.__version__} OK')"
RUN python -c "import torch; print(f'PyTorch {torch.__version__} OK')"

# Environment
ENV PYTHONUNBUFFERED=1
ENV HF_HOME=/workspace

# Ports
EXPOSE 7777 8188 8888

WORKDIR /workspace

# Start services
CMD ["/start.sh"]