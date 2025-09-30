#!/bin/bash

# Fix PyTorch CUDA Detection Script
# This script fixes common issues preventing PyTorch from detecting CUDA in containers

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Fixing PyTorch CUDA Detection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Activate virtual environment if exists
if [ -d "/workspace/venv" ]; then
    source /workspace/venv/bin/activate
    echo "✅ Activated virtual environment"
fi

# Check NVIDIA driver
echo ""
echo "1️⃣ Checking NVIDIA Driver..."
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader || echo "nvidia-smi failed"
else
    echo "❌ nvidia-smi not found - GPU drivers may not be mounted"
    echo "   This is the likely cause of CUDA detection failure"
fi

# Check CUDA toolkit
echo ""
echo "2️⃣ Checking CUDA Toolkit..."
if command -v nvcc &> /dev/null; then
    nvcc --version | grep "release" || echo "nvcc version check failed"
else
    echo "⚠️ nvcc not found"
fi

# Check LD_LIBRARY_PATH
echo ""
echo "3️⃣ Checking CUDA Libraries..."
echo "LD_LIBRARY_PATH: ${LD_LIBRARY_PATH:-Not set}"

# Look for CUDA libraries
if [ -d "/usr/local/cuda/lib64" ]; then
    echo "✅ Found CUDA libraries at /usr/local/cuda/lib64"
    export LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH}"
fi

# Check PyTorch installation
echo ""
echo "4️⃣ Checking PyTorch Installation..."
python -c "
import torch
print(f'PyTorch Version: {torch.__version__}')
print(f'CUDA Built: {torch.version.cuda}')
print(f'CUDA Available: {torch.cuda.is_available()}')

if not torch.cuda.is_available():
    print('')
    print('⚠️ CUDA not available to PyTorch')
    print('Possible causes:')
    print('1. GPU drivers not properly mounted in container')
    print('2. PyTorch installed without CUDA support')
    print('3. CUDA version mismatch')
    print('')
    print('Attempting fixes...')

    # Check if this is a CPU-only PyTorch
    if 'cpu' in torch.__version__ or not torch.version.cuda:
        print('❌ PyTorch installed without CUDA support!')
        print('Need to reinstall PyTorch with CUDA')
    else:
        print('PyTorch has CUDA support but cannot detect GPU')
        print('This usually means GPU drivers are not accessible')
else:
    print(f'✅ CUDA is working!')
    print(f'GPU: {torch.cuda.get_device_name(0)}')
    print(f'GPU Memory: {torch.cuda.get_device_properties(0).total_memory / 1024**3:.1f} GB')
" 2>&1 || echo "Python check failed"

# Try to fix common issues
echo ""
echo "5️⃣ Attempting Automatic Fixes..."

# Fix 1: Export CUDA paths
export CUDA_HOME=/usr/local/cuda
export PATH=/usr/local/cuda/bin:${PATH}
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH}

# Fix 2: Check if we need to reinstall PyTorch
python -c "
import torch
if not torch.cuda.is_available() and torch.version.cuda:
    print('GPU drivers may not be accessible from container')
    print('This is a RunPod/Docker configuration issue')
    print('')
    print('Workarounds:')
    print('1. Restart the pod')
    print('2. Ensure GPU is allocated to the pod')
    print('3. Check RunPod GPU availability')
elif not torch.version.cuda:
    print('❌ PyTorch needs to be reinstalled with CUDA support')
    print('Run: pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121')
"

# Final verification
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Final Status:"
python -c "
import torch
if torch.cuda.is_available():
    print('✅ CUDA Detection FIXED!')
    print(f'   GPU: {torch.cuda.get_device_name(0)}')
else:
    print('❌ CUDA still not available')
    print('   This appears to be a container/driver issue')
    print('   Try restarting the RunPod pod')
" 2>&1

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"