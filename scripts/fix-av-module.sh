#!/bin/bash

echo "🔧 Installing missing 'av' module for ComfyUI video support..."

# Activate venv
if [ -f "/workspace/venv/bin/activate" ]; then
    source /workspace/venv/bin/activate
    echo "✅ Virtual environment activated"
else
    echo "❌ Virtual environment not found at /workspace/venv"
    exit 1
fi

# Install av module
echo "📦 Installing av (PyAV) module..."
pip install av

# Verify installation
if python -c "import av; print(f'✅ av module version {av.__version__} installed successfully')" 2>/dev/null; then
    echo ""
    echo "✅ Installation complete! You can now start ComfyUI from the Control Panel."
else
    echo "❌ Failed to install av module"
    exit 1
fi