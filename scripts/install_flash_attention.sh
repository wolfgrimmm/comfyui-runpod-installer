#!/bin/bash

echo "=========================================="
echo "🔥 Flash Attention Installation"
echo "=========================================="

source /workspace/venv/bin/activate

if python -c "import flash_attn" 2>/dev/null; then
    echo "✅ Flash Attention is already installed"
    exit 0
fi

echo "📦 Installing Flash Attention packages..."
pip install --no-cache-dir \
    https://huggingface.co/MonsterMMORPG/SECourses_Premium_Flash_Attention/resolve/main/flash_attn-2.7.4.post1-cp310-cp310-linux_x86_64.whl \
    https://huggingface.co/MonsterMMORPG/SECourses_Premium_Flash_Attention/resolve/main/sageattention-2.1.1-cp310-cp310-linux_x86_64.whl \
    https://huggingface.co/MonsterMMORPG/SECourses_Premium_Flash_Attention/resolve/main/xformers-0.0.30+3abeaa9e.d20250427-cp310-cp310-linux_x86_64.whl

if [ $? -eq 0 ]; then
    echo "✅ Flash Attention installed successfully!"
else
    echo "⚠️  Flash Attention installation failed but ComfyUI will still work"
fi