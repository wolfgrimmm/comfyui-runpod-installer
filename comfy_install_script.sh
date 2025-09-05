#!/bin/bash

# ComfyUI Installation Script for RunPod
# Uses uv for faster package installation

set -e

echo "=========================================="
echo "🚀 ComfyUI Installation with UV"
echo "=========================================="

# Configuration
WORKSPACE_DIR="/workspace"
COMFYUI_DIR="$WORKSPACE_DIR/ComfyUI"
VENV_DIR="$WORKSPACE_DIR/venv"
MODELS_DIR="$WORKSPACE_DIR/models"
WORKFLOWS_DIR="$WORKSPACE_DIR/workflows"
OUTPUT_DIR="$WORKSPACE_DIR/output"

cd "$WORKSPACE_DIR"

# Install uv for faster package management
echo "📦 Installing uv for faster package installation..."
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env
export PATH="$HOME/.local/bin:$PATH"

# Set UV link mode to avoid hardlink warnings on RunPod
export UV_LINK_MODE=copy

# Create directory structure
echo "📁 Creating directory structure..."
mkdir -p "$MODELS_DIR"
mkdir -p "$WORKFLOWS_DIR"
mkdir -p "$OUTPUT_DIR"

# Clone ComfyUI
echo "📥 Cloning ComfyUI..."
if [ -d "$COMFYUI_DIR" ]; then
    echo "⚠️  ComfyUI already exists, updating..."
    cd "$COMFYUI_DIR"
    git pull
    cd "$WORKSPACE_DIR"
else
    git clone https://github.com/comfyanonymous/ComfyUI.git
fi

# No need to copy models folder structure anymore - we'll use ComfyUI's folders directly

# Create virtual environment with uv
echo "🐍 Creating virtual environment with uv..."
if [ -d "$VENV_DIR" ]; then
    echo "⚠️  Virtual environment already exists, skipping creation..."
else
    uv venv "$VENV_DIR" --python 3.11
fi

# Activate virtual environment
echo "🔧 Activating virtual environment..."
source "$VENV_DIR/bin/activate"

# Upgrade pip and install base packages with uv
echo "⬆️  Upgrading pip and installing base packages..."
uv pip install --upgrade pip setuptools wheel

# Install ComfyUI requirements
echo "📋 Installing ComfyUI requirements..."
cd "$COMFYUI_DIR"
uv pip install -r requirements.txt

# Remove and reinstall PyTorch with specific version
echo "🔥 Installing PyTorch 2.7.0 with CUDA 12.8..."
uv pip uninstall torch torchvision xformers torchaudio || true
uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128

# Install custom nodes
echo "🔧 Installing custom nodes..."
cd "$COMFYUI_DIR/custom_nodes"

echo "📦 Installing ComfyUI Manager..."
if [ -d "ComfyUI-Manager" ]; then
    cd ComfyUI-Manager
    git pull
    cd ..
else
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git
fi

echo "📦 Installing IPAdapter Plus..."
if [ -d "ComfyUI_IPAdapter_plus" ]; then
    cd ComfyUI_IPAdapter_plus
    git pull
    cd ..
else
    git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git
fi

echo "📦 Installing ReActor..."
if [ -d "ComfyUI-ReActor" ]; then
    cd ComfyUI-ReActor
    git pull
else
    git clone https://github.com/Gourieff/ComfyUI-ReActor.git
    cd ComfyUI-ReActor
fi
python install.py
cd ..

echo "📦 Installing GGUF..."
if [ -d "ComfyUI-GGUF" ]; then
    cd ComfyUI-GGUF
    git pull
else
    git clone https://github.com/city96/ComfyUI-GGUF.git
    cd ComfyUI-GGUF
fi
if [ -f "requirements.txt" ]; then
    uv pip install -r requirements.txt
fi
cd ..

echo "📦 Installing Impact Pack..."
if [ -d "ComfyUI-Impact-Pack" ]; then
    cd ComfyUI-Impact-Pack
    git pull
else
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git
    cd ComfyUI-Impact-Pack
fi
python install.py
cd ..

cd "$COMFYUI_DIR"

# Install Flash Attention and related packages from specific wheel files
echo "🔥 Installing Flash Attention and related packages..."
uv pip install https://huggingface.co/MonsterMMORPG/SECourses_Premium_Flash_Attention/resolve/main/flash_attn-2.7.4.post1-cp310-cp310-linux_x86_64.whl
uv pip install https://huggingface.co/MonsterMMORPG/SECourses_Premium_Flash_Attention/resolve/main/sageattention-2.1.1-cp310-cp310-linux_x86_64.whl
uv pip install https://huggingface.co/MonsterMMORPG/SECourses_Premium_Flash_Attention/resolve/main/xformers-0.0.30+3abeaa9e.d20250427-cp310-cp310-linux_x86_64.whl

# Install additional AI packages
echo "🤖 Installing additional AI packages..."
uv pip install https://github.com/deepinsight/insightface/releases/download/v0.7.3/insightface-0.7.3-cp311-cp311-linux_x86_64.whl
uv pip install onnxruntime-gpu
uv pip install piexif
uv pip install triton
uv pip install deepspeed
uv pip install accelerate
uv pip install diffusers
uv pip install requests

# Install HuggingFace tools
echo "🤗 Installing HuggingFace tools..."
uv pip install huggingface_hub hf_transfer

# Set HuggingFace environment variables
echo "🔧 Setting HuggingFace environment variables..."
export HF_HOME="/workspace"
export HF_HUB_ENABLE_HF_TRANSFER=1
export HF_XET_CHUNK_CACHE_SIZE_BYTES=90737418240

# Install system utilities
echo "🛠️  Installing system utilities..."
apt update
apt install -y psmisc

# Download Reactor models if script exists
if [ -f "$WORKSPACE_DIR/Download_Reactor_Models.py" ]; then
    echo "📥 Downloading Reactor models..."
    cd "$WORKSPACE_DIR"
    python Download_Reactor_Models.py
fi

# Create symlinks in workspace pointing to ComfyUI folders
echo "🔗 Setting up symlinks from workspace to ComfyUI folders..."

# Remove workspace folders if they exist
[ -d "$MODELS_DIR" ] && rm -rf "$MODELS_DIR"
[ -d "$OUTPUT_DIR" ] && rm -rf "$OUTPUT_DIR"
[ -d "$WORKFLOWS_DIR" ] && rm -rf "$WORKFLOWS_DIR"

# Create symlinks from workspace to ComfyUI
ln -s "$COMFYUI_DIR/models" "$MODELS_DIR"
ln -s "$COMFYUI_DIR/output" "$OUTPUT_DIR"

# Create user/default/workflows directory if it doesn't exist
mkdir -p "$COMFYUI_DIR/user/default/workflows"
ln -s "$COMFYUI_DIR/user/default/workflows" "$WORKFLOWS_DIR"

echo "✅ Symlinks created:"
echo "   $MODELS_DIR -> $COMFYUI_DIR/models"
echo "   $OUTPUT_DIR -> $COMFYUI_DIR/output"
echo "   $WORKFLOWS_DIR -> $COMFYUI_DIR/user/default/workflows"

# Models directory created above - subdirectories will come from Google Drive sync

# Create startup script
echo "📝 Creating startup script..."
cat > "$WORKSPACE_DIR/start_comfyui.sh" << 'EOF'
#!/bin/bash
# ComfyUI Startup Script

# Ensure psmisc is installed for fuser command
if ! command -v fuser &> /dev/null; then
    echo "Installing psmisc for port management..."
    apt update
    apt install -y psmisc
fi

# Kill any existing ComfyUI processes
echo "Clearing port 8188..."
fuser -k 8188/tcp 2>/dev/null || true

# Activate virtual environment
source /workspace/venv/bin/activate

# Set environment variables
export HF_HOME="/workspace"
export HF_HUB_ENABLE_HF_TRANSFER=1
export COMFYUI_PATH="/workspace/ComfyUI"
export COMFYUI_MODEL_PATH="/workspace/models"

# Change to ComfyUI directory and start
cd /workspace/ComfyUI
echo "Starting ComfyUI on port 8188..."
python main.py --use-sage-attention --listen 0.0.0.0 --port 8188
EOF

chmod +x "$WORKSPACE_DIR/start_comfyui.sh"

echo ""
echo "=========================================="
echo "🎉 ComfyUI Installation Complete!"
echo "=========================================="
echo ""
echo "📋 Installation Summary:"
echo "✅ ComfyUI installed with uv for faster package management"
echo "✅ Virtual environment created at: $VENV_DIR"
echo "✅ Shared folder structure created with symlinks"
echo "✅ Flash Attention, XFormers, and AI packages installed"
echo "✅ Model subdirectories created"
echo "✅ Startup script created"
echo ""
echo "📁 Directory Structure:"
echo "   /workspace/venv/           - Virtual environment"
echo "   /workspace/ComfyUI/        - ComfyUI installation"
echo "   /workspace/models/         - Symlink to ComfyUI/models"
echo "   /workspace/workflows/      - Symlink to ComfyUI/user/default/workflows"
echo "   /workspace/output/         - Symlink to ComfyUI/output"
echo ""
echo "🚀 Next Steps:"
echo "1. Run custom nodes installation: ./install_custom_nodes.sh"
echo "2. Download models or sync with Google Drive"
echo "3. Start ComfyUI: ./start_comfyui.sh"
echo "   OR manually: source /workspace/venv/bin/activate && cd /workspace/ComfyUI && python main.py --listen 0.0.0.0"
echo ""
echo "🌐 ComfyUI will be available at: http://localhost:8188"
echo "🔗 Use RunPod's port 8188 connect button"
echo "=========================================="
