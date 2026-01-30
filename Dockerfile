# Optimized for RunPod Pods - Uses RunPod's PyTorch base
# Using latest available RunPod image with CUDA 12.4 (we'll upgrade to 12.9)
FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

WORKDIR /

# Install system dependencies including Python build tools and ffmpeg
RUN apt-get update && apt-get install -y \
    git wget curl psmisc lsof unzip \
    python3.11-dev python3.11-venv python3-pip \
    build-essential software-properties-common \
    ffmpeg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Use CUDA 12.4 from base image (runtime only - just drivers)
# PyTorch 2.8.0 cu129 brings its own CUDA 12.9 libraries in the wheel
# No CUDA toolkit installation needed - avoids version conflicts
ENV PATH="/usr/local/cuda-12.4/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/cuda-12.4/lib64:${LD_LIBRARY_PATH}"
ENV CUDA_HOME="/usr/local/cuda-12.4"
ENV CUDA_VERSION="12.4"

# Create app directory
RUN mkdir -p /app

# Create init script that sets up venv if needed
RUN cat > /app/init.sh << 'EOF'
#!/bin/bash
set -e

# IMPORTANT: Deactivate any existing virtual environment first
# This ensures we don't accidentally use /opt/venv or any other venv
if [ -n "$VIRTUAL_ENV" ]; then
    echo "⚠️ Deactivating existing virtual environment: $VIRTUAL_ENV"
    deactivate 2>/dev/null || true
    unset VIRTUAL_ENV
    unset PYTHONHOME
    # Reset PATH to remove any venv paths
    export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/cuda/bin"
fi

# Quick check - if everything exists, verify PyTorch supports current GPU
if [ -f "/workspace/venv/bin/activate" ] && [ -f "/workspace/ComfyUI/main.py" ] && [ -d "/workspace/ComfyUI/custom_nodes/ComfyUI-Manager" ]; then
    source /workspace/venv/bin/activate

    # Universal GPU compatibility check - works for ANY GPU
    # Tests if PyTorch can actually use CUDA, not just if it's installed
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    echo "🔍 Checking PyTorch compatibility with $GPU_NAME..."

    # Try to actually use the GPU - this catches ALL incompatibility issues
    GPU_WORKS=$(python -c "
import torch
try:
    if torch.cuda.is_available():
        # Actually try to use the GPU, not just check availability
        x = torch.tensor([1.0]).cuda()
        del x
        print('True')
    else:
        print('False')
except Exception as e:
    print('False')
" 2>/dev/null || echo "False")

    if [ "$GPU_WORKS" != "True" ]; then
        echo "⚠️ PyTorch cannot use $GPU_NAME!"
        echo "🔧 Reinstalling PyTorch stack with CUDA 12.9..."

        # CRITICAL: Must use PyTorch 2.8.0 to match pre-compiled xformers/sageattention wheels
        # PyTorch 2.9.x causes std::bad_alloc crash with these wheels (Bug #33)
        pip install torch==2.8.0 torchvision torchaudio \
            --index-url https://download.pytorch.org/whl/cu129 \
            --force-reinstall --quiet

        # Pre-compiled xformers with RTX 5090 (sm_120) support - built for PyTorch 2.8.0
        echo "🔧 Installing pre-compiled xformers..."
        pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/xformers-0.0.33+c159edc0.d20250906-cp39-abi3-linux_x86_64.whl --quiet

        # Pre-compiled sageattention 2.2.0.post4 with RTX 5090 support - built for PyTorch 2.8.0
        echo "🔧 Installing pre-compiled sageattention..."
        pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/sageattention-2.2.0.post4-cp39-abi3-linux_x86_64.whl --quiet

        echo "✅ PyTorch + xformers + sageattention upgraded"
    else
        echo "✅ PyTorch works with $GPU_NAME"
    fi

    echo "✅ Environment already initialized (fast path)"
    exit 0
elif [ ! -f "/workspace/venv/bin/activate" ] && [ -f "/workspace/ComfyUI/main.py" ]; then
    echo "⚠️ Venv missing or incomplete - will rebuild venv..."
    rm -rf /workspace/venv 2>/dev/null
    # Continue to rebuild venv
fi

echo "🚀 RunPod ComfyUI Installer Initializing..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Configure git (only if not done)
if ! git config --global --get user.email > /dev/null 2>&1; then
    git config --global --add safe.directory '*'
    git config --global user.email "comfyui@runpod.local" 2>/dev/null || true
    git config --global user.name "ComfyUI" 2>/dev/null || true
fi

# Create necessary directories (mkdir -p is fast if they exist)
mkdir -p /workspace/models/{checkpoints,loras,vae,controlnet,clip,clip_vision,diffusers,embeddings,upscale_models}
mkdir -p /workspace/output /workspace/input /workspace/workflows

# Setup Python virtual environment in persistent storage
if [ ! -d "/workspace/venv" ]; then
    echo "📦 Creating virtual environment in /workspace/venv..."
    # Use python3.11 if available, otherwise fall back to python3
    if command -v python3.11 &> /dev/null; then
        python3.11 -m venv /workspace/venv
        echo "   Using Python 3.11"
    else
        python3 -m venv /workspace/venv
        echo "   Using Python $(python3 --version)"
    fi
    source /workspace/venv/bin/activate
    NEED_INSTALL=1
elif [ ! -f "/workspace/venv/.cuda129_upgraded" ]; then
    echo "📦 Existing venv found, checking CUDA compatibility..."
    source /workspace/venv/bin/activate
    # Check if PyTorch has correct CUDA version
    CUDA_VER=$(python -c "import torch; print(torch.version.cuda)" 2>/dev/null || echo "none")
    if [[ "$CUDA_VER" != "12.9" ]]; then
        echo "⚠️ Venv has old CUDA version ($CUDA_VER), upgrading to CUDA 12.9 compatible packages..."
        NEED_INSTALL=1
    else
        echo "✅ Venv already has CUDA 12.9 compatible packages"
        NEED_INSTALL=0
    fi
else
    echo "✅ Using existing CUDA 12.9 compatible venv"
    source /workspace/venv/bin/activate
    NEED_INSTALL=0
fi

if [ "$NEED_INSTALL" = "1" ]; then

    echo "📦 Installing Python packages..."
    pip install --upgrade pip wheel setuptools

    # Install uv for faster package management
    echo "🚀 Installing uv package manager for faster builds..."
    pip install uv

    # Core packages for UI
    uv pip install flask==3.0.0 psutil requests

    # Google Sheets API for usage tracking
    uv pip install gspread oauth2client

    # CivitAI integration packages
    uv pip install civitai-downloader aiofiles

    # ComfyUI requirements - PyTorch 2.8.0 with CUDA 12.9
    # CRITICAL: Must use PyTorch 2.8.0 to match pre-compiled xformers/sageattention wheels (Bug #33)
    # PyTorch 2.9.x causes std::bad_alloc crash with MonsterMMORPG wheels
    echo "📦 Installing PyTorch 2.8.0 with CUDA 12.9..."
    pip install torch==2.8.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu129

    # Core ComfyUI dependencies
    uv pip install einops torchsde "kornia>=0.7.1" spandrel "safetensors>=0.4.2"
    uv pip install aiohttp pyyaml Pillow tqdm scipy
    uv pip install transformers diffusers accelerate
    uv pip install opencv-python

    # Video processing support (required by ComfyUI for video input)
    uv pip install av

    # Text processing support (required for tokenization in many models)
    uv pip install sentencepiece

    # ONNX Runtime 1.22.1+ - CRITICAL for RTX 5090 and CUDA 12.9 support
    # Version 1.22.0 has PTX toolchain errors on RTX 5090 (Bug #30)
    # Version 1.22.1+ includes CUDA 12.9 and sm_120 compute capability support
    uv pip install "onnxruntime-gpu>=1.22.1" || pip install "onnxruntime-gpu>=1.22.1"

    # Install triton for GPU kernel optimization - CRITICAL for Sage Attention + WAN 2.2!
    echo "📦 Installing Triton (ESSENTIAL for 13x speedup with Sage Attention)..."
    uv pip install triton --upgrade
    # Ensure latest version for RTX 5090 compatibility
    pip install --upgrade triton

    # Install ninja and packaging for compiling from source
    uv pip install ninja packaging wheel

    # Performance optimization libraries
    uv pip install huggingface_hub hf_transfer hf_xet accelerate piexif requests deepspeed ultralytics==8.3.197

    # ============================================================================
    # ATTENTION MECHANISMS - RTX 3000/4000/5000 SERIES SUPPORT
    # ============================================================================
    # Using pre-compiled wheels from MonsterMMORPG/Wan_GGUF HuggingFace repo
    # These wheels include sm_120 compute capability (RTX 5090 Blackwell) support
    # Compatible with: RTX 3090, RTX 4090, RTX 5090, H100, H200, and more
    #
    # Versions:
    #   - Flash Attention: 2.8.2
    #   - xformers: 0.0.33
    #   - Sage Attention: 2.2.0
    #   - insightface: 0.7.3
    #
    # Benefits:
    #   ✅ No compilation errors
    #   ✅ ~30 minute faster build time
    #   ✅ RTX 5090 sm_120 support
    #   ✅ Tested by thousands of users
    # ============================================================================
    echo "🚀 Installing pre-compiled attention mechanisms with RTX 5090 support..."

    # Clear any existing Triton cache first
    rm -rf ~/.triton /tmp/triton_* 2>/dev/null || true

    # 1. xformers 0.0.33 - Universal fallback (abi3 wheel works with Python 3.9+)
    echo "📦 Installing xformers 0.0.33 (pre-compiled with sm_120 support)..."
    uv pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/xformers-0.0.33+c159edc0.d20250906-cp39-abi3-linux_x86_64.whl || \
    pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/xformers-0.0.33+c159edc0.d20250906-cp39-abi3-linux_x86_64.whl

    # 2. Flash Attention 2.8.2 - For Ampere/Ada/Blackwell GPUs
    echo "📦 Installing Flash Attention 2.8.2 (pre-compiled with sm_120 support)..."
    uv pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/flash_attn-2.8.2-cp311-cp311-linux_x86_64.whl || \
    pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/flash_attn-2.8.2-cp311-cp311-linux_x86_64.whl

    # 3. Sage Attention 2.2.0.post4 - CRITICAL for WAN 2.2 (13x speedup!)
    # Using abi3 wheel (universal binary, works with Python 3.9+)
    # MUST use .post4 version - older 2.2.0 crashes with std::bad_alloc (Bug #33)
    echo "📦 Installing Sage Attention 2.2.0.post4 (pre-compiled with sm_120 support)..."
    uv pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/sageattention-2.2.0.post4-cp39-abi3-linux_x86_64.whl || \
    pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/sageattention-2.2.0.post4-cp39-abi3-linux_x86_64.whl

    # 4. insightface 0.7.3 - For ReActor face swap
    echo "📦 Installing insightface 0.7.3 (pre-compiled with sm_120 support)..."
    uv pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/insightface-0.7.3-cp311-cp311-linux_x86_64.whl || \
    pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/insightface-0.7.3-cp311-cp311-linux_x86_64.whl

    # Verify installations
    echo "✅ Verifying attention mechanism installations..."
    python -c "import flash_attn; print('   ✅ Flash Attention 2.8.2 installed')" 2>/dev/null || echo "   ⚠️ Flash Attention import failed"
    python -c "import xformers; print('   ✅ xformers 0.0.33 installed')" 2>/dev/null || echo "   ⚠️ xformers import failed"
    python -c "import sageattention; print('   ✅ Sage Attention 2.2.0 installed')" 2>/dev/null || echo "   ⚠️ Sage Attention import failed"
    python -c "import insightface; print('   ✅ insightface 0.7.3 installed')" 2>/dev/null || echo "   ⚠️ insightface import failed"

    # Clear build caches to reduce image size
    rm -rf ~/.cache/pip ~/.triton /tmp/*

    # Git integration
    uv pip install GitPython PyGithub==1.59.1

    # Jupyter
    uv pip install jupyterlab ipywidgets notebook

    # Mark venv as CUDA 12.9 compatible (PyTorch cu129)
    touch /workspace/venv/.cuda129_upgraded

    echo "✅ Virtual environment setup complete with CUDA 12.9 support (PyTorch cu129)"
fi

# GPU-adaptive attention mechanism configuration
echo "🔍 Detecting GPU for optimal attention mechanism..."
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "Unknown")
echo "   GPU detected: $GPU_NAME"

# Detect GPU family - Complete RunPod GPU Support
if echo "$GPU_NAME" | grep -qE "B200|NVIDIA B200|RTX PRO 6000|RTX 6000 WK|RTX 6000"; then
    # Blackwell GPUs (latest generation) - including RTX PRO 6000 with 96GB GDDR7
    GPU_TYPE="blackwell"
    echo "   🚀 Blackwell architecture detected"
elif echo "$GPU_NAME" | grep -qE "H100|H200|H800|NVIDIA H100|NVIDIA H200"; then
    # Hopper GPUs - H100 NVL, H100 SXM, H200 SXM, H100 PCIe
    GPU_TYPE="hopper"
    echo "   ⚡ Hopper architecture detected"
elif echo "$GPU_NAME" | grep -qE "RTX 4090|RTX 4080|RTX 4070|RTX 4060"; then
    # Ada Lovelace Consumer GPUs
    GPU_TYPE="ada"
    echo "   📦 Ada Lovelace architecture detected (RTX 40 series)"
elif echo "$GPU_NAME" | grep -qE "L40|L40S|L4|NVIDIA L40|NVIDIA L4"; then
    # Ada Lovelace Data Center GPUs
    GPU_TYPE="ada"
    echo "   📦 Ada Lovelace architecture detected (L-series)"
elif echo "$GPU_NAME" | grep -qE "RTX 6000 Ada|RTX 5000 Ada|RTX 4000 Ada|RTX 2000 Ada|RTX Ada"; then
    # Ada Lovelace Professional GPUs (older RTX Ada generation, not the new Blackwell RTX PRO 6000)
    GPU_TYPE="ada"
    echo "   📦 Ada Lovelace architecture detected (RTX Ada)"
elif echo "$GPU_NAME" | grep -qE "A100|A40|A30|A10|NVIDIA A100|NVIDIA A40"; then
    # Ampere Data Center GPUs
    GPU_TYPE="ampere"
    echo "   ⚡ Ampere architecture detected (A-series)"
elif echo "$GPU_NAME" | grep -qE "RTX 3090|RTX 3080|RTX 3070|RTX 3060"; then
    # Ampere Consumer GPUs (RTX 30 series)
    GPU_TYPE="ampere"
    echo "   📦 Ampere architecture detected (RTX 30 series)"
elif echo "$GPU_NAME" | grep -qE "RTX 5090|RTX 5080|RTX 5070|RTX 5060"; then
    # RTX 50 series (when released, likely Blackwell)
    GPU_TYPE="blackwell"
    echo "   🚀 Blackwell architecture detected (RTX 50 series)"
elif echo "$GPU_NAME" | grep -qE "A800|A6000"; then
    # Other Ampere variants
    GPU_TYPE="ampere"
    echo "   ⚡ Ampere architecture detected"
else
    # Unknown or older GPUs - use broadest compatibility
    GPU_TYPE="generic"
    echo "   📦 Generic/Unknown GPU detected - will use safe defaults"
fi

# All attention mechanisms are now pre-installed during build
# ComfyUI will auto-detect and use the best one available
echo "✅ All attention mechanisms pre-installed:"

# Create env settings file if it doesn't exist
mkdir -p /workspace/venv
touch /workspace/venv/.env_settings

# ComfyUI V54 Approach: Always use Sage Attention (universal best performance)
# ComfyUI will auto-fallback to xformers/flash if sage doesn't work on specific hardware
# This matches the MonsterMMORPG/Wan_GGUF optimized setup used by thousands of users

if python -c "import sageattention" 2>/dev/null; then
    echo "   🚀 Sage Attention selected for $GPU_NAME (universal best performance)"
    echo "   ⚡ Optimized for all GPUs: RTX 3090/4090/5090, H100, A100, L40S, etc."
    echo "   📦 ComfyUI will auto-fallback to xformers/flash if needed"
    echo "export COMFYUI_ATTENTION_MECHANISM=sage" > /workspace/venv/.env_settings
elif python -c "import xformers" 2>/dev/null; then
    echo "   ✅ xformers selected as fallback for $GPU_NAME"
    echo "export COMFYUI_ATTENTION_MECHANISM=xformers" > /workspace/venv/.env_settings
else
    echo "   ⚠️ No optimized attention available, using PyTorch native"
    echo "export COMFYUI_ATTENTION_MECHANISM=default" > /workspace/venv/.env_settings
fi

# Log the final configuration
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 GPU Configuration Summary:"
echo "   GPU Model: $GPU_NAME"
echo "   Architecture: $GPU_TYPE"
if [ -f /workspace/venv/.env_settings ]; then
    source /workspace/venv/.env_settings
    echo "   Selected Mechanism: ${COMFYUI_ATTENTION_MECHANISM:-auto-detect}"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# If no specific mechanism was set, let ComfyUI auto-detect
if ! grep -q "COMFYUI_ATTENTION_MECHANISM" /workspace/venv/.env_settings 2>/dev/null; then
    echo "export COMFYUI_ATTENTION_MECHANISM=auto" >> /workspace/venv/.env_settings
    echo "   ℹ️ ComfyUI will auto-select the best attention mechanism"
fi

echo "✅ Attention mechanism configuration complete"

# Install ComfyUI if not present
if [ ! -f "/workspace/ComfyUI/main.py" ]; then
    echo "📦 Installing ComfyUI..."
    cd /workspace
    rm -rf ComfyUI 2>/dev/null || true

    if git clone https://github.com/comfyanonymous/ComfyUI.git; then
        echo "✅ ComfyUI cloned successfully"
    else
        echo "⚠️ Regular clone failed, trying shallow clone..."
        git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git
    fi

    if [ -f "/workspace/ComfyUI/main.py" ]; then
        echo "✅ ComfyUI installed at /workspace/ComfyUI"

        # Install ComfyUI Python requirements
        cd /workspace/ComfyUI
        if [ -f "requirements.txt" ]; then
            echo "📦 Installing ComfyUI requirements..."
            pip install -r requirements.txt 2>/dev/null || true
        fi

        # Install ComfyUI Manager
        echo "📦 Installing ComfyUI Manager..."
        mkdir -p /workspace/ComfyUI/custom_nodes
        cd /workspace/ComfyUI/custom_nodes
        if git clone https://github.com/ltdrdata/ComfyUI-Manager.git; then
            echo "✅ ComfyUI Manager cloned"
            if [ -f "ComfyUI-Manager/requirements.txt" ]; then
                echo "📦 Installing Manager requirements..."
                pip install -r ComfyUI-Manager/requirements.txt 2>/dev/null || true
            fi
        else
            echo "⚠️ Failed to install ComfyUI Manager"
        fi

        # Setup symlinks for models, workflows, input, and output
        cd /workspace

        # Models symlink
        if [ -e /workspace/ComfyUI/models ]; then
            rm -rf /workspace/ComfyUI/models
        fi
        ln -sf /workspace/models /workspace/ComfyUI/models
        echo "✅ Model symlink created"

        # Workflows symlink - IMPORTANT: ComfyUI saves to user/default/workflows
        mkdir -p /workspace/ComfyUI/user/default
        if [ -d "/workspace/ComfyUI/user/default/workflows" ] && [ ! -L "/workspace/ComfyUI/user/default/workflows" ]; then
            # Migrate existing workflows
            cp -r /workspace/ComfyUI/user/default/workflows/* /workspace/workflows/ 2>/dev/null || true
            rm -rf /workspace/ComfyUI/user/default/workflows
        fi
        ln -sf /workspace/workflows /workspace/ComfyUI/user/default/workflows
        echo "✅ Workflows symlink created"

        # Output symlink
        if [ -d "/workspace/ComfyUI/output" ] && [ ! -L "/workspace/ComfyUI/output" ]; then
            cp -r /workspace/ComfyUI/output/* /workspace/output/ 2>/dev/null || true
            rm -rf /workspace/ComfyUI/output
        fi
        ln -sf /workspace/output /workspace/ComfyUI/output
        echo "✅ Output symlink created"

        # Input symlink
        if [ -d "/workspace/ComfyUI/input" ] && [ ! -L "/workspace/ComfyUI/input" ]; then
            cp -r /workspace/ComfyUI/input/* /workspace/input/ 2>/dev/null || true
            rm -rf /workspace/ComfyUI/input
        fi
        ln -sf /workspace/input /workspace/ComfyUI/input
        echo "✅ Input symlink created"
    else
        echo "❌ Failed to install ComfyUI"
        exit 1
    fi
else
    echo "✅ ComfyUI already installed"

    # Ensure Manager is installed even if ComfyUI exists
    if [ ! -d "/workspace/ComfyUI/custom_nodes/ComfyUI-Manager" ]; then
        echo "📦 Installing ComfyUI Manager..."
        mkdir -p /workspace/ComfyUI/custom_nodes
        cd /workspace/ComfyUI/custom_nodes
        git clone https://github.com/ltdrdata/ComfyUI-Manager.git 2>/dev/null || true
        if [ -f "ComfyUI-Manager/requirements.txt" ]; then
            pip install -r ComfyUI-Manager/requirements.txt 2>/dev/null || true
        fi
    fi
fi

echo "✅ Environment prepared"

# Verify CUDA installation
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 CUDA Verification:"
if command -v nvcc &> /dev/null; then
    nvcc --version | grep "release" || echo "nvcc version check failed"
else
    echo "⚠️ nvcc not found in PATH"
fi

# Check PyTorch CUDA availability (may show False in build stage - normal behavior)
python3 -c "
import torch
print(f'PyTorch CUDA Available: {torch.cuda.is_available()}')
print(f'PyTorch CUDA Version: {torch.version.cuda}')
if not torch.cuda.is_available() and torch.version.cuda:
    print('Note: CUDA not detected during build - this is normal')
    print('GPU will be available when container runs on RunPod')
else:
    print(f'PyTorch built with CUDA: {torch.version.cuda is not None}')
" 2>/dev/null || echo "PyTorch CUDA check skipped"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
EOF

RUN chmod +x /app/init.sh

# Create startup script
RUN cat > /start.sh << 'EOF'
#!/bin/bash
set -e

echo "🚀 Starting RunPod Services..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# CRITICAL: Verify GPU is accessible before starting services
echo "🔍 Verifying GPU access..."
if ! nvidia-smi > /dev/null 2>&1; then
    echo "❌ FATAL: nvidia-smi failed - GPU not accessible"
    echo ""
    echo "This usually means:"
    echo "  1. No GPU allocated to this pod"
    echo "  2. GPU drivers not mounted in container"
    echo "  3. Pod needs to be restarted"
    echo ""
    echo "Please check RunPod dashboard and ensure:"
    echo "  - Pod has a GPU tier selected (not CPU-only)"
    echo "  - Pod is running on a GPU node"
    echo ""
    exit 1
fi

# Show GPU info
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader || echo "Warning: GPU info query failed"

# Verify PyTorch can see CUDA
echo "🔍 Verifying PyTorch CUDA access..."
python3 -c "import torch; assert torch.cuda.is_available(), 'PyTorch cannot access CUDA'; print(f'✅ GPU detected: {torch.cuda.get_device_name(0)}')" || {
    echo "❌ FATAL: PyTorch cannot access CUDA"
    echo ""
    echo "GPU hardware is visible but PyTorch cannot use it."
    echo "This usually means:"
    echo "  1. PyTorch not built with CUDA support"
    echo "  2. CUDA version mismatch"
    echo "  3. Driver compatibility issue"
    echo ""
    echo "Attempting to show more details..."
    python3 -c "import torch; print(f'PyTorch version: {torch.__version__}'); print(f'CUDA built: {torch.version.cuda}'); print(f'CUDA available: {torch.cuda.is_available()}')"
    exit 1
}

# IMPORTANT: Clean environment first - remove any pre-existing venv
if [ -n "$VIRTUAL_ENV" ]; then
    echo "⚠️ Found pre-activated venv: $VIRTUAL_ENV - deactivating..."
    deactivate 2>/dev/null || true
    unset VIRTUAL_ENV
    unset PYTHONHOME
    export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/cuda/bin"
fi

# Initialize environment (creates venv if needed)
/app/init.sh || {
    echo "⚠️ Init failed, attempting recovery..."
    rm -rf /workspace/venv
    /app/init.sh
}

# Activate virtual environment - ONLY use /workspace/venv
if [ -f "/workspace/venv/bin/activate" ]; then
    source /workspace/venv/bin/activate
    echo "✅ Activated /workspace/venv (Python: $(which python))"
else
    echo "❌ ERROR: /workspace/venv not found after init!"
    echo "Attempting emergency venv creation..."
    python3 -m venv /workspace/venv
    source /workspace/venv/bin/activate
    pip install --upgrade pip wheel setuptools
fi

# Start Control Panel UI
echo "🌐 Starting Control Panel on port 7777..."
cd /app/ui && python -u app.py 2>&1 | tee /workspace/ui.log &
CONTROL_PID=$!

# Start JupyterLab
echo "📊 Starting JupyterLab on port 8888..."
jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root \
    --NotebookApp.token="" --NotebookApp.password="" \
    --ServerApp.allow_origin="*" > /workspace/jupyter.log 2>&1 &

# Wait for services
sleep 3

# Check Control Panel status
if kill -0 $CONTROL_PID 2>/dev/null; then
    if curl -s http://localhost:7777/health > /dev/null 2>&1; then
        echo "✅ Control Panel running on http://localhost:7777"
        echo "   Use the Control Panel to select user and start ComfyUI"
    else
        echo "⚠️ Control Panel process running but not responding on port 7777"
        echo "📋 Checking for errors in log:"
        tail -20 /workspace/ui.log 2>/dev/null || echo "No log file found"
    fi
else
    echo "❌ Control Panel failed to start. Checking log for errors:"
    tail -30 /workspace/ui.log 2>/dev/null || echo "No log file found"
    echo ""
    echo "Attempting to start with error output:"
    cd /app/ui && python app.py 2>&1 | head -50 &
fi

if lsof -i:8888 > /dev/null 2>&1; then
    echo "✅ JupyterLab running on http://localhost:8888"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Auto-start ComfyUI if COMFYUI_USER and COMFYUI_AUTO_START are set
if [ -n "$COMFYUI_USER" ] && [ "$COMFYUI_AUTO_START" = "true" ]; then
    echo "🚀 Auto-starting ComfyUI for user: $COMFYUI_USER"

    # Wait for control panel to be ready
    for i in {1..30}; do
        if curl -s http://localhost:7777/health > /dev/null 2>&1; then
            break
        fi
        sleep 1
    done

    # Call the start API
    curl -X POST http://localhost:7777/api/start \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$COMFYUI_USER\"}" \
        > /dev/null 2>&1 && echo "✅ ComfyUI started for $COMFYUI_USER" || echo "⚠️ Failed to auto-start ComfyUI"
else
    echo "Ready! Visit port 7777 to manage ComfyUI"
fi

# Keep container running
sleep infinity
EOF

RUN chmod +x /start.sh

# Create ComfyUI start script
RUN cat > /app/start_comfyui.sh << 'EOF'
#!/bin/bash

echo "🎨 Starting ComfyUI..."

# IMPORTANT: Deactivate any existing venv first (like /opt/venv)
if [ -n "$VIRTUAL_ENV" ] && [ "$VIRTUAL_ENV" != "/workspace/venv" ]; then
    echo "⚠️ Deactivating incorrect venv: $VIRTUAL_ENV"
    deactivate 2>/dev/null || true
    unset VIRTUAL_ENV
    unset PYTHONHOME
    export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/cuda/bin"
fi

# Activate virtual environment - ONLY from /workspace/venv
if [ -d "/workspace/venv" ]; then
    source /workspace/venv/bin/activate
    echo "✅ Using /workspace/venv (Python: $(which python))"
else
    echo "⚠️ Virtual environment not found, creating..."
    /app/init.sh
    if [ -d "/workspace/venv" ]; then
        source /workspace/venv/bin/activate
        echo "✅ Created and activated /workspace/venv"
    else
        echo "❌ ERROR: Failed to create /workspace/venv"
        exit 1
    fi
fi

# ComfyUI V54 Approach: ALWAYS use Sage Attention for all modern GPUs
# Don't trust old .env_settings file - it may be from old Docker image
# Sage has universal compatibility and best performance for ALL GPUs

# Force sage attention for all GPUs (ComfyUI will auto-fallback if needed)
if python -c "import sageattention" 2>/dev/null; then
    export COMFYUI_ATTENTION_MECHANISM="sage"
    echo "🚀 Using Sage Attention (universal best performance for all GPUs)"
elif python -c "import xformers" 2>/dev/null; then
    export COMFYUI_ATTENTION_MECHANISM="xformers"
    echo "📦 Using xformers (fallback)"
else
    export COMFYUI_ATTENTION_MECHANISM="default"
    echo "ℹ️ Using default PyTorch attention"
fi

# Update .env_settings file for consistency
mkdir -p /workspace/venv
echo "export COMFYUI_ATTENTION_MECHANISM=$COMFYUI_ATTENTION_MECHANISM" > /workspace/venv/.env_settings

# ============================================================================
# GPU CHANGE DETECTION AND CACHE CLEANING
# ============================================================================
# When switching between different GPUs (e.g., RTX 4090 -> RTX 5090),
# cached CUDA kernels from the previous GPU will cause errors.
# This section detects GPU changes and clears all GPU-specific caches.
# ============================================================================

echo "🔍 Checking for GPU changes..."

# Get current GPU info
CURRENT_GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "unknown")
CURRENT_COMPUTE_CAP=$(python -c "import torch; cc = torch.cuda.get_device_capability(); print(f'{cc[0]}.{cc[1]}')" 2>/dev/null || echo "unknown")

echo "   Current GPU: $CURRENT_GPU (compute $CURRENT_COMPUTE_CAP)"

# Check if GPU changed since last run
GPU_CHANGED=false
if [ -f "/workspace/.last_gpu_info" ]; then
    LAST_GPU=$(cat /workspace/.last_gpu_info 2>/dev/null || echo "")
    if [ "$LAST_GPU" != "$CURRENT_GPU:$CURRENT_COMPUTE_CAP" ]; then
        echo "   ⚠️  GPU changed since last run!"
        echo "   Previous: $(echo $LAST_GPU | cut -d: -f1) (compute $(echo $LAST_GPU | cut -d: -f2))"
        echo "   Current:  $CURRENT_GPU (compute $CURRENT_COMPUTE_CAP)"
        GPU_CHANGED=true
    fi
else
    echo "   First run on this workspace"
    GPU_CHANGED=true
fi

# If GPU changed, clear ALL GPU-specific caches
if [ "$GPU_CHANGED" = true ]; then
    echo ""
    echo "🧹 Clearing all GPU-specific caches to prevent errors..."

    # 1. Triton cache (Sage Attention, custom CUDA kernels)
    if [ -d "/root/.triton" ] || [ -d "/workspace/.triton" ]; then
        echo "   • Clearing Triton cache..."
        rm -rf /root/.triton /workspace/.triton ~/.triton 2>/dev/null || true
        rm -rf /tmp/triton_* /tmp/*triton* 2>/dev/null || true
    fi

    # 2. PyTorch kernel cache
    if [ -d "/root/.cache/torch" ] || [ -d "/workspace/.cache/torch" ]; then
        echo "   • Clearing PyTorch kernel cache..."
        rm -rf /root/.cache/torch/kernels 2>/dev/null || true
        rm -rf /workspace/.cache/torch/kernels 2>/dev/null || true
    fi

    # 3. CUDA compute cache
    if [ -d "/root/.nv" ] || [ -d "/workspace/.nv" ]; then
        echo "   • Clearing CUDA compute cache..."
        rm -rf /root/.nv/ComputeCache 2>/dev/null || true
        rm -rf /workspace/.nv/ComputeCache 2>/dev/null || true
    fi

    # 4. Python __pycache__ with GPU-specific compiled code
    echo "   • Clearing Python cache in ComfyUI..."
    find /workspace/ComfyUI -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

    # 5. TensorRT engines (handled separately below)
    if [ -d "/workspace/ComfyUI/models/tensorrt" ]; then
        echo "   • Clearing TensorRT engines..."
        rm -rf /workspace/ComfyUI/models/tensorrt/*.trt 2>/dev/null || true
        rm -rf /workspace/ComfyUI/models/tensorrt/*.engine 2>/dev/null || true
    fi

    echo "   ✅ All GPU caches cleared"
    echo ""
fi

# Save current GPU info for next run
echo "$CURRENT_GPU:$CURRENT_COMPUTE_CAP" > /workspace/.last_gpu_info

# Clean up incompatible TensorRT engines (even if GPU didn't change)
if [ -d "/workspace/ComfyUI/models/tensorrt" ]; then
    echo "🔍 Checking for incompatible TensorRT engines..."

    # Get current GPU compute capability
    GPU_COMPUTE_CAP="$CURRENT_COMPUTE_CAP"

    if [ "$GPU_COMPUTE_CAP" != "unknown" ]; then
        # Find and remove TRT engines that don't match current GPU
        find /workspace/ComfyUI/models/tensorrt -name "*.trt" -type f 2>/dev/null | while read -r trt_file; do
            # Extract compute capability from filename if present (e.g., _8.0.trt or _10.12.0.36.trt)
            if [[ "$trt_file" =~ _([0-9]+\.[0-9]+)(\..*)?\.(trt|engine)$ ]]; then
                ENGINE_CC="${BASH_REMATCH[1]}"
                if [ "$ENGINE_CC" != "$GPU_COMPUTE_CAP" ]; then
                    echo "  ⚠️ Removing incompatible engine (built for compute $ENGINE_CC, current is $GPU_COMPUTE_CAP): $(basename "$trt_file")"
                    rm -f "$trt_file"
                fi
            else
                # If we can't determine the compute capability, check with trtexec
                echo "  🔍 Checking engine: $(basename "$trt_file")"
                # Try to load the engine and catch errors
                if ! python -c "import tensorrt as trt; logger = trt.Logger(trt.Logger.ERROR); runtime = trt.Runtime(logger); engine = runtime.deserialize_cuda_engine(open('$trt_file', 'rb').read())" 2>/dev/null; then
                    echo "  ⚠️ Removing incompatible engine: $(basename "$trt_file")"
                    rm -f "$trt_file"
                fi
            fi
        done
        echo "✅ TensorRT engine cleanup complete"
    fi
fi

# Attention mechanism already set above (lines 1072-1085)
# No need for additional detection here

# Check if ComfyUI is installed
if [ ! -f "/workspace/ComfyUI/main.py" ]; then
    echo "📦 Installing ComfyUI first..."
    cd /workspace
    rm -rf ComfyUI

    if ! git clone https://github.com/comfyanonymous/ComfyUI.git; then
        echo "⚠️ Git clone failed, trying shallow clone..."
        git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git
    fi

    if [ ! -f "/workspace/ComfyUI/main.py" ]; then
        echo "❌ Failed to install ComfyUI"
        exit 1
    fi

    # Install ComfyUI requirements (preserve our CUDA 12.9 compatible PyTorch)
    cd /workspace/ComfyUI
    if [ -f "requirements.txt" ]; then
        # Install requirements but skip torch to keep our CUDA 12.9 version
        grep -v "^torch" requirements.txt > /tmp/comfy_req.txt || cp requirements.txt /tmp/comfy_req.txt
        pip install -r /tmp/comfy_req.txt
        # Ensure we have PyTorch 2.8.0 for CUDA 12.9 (Bug #33 - must match pre-compiled wheels)
        pip install torch==2.8.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu129 --upgrade
    fi
fi

# Setup all symlinks
if [ -e /workspace/ComfyUI/models ]; then
    rm -rf /workspace/ComfyUI/models
fi
ln -sf /workspace/models /workspace/ComfyUI/models

# Workflows symlink - IMPORTANT: ComfyUI saves to user/default/workflows
mkdir -p /workspace/ComfyUI/user/default
if [ ! -L "/workspace/ComfyUI/user/default/workflows" ]; then
    [ -d "/workspace/ComfyUI/user/default/workflows" ] && cp -r /workspace/ComfyUI/user/default/workflows/* /workspace/workflows/ 2>/dev/null || true
    rm -rf /workspace/ComfyUI/user/default/workflows 2>/dev/null
    ln -sf /workspace/workflows /workspace/ComfyUI/user/default/workflows
fi

# Output symlink
if [ ! -L "/workspace/ComfyUI/output" ]; then
    [ -d "/workspace/ComfyUI/output" ] && cp -r /workspace/ComfyUI/output/* /workspace/output/ 2>/dev/null || true
    rm -rf /workspace/ComfyUI/output 2>/dev/null
    ln -sf /workspace/output /workspace/ComfyUI/output
fi

# Input symlink
if [ ! -L "/workspace/ComfyUI/input" ]; then
    [ -d "/workspace/ComfyUI/input" ] && cp -r /workspace/ComfyUI/input/* /workspace/input/ 2>/dev/null || true
    rm -rf /workspace/ComfyUI/input 2>/dev/null
    ln -sf /workspace/input /workspace/ComfyUI/input
fi

# Install Manager if needed
if [ ! -d "/workspace/ComfyUI/custom_nodes/ComfyUI-Manager" ]; then
    echo "📦 Installing ComfyUI Manager..."
    mkdir -p /workspace/ComfyUI/custom_nodes
    cd /workspace/ComfyUI/custom_nodes
    if git clone https://github.com/ltdrdata/ComfyUI-Manager.git; then
        if [ -f "ComfyUI-Manager/requirements.txt" ]; then
            pip install -r ComfyUI-Manager/requirements.txt 2>/dev/null || true
        fi
    fi
fi

# Setup GPU-specific TensorRT directories using symlinks
# This is the PRIMARY mechanism for multi-GPU support (more reliable than code patching)
# Each GPU type (4090, 5090, B200, etc.) gets its own cache directory
# /workspace/ComfyUI/models/tensorrt/upscaler -> /workspace/.tensorrt_cache/{compute_cap}/upscaler
echo "🔧 Setting up GPU-specific TensorRT directories..."
if [ -f "/app/scripts/setup_tensorrt_gpu_dirs.sh" ]; then
    /app/scripts/setup_tensorrt_gpu_dirs.sh 2>&1 || echo "   ℹ️ TensorRT directory setup skipped (non-critical)"
fi

# Legacy: Apply GPU-aware TensorRT code patch (kept for backwards compatibility)
# The symlink approach above is more reliable, but this patch adds extra safety
if [ -f "/app/scripts/patch_tensorrt_gpu_aware.sh" ]; then
    /app/scripts/patch_tensorrt_gpu_aware.sh 2>/dev/null || true
fi

# Start ComfyUI with appropriate attention mechanism
cd /workspace/ComfyUI

# Display which attention mechanism is being used
echo "🎆 Attention Mechanism: $COMFYUI_ATTENTION_MECHANISM"

# CRITICAL: Verify CUDA is accessible before starting ComfyUI
echo "🔍 Verifying CUDA availability..."
python -c "
import torch
import sys

if not torch.cuda.is_available():
    print('❌ ERROR: CUDA not available to PyTorch!')
    print(f'   PyTorch version: {torch.__version__}')
    print(f'   CUDA built version: {torch.version.cuda}')
    print('')
    print('This will cause ComfyUI to crash at startup.')
    print('Possible causes:')
    print('1. GPU not allocated to pod')
    print('2. GPU drivers not mounted in container')
    print('3. PyTorch installed without CUDA support')
    sys.exit(1)

print(f'✅ CUDA is available')
print(f'   GPU: {torch.cuda.get_device_name(0)}')
print(f'   VRAM: {torch.cuda.get_device_properties(0).total_memory / (1024**3):.1f} GB')
print(f'   CUDA Version: {torch.version.cuda}')
" || {
    echo "❌ CUDA verification failed!"
    echo "ComfyUI cannot start without GPU access"
    exit 1
}

# Disable torch inductor/Triton compilation to prevent errors on newer GPUs
# This won't affect Sage Attention which has its own optimized kernels
export TORCH_COMPILE_DISABLE=1
export TORCHINDUCTOR_DISABLE=1
echo "🔧 Torch inductor disabled (Sage Attention still active for RTX 5090)"

# Clear Triton cache if it exists to prevent conflicts
if [ -d "$HOME/.triton" ] || [ -d "/root/.triton" ]; then
    echo "🧹 Clearing Triton cache..."
    rm -rf ~/.triton /root/.triton /tmp/triton_* 2>/dev/null || true
fi

# Function to try starting ComfyUI with fallback
start_comfyui_with_fallback() {
    local attempt=1
    local max_attempts=3

    while [ $attempt -le $max_attempts ]; do
        echo "📊 Attempt $attempt of $max_attempts to start ComfyUI..."

        # ComfyUI V54 Approach: Simple sage/xformers/default selection (no flash attention)
        case "$COMFYUI_ATTENTION_MECHANISM" in
            sage)
                echo "🎯 Starting ComfyUI with Sage Attention 2.2.0"
                echo "   ⚡ WAN 2.2 will generate 13x faster with Sage!"
                python main.py --listen 0.0.0.0 --port 8188 --use-sage-attention 2>&1 | tee /tmp/comfyui_start.log &
                ;;
            xformers)
                echo "📦 Starting ComfyUI with xformers"
                python main.py --listen 0.0.0.0 --port 8188 --disable-smart-memory 2>&1 | tee /tmp/comfyui_start.log &
                ;;
            auto|default|*)
                echo "🌐 Starting ComfyUI with auto-selected attention"
                python main.py --listen 0.0.0.0 --port 8188 --disable-smart-memory 2>&1 | tee /tmp/comfyui_start.log &
                ;;
        esac

        COMFYUI_PID=$!

        # Give ComfyUI more time to start on RTX 5090 (kernel compilation can be slow)
        echo "⏳ Waiting for ComfyUI to start (this may take 30-60s on first run)..."
        local wait_time=0
        local max_wait=60

        while [ $wait_time -lt $max_wait ]; do
            sleep 5
            wait_time=$((wait_time + 5))

            # Check if process is still running
            if ! kill -0 $COMFYUI_PID 2>/dev/null; then
                echo "❌ ComfyUI process died"
                break
            fi

            # Check if web server is responding
            if curl -s http://localhost:8188 >/dev/null 2>&1; then
                echo "✅ ComfyUI started successfully after ${wait_time}s!"
                wait $COMFYUI_PID
                return 0
            fi

            echo "   Still waiting... (${wait_time}s/${max_wait}s)"
        done

        # If we got here, startup failed
        if kill -0 $COMFYUI_PID 2>/dev/null; then
            echo "⚠️ ComfyUI still starting after ${max_wait}s, checking logs..."
            tail -20 /tmp/comfyui_start.log
            kill $COMFYUI_PID 2>/dev/null || true
        else
            echo "⚠️ ComfyUI failed to start with $COMFYUI_ATTENTION_MECHANISM"
            kill $COMFYUI_PID 2>/dev/null || true

            # Check for common errors in log
            if grep -q "CUDA out of memory\|OutOfMemoryError" /tmp/comfyui_start.log 2>/dev/null; then
                echo "❌ Out of memory error detected"
                export COMFYUI_ATTENTION_MECHANISM="xformers"
                echo "🔄 Switching to xformers (lower memory usage)"
            elif grep -q "sage\|SageAttention" /tmp/comfyui_start.log 2>/dev/null && [ "$COMFYUI_ATTENTION_MECHANISM" = "sage" ]; then
                echo "❌ Sage Attention error detected"
                export COMFYUI_ATTENTION_MECHANISM="xformers"
                echo "🔄 Falling back to xformers"
            elif grep -q "flash_attn\|Flash Attention" /tmp/comfyui_start.log 2>/dev/null && [[ "$COMFYUI_ATTENTION_MECHANISM" =~ flash ]]; then
                echo "❌ Flash Attention error detected"
                export COMFYUI_ATTENTION_MECHANISM="xformers"
                echo "🔄 Falling back to xformers"
            elif [ "$attempt" -eq 2 ]; then
                # Second attempt: try with disabled optimizations
                echo "🔄 Trying with disabled optimizations..."
                export COMFYUI_ATTENTION_MECHANISM="default"
            elif [ "$attempt" -eq 3 ]; then
                # Final attempt: most conservative settings
                echo "🔄 Final attempt with most conservative settings..."
                # Try to start with minimal settings
                exec python main.py --listen 0.0.0.0 --port 8188 --cpu --disable-smart-memory 2>&1 | tee /tmp/comfyui_start.log
            fi

            attempt=$((attempt + 1))
        fi
    done

    echo "❌ Failed to start ComfyUI after $max_attempts attempts"
    echo "📋 Last error log:"
    tail -50 /tmp/comfyui_start.log
    exit 1
}

# Try to start ComfyUI with fallback mechanism
start_comfyui_with_fallback
EOF

RUN chmod +x /app/start_comfyui.sh

# Copy application files (done last for better caching - changes to these don't invalidate earlier layers)
COPY scripts /app/scripts
COPY config /app/config
COPY ui /app/ui
# NOTE: ComfyViewer removed - users can install ComfyUI-Gallery custom node instead
RUN chmod +x /app/scripts/*.sh 2>/dev/null || true

# ComfyViewer removed - users can install ComfyUI-Gallery custom node from ComfyUI Manager
# ComfyUI-Gallery provides a better integrated gallery experience directly in ComfyUI

# Environment
ENV PYTHONUNBUFFERED=1
ENV HF_HOME=/workspace

# Ports
EXPOSE 7777 8188 8888

WORKDIR /workspace

# Start services
CMD ["/start.sh"]
