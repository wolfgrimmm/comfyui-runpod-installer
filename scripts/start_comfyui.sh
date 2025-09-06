#!/bin/bash

# Install Flash Attention on first run if not already installed
if ! python -c "import flash_attn" 2>/dev/null; then
    echo "Installing Flash Attention packages (first run only)..."
    pip install --no-cache-dir \
        https://huggingface.co/MonsterMMORPG/SECourses_Premium_Flash_Attention/resolve/main/flash_attn-2.7.4.post1-cp310-cp310-linux_x86_64.whl \
        https://huggingface.co/MonsterMMORPG/SECourses_Premium_Flash_Attention/resolve/main/sageattention-2.1.1-cp310-cp310-linux_x86_64.whl \
        https://huggingface.co/MonsterMMORPG/SECourses_Premium_Flash_Attention/resolve/main/xformers-0.0.30+3abeaa9e.d20250427-cp310-cp310-linux_x86_64.whl || \
        echo "Warning: Flash Attention installation failed. ComfyUI will run without acceleration."
fi

fuser -k 8188/tcp 2>/dev/null || true
source /workspace/venv/bin/activate
export HF_HOME="/workspace"
export HF_HUB_ENABLE_HF_TRANSFER=1
cd /workspace/ComfyUI
echo "Starting ComfyUI on port 8188..."
python main.py --listen 0.0.0.0 --port 8188