# RTX 5090 Optimized with CUDA 12.4
FROM nvidia/cuda:12.4.0-devel-ubuntu22.04

WORKDIR /workspace
ENV DEBIAN_FRONTEND=noninteractive

# Install Python, git, wget, psmisc (for fuser), lsof, curl, and rclone
RUN apt-get update && \
    apt-get install -y python3.10 python3-pip git wget psmisc lsof curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    ln -s /usr/bin/python3 /usr/bin/python && \
    curl https://rclone.org/install.sh | bash

# Install PyTorch with CUDA 12.4 for RTX 5090
RUN pip3 install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124

# Install ComfyUI requirements without cloning ComfyUI itself
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /tmp/comfyui-req && \
    pip install --no-cache-dir -r /tmp/comfyui-req/requirements.txt && \
    rm -rf /tmp/comfyui-req

# Install additional AI packages, JupyterLab, and UI dependencies
RUN pip install --no-cache-dir \
    onnxruntime-gpu \
    opencv-python \
    accelerate \
    diffusers \
    jupyterlab \
    ipywidgets \
    notebook \
    flask==3.0.0 \
    psutil==5.9.0

# Copy configuration files
COPY config /app/config

# Create workspace directories structure
RUN mkdir -p /workspace/models/checkpoints && \
    mkdir -p /workspace/models/clip && \
    mkdir -p /workspace/models/clip_vision && \
    mkdir -p /workspace/models/configs && \
    mkdir -p /workspace/models/controlnet && \
    mkdir -p /workspace/models/diffusers && \
    mkdir -p /workspace/models/embeddings && \
    mkdir -p /workspace/models/gligen && \
    mkdir -p /workspace/models/hypernetworks && \
    mkdir -p /workspace/models/loras && \
    mkdir -p /workspace/models/photomaker && \
    mkdir -p /workspace/models/style_models && \
    mkdir -p /workspace/models/unet && \
    mkdir -p /workspace/models/upscale_models && \
    mkdir -p /workspace/models/vae && \
    mkdir -p /workspace/models/vae_approx && \
    mkdir -p /workspace/output && \
    mkdir -p /workspace/input && \
    mkdir -p /workspace/workflows && \
    mkdir -p /workspace/user_data

# Create app directory for scripts
RUN mkdir -p /app

# Create initialization script to set up ComfyUI in workspace on first run
RUN cat > /app/init_workspace.sh << 'EOF'
#!/bin/bash
echo "==================================="
echo "Initializing ComfyUI workspace..."
echo "==================================="

# Debug: Show current state
echo "Current directory: $(pwd)"
echo "Checking /workspace contents:"
ls -la /workspace/ || echo "Cannot list /workspace"

# Check if ComfyUI is properly installed (not just directory exists)
if [ ! -f "/workspace/ComfyUI/main.py" ]; then
    echo "📦 ComfyUI not found or incomplete - Installing from GitHub..."
    
    # Remove empty or incomplete directory if it exists
    if [ -d "/workspace/ComfyUI" ]; then
        echo "Removing incomplete ComfyUI directory..."
        rm -rf /workspace/ComfyUI
    fi
    
    cd /workspace
    git clone https://github.com/comfyanonymous/ComfyUI.git ComfyUI || {
        echo "❌ Failed to clone ComfyUI!"
        echo "Trying alternative method..."
        mkdir -p /workspace/ComfyUI
        cd /workspace/ComfyUI
        git init
        git remote add origin https://github.com/comfyanonymous/ComfyUI.git
        git fetch --depth=1 origin main
        git checkout main
    }
    
    # Verify installation
    if [ -f "/workspace/ComfyUI/main.py" ]; then
        echo "✅ ComfyUI installed at /workspace/ComfyUI"
    else
        echo "❌ Installation failed - main.py not found"
        exit 1
    fi
else
    echo "✅ ComfyUI found at /workspace/ComfyUI (main.py exists)"
    
    # Optional: Update ComfyUI
    if [ "${COMFYUI_AUTO_UPDATE:-false}" == "true" ]; then
        echo "🔄 Updating ComfyUI..."
        cd /workspace/ComfyUI && git pull || echo "Could not update"
    fi
fi

# Ensure custom_nodes directory exists
mkdir -p /workspace/ComfyUI/custom_nodes

# Install baseline custom nodes if not present
if [ -f "/app/config/baseline-nodes.txt" ] && [ -d "/workspace/ComfyUI/custom_nodes" ]; then
    echo "📦 Checking custom nodes..."
    while IFS= read -r node || [ -n "$node" ]; do
        [[ "$node" =~ ^#.*$ ]] && continue
        [[ -z "$node" ]] && continue
        repo_name=$(echo "$node" | sed 's/.*\///')
        
        if [ ! -d "/workspace/ComfyUI/custom_nodes/$repo_name" ]; then
            echo "  Installing: $repo_name"
            cd /workspace/ComfyUI/custom_nodes
            git clone "https://github.com/$node" || echo "Failed to clone $node"
            
            # Run install.py if exists
            if [ -f "/workspace/ComfyUI/custom_nodes/$repo_name/install.py" ]; then
                cd "/workspace/ComfyUI/custom_nodes/$repo_name"
                python install.py || echo "Install script failed for $repo_name"
            fi
        else
            echo "  ✓ $repo_name already installed"
        fi
    done < /app/config/baseline-nodes.txt
fi

# Always ensure symlinks are correct
echo "Setting up symlinks..."
rm -rf /workspace/ComfyUI/models
ln -sf /workspace/models /workspace/ComfyUI/models
rm -rf /workspace/ComfyUI/output
rm -rf /workspace/ComfyUI/input
mkdir -p /workspace/ComfyUI/user

# Ensure all model directories exist
mkdir -p /workspace/models/checkpoints
mkdir -p /workspace/models/clip
mkdir -p /workspace/models/clip_vision
mkdir -p /workspace/models/configs
mkdir -p /workspace/models/controlnet
mkdir -p /workspace/models/diffusers
mkdir -p /workspace/models/embeddings
mkdir -p /workspace/models/gligen
mkdir -p /workspace/models/hypernetworks
mkdir -p /workspace/models/loras
mkdir -p /workspace/models/photomaker
mkdir -p /workspace/models/style_models
mkdir -p /workspace/models/unet
mkdir -p /workspace/models/upscale_models
mkdir -p /workspace/models/vae
mkdir -p /workspace/models/vae_approx

echo "✅ Initialization complete!"
EOF

RUN chmod +x /app/init_workspace.sh

# Copy UI application
COPY ui /app/ui

# Create start script that runs UI, JupyterLab and ComfyUI
RUN cat > /app/start.sh << 'EOF'
#!/bin/bash
echo "Initializing workspace..."
/app/init_workspace.sh
echo "Starting UI on port 7777..."
cd /app/ui && python app.py &
echo "Starting JupyterLab on port 8888..."
jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root --NotebookApp.token="" --NotebookApp.password="" --NotebookApp.allow_origin="*" --NotebookApp.disable_check_xsrf=True --ServerApp.allow_origin="*" --ServerApp.disable_check_xsrf=True --ServerApp.terminado_settings="shell_command=[\"bash\"]" &
echo "UI running on port 7777 - visit to start ComfyUI"
sleep infinity
EOF

RUN chmod +x /app/start.sh

# Create ComfyUI start script for UI to use
RUN cat > /app/start_comfyui.sh << 'EOF'
#!/bin/bash
echo "Starting ComfyUI..."

# Ensure workspace is initialized
/app/init_workspace.sh

# Verify ComfyUI exists
if [ ! -f "/workspace/ComfyUI/main.py" ]; then
    echo "❌ ERROR: ComfyUI main.py not found at /workspace/ComfyUI/main.py"
    echo "Contents of /workspace:"
    ls -la /workspace/
    echo "Contents of /workspace/ComfyUI (if exists):"
    ls -la /workspace/ComfyUI/ 2>/dev/null || echo "ComfyUI directory not found"
    exit 1
fi

# Start ComfyUI
cd /workspace/ComfyUI
echo "Starting ComfyUI from $(pwd)..."
python main.py --listen 0.0.0.0 --port 8188
EOF

RUN chmod +x /app/start_comfyui.sh

ENV HF_HOME="/workspace"

EXPOSE 7777 8188 8888
WORKDIR /workspace

# Start ComfyUI
CMD ["/app/start.sh"]