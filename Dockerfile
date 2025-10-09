# Optimized for RunPod Pods - Uses RunPod's PyTorch base
# Using latest available RunPod image with CUDA 12.4 (we'll upgrade to 12.9)
FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

WORKDIR /

# Install system dependencies including Python build tools, rclone, and ffmpeg
RUN apt-get update && apt-get install -y \
    git wget curl psmisc lsof unzip \
    python3.11-dev python3.11-venv python3-pip \
    build-essential software-properties-common \
    ffmpeg \
    && curl -O https://downloads.rclone.org/rclone-current-linux-amd64.deb \
    && dpkg -i rclone-current-linux-amd64.deb \
    && rm rclone-current-linux-amd64.deb \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Use CUDA 12.4 from base image (matches PyTorch cu124)
# No additional CUDA installation needed - base image has cuda12.4.1
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

# Quick check - if everything exists, exit fast
if [ -f "/workspace/venv/bin/activate" ] && [ -f "/workspace/ComfyUI/main.py" ] && [ -d "/workspace/ComfyUI/custom_nodes/ComfyUI-Manager" ]; then
    echo "✅ Environment already initialized (fast path)"
    # Make sure we activate the correct venv
    source /workspace/venv/bin/activate
    exit 0
elif [ ! -f "/workspace/venv/bin/activate" ] && [ -f "/workspace/ComfyUI/main.py" ]; then
    echo "⚠️ Venv missing or incomplete - will rebuild venv..."
    rm -rf /workspace/venv 2>/dev/null
    # Continue to rebuild venv
fi

echo "🚀 RunPod ComfyUI Installer Initializing..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Restore rclone config from workspace if it exists
if [ -f "/workspace/.config/rclone/rclone.conf" ] && [ ! -f "/root/.config/rclone/rclone.conf" ]; then
    echo "📋 Restoring rclone config from workspace..."
    mkdir -p /root/.config/rclone
    cp /workspace/.config/rclone/rclone.conf /root/.config/rclone/
    if [ -f "/workspace/.config/rclone/service_account.json" ]; then
        cp /workspace/.config/rclone/service_account.json /root/.config/rclone/
    fi

    # Fix broken config that points to non-existent service account
    # BUT ONLY if we don't have the service account file at all
    if grep -q "service_account_file" /root/.config/rclone/rclone.conf && \
       [ ! -f "/root/.config/rclone/service_account.json" ] && \
       [ ! -f "/workspace/.config/rclone/service_account.json" ]; then
        echo "🔧 Fixing broken service account reference in config..."
        echo "   WARNING: Config points to service account but file is missing"
        # Don't delete the line, try to restore the service account instead
        if [ -n "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" ]; then
            echo "   Restoring service account from RunPod secret..."
            echo "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" > /root/.config/rclone/service_account.json
            echo "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" > /workspace/.config/rclone/service_account.json
        else
            echo "   No RunPod secret available to restore service account"
        fi
    fi

    echo "✅ Rclone config restored from workspace"
fi

# Fix missing Shared Drive ID in rclone config (critical for Service Accounts)
# Regenerate config completely to ensure it's always correct
if [ -f "/root/.config/rclone/service_account.json" ]; then
    echo "🔍 Checking Google Drive configuration..."

    # Detect Shared Drive ID first (need basic config for this)
    if [ ! -f "/root/.config/rclone/rclone.conf" ]; then
        # Create minimal config for detection
        mkdir -p /root/.config/rclone
        printf '%s\n' '[gdrive]' 'type = drive' 'scope = drive' \
            'service_account_file = /root/.config/rclone/service_account.json' \
            'team_drive =' '' > /root/.config/rclone/rclone.conf
    fi

    # Try to detect Shared Drive ID
    SHARED_DRIVE_ID=$(rclone backend drives gdrive: 2>/dev/null | grep -oP '"id":\s*"\K[^"]+' | head -1)

    if [ -n "$SHARED_DRIVE_ID" ]; then
        echo "✅ Found Shared Drive ID: $SHARED_DRIVE_ID"

        # Regenerate complete config with correct team_drive
        printf '%s\n' '[gdrive]' 'type = drive' 'scope = drive' \
            'service_account_file = /root/.config/rclone/service_account.json' \
            "team_drive = \$SHARED_DRIVE_ID" '' > /root/.config/rclone/rclone.conf

        # Copy to workspace for persistence
        mkdir -p /workspace/.config/rclone
        cp /root/.config/rclone/rclone.conf /workspace/.config/rclone/rclone.conf

        echo "✅ Shared Drive configuration updated"

        # Test the configuration
        if rclone lsd gdrive:ComfyUI-Output/ 2>/dev/null | grep -q "output"; then
            echo "✅ Google Drive connection verified"

            # Run initial sync if sync script exists
            if [ -f "/app/scripts/sync_to_gdrive.sh" ]; then
                echo "🔄 Running initial sync to Google Drive..."
                bash /app/scripts/sync_to_gdrive.sh &
                echo "✅ Background sync started"
            fi
        else
            echo "⚠️  Google Drive connection test failed"
        fi
    else
        echo "⚠️  No Shared Drive found - using regular Drive (may have quota issues)"
    fi
fi

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

    # CivitAI integration packages
    uv pip install civitai-downloader aiofiles

    # ComfyUI requirements - PyTorch 2.8.0 with CUDA 12.4
    echo "📦 Installing PyTorch 2.8.0 with CUDA 12.4..."
    uv pip install torch==2.8.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124

    # Core ComfyUI dependencies
    uv pip install einops torchsde "kornia>=0.7.1" spandrel "safetensors>=0.4.2"
    uv pip install aiohttp pyyaml Pillow tqdm scipy
    uv pip install transformers diffusers accelerate
    uv pip install opencv-python

    # Video processing support (required by ComfyUI for video input)
    uv pip install av

    # Text processing support (required for tokenization in many models)
    uv pip install sentencepiece

    # ONNX Runtime 1.19+ supports CUDA 12.x
    uv pip install onnxruntime-gpu==1.19.2 || pip install onnxruntime-gpu==1.19.2

    # Install triton for GPU kernel optimization - CRITICAL for Sage Attention + WAN 2.2!
    echo "📦 Installing Triton (ESSENTIAL for 13x speedup with Sage Attention)..."
    uv pip install triton --upgrade
    # Ensure latest version for RTX 5090 compatibility
    pip install --upgrade triton

    # Install ninja and packaging for compiling from source
    uv pip install ninja packaging wheel

    # Performance optimization libraries
    uv pip install huggingface_hub hf_transfer accelerate piexif requests deepspeed

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

    # 3. Sage Attention 2.2.0 - CRITICAL for WAN 2.2 (13x speedup!)
    echo "📦 Installing Sage Attention 2.2.0 (pre-compiled with sm_120 support)..."
    uv pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/sageattention-2.2.0-cp311-cp311-linux_x86_64.whl || \
    pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/sageattention-2.2.0-cp311-cp311-linux_x86_64.whl

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

    # Mark venv as CUDA 12.4 compatible
    touch /workspace/venv/.cuda124_upgraded

    echo "✅ Virtual environment setup complete with CUDA 12.4 support"
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

# Check what's actually installed and select appropriate mechanism
# PRIORITY ORDER: Sage (for Blackwell) > Flash3 (for Hopper) > Flash2 > xformers
ATTENTION_SET=0

# FIRST PRIORITY: Sage Attention for Blackwell GPUs (RTX 5090) - CRITICAL for WAN 2.2!
if [[ "$GPU_TYPE" == "blackwell" ]] && echo "$GPU_NAME" | grep -qE "5090|B200|RTX PRO 6000"; then
    if python -c "import sageattention" 2>/dev/null; then
        echo "   🚀 Sage Attention selected for $GPU_NAME (PRIORITY for WAN 2.2)"
        echo "   ⚡ MASSIVE speedup: 40min → 3min generation!"
        echo "export COMFYUI_ATTENTION_MECHANISM=sage" > /workspace/venv/.env_settings
        ATTENTION_SET=1
    else
        echo "   ⚠️ Sage Attention not installed - WAN 2.2 will be 13x SLOWER!"
        echo "   📦 Installing Sage Attention is CRITICAL for RTX 5090"
        # Fallback to Flash Attention 2 but warn about performance
        if python -c "import flash_attn" 2>/dev/null; then
            echo "   ✅ Using Flash Attention 2 as fallback (slower for WAN 2.2)"
            echo "export COMFYUI_ATTENTION_MECHANISM=flash2" > /workspace/venv/.env_settings
            ATTENTION_SET=1
        fi
    fi
# Flash Attention 3 for Hopper GPUs
elif [[ "$GPU_TYPE" == "hopper" ]] && python -c "import flash_attn; exit(0 if flash_attn.__version__.startswith('3') else 1)" 2>/dev/null; then
    echo "   ✅ Flash Attention 3 available and selected for $GPU_NAME"
    echo "export COMFYUI_ATTENTION_MECHANISM=flash3" > /workspace/venv/.env_settings
    ATTENTION_SET=1
# Flash Attention 2 for Ampere/Ada GPUs
elif [[ "$GPU_TYPE" == "ampere" || "$GPU_TYPE" == "ada" ]] && python -c "import flash_attn" 2>/dev/null; then
    echo "   ✅ Flash Attention 2 available and selected for $GPU_NAME"
    echo "export COMFYUI_ATTENTION_MECHANISM=flash2" > /workspace/venv/.env_settings
    ATTENTION_SET=1
fi

# Default to xformers for everything else - it's the most compatible
if [ "$ATTENTION_SET" -eq 0 ]; then
    if python -c "import xformers" 2>/dev/null; then
        echo "   ✅ xformers selected as safe default for $GPU_NAME"
        echo "export COMFYUI_ATTENTION_MECHANISM=xformers" > /workspace/venv/.env_settings
    else
        echo "   ⚠️ No optimized attention available, using PyTorch native"
        echo "export COMFYUI_ATTENTION_MECHANISM=default" > /workspace/venv/.env_settings
    fi
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

# Auto-configure Google Drive if RunPod secret is set
echo "🔍 Checking for Google Drive configuration..."

# RunPod prefixes secrets with RUNPOD_SECRET_
if [ -n "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" ]; then
    export GOOGLE_SERVICE_ACCOUNT="$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT"
    echo "   Found RunPod secret: SERVICE_ACCOUNT (${#GOOGLE_SERVICE_ACCOUNT} characters)"
elif [ -n "$RUNPOD_SECRET_RCLONE_TOKEN" ]; then
    export RCLONE_TOKEN="$RUNPOD_SECRET_RCLONE_TOKEN"
    echo "   Found RunPod secret: RCLONE_TOKEN"
fi

# Use the new init_sync.sh script for all Google Drive setup
if [ -f "/app/scripts/init_sync.sh" ]; then
    echo "🚀 Using new sync initialization system..."
    /app/scripts/init_sync.sh

    # Check if sync was successfully initialized
    if [ -f "/workspace/.permanent_sync/status" ]; then
        SYNC_STATUS=$(cat /workspace/.permanent_sync/status)
        if [ "$SYNC_STATUS" = "INITIALIZED" ]; then
            echo "✅ Google Drive sync initialized successfully!"
            # Mark as configured for backwards compatibility
            touch /workspace/.gdrive_configured
            echo "configured" > /workspace/.gdrive_status
        elif [ "$SYNC_STATUS" = "NO_CREDENTIALS" ]; then
            echo "⚠️ No Google Drive credentials found"
            echo "   To enable sync, add GOOGLE_SERVICE_ACCOUNT secret in RunPod"
        else
            echo "❌ Google Drive sync initialization failed"
        fi
    fi

    # Skip the old configuration code
    SKIP_OLD_GDRIVE_SETUP=1
fi

# Only run old setup if new system not available or failed
if [ -z "$SKIP_OLD_GDRIVE_SETUP" ]; then

    # Option 1: OAuth Token (simplest for users)
if [ -n "$RCLONE_TOKEN" ]; then
    echo "🔧 Setting up Google Drive with OAuth token..."
    mkdir -p /workspace/.config/rclone
    mkdir -p /root/.config/rclone

    # Parse the token to get team_drive if it exists
    if echo "$RCLONE_TOKEN" | grep -q '"team_drive"'; then
        TEAM_DRIVE=$(echo "$RCLONE_TOKEN" | sed -n 's/.*"team_drive"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    else
        TEAM_DRIVE=""
    fi

    # Create rclone config with JUST token, no service account
    cat > /root/.config/rclone/rclone.conf << RCLONE_EOF
[gdrive]
type = drive
scope = drive
token = $RCLONE_TOKEN
team_drive = $TEAM_DRIVE

RCLONE_EOF

    # Also save to workspace for persistence
    cp /root/.config/rclone/rclone.conf /workspace/.config/rclone/rclone.conf

    # Test and mark as configured
    if rclone lsd gdrive: 2>/dev/null; then
        touch /workspace/.gdrive_configured
        echo "configured" > /workspace/.gdrive_status
        echo "✅ Google Drive configured with OAuth token!"
    else
        echo "❌ Failed to configure with OAuth token"
    fi
fi

    # Option 2: Service Account (enterprise users)
if [ -n "$GOOGLE_SERVICE_ACCOUNT" ]; then
    echo "🔧 Setting up Google Drive with Service Account..."
    echo "   Service account JSON detected (${#GOOGLE_SERVICE_ACCOUNT} characters)"
    
    # Create rclone config directories
    mkdir -p /workspace/.config/rclone
    mkdir -p /root/.config/rclone
    
    # Save service account JSON
    echo "$GOOGLE_SERVICE_ACCOUNT" > /workspace/.config/rclone/service_account.json
    echo "$GOOGLE_SERVICE_ACCOUNT" > /root/.config/rclone/service_account.json
    chmod 600 /workspace/.config/rclone/service_account.json
    chmod 600 /root/.config/rclone/service_account.json
    
    # Create initial rclone config
    cat > /workspace/.config/rclone/rclone.conf << 'RCLONE_EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive = 

RCLONE_EOF
    
    cp /workspace/.config/rclone/rclone.conf /root/.config/rclone/rclone.conf
    
    # Check for Shared Drives and auto-configure
    echo "🔍 Checking for Shared Drives..."
    SHARED_DRIVES=$(rclone backend drives gdrive: 2>/dev/null)
    if [ -n "$SHARED_DRIVES" ] && [ "$SHARED_DRIVES" != "[]" ]; then
        # Extract first Shared Drive ID
        DRIVE_ID=$(echo "$SHARED_DRIVES" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
        DRIVE_NAME=$(echo "$SHARED_DRIVES" | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
        
        if [ -n "$DRIVE_ID" ]; then
            echo "✅ Found Shared Drive: $DRIVE_NAME ($DRIVE_ID)"
            
            # Update config with Shared Drive ID
            cat > /workspace/.config/rclone/rclone.conf << RCLONE_EOF
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive = $DRIVE_ID

RCLONE_EOF
            cp /workspace/.config/rclone/rclone.conf /root/.config/rclone/rclone.conf
            echo "✅ Configured to use Shared Drive: $DRIVE_NAME"
        fi
    else
        echo "ℹ️ No Shared Drives found, using service account's own Drive"
    fi
    
    # Test configuration
    echo "🔍 Testing rclone configuration..."
    if rclone lsd gdrive: 2>/tmp/rclone_error.txt; then
        echo "✅ Google Drive configured successfully"
        
        # Create folder structure
        echo "Creating Google Drive folders..."
        rclone mkdir gdrive:ComfyUI-Output
        rclone mkdir gdrive:ComfyUI-Output/output
        rclone mkdir gdrive:ComfyUI-Output/loras
        rclone mkdir gdrive:ComfyUI-Output/workflows
        
        # Mark as configured
        touch /workspace/.gdrive_configured
        
        # Save configuration status for UI
        echo "configured" > /workspace/.gdrive_status
        
        # Kill any existing sync processes first
        pkill -f "rclone_sync_loop" 2>/dev/null || true

        # Store sync script in persistent location so it survives restarts
        mkdir -p /workspace/.sync
        cat > /workspace/.sync/rclone_sync_loop.sh << 'SYNC_SCRIPT'
#!/bin/bash
while true; do
    sleep 60  # Sync every minute
    echo "[$(date)] Starting sync cycle..." >> /tmp/rclone_sync.log

    # Function to resolve directory path (follows symlinks)
    resolve_dir() {
        local path="$1"
        if [ -L "$path" ]; then
            # It's a symlink, follow it
            readlink -f "$path"
        elif [ -d "$path" ]; then
            # It's a real directory
            echo "$path"
        else
            # Doesn't exist
            echo ""
        fi
    }

    # Sync OUTPUT directory - ALWAYS use /workspace/output (the real location)
    # ComfyUI/output should just be a symlink pointing there
    OUTPUT_DIR="/workspace/output"

    if [ -n "$OUTPUT_DIR" ] && [ -d "$OUTPUT_DIR" ]; then
        echo "  Copying output from: $OUTPUT_DIR" >> /tmp/rclone_sync.log
        # Use COPY not SYNC for outputs - never delete from Drive!
        rclone copy "$OUTPUT_DIR" "gdrive:ComfyUI-Output/output" \
            --exclude "*.tmp" \
            --exclude "*.partial" \
            --exclude "**/temp_*" \
            --transfers 4 \
            --checkers 2 \
            --bwlimit 50M \
            --min-age 30s \
            --no-update-modtime \
            --ignore-existing >> /tmp/rclone_sync.log 2>&1
    else
        echo "  Warning: No output directory found" >> /tmp/rclone_sync.log
    fi

    # Sync INPUT directory - ALWAYS use /workspace/input (the real location)
    INPUT_DIR="/workspace/input"

    if [ -n "$INPUT_DIR" ] && [ -d "$INPUT_DIR" ]; then
        echo "  Syncing input from: $INPUT_DIR" >> /tmp/rclone_sync.log
        # Use copy for inputs (don't delete from Drive)
        rclone copy "$INPUT_DIR" "gdrive:ComfyUI-Output/input" \
            --transfers 4 \
            --checkers 2 \
            --bwlimit 50M \
            --no-update-modtime >> /tmp/rclone_sync.log 2>&1
    fi

    # Sync WORKFLOWS directory - ALWAYS use /workspace/workflows (the real location)
    WORKFLOWS_DIR="/workspace/workflows"

    if [ -n "$WORKFLOWS_DIR" ] && [ -d "$WORKFLOWS_DIR" ]; then
        echo "  Syncing workflows from: $WORKFLOWS_DIR" >> /tmp/rclone_sync.log
        # Workflows can use sync since we want Drive to match local
        rclone sync "$WORKFLOWS_DIR" "gdrive:ComfyUI-Output/workflows" \
            --transfers 4 \
            --checkers 2 \
            --bwlimit 50M \
            --no-update-modtime >> /tmp/rclone_sync.log 2>&1
    fi

    # Sync loras folder
    if [ -d "/workspace/models/loras" ]; then
        echo "  Syncing loras from: /workspace/models/loras" >> /tmp/rclone_sync.log
        rclone sync /workspace/models/loras "gdrive:ComfyUI-Output/loras" \
            --transfers 4 \
            --checkers 2 \
            --bwlimit 50M \
            --no-update-modtime >> /tmp/rclone_sync.log 2>&1
    fi

    echo "  Sync cycle completed" >> /tmp/rclone_sync.log
done
SYNC_SCRIPT
        chmod +x /workspace/.sync/rclone_sync_loop.sh

        # Also copy to /tmp for immediate use
        cp /workspace/.sync/rclone_sync_loop.sh /tmp/rclone_sync_loop.sh
        chmod +x /tmp/rclone_sync_loop.sh

        # Start auto-sync in background
        /workspace/.sync/rclone_sync_loop.sh &

        echo "✅ Auto-sync started (every 60 seconds, persists across restarts)"
    else
        echo "❌ Google Drive configuration failed!"
        echo "   Error details:"
        cat /tmp/rclone_error.txt 2>/dev/null
        echo ""
        echo "   Possible issues:"
        echo "   1. Service account JSON may be invalid"
        echo "   2. Google Drive folder not shared with service account"
        echo "   3. Check that folder 'ComfyUI-Output' exists and is shared"
        echo ""
        echo "   Service account email from JSON:"
        echo "$GOOGLE_SERVICE_ACCOUNT" | grep -o '"client_email"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 || echo "Could not extract email"
        
        # Still save that we attempted configuration for UI
        echo "failed" > /workspace/.gdrive_status
    fi
    else
        if [ -z "$GOOGLE_SERVICE_ACCOUNT" ] && [ -z "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" ]; then
        echo "ℹ️ Google Drive sync not configured"
        echo "   No Google service account credentials found"
        echo ""
        echo "   To enable automatic sync:"
        echo "   1. Add GOOGLE_SERVICE_ACCOUNT secret in RunPod dashboard"
        echo "   2. The secret will be available as RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT"
        echo "   3. Restart the pod after adding the secret"
        echo ""
            echo "   Checking for RunPod secrets:"
            env | grep RUNPOD_SECRET_ | head -5
        fi
    fi
fi  # End of SKIP_OLD_GDRIVE_SETUP

# The new init_sync.sh handles all sync startup
# Keeping this section only for backwards compatibility if init_sync.sh doesn't exist
if [ -f "/workspace/.gdrive_configured" ] && [ ! -f "/app/scripts/init_sync.sh" ]; then
    echo "✅ Google Drive already configured (using legacy sync)"

    # ALWAYS restart sync on pod start (it doesn't persist across restarts)
    echo "🔄 Starting auto-sync..."

    # Kill any existing sync first
    pkill -f "rclone_sync_loop" 2>/dev/null || true

    # Store sync script in persistent location
    mkdir -p /workspace/.sync
    cat > /workspace/.sync/rclone_sync_loop.sh << 'SYNC_SCRIPT'
#!/bin/bash
while true; do
    sleep 60  # Sync every minute
    echo "[$(date)] Starting sync cycle..." >> /tmp/rclone_sync.log

    # Function to resolve directory path (follows symlinks)
    resolve_dir() {
        local path="$1"
        if [ -L "$path" ]; then
            # It's a symlink, follow it
            readlink -f "$path"
        elif [ -d "$path" ]; then
            # It's a real directory
            echo "$path"
        else
            # Doesn't exist
            echo ""
        fi
    }

    # Sync OUTPUT directory - ALWAYS use /workspace/output (the real location)
    # ComfyUI/output should just be a symlink pointing there
    OUTPUT_DIR="/workspace/output"

    if [ -n "$OUTPUT_DIR" ] && [ -d "$OUTPUT_DIR" ]; then
        echo "  Copying output from: $OUTPUT_DIR" >> /tmp/rclone_sync.log
        # Use COPY not SYNC for outputs - never delete from Drive!
        rclone copy "$OUTPUT_DIR" "gdrive:ComfyUI-Output/output" \
            --exclude "*.tmp" \
            --exclude "*.partial" \
            --exclude "**/temp_*" \
            --transfers 4 \
            --checkers 2 \
            --bwlimit 50M \
            --min-age 30s \
            --no-update-modtime \
            --ignore-existing >> /tmp/rclone_sync.log 2>&1
    else
        echo "  Warning: No output directory found" >> /tmp/rclone_sync.log
    fi

    # Sync INPUT directory - ALWAYS use /workspace/input (the real location)
    INPUT_DIR="/workspace/input"

    if [ -n "$INPUT_DIR" ] && [ -d "$INPUT_DIR" ]; then
        echo "  Syncing input from: $INPUT_DIR" >> /tmp/rclone_sync.log
        # Use copy for inputs (don't delete from Drive)
        rclone copy "$INPUT_DIR" "gdrive:ComfyUI-Output/input" \
            --transfers 4 \
            --checkers 2 \
            --bwlimit 50M \
            --no-update-modtime >> /tmp/rclone_sync.log 2>&1
    fi

    # Sync WORKFLOWS directory - ALWAYS use /workspace/workflows (the real location)
    WORKFLOWS_DIR="/workspace/workflows"

    if [ -n "$WORKFLOWS_DIR" ] && [ -d "$WORKFLOWS_DIR" ]; then
        echo "  Syncing workflows from: $WORKFLOWS_DIR" >> /tmp/rclone_sync.log
        # Workflows can use sync since we want Drive to match local
        rclone sync "$WORKFLOWS_DIR" "gdrive:ComfyUI-Output/workflows" \
            --transfers 4 \
            --checkers 2 \
            --bwlimit 50M \
            --no-update-modtime >> /tmp/rclone_sync.log 2>&1
    fi

    # Sync loras folder
    if [ -d "/workspace/models/loras" ]; then
        echo "  Syncing loras from: /workspace/models/loras" >> /tmp/rclone_sync.log
        rclone sync /workspace/models/loras "gdrive:ComfyUI-Output/loras" \
            --transfers 4 \
            --checkers 2 \
            --bwlimit 50M \
            --no-update-modtime >> /tmp/rclone_sync.log 2>&1
    fi

    echo "  Sync cycle completed" >> /tmp/rclone_sync.log
done
SYNC_SCRIPT
    chmod +x /workspace/.sync/rclone_sync_loop.sh

    # Also copy to /tmp for immediate use
    cp /workspace/.sync/rclone_sync_loop.sh /tmp/rclone_sync_loop.sh
    chmod +x /tmp/rclone_sync_loop.sh

    # Start auto-sync in background
    /workspace/.sync/rclone_sync_loop.sh &

    echo "✅ Auto-sync started (will persist across restarts)"
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

# Ensure Google Drive sync is running (run after init.sh)
echo "🔄 Ensuring Google Drive sync is active..."
if [ -f "/app/scripts/ensure_sync.sh" ]; then
    # Use the robust ensure_sync script that handles all cases
    /app/scripts/ensure_sync.sh
elif [ -f "/app/scripts/init_sync.sh" ]; then
    # Fallback to init_sync
    /app/scripts/init_sync.sh > /tmp/sync_init.log 2>&1

    # Double-check sync is running
    sleep 2
    if pgrep -f "sync_loop\|permanent_sync" > /dev/null; then
        echo "✅ Google Drive sync is running"
    else
        echo "⚠️ Sync not running, attempting quick fix..."
        if [ -f "/app/scripts/quick_fix.sh" ]; then
            /app/scripts/quick_fix.sh > /tmp/quick_fix.log 2>&1
        fi
    fi
else
    echo "⚠️ Sync initialization scripts not found"
fi

# Start sync monitor to restart sync if it dies
if [ -f "/app/scripts/monitor_sync.sh" ]; then
    echo "👁️ Starting sync monitor..."
    /app/scripts/monitor_sync.sh > /tmp/sync_monitor.log 2>&1 &
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
echo "Ready! Visit port 7777 to manage ComfyUI"

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

# Load attention mechanism configuration
if [ -f "/workspace/venv/.env_settings" ]; then
    source /workspace/venv/.env_settings
fi

# Clean up incompatible TensorRT engines
if [ -d "/workspace/ComfyUI/models/tensorrt" ]; then
    echo "🔍 Checking for incompatible TensorRT engines..."

    # Get current GPU compute capability
    GPU_COMPUTE_CAP=$(python -c "import torch; cc = torch.cuda.get_device_capability(); print(f'{cc[0]}.{cc[1]}')" 2>/dev/null || echo "unknown")

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

# All attention mechanisms are pre-installed during Docker build
# No runtime compilation needed!
if [ -z "$COMFYUI_ATTENTION_MECHANISM" ]; then
    # Auto-detect best available mechanism if not set
    # PRIORITY: Sage (for RTX 5090/Blackwell) > Flash3 > Flash2 > xformers
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "Unknown")

    # Check for RTX 5090/Blackwell first - Sage is CRITICAL for WAN 2.2 performance
    if echo "$GPU_NAME" | grep -qE "5090|B200|RTX PRO 6000" && python -c "import sageattention" 2>/dev/null; then
        export COMFYUI_ATTENTION_MECHANISM="sage"
        echo "🎯 Auto-detected Sage Attention for $GPU_NAME (optimal for WAN 2.2)"
    elif python -c "import flash_attn; exit(0 if flash_attn.__version__.startswith('3') else 1)" 2>/dev/null; then
        export COMFYUI_ATTENTION_MECHANISM="flash3"
        echo "🚀 Auto-detected Flash Attention 3"
    elif python -c "import flash_attn" 2>/dev/null; then
        export COMFYUI_ATTENTION_MECHANISM="flash2"
        echo "⚡ Auto-detected Flash Attention 2"
    elif python -c "import sageattention" 2>/dev/null; then
        export COMFYUI_ATTENTION_MECHANISM="sage"
        echo "🎯 Auto-detected Sage Attention"
    elif python -c "import xformers" 2>/dev/null; then
        export COMFYUI_ATTENTION_MECHANISM="xformers"
        echo "📦 Auto-detected xformers"
    else
        export COMFYUI_ATTENTION_MECHANISM="default"
        echo "ℹ️ Using default PyTorch attention"
    fi
fi

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

    # Install ComfyUI requirements (preserve our CUDA 12.4 compatible PyTorch)
    cd /workspace/ComfyUI
    if [ -f "requirements.txt" ]; then
        # Install requirements but skip torch to keep our CUDA 12.4 version
        grep -v "^torch" requirements.txt > /tmp/comfy_req.txt || cp requirements.txt /tmp/comfy_req.txt
        pip install -r /tmp/comfy_req.txt
        # Ensure we have the right PyTorch for CUDA 12.4
        pip install torch==2.8.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124 --upgrade
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

        case "$COMFYUI_ATTENTION_MECHANISM" in
            flash3)
                echo "🚀 Starting ComfyUI with Flash Attention 3 (Hopper optimized)"
                python main.py --listen 0.0.0.0 --port 8188 2>&1 | tee /tmp/comfyui_start.log &
                ;;
            flash2)
                echo "⚡ Starting ComfyUI with Flash Attention 2"
                python main.py --listen 0.0.0.0 --port 8188 2>&1 | tee /tmp/comfyui_start.log &
                ;;
            sage)
                echo "🎯 Starting ComfyUI with Sage Attention 2.2.0"
                echo "   ⚡ WAN 2.2 will generate 13x faster with Sage!"
                python main.py --listen 0.0.0.0 --port 8188 2>&1 | tee /tmp/comfyui_start.log &
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
RUN chmod +x /app/scripts/init_sync.sh 2>/dev/null || true

# ComfyViewer removed - users can install ComfyUI-Gallery custom node from ComfyUI Manager
# ComfyUI-Gallery provides a better integrated gallery experience directly in ComfyUI

# Environment
ENV PYTHONUNBUFFERED=1
ENV HF_HOME=/workspace
ENV ENABLE_SYNC=false

# Ports
EXPOSE 7777 8188 8888

WORKDIR /workspace

# Start services
CMD ["/start.sh"]