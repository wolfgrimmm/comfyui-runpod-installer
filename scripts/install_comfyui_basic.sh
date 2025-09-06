#!/bin/bash

# Basic ComfyUI Installation - Works on any RunPod template
# No Flash Attention, no complex dependencies - just working ComfyUI

set -e

echo "=========================================="
echo "🚀 Basic ComfyUI Installation"
echo "=========================================="

cd /workspace

# Clone ComfyUI if not exists
if [ ! -d "ComfyUI" ]; then
    echo "📥 Cloning ComfyUI..."
    git clone https://github.com/comfyanonymous/ComfyUI.git
else
    echo "✅ ComfyUI already exists"
fi

cd ComfyUI

# Upgrade PyTorch to 2.4+ for RMSNorm support
echo "🔥 Upgrading PyTorch to 2.4+..."
pip install --upgrade torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121

# Install basic requirements
echo "📦 Installing ComfyUI requirements..."
pip install -r requirements.txt

# Install useful but not critical packages
echo "📦 Installing additional packages..."
pip install opencv-python accelerate onnxruntime-gpu || true

# Install ComfyUI Manager (essential)
echo "🔧 Installing ComfyUI Manager..."
cd custom_nodes
if [ ! -d "ComfyUI-Manager" ]; then
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git
fi
cd ..

# Create directories
echo "📁 Creating directories..."
mkdir -p models/checkpoints
mkdir -p models/loras
mkdir -p models/vae
mkdir -p output
mkdir -p input

# Create simple start script
echo "📝 Creating start script..."
cat > /workspace/start_comfyui.sh << 'EOF'
#!/bin/bash
echo "Starting ComfyUI on port 8188..."
cd /workspace/ComfyUI
python main.py --listen 0.0.0.0 --port 8188
EOF

chmod +x /workspace/start_comfyui.sh

echo ""
echo "=========================================="
echo "✅ ComfyUI Installation Complete!"
echo "=========================================="
echo ""
echo "To start ComfyUI, run:"
echo "  /workspace/start_comfyui.sh"
echo ""
echo "Then access via RunPod's port 8188"
echo ""
echo "To install custom nodes:"
echo "  Use ComfyUI Manager in the UI"
echo "=========================================="