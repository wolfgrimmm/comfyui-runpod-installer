#!/bin/bash

# Workspace Cleanup Script
# Fixes control panel issues by removing corrupted/conflicting files
# Preserves ComfyUI, models, and user data

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧹 Workspace Cleanup for Control Panel Fix"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "This script will clean up files that cause control panel issues"
echo "while preserving your ComfyUI installation, models, and outputs."
echo ""

# Safety check - make sure we're in the right place
if [ ! -d "/workspace" ]; then
    echo "❌ Error: /workspace directory not found"
    echo "   This script must be run inside the RunPod container"
    exit 1
fi

# Show what will be preserved
echo "✅ Will PRESERVE:"
echo "   • /workspace/ComfyUI (and all models)"
echo "   • /workspace/output (generated images)"
echo "   • /workspace/input (input files)"
echo "   • /workspace/workflows (saved workflows)"
echo ""

echo "❌ Will DELETE:"
echo "   • /workspace/venv (Python environment)"
echo "   • /workspace/.setup_complete"
echo "   • /workspace/ui_cache"
echo "   • /workspace/*.log"
echo "   • Running Python processes"
echo ""

# Ask for confirmation
read -p "Continue with cleanup? (yes/no): " -n 3 -r
echo
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "Starting cleanup..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Step 1: Stop running services
echo "1️⃣ Stopping running services..."
pkill -f "python.*app.py" 2>/dev/null || true
pkill -f "python.*main.py" 2>/dev/null || true
pkill -f "flask run" 2>/dev/null || true
pkill -f "jupyter" 2>/dev/null || true
sleep 2

# Step 2: Remove Python virtual environment
if [ -d "/workspace/venv" ]; then
    echo "2️⃣ Removing old Python environment..."
    rm -rf /workspace/venv
    echo "   ✓ Removed /workspace/venv"
else
    echo "2️⃣ No venv found to remove"
fi

# Step 3: Remove setup markers
echo "3️⃣ Removing setup markers..."
rm -f /workspace/.setup_complete 2>/dev/null || true
rm -f /workspace/.python_packages_installed 2>/dev/null || true
rm -f /workspace/venv/.setup_complete 2>/dev/null || true
rm -f /workspace/venv/.cuda129_upgraded 2>/dev/null || true
echo "   ✓ Removed setup markers"

# Step 4: Clear UI cache
if [ -d "/workspace/ui_cache" ]; then
    echo "4️⃣ Clearing UI cache..."
    rm -rf /workspace/ui_cache
    echo "   ✓ Removed /workspace/ui_cache"
else
    echo "4️⃣ No UI cache found"
fi

# Step 5: Remove old logs
echo "5️⃣ Removing old log files..."
find /workspace -maxdepth 1 -name "*.log" -type f -delete 2>/dev/null || true
echo "   ✓ Removed log files"

# Step 6: Clear Python cache
echo "6️⃣ Clearing Python cache..."
find /workspace -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find /workspace -type f -name "*.pyc" -delete 2>/dev/null || true
echo "   ✓ Cleared Python cache"

# Step 7: Remove pip cache to ensure fresh installs
echo "7️⃣ Clearing pip cache..."
rm -rf /root/.cache/pip 2>/dev/null || true
rm -rf /workspace/.cache/pip 2>/dev/null || true
echo "   ✓ Cleared pip cache"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Cleanup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "1. Restart your RunPod pod"
echo "2. The startup script will rebuild everything fresh"
echo "3. Control panel should work normally"
echo ""
echo "Your ComfyUI installation and models are safe!"