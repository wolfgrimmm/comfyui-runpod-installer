# RTX 5090 Optimized with CUDA 12.4
FROM nvidia/cuda:12.4.0-devel-ubuntu22.04

WORKDIR /workspace
ENV DEBIAN_FRONTEND=noninteractive

# Install Python, git, wget
RUN apt-get update && \
    apt-get install -y python3.10 python3-pip git wget && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    ln -s /usr/bin/python3 /usr/bin/python

# Install PyTorch with CUDA 12.4 for RTX 5090
RUN pip3 install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124

# Install ComfyUI to /app (NOT /workspace which is for volumes)
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /app/ComfyUI && \
    cd /app/ComfyUI && \
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

# Install custom nodes
RUN cd /app/ComfyUI/custom_nodes && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git && \
    git clone https://github.com/city96/ComfyUI-GGUF.git && \
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    cd ComfyUI-Impact-Pack && python install.py && cd ..

# Create workspace directories for network volume
RUN mkdir -p /workspace/models/checkpoints && \
    mkdir -p /workspace/models/loras && \
    mkdir -p /workspace/models/vae && \
    mkdir -p /workspace/output && \
    mkdir -p /workspace/input && \
    mkdir -p /workspace/workflows

# Link ComfyUI to use workspace directories
RUN rm -rf /app/ComfyUI/models && ln -sf /workspace/models /app/ComfyUI/models && \
    rm -rf /app/ComfyUI/output && ln -sf /workspace/output /app/ComfyUI/output && \
    rm -rf /app/ComfyUI/input && ln -sf /workspace/input /app/ComfyUI/input && \
    mkdir -p /app/ComfyUI/user/default && \
    ln -sf /workspace/workflows /app/ComfyUI/user/default/workflows

# Copy UI application
COPY ui /app/ui

# Create start script that runs UI, JupyterLab and ComfyUI
RUN echo '#!/bin/bash' > /app/start.sh && \
    echo 'echo "Starting UI on port 7777..."' >> /app/start.sh && \
    echo 'cd /app/ui && python app.py &' >> /app/start.sh && \
    echo 'echo "Starting JupyterLab on port 8888..."' >> /app/start.sh && \
    echo 'jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root --NotebookApp.token="" --NotebookApp.password="" --ServerApp.terminado_settings="shell_command=[\"bash\"]" &' >> /app/start.sh && \
    echo 'echo "Waiting for UI to handle ComfyUI startup..."' >> /app/start.sh && \
    echo 'sleep infinity' >> /app/start.sh && \
    chmod +x /app/start.sh

# Create ComfyUI start script for UI to use
RUN echo '#!/bin/bash' > /app/start_comfyui.sh && \
    echo 'cd /app/ComfyUI' >> /app/start_comfyui.sh && \
    echo 'python main.py --listen 0.0.0.0 --port 8188' >> /app/start_comfyui.sh && \
    chmod +x /app/start_comfyui.sh

ENV HF_HOME="/workspace"

EXPOSE 7777 8188 8888
WORKDIR /workspace

# Start ComfyUI
CMD ["/app/start.sh"]