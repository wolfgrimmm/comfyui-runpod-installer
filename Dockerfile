# RTX 5090 Optimized with CUDA 12.4
FROM nvidia/cuda:12.4.0-devel-ubuntu22.04

WORKDIR /workspace
ENV DEBIAN_FRONTEND=noninteractive

# Install Python, git, wget, psmisc (for fuser), lsof, curl, and other dependencies
RUN apt-get update && \
    apt-get install -y python3.10 python3-pip git wget psmisc lsof curl unzip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    ln -s /usr/bin/python3 /usr/bin/python

# Install rclone separately with error handling
RUN curl -O https://downloads.rclone.org/rclone-current-linux-amd64.zip && \
    unzip rclone-current-linux-amd64.zip && \
    cd rclone-*-linux-amd64 && \
    cp rclone /usr/bin/ && \
    chown root:root /usr/bin/rclone && \
    chmod 755 /usr/bin/rclone && \
    cd .. && \
    rm -rf rclone-*-linux-amd64* && \
    rclone version || echo "rclone installation completed"

# Install PyTorch with CUDA 12.4 for RTX 5090
RUN pip3 install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124

# Install ComfyUI requirements without cloning ComfyUI itself
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /tmp/comfyui-req && \
    pip install --no-cache-dir -r /tmp/comfyui-req/requirements.txt && \
    rm -rf /tmp/comfyui-req

# Install additional AI packages, JupyterLab, UI dependencies, and ComfyUI Manager requirements
RUN pip install --no-cache-dir \
    onnxruntime-gpu \
    opencv-python \
    accelerate \
    diffusers \
    jupyterlab \
    ipywidgets \
    notebook \
    flask==3.0.0 \
    psutil==5.9.0 \
    requests==2.31.0 \
    GitPython \
    PyGithub \
    matrix-client==0.4.0 \
    transformers \
    safetensors

# Create workspace directories structure (matching official ComfyUI)
RUN mkdir -p /workspace/models/audio_encoders && \
    mkdir -p /workspace/models/checkpoints && \
    mkdir -p /workspace/models/clip && \
    mkdir -p /workspace/models/clip_vision && \
    mkdir -p /workspace/models/configs && \
    mkdir -p /workspace/models/controlnet && \
    mkdir -p /workspace/models/diffusers && \
    mkdir -p /workspace/models/diffusion_models && \
    mkdir -p /workspace/models/embeddings && \
    mkdir -p /workspace/models/gligen && \
    mkdir -p /workspace/models/hypernetworks && \
    mkdir -p /workspace/models/loras && \
    mkdir -p /workspace/models/model_patches && \
    mkdir -p /workspace/models/photomaker && \
    mkdir -p /workspace/models/style_models && \
    mkdir -p /workspace/models/text_encoders && \
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

# Copy scripts first (needed for init_workspace.sh)
COPY scripts /app/scripts
RUN chmod +x /app/scripts/*.sh 2>/dev/null || true

# Copy UI application
COPY ui /app/ui

# Copy configuration files
COPY config /app/config

# Link the universal initialization script
RUN ln -sf /app/scripts/init_universal.sh /app/init_workspace.sh && \
    chmod +x /app/init_workspace.sh

# Create start script that runs UI, JupyterLab and ComfyUI
RUN cat > /app/start.sh << 'EOF'
#!/bin/bash
echo "Initializing workspace..."
/app/init_workspace.sh

# Auto-configure Google Drive from RunPod Secrets
if [ -f "/app/scripts/init_gdrive.sh" ]; then
    echo "Checking Google Drive configuration..."
    /app/scripts/init_gdrive.sh || true
fi

# Activate venv if it was created
if [ -f "/workspace/venv/bin/activate" ]; then
    echo "Activating virtual environment..."
    source /workspace/venv/bin/activate
fi

echo "Starting UI on port 7777..."
cd /app/ui && python app.py > /workspace/ui.log 2>&1 &
sleep 2
if ! lsof -i:7777 > /dev/null 2>&1; then
    echo "WARNING: UI failed to start on port 7777"
    echo "Check /workspace/ui.log for errors"
    if [ -f /workspace/ui.log ]; then
        echo "Last 20 lines of UI log:"
        tail -20 /workspace/ui.log
    fi
else
    echo "UI successfully started on port 7777"
fi
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

# Activate venv if it exists
if [ -f "/workspace/venv/bin/activate" ]; then
    source /workspace/venv/bin/activate
fi

# Verify ComfyUI exists
if [ ! -f "/workspace/ComfyUI/main.py" ]; then
    echo "❌ ERROR: ComfyUI main.py not found at /workspace/ComfyUI/main.py"
    echo "Contents of /workspace:"
    ls -la /workspace/
    echo "Contents of /workspace/ComfyUI (if exists):"
    ls -la /workspace/ComfyUI/ 2>/dev/null || echo "ComfyUI directory not found"
    exit 1
fi

# Verify Manager installation
if [ -d "/workspace/ComfyUI/custom_nodes/ComfyUI-Manager" ]; then
    echo "✅ ComfyUI Manager is installed"
    ls -la /workspace/ComfyUI/custom_nodes/ComfyUI-Manager/ | head -5
else
    echo "⚠️ ComfyUI Manager not found - attempting reinstall..."
    cd /workspace/ComfyUI/custom_nodes
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git
    if [ -f "ComfyUI-Manager/requirements.txt" ]; then
        pip install -r ComfyUI-Manager/requirements.txt
    fi
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