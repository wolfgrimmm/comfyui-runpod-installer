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

# Clone ComfyUI to temp location for later copying
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI-install && \
    cd /opt/ComfyUI-install && \
    pip install --no-cache-dir -r requirements.txt

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

# Install custom nodes to temp location
RUN cd /opt/ComfyUI-install/custom_nodes && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git && \
    git clone https://github.com/city96/ComfyUI-GGUF.git && \
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    cd ComfyUI-Impact-Pack && python install.py && cd ..

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
if [ ! -d "/workspace/ComfyUI" ]; then
    echo "First run detected - setting up ComfyUI in /workspace..."
    cp -r /opt/ComfyUI-install /workspace/ComfyUI
    echo "ComfyUI copied to /workspace"
fi
# Always ensure symlinks are correct
rm -rf /workspace/ComfyUI/models
ln -sf /workspace/models /workspace/ComfyUI/models
rm -rf /workspace/ComfyUI/output
rm -rf /workspace/ComfyUI/input
mkdir -p /workspace/ComfyUI/user
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