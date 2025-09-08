#!/bin/bash
# Optimize downloads for RunPod - use fastest mirrors and parallel downloads

echo "🚀 Optimizing downloads for RunPod..."

# Use aria2 for parallel downloads (much faster)
apt-get update && apt-get install -y aria2

# Function to download with aria2 (16 connections)
fast_download() {
    url=$1
    output=$2
    echo "Downloading $output with aria2..."
    aria2c -x 16 -s 16 -k 1M "$url" -o "$output"
}

# Use GitHub mirrors when possible (faster than pytorch.org)
echo "Installing PyTorch from fastest mirror..."

# Option 1: Use pip with faster index
pip install torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/cu124 \
    --extra-index-url https://pypi.org/simple \
    --trusted-host pypi.org \
    --trusted-host files.pythonhosted.org

# Option 2: For large files, use aria2
# fast_download "https://download.pytorch.org/whl/cu124/torch-2.1.0-cp310-linux_x86_64.whl" "torch.whl"
# pip install torch.whl

# Clone from GitHub with depth=1 (faster)
echo "Cloning ComfyUI (shallow clone)..."
git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI

# Use git sparse-checkout for custom nodes (only download what's needed)
echo "Installing custom nodes (optimized)..."
cd /workspace/ComfyUI/custom_nodes

# Shallow clone for faster downloads
git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Manager.git

# For Python packages, use faster mirrors
pip config set global.index-url https://pypi.org/simple
pip config set global.extra-index-url https://pypi.python.org/simple

echo "✅ Download optimization complete!"