#!/bin/bash

# Install popular custom nodes - Run AFTER basic installation
# These are optional but useful

echo "=========================================="
echo "🔧 Installing Custom Nodes"
echo "=========================================="

cd /workspace/ComfyUI/custom_nodes

# Install IPAdapter Plus
if [ ! -d "ComfyUI_IPAdapter_plus" ]; then
    echo "📦 Installing IPAdapter Plus..."
    git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git
fi

# Install GGUF support
if [ ! -d "ComfyUI-GGUF" ]; then
    echo "📦 Installing GGUF support..."
    git clone https://github.com/city96/ComfyUI-GGUF.git
fi

# Install Impact Pack
if [ ! -d "ComfyUI-Impact-Pack" ]; then
    echo "📦 Installing Impact Pack..."
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git
    cd ComfyUI-Impact-Pack
    python install.py || true
    cd ..
fi

# Install ControlNet Aux
if [ ! -d "comfyui_controlnet_aux" ]; then
    echo "📦 Installing ControlNet Aux..."
    git clone https://github.com/Fannovel16/comfyui_controlnet_aux.git
    cd comfyui_controlnet_aux
    pip install -r requirements.txt || true
    cd ..
fi

# Install WAS Node Suite
if [ ! -d "was-node-suite-comfyui" ]; then
    echo "📦 Installing WAS Node Suite..."
    git clone https://github.com/WASasquatch/was-node-suite-comfyui.git
fi

echo ""
echo "✅ Custom nodes installed!"
echo "Restart ComfyUI to load new nodes"