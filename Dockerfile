# Optimized for RunPod Pods - Uses RunPod's PyTorch base
# Using latest available RunPod image with CUDA 12.4 (we'll upgrade to 12.9)
FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

WORKDIR /

# Install system dependencies including Python build tools and rclone
RUN apt-get update && apt-get install -y \
    git wget curl psmisc lsof unzip \
    python3.11-dev python3.11-venv python3-pip \
    build-essential software-properties-common \
    && curl https://rclone.org/install.sh | bash \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install CUDA 12.9 Toolkit (without driver, using RunPod's driver)
RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb && \
    dpkg -i cuda-keyring_1.1-1_all.deb && \
    rm cuda-keyring_1.1-1_all.deb && \
    apt-get update && \
    apt-get install -y cuda-toolkit-12-9 libcudnn9-cuda-12 libcudnn9-dev-cuda-12 --no-install-recommends && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    # Create symlink for CUDA
    rm -f /usr/local/cuda && \
    ln -s /usr/local/cuda-12.9 /usr/local/cuda

# Set CUDA environment variables
ENV PATH="/usr/local/cuda-12.9/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/cuda-12.9/lib64:${LD_LIBRARY_PATH}"
ENV CUDA_HOME="/usr/local/cuda-12.9"
ENV CUDA_VERSION="12.9"

# Create app directory
RUN mkdir -p /app

# Copy application files
COPY scripts /app/scripts
COPY config /app/config
COPY ui /app/ui
RUN chmod +x /app/scripts/*.sh 2>/dev/null || true
RUN chmod +x /app/scripts/init_sync.sh 2>/dev/null || true

# Create init script that sets up venv if needed
RUN cat > /app/init.sh << 'EOF'
#!/bin/bash
set -e

# Quick check - if everything exists, exit fast
if [ -d "/workspace/venv" ] && [ -f "/workspace/ComfyUI/main.py" ] && [ -d "/workspace/ComfyUI/custom_nodes/ComfyUI-Manager" ]; then
    echo "✅ Environment already initialized (fast path)"
    exit 0
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
    python3.11 -m venv /workspace/venv
    source /workspace/venv/bin/activate
    NEED_INSTALL=1
elif [ ! -f "/workspace/venv/.cuda129_upgraded" ]; then
    echo "📦 Existing venv found, checking CUDA compatibility..."
    source /workspace/venv/bin/activate
    # Check if PyTorch has correct CUDA version
    CUDA_VER=$(python -c "import torch; print(torch.version.cuda)" 2>/dev/null || echo "none")
    if [[ "$CUDA_VER" != "12.4" ]]; then
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

    # ComfyUI requirements - PyTorch with CUDA 12.4 (better compatibility with 12.9)
    uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124
    uv pip install einops torchsde "kornia>=0.7.1" spandrel "safetensors>=0.4.2"
    uv pip install aiohttp pyyaml Pillow tqdm scipy
    uv pip install transformers diffusers accelerate
    uv pip install opencv-python

    # ONNX Runtime 1.19+ supports CUDA 12.x
    uv pip install onnxruntime-gpu==1.19.2 || pip install onnxruntime-gpu==1.19.2

    # Sage Attention for RTX 5090 optimization (pre-built wheels, no compilation)
    echo "Installing Sage Attention for RTX 5090..."
    uv pip install sageattention || echo "Sage Attention not available"

    # Install triton for GPU kernel optimization
    uv pip install triton  # Required for sageattention and other GPU optimizations

    # Install xformers for video model compatibility (Wan2.2 requires it)
    echo "Installing xformers for video generation..."
    uv pip install xformers --index-url https://download.pytorch.org/whl/cu124 || \
    pip install xformers || \
    echo "Warning: xformers failed to install - video models may not work properly"

    # Git integration
    uv pip install GitPython PyGithub==1.59.1

    # Jupyter
    uv pip install jupyterlab ipywidgets notebook

    # Mark venv as CUDA 12.9 compatible
    touch /workspace/venv/.cuda129_upgraded

    echo "✅ Virtual environment setup complete with CUDA 12.9 support"
fi

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

# Check PyTorch CUDA availability
python3 -c "import torch; print(f'PyTorch CUDA Available: {torch.cuda.is_available()}'); print(f'PyTorch CUDA Version: {torch.version.cuda}')" 2>/dev/null || echo "PyTorch CUDA check skipped"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
EOF

RUN chmod +x /app/init.sh

# Create startup script
RUN cat > /start.sh << 'EOF'
#!/bin/bash
set -e

echo "🚀 Starting RunPod Services..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Initialize environment (creates venv if needed)
/app/init.sh

# Activate virtual environment
source /workspace/venv/bin/activate

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

# Start Control Panel UI
echo "🌐 Starting Control Panel on port 7777..."
cd /app/ui && python app.py > /workspace/ui.log 2>&1 &

# Start JupyterLab
echo "📊 Starting JupyterLab on port 8888..."
jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root \
    --NotebookApp.token="" --NotebookApp.password="" \
    --ServerApp.allow_origin="*" > /workspace/jupyter.log 2>&1 &

# Wait for services
sleep 3

# Check status
if lsof -i:7777 > /dev/null 2>&1; then
    echo "✅ Control Panel running on http://localhost:7777"
    echo "   Use the Control Panel to install and start ComfyUI"
else
    echo "⚠️ Control Panel failed to start. Check /workspace/ui.log"
    tail -20 /workspace/ui.log 2>/dev/null || true
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

# Activate virtual environment
if [ -d "/workspace/venv" ]; then
    source /workspace/venv/bin/activate
else
    echo "⚠️ Virtual environment not found, creating..."
    /app/init.sh
    source /workspace/venv/bin/activate
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
    
    # Install ComfyUI requirements (preserve our CUDA 12.9 compatible PyTorch)
    cd /workspace/ComfyUI
    if [ -f "requirements.txt" ]; then
        # Install requirements but skip torch to keep our CUDA 12.4 version
        grep -v "^torch" requirements.txt > /tmp/comfy_req.txt || cp requirements.txt /tmp/comfy_req.txt
        pip install -r /tmp/comfy_req.txt
        # Ensure we have the right PyTorch for CUDA 12.9
        pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124 --upgrade
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

# Start ComfyUI
cd /workspace/ComfyUI
echo "Starting ComfyUI on port 8188..."
exec python main.py --listen 0.0.0.0 --port 8188
EOF

RUN chmod +x /app/start_comfyui.sh

# Environment
ENV PYTHONUNBUFFERED=1
ENV HF_HOME=/workspace

# Ports
EXPOSE 7777 8188 8888

WORKDIR /workspace

# Start services
CMD ["/start.sh"]