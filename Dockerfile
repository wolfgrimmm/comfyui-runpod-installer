# RTX 5090 Optimized with CUDA 12.4
FROM nvidia/cuda:12.4.0-devel-ubuntu22.04

WORKDIR /workspace
ENV DEBIAN_FRONTEND=noninteractive

# Install Python, git, wget, psmisc (for fuser), lsof
RUN apt-get update && \
    apt-get install -y python3.10 python3-pip git wget psmisc lsof && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    ln -s /usr/bin/python3 /usr/bin/python

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
    mkdir -p /workspace/models/loras && \
    mkdir -p /workspace/models/vae && \
    mkdir -p /workspace/models/controlnet && \
    mkdir -p /workspace/output && \
    mkdir -p /workspace/input && \
    mkdir -p /workspace/workflows && \
    mkdir -p /workspace/user_data

# Create app directory for scripts
RUN mkdir -p /app

# Create initialization script to set up ComfyUI in workspace on first run
RUN cat > /app/init_workspace.sh << 'EOF'
#!/bin/bash
echo "Initializing ComfyUI workspace..."

# Check if ComfyUI exists
if [ ! -d "/workspace/ComfyUI" ]; then
    echo "📦 ComfyUI not found - Installing from GitHub..."
    git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI
    echo "✅ ComfyUI installed"
else
    echo "✅ ComfyUI found - skipping installation"
    
    # Optional: Update ComfyUI
    if [ "${COMFYUI_AUTO_UPDATE:-false}" == "true" ]; then
        echo "🔄 Updating ComfyUI..."
        cd /workspace/ComfyUI && git pull
    fi
fi

# Install baseline custom nodes if not present
if [ -f "/app/config/baseline-nodes.txt" ]; then
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
            if [ -f "$repo_name/install.py" ]; then
                cd "$repo_name" && python install.py
            fi
        fi
    done < /app/config/baseline-nodes.txt
fi

# Always ensure symlinks are correct
rm -rf /workspace/ComfyUI/models
ln -sf /workspace/models /workspace/ComfyUI/models
rm -rf /workspace/ComfyUI/output
rm -rf /workspace/ComfyUI/input
mkdir -p /workspace/ComfyUI/user
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
/app/init_workspace.sh
cd /workspace/ComfyUI
python main.py --listen 0.0.0.0 --port 8188
EOF

RUN chmod +x /app/start_comfyui.sh

ENV HF_HOME="/workspace"

EXPOSE 7777 8188 8888
WORKDIR /workspace

# Start ComfyUI
CMD ["/app/start.sh"]