#!/bin/bash

# Universal initialization script that works with both traditional and fast builds
# Automatically uses venv if it exists, creates it if needed, or uses system Python

echo "===================================="
echo "🔧 Universal ComfyUI Initialization"
echo "===================================="

# Function to detect Python environment
detect_python_env() {
    # Check if we're already in a venv
    if [ -n "$VIRTUAL_ENV" ]; then
        echo "📍 Already in virtual environment: $VIRTUAL_ENV"
        return 0
    fi
    
    # Check if persistent venv exists and is complete
    if [ -f "/workspace/venv/bin/activate" ] && [ -f "/workspace/venv/.setup_complete" ]; then
        echo "✅ Found existing venv at /workspace/venv"
        source /workspace/venv/bin/activate
        return 0
    fi
    
    # Check if system has all required packages (traditional build)
    if python -c "import torch" 2>/dev/null; then
        echo "✅ Using system Python with pre-installed packages"
        return 0
    fi
    
    # No suitable environment found
    return 1
}

# Function to setup venv if needed
setup_venv_if_needed() {
    echo "📦 Setting up Python environment..."
    
    # Try to use existing environment first
    if detect_python_env; then
        return 0
    fi
    
    # Create venv in /workspace for persistence
    echo "Creating new venv at /workspace/venv..."
    echo "This will take 5-10 minutes on first run but will be reused later."
    
    python3 -m venv /workspace/venv
    source /workspace/venv/bin/activate
    
    # Upgrade pip
    pip install --upgrade pip wheel setuptools
    
    # Install PyTorch with CUDA 12.4
    echo "Installing PyTorch with CUDA 12.4..."
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124
    
    # Install ComfyUI requirements
    echo "Installing ComfyUI requirements..."
    if [ -f "/workspace/ComfyUI/requirements.txt" ]; then
        pip install -r /workspace/ComfyUI/requirements.txt
    else
        # Fallback: get requirements from repo
        git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /tmp/comfyui-req
        pip install -r /tmp/comfyui-req/requirements.txt
        rm -rf /tmp/comfyui-req
    fi
    
    # Install additional packages
    echo "Installing additional packages..."
    pip install \
        onnxruntime-gpu \
        opencv-python \
        accelerate \
        diffusers \
        jupyterlab \
        ipywidgets \
        notebook \
        flask==3.0.0 \
        psutil==5.9.0 \
        requests==2.31.0 \
        GitPython \
        PyGithub \
        matrix-client==0.4.0 \
        transformers \
        safetensors \
        aiohttp \
        pyyaml \
        Pillow \
        einops \
        torchsde \
        kornia \
        spandrel \
        tqdm
    
    # Mark venv as complete
    touch /workspace/venv/.setup_complete
    echo "✅ Virtual environment setup complete"
}

# Function to install ComfyUI
install_comfyui() {
    if [ ! -f "/workspace/ComfyUI/main.py" ]; then
        echo "📦 Installing ComfyUI..."
        
        # Remove any incomplete installation (including folders created by this script)
        if [ -d "/workspace/ComfyUI" ]; then
            echo "Removing incomplete ComfyUI directory..."
            rm -rf /workspace/ComfyUI
        fi
        
        # Also clean up any symlinks that might exist
        if [ -L "/workspace/ComfyUI/input" ]; then
            rm -f /workspace/ComfyUI/input
        fi
        if [ -L "/workspace/ComfyUI/output" ]; then
            rm -f /workspace/ComfyUI/output
        fi
        if [ -L "/workspace/ComfyUI/models" ]; then
            rm -f /workspace/ComfyUI/models
        fi
        
        cd /workspace
        
        # Try multiple methods to clone
        echo "Attempting to clone ComfyUI repository..."
        echo "Method 1: Standard clone..."
        if git clone https://github.com/comfyanonymous/ComfyUI.git ComfyUI 2>&1; then
            echo "✅ Successfully cloned ComfyUI"
        else
            echo "Method 1 failed, trying shallow clone..."
            if git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git ComfyUI 2>&1; then
                echo "✅ Successfully cloned ComfyUI (shallow)"
            else
                echo "Method 2 failed, trying wget download..."
                
                # Last resort: download as zip
                if wget https://github.com/comfyanonymous/ComfyUI/archive/refs/heads/master.zip -O comfyui.zip 2>&1; then
                    echo "Downloaded zip, extracting..."
                    if unzip -q comfyui.zip; then
                        mv ComfyUI-master ComfyUI
                        rm comfyui.zip
                        echo "✅ Downloaded ComfyUI via wget"
                    else
                        echo "❌ FATAL: Failed to extract ComfyUI zip"
                        return 1
                    fi
                else
                    echo "❌ FATAL: Could not download ComfyUI via any method"
                    echo "Please check your internet connection"
                    return 1
                fi
            fi
        fi
        
        # Verify installation
        if [ -f "/workspace/ComfyUI/main.py" ]; then
            echo "✅ ComfyUI successfully installed"
        else
            echo "❌ ComfyUI installation verification failed"
            return 1
        fi
    else
        echo "✅ ComfyUI already installed"
        if [ "${COMFYUI_AUTO_UPDATE:-false}" == "true" ]; then
            echo "🔄 Updating ComfyUI..."
            cd /workspace/ComfyUI && git pull || echo "Could not update"
        fi
    fi
}

# Function to ensure ComfyUI Manager is installed
ensure_manager() {
    cd /workspace/ComfyUI/custom_nodes
    
    if [ ! -d "ComfyUI-Manager" ]; then
        echo "🎯 Installing ComfyUI Manager (Required)..."
        git clone https://github.com/ltdrdata/ComfyUI-Manager.git || {
            echo "Retrying with shallow clone..."
            git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git
        }
    fi
    
    if [ -d "ComfyUI-Manager" ]; then
        # Install requirements
        if [ -f "ComfyUI-Manager/requirements.txt" ]; then
            echo "Installing Manager requirements..."
            pip install -r "ComfyUI-Manager/requirements.txt" 2>/dev/null || true
        fi
        
        # Run install script
        if [ -f "ComfyUI-Manager/install.py" ]; then
            cd ComfyUI-Manager
            python install.py 2>/dev/null || true
            cd ..
        fi
        
        echo "✅ ComfyUI Manager ready"
    else
        echo "⚠️ Failed to install ComfyUI Manager"
    fi
}

# Function to install custom nodes
install_custom_nodes() {
    if [ ! -f "/app/config/baseline-nodes.txt" ]; then
        return
    fi
    
    echo "📦 Installing custom nodes..."
    cd /workspace/ComfyUI/custom_nodes
    
    while IFS= read -r node || [ -n "$node" ]; do
        [[ "$node" =~ ^#.*$ ]] && continue
        [[ -z "$node" ]] && continue
        repo_name=$(echo "$node" | sed 's/.*\///')
        
        # Skip Manager (handled separately)
        if [ "$repo_name" == "ComfyUI-Manager" ]; then
            continue
        fi
        
        if [ ! -d "$repo_name" ]; then
            echo "  Installing: $repo_name"
            git clone "https://github.com/$node" 2>/dev/null || continue
            
            # Install requirements
            if [ -f "$repo_name/requirements.txt" ]; then
                pip install -r "$repo_name/requirements.txt" 2>/dev/null || true
            fi
            
            # Run install.py
            if [ -f "$repo_name/install.py" ]; then
                cd "$repo_name"
                python install.py 2>/dev/null || true
                cd ..
            fi
        else
            echo "  ✓ $repo_name already installed"
        fi
    done < /app/config/baseline-nodes.txt
}

# Configure git to avoid issues
configure_git() {
    # Set git config to avoid errors
    git config --global --add safe.directory /workspace
    git config --global --add safe.directory /workspace/ComfyUI
    git config --global --add safe.directory '*'
    
    # Set a default user if not set (required for some operations)
    if ! git config --global user.email > /dev/null 2>&1; then
        git config --global user.email "comfyui@runpod.local"
        git config --global user.name "ComfyUI"
    fi
}

# Main execution flow
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 0: Git Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
configure_git

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1: Python Environment"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
setup_venv_if_needed

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2: ComfyUI Installation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if ! install_comfyui; then
    echo "⚠️  WARNING: ComfyUI installation failed!"
    echo "The UI will start but ComfyUI won't be available."
    echo "You can try installing it later from the UI."
    # Don't exit - let the UI start so user can debug
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3: Directory Structure"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
# Create directories even if ComfyUI isn't installed yet
# This allows the UI to start and potentially install ComfyUI later
if [ -f "/workspace/ComfyUI/main.py" ]; then
    mkdir -p /workspace/ComfyUI/custom_nodes
    echo "✅ ComfyUI directories created"
else
    echo "⚠️  WARNING: ComfyUI not found at /workspace/ComfyUI/main.py"
    echo "Creating basic directory structure anyway..."
fi
mkdir -p /workspace/models/{audio_encoders,checkpoints,clip,clip_vision,configs,controlnet,diffusers,diffusion_models,embeddings,gligen,hypernetworks,loras,model_patches,photomaker,style_models,text_encoders,unet,upscale_models,vae,vae_approx}
mkdir -p /workspace/output
mkdir -p /workspace/input
mkdir -p /workspace/workflows

# Setup symlinks
rm -rf /workspace/ComfyUI/models
ln -sf /workspace/models /workspace/ComfyUI/models
echo "✅ Directories and symlinks ready"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4: ComfyUI Manager"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ensure_manager

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 5: Custom Nodes"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
install_custom_nodes

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Initialization Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Show environment info
if [ -n "$VIRTUAL_ENV" ]; then
    echo "📍 Using venv: $VIRTUAL_ENV"
else
    echo "📍 Using system Python"
fi

python --version
echo "📦 PyTorch: $(python -c 'import torch; print(torch.__version__)' 2>/dev/null || echo 'Not installed')"
echo "🎯 ComfyUI: /workspace/ComfyUI"
echo "📁 Models: /workspace/models"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"