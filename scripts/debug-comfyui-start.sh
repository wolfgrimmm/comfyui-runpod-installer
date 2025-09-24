#!/bin/bash

echo "========================================="
echo "🔍 ComfyUI Startup Diagnostic"
echo "========================================="
echo ""

# Check if venv exists
echo "1️⃣ Checking virtual environment..."
if [ -f "/workspace/venv/bin/activate" ]; then
    echo "✅ Venv exists at /workspace/venv"
    source /workspace/venv/bin/activate
    echo "   Python: $(which python)"
    echo "   Python version: $(python --version)"
else
    echo "❌ Venv NOT found at /workspace/venv"
    exit 1
fi

echo ""
echo "2️⃣ Checking ComfyUI installation..."
if [ -f "/workspace/ComfyUI/main.py" ]; then
    echo "✅ ComfyUI main.py exists"
else
    echo "❌ ComfyUI main.py NOT found"
    exit 1
fi

echo ""
echo "3️⃣ Checking required Python packages..."
python -c "import torch; print(f'✅ PyTorch {torch.__version__}')" 2>/dev/null || echo "❌ PyTorch not found"
python -c "import xformers; print('✅ xformers installed')" 2>/dev/null || echo "⚠️ xformers not found"
python -c "import sageattention; print('✅ Sage Attention installed')" 2>/dev/null || echo "⚠️ Sage Attention not found"

echo ""
echo "4️⃣ Checking GPU..."
nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo "❌ nvidia-smi failed"

echo ""
echo "5️⃣ Checking if port 8188 is in use..."
if lsof -i:8188 > /dev/null 2>&1; then
    echo "⚠️ Port 8188 is already in use by:"
    lsof -i:8188
else
    echo "✅ Port 8188 is free"
fi

echo ""
echo "6️⃣ Checking /app/start_comfyui.sh script..."
if [ -f "/app/start_comfyui.sh" ]; then
    echo "✅ Script exists"
    echo "   First 10 lines:"
    head -10 /app/start_comfyui.sh
else
    echo "❌ Script NOT found at /app/start_comfyui.sh"
fi

echo ""
echo "7️⃣ Testing direct ComfyUI startup..."
echo "Attempting to start ComfyUI directly (5 second test)..."
cd /workspace/ComfyUI

# Start ComfyUI in background with timeout
timeout 5 python main.py --listen 0.0.0.0 --port 8188 2>&1 | head -50 &
PID=$!

sleep 3

# Check if it started
if kill -0 $PID 2>/dev/null; then
    echo "✅ ComfyUI process is running (PID: $PID)"
    kill $PID 2>/dev/null
else
    echo "❌ ComfyUI process died immediately"
fi

echo ""
echo "8️⃣ Checking for error logs..."
if [ -f "/workspace/ui.log" ]; then
    echo "📋 Last 20 lines of /workspace/ui.log:"
    tail -20 /workspace/ui.log
fi

if [ -f "/tmp/comfyui_start.log" ]; then
    echo ""
    echo "📋 Last 20 lines of /tmp/comfyui_start.log:"
    tail -20 /tmp/comfyui_start.log
fi

echo ""
echo "========================================="
echo "Diagnostic complete!"
echo "========================================="