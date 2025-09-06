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

# Install ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI && \
    cd /workspace/ComfyUI && \
    pip install --no-cache-dir -r requirements.txt

# Install additional AI packages
RUN pip install --no-cache-dir \
    onnxruntime-gpu \
    opencv-python \
    accelerate \
    diffusers

# Install custom nodes
RUN cd /workspace/ComfyUI/custom_nodes && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git && \
    git clone https://github.com/city96/ComfyUI-GGUF.git && \
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    cd ComfyUI-Impact-Pack && python install.py && cd ..

# Create directories and IMPORTANT symlinks for persistence
RUN mkdir -p /workspace/ComfyUI/models/checkpoints && \
    mkdir -p /workspace/ComfyUI/models/loras && \
    mkdir -p /workspace/ComfyUI/models/vae && \
    mkdir -p /workspace/ComfyUI/output && \
    mkdir -p /workspace/ComfyUI/input && \
    mkdir -p /workspace/ComfyUI/user/default/workflows && \
    ln -sf /workspace/ComfyUI/models /workspace/models && \
    ln -sf /workspace/ComfyUI/output /workspace/output && \
    ln -sf /workspace/ComfyUI/input /workspace/input && \
    ln -sf /workspace/ComfyUI/user/default/workflows /workspace/workflows

# Create simple start script
RUN echo '#!/bin/bash' > /workspace/start_comfyui.sh && \
    echo 'cd /workspace/ComfyUI' >> /workspace/start_comfyui.sh && \
    echo 'python main.py --listen 0.0.0.0 --port 8188' >> /workspace/start_comfyui.sh && \
    chmod +x /workspace/start_comfyui.sh

ENV HF_HOME="/workspace"

EXPOSE 8188
WORKDIR /workspace

# Start ComfyUI
CMD ["/workspace/start_comfyui.sh"]