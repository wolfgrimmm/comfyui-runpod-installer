#!/bin/bash

echo "🔧 Installing AI Toolkit on RunPod..."
echo ""

# Navigate to workspace
cd /workspace

# Clone repository
if [ -d "ai-toolkit" ]; then
    echo "⚠️  ai-toolkit directory already exists, removing..."
    rm -rf ai-toolkit
fi

echo "📥 Cloning ai-toolkit repository..."
git clone https://github.com/ostris/ai-toolkit.git
cd ai-toolkit

# Create separate virtual environment for ai-toolkit
echo "🐍 Creating separate virtual environment for ai-toolkit..."
echo "   (This prevents conflicts with ComfyUI dependencies)"
python3 -m venv venv

# Activate the new venv
source venv/bin/activate

# Upgrade pip
echo ""
echo "📦 Upgrading pip..."
pip install --upgrade pip wheel setuptools

# Install PyTorch 2.8.0 with CUDA 12.9 (matching your RTX 5090 setup)
echo ""
echo "📦 Installing PyTorch 2.8.0 with CUDA 12.9..."
echo "   (Using cu129 for RTX 5090 compatibility)"
pip3 install --no-cache-dir torch==2.8.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu129

# Verify PyTorch installation
echo ""
echo "✅ Verifying PyTorch installation..."
python3 -c "import torch; print(f'PyTorch: {torch.__version__}'); print(f'CUDA Available: {torch.cuda.is_available()}'); print(f'CUDA Version: {torch.version.cuda}')"

# Install ai-toolkit requirements
echo ""
echo "📦 Installing ai-toolkit requirements..."
pip3 install -r requirements.txt

# Verify installation
echo ""
echo "✅ AI Toolkit installed successfully in separate environment!"
echo ""
echo "To use ai-toolkit:"
echo "  cd /workspace/ai-toolkit"
echo "  source venv/bin/activate"
echo "  python3 your_script.py"
echo ""
echo "To switch back to ComfyUI environment:"
echo "  source /workspace/venv/bin/activate"
echo ""
