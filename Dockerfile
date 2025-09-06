# RTX 5090 Optimized - Using RunPod's base image
FROM runpod/pytorch:2.8.0-py3.11-cuda12.8-devel-ubuntu22.04

WORKDIR /workspace
ENV DEBIAN_FRONTEND=noninteractive

# RunPod image already has Python 3.11 and PyTorch 2.8.0 with CUDA 12.8!
# Just need git and wget
RUN apt-get update && \
    apt-get install -y git wget && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install ComfyUI to /app (NOT /workspace which is for volumes)
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /app/ComfyUI && \
    cd /app/ComfyUI && \
    pip install --no-cache-dir -r requirements.txt

# Install additional AI packages
RUN pip install --no-cache-dir \
    onnxruntime-gpu \
    opencv-python \
    accelerate \
    diffusers

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

# Create simple start script
RUN echo '#!/bin/bash' > /app/start.sh && \
    echo 'cd /app/ComfyUI' >> /app/start.sh && \
    echo 'python main.py --listen 0.0.0.0 --port 8188' >> /app/start.sh && \
    chmod +x /app/start.sh

ENV HF_HOME="/workspace"

EXPOSE 8188
WORKDIR /workspace

# Start ComfyUI
CMD ["/app/start.sh"]