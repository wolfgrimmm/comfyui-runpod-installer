# Split installation into multiple layers to avoid storage exhaustion
FROM nvidia/cuda:12.9.0-devel-ubuntu22.04

WORKDIR /workspace
ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_NO_CACHE_DIR=1

# Layer 1: System dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.10 python3.10-dev python3-pip python3.10-venv \
    curl git psmisc && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Layer 2: Create venv and upgrade pip
RUN python3 -m venv /workspace/venv && \
    . /workspace/venv/bin/activate && \
    pip install --no-cache-dir --upgrade pip setuptools wheel

ENV PATH="/workspace/venv/bin:$PATH"
ENV VIRTUAL_ENV="/workspace/venv"

# Layer 3: Install PyTorch first (largest package)
RUN pip install --no-cache-dir torch==2.7.1 torchvision==0.22.1 torchaudio==2.7.1 --index-url https://download.pytorch.org/whl/cu128 && \
    rm -rf /root/.cache/pip/*

# Layer 4: Clone ComfyUI and install base requirements
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI && \
    cd /workspace/ComfyUI && \
    pip install --no-cache-dir -r requirements.txt && \
    rm -rf /root/.cache/pip/*

# Layer 5: Install AI packages
RUN pip install --no-cache-dir \
    https://huggingface.co/deauxpas/colabrepo/resolve/main/insightface-0.7.3-cp310-cp310-linux_x86_64.whl \
    onnxruntime-gpu \
    accelerate \
    diffusers && \
    rm -rf /root/.cache/pip/*

# Layer 6: Install additional packages
RUN pip install --no-cache-dir \
    piexif \
    triton \
    requests \
    huggingface_hub \
    hf_transfer && \
    rm -rf /root/.cache/pip/*

# Layer 7: Clone custom nodes (lightweight)
RUN cd /workspace/ComfyUI/custom_nodes && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git && \
    git clone https://github.com/city96/ComfyUI-GGUF.git

# Layer 8: Install Flash Attention wheels
RUN pip install --no-cache-dir \
    https://huggingface.co/MonsterMMORPG/SECourses_Premium_Flash_Attention/resolve/main/flash_attn-2.7.4.post1-cp310-cp310-linux_x86_64.whl \
    https://huggingface.co/MonsterMMORPG/SECourses_Premium_Flash_Attention/resolve/main/sageattention-2.1.1-cp310-cp310-linux_x86_64.whl \
    https://huggingface.co/MonsterMMORPG/SECourses_Premium_Flash_Attention/resolve/main/xformers-0.0.30+3abeaa9e.d20250427-cp310-cp310-linux_x86_64.whl && \
    rm -rf /root/.cache/pip/*

# Create directories and startup script
RUN mkdir -p /workspace/models /workspace/workflows /workspace/output && \
    ln -sf /workspace/ComfyUI/models /workspace/models && \
    ln -sf /workspace/ComfyUI/output /workspace/output && \
    mkdir -p /workspace/ComfyUI/user/default/workflows && \
    ln -sf /workspace/ComfyUI/user/default/workflows /workspace/workflows

# Create startup script
RUN echo '#!/bin/bash' > /workspace/start_comfyui.sh && \
    echo 'fuser -k 8188/tcp 2>/dev/null || true' >> /workspace/start_comfyui.sh && \
    echo 'source /workspace/venv/bin/activate' >> /workspace/start_comfyui.sh && \
    echo 'export HF_HOME="/workspace"' >> /workspace/start_comfyui.sh && \
    echo 'export HF_HUB_ENABLE_HF_TRANSFER=1' >> /workspace/start_comfyui.sh && \
    echo 'cd /workspace/ComfyUI' >> /workspace/start_comfyui.sh && \
    echo 'echo "Starting ComfyUI on port 8188..."' >> /workspace/start_comfyui.sh && \
    echo 'python main.py --listen 0.0.0.0 --port 8188' >> /workspace/start_comfyui.sh

RUN chmod +x /workspace/start_comfyui.sh && \
    ln -sf /workspace/start_comfyui.sh /start_comfyui.sh && \
    ln -sf /workspace/start_comfyui.sh /start.sh

# Set environment variables
ENV HF_HOME="/workspace"
ENV HF_HUB_ENABLE_HF_TRANSFER=1

EXPOSE 8188
WORKDIR /workspace
CMD ["/bin/bash", "/workspace/start_comfyui.sh"]