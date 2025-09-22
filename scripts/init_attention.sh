#!/bin/bash
# Attention Mechanism Installation Script for ComfyUI
# Handles Flash Attention 2/3, Sage Attention, and xformers installation

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Installing Optimized Attention Mechanisms"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Detect Python version
PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
PYTHON_VERSION_NO_DOT=$(echo $PYTHON_VERSION | tr -d '.')
echo "📦 Detected Python version: $PYTHON_VERSION"

# Detect GPU for optimal configuration
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "Unknown")
echo "🔍 GPU detected: $GPU_NAME"

# Determine GPU type
if echo "$GPU_NAME" | grep -qE "H100|H200|H800"; then
    GPU_ARCH="hopper"
    CUDA_ARCH="9.0"
elif echo "$GPU_NAME" | grep -qE "RTX 4090|RTX 4080|RTX 4070|L40|L40S|RTX 6000 Ada"; then
    GPU_ARCH="ada"
    CUDA_ARCH="8.9"
elif echo "$GPU_NAME" | grep -qE "A100|A40|A30|A10"; then
    GPU_ARCH="ampere"
    CUDA_ARCH="8.0,8.6"
elif echo "$GPU_NAME" | grep -qE "RTX 3090|RTX 3080|RTX 3070|RTX 3060"; then
    GPU_ARCH="ampere"
    CUDA_ARCH="8.6"
elif echo "$GPU_NAME" | grep -qE "RTX 5090|RTX 5080|B200|B100"; then
    GPU_ARCH="blackwell"
    CUDA_ARCH="10.0"
else
    GPU_ARCH="unknown"
    CUDA_ARCH="7.5,8.0,8.6,8.9,9.0"
fi

echo "📊 GPU Architecture: $GPU_ARCH (CUDA Arch: $CUDA_ARCH)"

# Install Triton for GPU kernel compilation
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Installing Triton for GPU optimization..."
pip install triton --upgrade

# Clear Triton cache to prevent conflicts
echo "🧹 Clearing Triton cache..."
rm -rf ~/.triton 2>/dev/null || true
rm -rf /tmp/triton_* 2>/dev/null || true

# Install pre-built wheels with proper Python version
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Installing pre-compiled attention mechanisms..."

# Try to find the right wheel for Python version
if [ "$PYTHON_VERSION" == "3.11" ]; then
    CP_TAG="cp311"
elif [ "$PYTHON_VERSION" == "3.10" ]; then
    CP_TAG="cp310"
elif [ "$PYTHON_VERSION" == "3.9" ]; then
    CP_TAG="cp39"
else
    CP_TAG="cp310"  # Default fallback
fi

# 1. Install xformers (works for all GPUs)
echo "📦 Installing xformers 0.33..."
pip uninstall xformers -y 2>/dev/null || true
# Try abi3 wheel first (works with multiple Python versions)
if ! pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/xformers-0.0.33+c159edc0.d20250906-cp39-abi3-linux_x86_64.whl; then
    echo "⚠️ Pre-built xformers failed, installing from PyTorch index..."
    pip install xformers --index-url https://download.pytorch.org/whl/cu129
fi

# 2. Install Flash Attention 2 (for non-Hopper GPUs)
echo "📦 Installing Flash Attention 2.8.3..."
if [ "$GPU_ARCH" != "hopper" ]; then
    # Try pre-built wheel
    if ! pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/flash_attn-2.8.2-${CP_TAG}-${CP_TAG}-linux_x86_64.whl 2>/dev/null; then
        # Try alternative pre-built
        if ! pip install flash-attn --no-build-isolation; then
            echo "⚠️ Flash Attention 2 installation failed, will use xformers"
        fi
    fi
fi

# 3. Install Sage Attention (for Blackwell and newer)
echo "📦 Installing Sage Attention 2.2.0..."
# Try different Python versions
for PY_VER in $CP_TAG cp310 cp311; do
    if pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/sageattention-2.2.0-${PY_VER}-${PY_VER}-linux_x86_64.whl 2>/dev/null; then
        echo "✅ Sage Attention installed successfully"
        break
    fi
done

# 4. Install/Compile Flash Attention 3 for Hopper GPUs
if [ "$GPU_ARCH" == "hopper" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚡ Hopper GPU detected - Installing Flash Attention 3"

    # Check if FA3 is already installed
    if python -c "import flash_attn; v=flash_attn.__version__; exit(0 if v.startswith('3') else 1)" 2>/dev/null; then
        echo "✅ Flash Attention 3 already installed"
    else
        echo "🔨 Compiling Flash Attention 3 for maximum performance..."
        echo "   This will take 15-30 minutes during Docker build"

        # Uninstall any existing flash-attn
        pip uninstall flash-attn -y 2>/dev/null || true

        # Install build dependencies
        pip install ninja packaging wheel

        # Clone and compile FA3
        cd /tmp
        rm -rf flash-attention 2>/dev/null || true
        git clone https://github.com/Dao-AILab/flash-attention.git
        cd flash-attention

        # Check if hopper branch exists, otherwise use main with FA3
        if git ls-remote --heads origin hopper | grep -q hopper; then
            git checkout hopper
        else
            # Use main branch and ensure we get v3
            git checkout main
            # Check for v3 tags
            LATEST_V3_TAG=$(git tag -l "v3.*" | sort -V | tail -1)
            if [ -n "$LATEST_V3_TAG" ]; then
                git checkout $LATEST_V3_TAG
                echo "Using Flash Attention $LATEST_V3_TAG"
            fi
        fi

        # Set environment for Hopper compilation
        export TORCH_CUDA_ARCH_LIST="9.0"
        export MAX_JOBS=16  # Limit parallel jobs to prevent OOM
        export FLASH_ATTENTION_FORCE_BUILD=TRUE
        export FLASH_ATTENTION_SKIP_CUDA_BUILD=FALSE

        # Build and install
        python setup.py build
        python setup.py install

        # Cleanup
        cd /
        rm -rf /tmp/flash-attention

        # Verify installation
        if python -c "import flash_attn; print(f'Flash Attention {flash_attn.__version__} installed')" 2>/dev/null; then
            echo "✅ Flash Attention 3 compilation successful!"
        else
            echo "⚠️ Flash Attention 3 compilation failed, falling back to Flash Attention 2"
            pip install flash-attn --no-build-isolation
        fi
    fi
fi

# Install additional optimization libraries
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Installing additional optimization libraries..."

# DeepSpeed for training optimizations
pip install deepspeed --upgrade

# Accelerate for Hugging Face models
pip install accelerate --upgrade

# Install insightface for face models
for PY_VER in $CP_TAG cp310 cp311; do
    if pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/insightface-0.7.3-${PY_VER}-${PY_VER}-linux_x86_64.whl 2>/dev/null; then
        break
    fi
done

# Verify installations
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Verifying attention mechanism installations..."

# Check what's installed
echo ""
python -c "
import importlib
import sys

mechanisms = {
    'xformers': 'xformers',
    'flash_attn': 'Flash Attention',
    'sageattention': 'Sage Attention',
    'triton': 'Triton'
}

installed = []
for module, name in mechanisms.items():
    try:
        mod = importlib.import_module(module)
        version = getattr(mod, '__version__', 'unknown')
        installed.append(f'✅ {name} ({version})')
        if module == 'flash_attn':
            # Check if it's v3
            if version.startswith('3'):
                print(f'   🚀 Flash Attention 3 detected - Hopper optimized!')
    except ImportError:
        pass

if installed:
    print('Installed attention mechanisms:')
    for item in installed:
        print(f'   {item}')
else:
    print('⚠️ No attention mechanisms found!')
" || echo "⚠️ Could not verify installations"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Attention mechanism setup complete!"

# Create environment file for ComfyUI to know what's available
cat > /workspace/venv/.attention_config << EOF
# Attention Mechanisms Installed
GPU_NAME=$GPU_NAME
GPU_ARCH=$GPU_ARCH
CUDA_ARCH=$CUDA_ARCH
PYTHON_VERSION=$PYTHON_VERSION
TIMESTAMP=$(date)
EOF

# List what's available
if python -c "import flash_attn; exit(0 if flash_attn.__version__.startswith('3') else 1)" 2>/dev/null; then
    echo "FLASH_ATTENTION_VERSION=3" >> /workspace/venv/.attention_config
elif python -c "import flash_attn" 2>/dev/null; then
    echo "FLASH_ATTENTION_VERSION=2" >> /workspace/venv/.attention_config
fi

python -c "import xformers" 2>/dev/null && echo "XFORMERS_AVAILABLE=true" >> /workspace/venv/.attention_config
python -c "import sageattention" 2>/dev/null && echo "SAGE_ATTENTION_AVAILABLE=true" >> /workspace/venv/.attention_config

echo "Configuration saved to /workspace/venv/.attention_config"