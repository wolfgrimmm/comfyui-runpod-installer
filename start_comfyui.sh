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
