#!/bin/bash

# Start UI Manager for ComfyUI
echo "Starting ComfyUI Manager UI..."

# Activate virtual environment
source /workspace/venv/bin/activate

# Install Flask if not already installed
pip install flask psutil

# Kill any existing UI process
fuser -k 7777/tcp 2>/dev/null || true

# Start the UI
cd /workspace/ui
python app.py