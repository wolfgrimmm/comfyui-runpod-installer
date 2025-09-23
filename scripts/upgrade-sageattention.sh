#!/bin/bash

echo "========================================="
echo "🔄 SageAttention 2.2.0 Upgrade Script"
echo "========================================="
echo ""
echo "This will upgrade your existing installation to use SageAttention 2.2.0"
echo "with SageAttention2++ for 13x WAN 2.2 speedup!"
echo ""

# Check if we're in the right location
if [ ! -d "/workspace" ]; then
    echo "❌ Error: /workspace not found. Run this inside your RunPod container."
    exit 1
fi

echo "📦 Step 1: Removing old venv to force clean rebuild..."
if [ -d "/workspace/venv" ]; then
    rm -rf /workspace/venv
    echo "   ✅ Old venv removed"
else
    echo "   ℹ️ No existing venv found"
fi

echo ""
echo "🧹 Step 2: Clearing Triton/CUDA caches..."
rm -rf /root/.triton/cache/* 2>/dev/null
rm -rf /workspace/.triton/cache/* 2>/dev/null
rm -rf ~/.cache/torch_extensions/* 2>/dev/null
rm -rf /tmp/triton_cache_* 2>/dev/null
rm -rf /tmp/tmpx* 2>/dev/null
echo "   ✅ Caches cleared"

echo ""
echo "🔄 Step 3: Restarting container to trigger fresh install..."
echo ""
echo "The container will now restart and rebuild with SageAttention 2.2.0"
echo "This will take ~5-10 minutes for the initial setup."
echo ""
echo "After restart:"
echo "1. Your ComfyUI workflows will remain intact"
echo "2. Your models will remain intact"
echo "3. SageAttention 2.2.0 will be installed"
echo "4. WAN 2.2 will run 13x faster!"
echo ""
read -p "Press Enter to restart the container..."

# Trigger container restart
kill 1