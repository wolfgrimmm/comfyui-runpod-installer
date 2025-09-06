#!/bin/bash

# Optional Flash Attention installation
# May fail depending on CUDA version - that's OK

echo "=========================================="
echo "⚡ Flash Attention Installation (Optional)"
echo "=========================================="
echo ""
echo "⚠️  This may fail depending on your CUDA version"
echo "ComfyUI works fine without it!"
echo ""

# Try to install Flash Attention
echo "Attempting to install Flash Attention..."

pip install --no-cache-dir \
    https://huggingface.co/MonsterMMORPG/SECourses_Premium_Flash_Attention/resolve/main/flash_attn-2.7.4.post1-cp310-cp310-linux_x86_64.whl \
    https://huggingface.co/MonsterMMORPG/SECourses_Premium_Flash_Attention/resolve/main/sageattention-2.1.1-cp310-cp310-linux_x86_64.whl \
    https://huggingface.co/MonsterMMORPG/SECourses_Premium_Flash_Attention/resolve/main/xformers-0.0.30+3abeaa9e.d20250427-cp310-cp310-linux_x86_64.whl \
    2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ Flash Attention installed successfully!"
    echo "You can use --use-sage-attention flag when starting ComfyUI"
else
    echo "⚠️  Flash Attention installation failed"
    echo "This is OK - ComfyUI will work without it"
fi