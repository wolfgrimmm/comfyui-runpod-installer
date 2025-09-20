#!/bin/bash

# Script to upgrade existing venv to CUDA 12.9 compatible packages
# Run this if you have an existing venv from before the CUDA 12.9 upgrade

echo "=========================================="
echo "🔄 Upgrading venv for CUDA 12.9"
echo "=========================================="

# Check if venv exists
if [ ! -d "/workspace/venv" ]; then
    echo "❌ No venv found at /workspace/venv"
    echo "Run /app/init.sh to create a new venv"
    exit 1
fi

# Activate venv
echo "📦 Activating virtual environment..."
source /workspace/venv/bin/activate

# Upgrade pip first
echo "📦 Upgrading pip..."
pip install --upgrade pip wheel setuptools

# Reinstall PyTorch with CUDA 12.4 support (compatible with CUDA 12.9)
echo "🔄 Reinstalling PyTorch for CUDA 12.9..."
pip uninstall torch torchvision torchaudio -y
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124

# Reinstall ONNX Runtime for CUDA 12.x
echo "🔄 Reinstalling ONNX Runtime for CUDA 12.x..."
pip uninstall onnxruntime onnxruntime-gpu -y
pip install onnxruntime-gpu==1.19.2

# Install Flash Attention 3 and xformers
echo "🔄 Installing Flash Attention 3 and xformers..."
pip install ninja packaging triton
pip install flash-attn --no-build-isolation 2>/dev/null || echo "Flash Attention not available"
pip install xformers==0.0.28 --index-url https://download.pytorch.org/whl/cu124 2>/dev/null || echo "xformers not available"

# Verify CUDA availability
echo ""
echo "🔍 Verifying CUDA compatibility..."
python -c "
import torch
print(f'PyTorch version: {torch.__version__}')
print(f'CUDA available: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'CUDA version: {torch.version.cuda}')
    print(f'GPU: {torch.cuda.get_device_name(0)}')
    print(f'✅ CUDA 12.9 compatible packages installed!')
else:
    print('⚠️ CUDA not detected - this might be normal if running outside of GPU environment')
"

# Mark venv as upgraded
touch /workspace/venv/.cuda129_upgraded

echo ""
echo "✅ Venv upgraded for CUDA 12.9 compatibility!"
echo ""
echo "To use the upgraded venv:"
echo "  source /workspace/venv/bin/activate"