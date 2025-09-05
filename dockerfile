# Optimized for caching - rarely changing items first, scripts last
FROM nvidia/cuda:12.9.0-devel-ubuntu22.04

WORKDIR /workspace
ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_NO_CACHE_DIR=1

# Layer 1: System dependencies (rarely changes)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.10 python3.10-dev python3-pip python3.10-venv \
    curl git psmisc && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Layer 2: Python venv (rarely changes)
RUN python3 -m venv /workspace/venv && \
    . /workspace/venv/bin/activate && \
    pip install --no-cache-dir --upgrade pip setuptools wheel

ENV PATH="/workspace/venv/bin:$PATH"
ENV VIRTUAL_ENV="/workspace/venv"

# Layer 3: PyTorch (changes only when upgrading versions)
RUN pip install --no-cache-dir torch==2.7.1 torchvision==0.22.1 torchaudio==2.7.1 --index-url https://download.pytorch.org/whl/cu128 && \
    rm -rf /root/.cache/pip/*

# Layer 4: ComfyUI core (changes when updating ComfyUI)
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI && \
    cd /workspace/ComfyUI && \
    pip install --no-cache-dir -r requirements.txt && \
    rm -rf /root/.cache/pip/*

# Layer 5: AI packages (changes occasionally)
RUN pip install --no-cache-dir \
    https://huggingface.co/deauxpas/colabrepo/resolve/main/insightface-0.7.3-cp310-cp310-linux_x86_64.whl \
    onnxruntime-gpu \
    accelerate \
    diffusers && \
    rm -rf /root/.cache/pip/*

# Layer 6: Additional packages (changes occasionally)
RUN pip install --no-cache-dir \
    piexif \
    triton \
    requests \
    huggingface_hub \
    hf_transfer && \
    rm -rf /root/.cache/pip/*

# Layer 7: Custom nodes (changes when adding/removing nodes)
RUN cd /workspace/ComfyUI/custom_nodes && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git && \
    git clone https://github.com/city96/ComfyUI-GGUF.git

# Layer 8: Flash Attention (changes rarely)
RUN pip install --no-cache-dir \
    https://huggingface.co/MonsterMMORPG/SECourses_Premium_Flash_Attention/resolve/main/flash_attn-2.7.4.post1-cp310-cp310-linux_x86_64.whl \
    https://huggingface.co/MonsterMMORPG/SECourses_Premium_Flash_Attention/resolve/main/sageattention-2.1.1-cp310-cp310-linux_x86_64.whl \
    https://huggingface.co/MonsterMMORPG/SECourses_Premium_Flash_Attention/resolve/main/xformers-0.0.30+3abeaa9e.d20250427-cp310-cp310-linux_x86_64.whl && \
    rm -rf /root/.cache/pip/*

# Layer 9: Directory structure (changes rarely)
RUN mkdir -p /workspace/models /workspace/workflows /workspace/output && \
    ln -sf /workspace/ComfyUI/models /workspace/models || true && \
    ln -sf /workspace/ComfyUI/output /workspace/output || true && \
    mkdir -p /workspace/ComfyUI/user/default/workflows && \
    ln -sf /workspace/ComfyUI/user/default/workflows /workspace/workflows || true

# Layer 10: Scripts (changes frequently - put last for fast rebuilds)
RUN echo '#!/bin/bash' > /workspace/start_comfyui.sh && \
    echo 'fuser -k 8188/tcp 2>/dev/null || true' >> /workspace/start_comfyui.sh && \
    echo 'source /workspace/venv/bin/activate' >> /workspace/start_comfyui.sh && \
    echo 'export HF_HOME="/workspace"' >> /workspace/start_comfyui.sh && \
    echo 'export HF_HUB_ENABLE_HF_TRANSFER=1' >> /workspace/start_comfyui.sh && \
    echo 'cd /workspace/ComfyUI' >> /workspace/start_comfyui.sh && \
    echo 'echo "Starting ComfyUI on port 8188..."' >> /workspace/start_comfyui.sh && \
    echo 'python main.py --listen 0.0.0.0 --port 8188' >> /workspace/start_comfyui.sh && \
    chmod +x /workspace/start_comfyui.sh && \
    ln -sf /workspace/start_comfyui.sh /start_comfyui.sh && \
    ln -sf /workspace/start_comfyui.sh /start.sh

# Set environment variables
ENV HF_HOME="/workspace"
ENV HF_HUB_ENABLE_HF_TRANSFER=1

EXPOSE 8188
EXPOSE 8888
EXPOSE 22
WORKDIR /workspace

# RunPod expects no CMD or a sleep command to keep container running
# ComfyUI should be started manually via JupyterLab terminal
CMD ["sleep", "infinity"]