#!/bin/bash
# Fast initialization with persistent venv

echo "===================================="
echo "🚀 Fast ComfyUI Initialization"
echo "===================================="

# Check if venv exists and is complete
if [ -f "/workspace/venv/bin/activate" ] && [ -f "/workspace/venv/.setup_complete" ]; then
    echo "✅ Using existing venv - FAST START!"
    source /workspace/venv/bin/activate
else
    echo "📦 First run - Setting up virtual environment..."
    echo "This will take 5-10 minutes but only happens once."
    
    # Create venv
    python3 -m venv /workspace/venv
    source /workspace/venv/bin/activate
    
    # Upgrade pip
    pip install --upgrade pip wheel setuptools
    
    # Install PyTorch with CUDA 12.4
    echo "Installing PyTorch with CUDA 12.4..."
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124
    
    # Clone ComfyUI if needed
    if [ ! -d "/workspace/ComfyUI" ]; then
        cd /workspace
        git clone https://github.com/comfyanonymous/ComfyUI.git
    fi
    
    # Install ComfyUI requirements
    echo "Installing ComfyUI requirements..."
    pip install -r /workspace/ComfyUI/requirements.txt
    
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
        tqdm \
        psutil
    
    # Mark as complete
    touch /workspace/venv/.setup_complete
    echo "✅ Virtual environment setup complete!"
fi

# Ensure ComfyUI exists
if [ ! -f "/workspace/ComfyUI/main.py" ]; then
    echo "📦 Installing ComfyUI..."
    cd /workspace
    git clone https://github.com/comfyanonymous/ComfyUI.git
fi

# Create model directories
echo "Setting up directories..."
mkdir -p /workspace/ComfyUI/custom_nodes
mkdir -p /workspace/models/{audio_encoders,checkpoints,clip,clip_vision,configs,controlnet,diffusers,diffusion_models,embeddings,gligen,hypernetworks,loras,model_patches,photomaker,style_models,text_encoders,unet,upscale_models,vae,vae_approx}
mkdir -p /workspace/output
mkdir -p /workspace/input

# Setup symlinks
rm -rf /workspace/ComfyUI/models
ln -sf /workspace/models /workspace/ComfyUI/models

# Install ComfyUI Manager (CRITICAL)
cd /workspace/ComfyUI/custom_nodes
if [ ! -d "ComfyUI-Manager" ]; then
    echo "🎯 Installing ComfyUI Manager..."
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git
    
    if [ -d "ComfyUI-Manager" ] && [ -f "ComfyUI-Manager/requirements.txt" ]; then
        pip install -r ComfyUI-Manager/requirements.txt
    fi
    
    if [ -f "ComfyUI-Manager/install.py" ]; then
        cd ComfyUI-Manager
        python install.py || true
        cd ..
    fi
else
    echo "✅ ComfyUI Manager already installed"
fi

# Install other custom nodes from config
if [ -f "/app/config/baseline-nodes.txt" ]; then
    while IFS= read -r node || [ -n "$node" ]; do
        [[ "$node" =~ ^#.*$ ]] && continue
        [[ -z "$node" ]] && continue
        repo_name=$(echo "$node" | sed 's/.*\///')
        
        if [ "$repo_name" != "ComfyUI-Manager" ] && [ ! -d "$repo_name" ]; then
            echo "Installing: $repo_name"
            git clone "https://github.com/$node" || continue
            
            if [ -f "$repo_name/requirements.txt" ]; then
                pip install -r "$repo_name/requirements.txt" || true
            fi
            
            if [ -f "$repo_name/install.py" ]; then
                cd "$repo_name"
                python install.py || true
                cd ..
            fi
        fi
    done < /app/config/baseline-nodes.txt
fi

echo "✅ Fast initialization complete!"
echo "📍 Venv: /workspace/venv (persisted)"
echo "🚀 Ready to start ComfyUI"