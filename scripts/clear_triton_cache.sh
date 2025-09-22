#!/bin/bash
# Clear Triton cache to prevent conflicts and free up space

echo "🧹 Clearing Triton cache..."

# Clear user Triton cache
if [ -d "$HOME/.triton" ]; then
    echo "Found Triton cache at $HOME/.triton"
    SIZE=$(du -sh "$HOME/.triton" 2>/dev/null | cut -f1)
    echo "Cache size: $SIZE"
    rm -rf "$HOME/.triton"
    echo "✅ User Triton cache cleared"
else
    echo "No user Triton cache found"
fi

# Clear root Triton cache (if running as root in Docker)
if [ -d "/root/.triton" ]; then
    echo "Found Triton cache at /root/.triton"
    SIZE=$(du -sh "/root/.triton" 2>/dev/null | cut -f1)
    echo "Cache size: $SIZE"
    rm -rf "/root/.triton"
    echo "✅ Root Triton cache cleared"
fi

# Clear workspace Triton cache
if [ -d "/workspace/.triton" ]; then
    echo "Found Triton cache at /workspace/.triton"
    SIZE=$(du -sh "/workspace/.triton" 2>/dev/null | cut -f1)
    echo "Cache size: $SIZE"
    rm -rf "/workspace/.triton"
    echo "✅ Workspace Triton cache cleared"
fi

# Clear temporary Triton files
echo "Clearing temporary Triton files..."
find /tmp -name "triton_*" -type f -delete 2>/dev/null
find /tmp -name "tmp*triton*" -type d -exec rm -rf {} + 2>/dev/null
find /var/tmp -name "*triton*" -delete 2>/dev/null

# Clear PyTorch kernel cache
if [ -d "$HOME/.cache/torch/kernels" ]; then
    echo "Clearing PyTorch kernel cache..."
    rm -rf "$HOME/.cache/torch/kernels"
    echo "✅ PyTorch kernel cache cleared"
fi

# Clear CUDA cache
if [ -d "$HOME/.nv/ComputeCache" ]; then
    echo "Clearing CUDA compute cache..."
    rm -rf "$HOME/.nv/ComputeCache"
    echo "✅ CUDA compute cache cleared"
fi

echo "✅ All Triton and GPU caches cleared successfully!"

# Show freed space
echo ""
echo "Disk usage after cleanup:"
df -h /workspace 2>/dev/null | tail -1 || df -h / | tail -1