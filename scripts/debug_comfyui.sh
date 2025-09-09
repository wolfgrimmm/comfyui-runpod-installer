#!/bin/bash

# Debug script to check ComfyUI installation issues

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 ComfyUI Installation Debugger"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "1. Checking /workspace directory:"
ls -la /workspace/ | head -20

echo ""
echo "2. Checking ComfyUI directory:"
if [ -d "/workspace/ComfyUI" ]; then
    echo "Directory exists. Contents:"
    ls -la /workspace/ComfyUI/ | head -20
    
    echo ""
    echo "3. Checking for main.py:"
    if [ -f "/workspace/ComfyUI/main.py" ]; then
        echo "✅ main.py exists"
        ls -la /workspace/ComfyUI/main.py
    else
        echo "❌ main.py NOT found"
    fi
else
    echo "❌ ComfyUI directory does NOT exist"
fi

echo ""
echo "4. Git configuration:"
git config --global --list 2>/dev/null || echo "No git config"

echo ""
echo "5. Testing git clone:"
cd /tmp
rm -rf test-clone
if git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git test-clone; then
    echo "✅ Git clone works"
    rm -rf test-clone
else
    echo "❌ Git clone failed"
    
    echo ""
    echo "6. Testing wget:"
    if wget -q --spider https://github.com/comfyanonymous/ComfyUI; then
        echo "✅ Can reach GitHub via wget"
    else
        echo "❌ Cannot reach GitHub"
    fi
fi

echo ""
echo "7. Network connectivity:"
ping -c 1 github.com 2>/dev/null && echo "✅ Can ping GitHub" || echo "❌ Cannot ping GitHub"
curl -I https://github.com 2>/dev/null | head -1

echo ""
echo "8. Disk space:"
df -h /workspace

echo ""
echo "9. Python check:"
python --version
python -c "import sys; print(f'Python path: {sys.executable}')"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Debug complete. Check output above for issues."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"