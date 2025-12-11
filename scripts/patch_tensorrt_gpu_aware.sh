#!/bin/bash

# Patch TensorRT Upscaler to use GPU-specific cache directories
# This allows multiple GPUs (B200, RTX 5090, etc.) to share the same network volume
# without TensorRT engine conflicts

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Patching TensorRT Upscaler for GPU-Aware Caching"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Find TensorRT upscaler node
TRT_UPSCALER_DIRS=(
    "/workspace/ComfyUI/custom_nodes/ComfyUI-Upscaler-Tensorrt"
    "/workspace/ComfyUI/custom_nodes/comfyui-upscaler-tensorrt"
)

TRT_NODE_DIR=""
for dir in "${TRT_UPSCALER_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        TRT_NODE_DIR="$dir"
        break
    fi
done

if [ -z "$TRT_NODE_DIR" ]; then
    echo "❌ TensorRT Upscaler node not found!"
    echo "   Expected locations:"
    for dir in "${TRT_UPSCALER_DIRS[@]}"; do
        echo "     - $dir"
    done
    exit 1
fi

echo "✅ Found TensorRT Upscaler: $TRT_NODE_DIR"
echo ""

# Target file to patch
TRT_UTILITIES="$TRT_NODE_DIR/trt_utilities.py"

if [ ! -f "$TRT_UTILITIES" ]; then
    echo "❌ trt_utilities.py not found at: $TRT_UTILITIES"
    exit 1
fi

# Check if already patched
if grep -q "GPU-AWARE CACHE PATCH" "$TRT_UTILITIES"; then
    echo "✅ Already patched! GPU-aware caching is active."
    exit 0
fi

echo "📝 Creating backup..."
cp "$TRT_UTILITIES" "$TRT_UTILITIES.backup.$(date +%Y%m%d_%H%M%S)"

echo "🔨 Applying GPU-aware cache patch..."

# Create Python patch script
cat > /tmp/patch_trt.py << 'PYTHON_PATCH'
import sys
import re

# Read the file
with open(sys.argv[1], 'r') as f:
    content = f.read()

# Find the __init__ method of the Engine class
# We'll add GPU detection code after engine_path is set

patch_code = '''
        # === GPU-AWARE CACHE PATCH ===
        # Organize TensorRT engines by GPU compute capability
        # This allows multiple pods with different GPUs to share the same network volume
        # without engine incompatibility issues (Bug #29)
        try:
            import torch
            if torch.cuda.is_available():
                compute_cap = torch.cuda.get_device_capability(0)
                compute_id = f"sm_{compute_cap[0]}{compute_cap[1]}"  # e.g., "sm_100", "sm_120"

                # Modify engine path to include GPU subdirectory
                import os
                base_path = os.path.dirname(self.engine_path)
                filename = os.path.basename(self.engine_path)
                self.engine_path = os.path.join(base_path, compute_id, filename)

                # Create GPU-specific directory
                os.makedirs(os.path.dirname(self.engine_path), exist_ok=True)

                print(f"[TensorRT GPU-Aware] Using engine path for {compute_id}: {self.engine_path}")
        except Exception as e:
            print(f"[TensorRT GPU-Aware] Warning: Could not detect GPU, using default path: {e}")
        # === END GPU-AWARE CACHE PATCH ===
'''

# Find where engine_path is set in __init__
# Look for pattern: self.engine_path = ...
pattern = r'(self\.engine_path\s*=\s*[^\n]+\n)'

if re.search(pattern, content):
    # Insert patch code after engine_path assignment
    content = re.sub(pattern, r'\1' + patch_code, content, count=1)

    with open(sys.argv[1], 'w') as f:
        f.write(content)

    print("✅ Patch applied successfully!")
    sys.exit(0)
else:
    print("❌ Could not find engine_path assignment in file")
    sys.exit(1)
PYTHON_PATCH

# Apply the patch
python3 /tmp/patch_trt.py "$TRT_UTILITIES"

if [ $? -eq 0 ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ GPU-Aware TensorRT Caching Enabled!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📁 Engine directories will now be organized like:"
    echo "   /workspace/ComfyUI/models/tensorrt/upscaler/"
    echo "   ├── sm_89/   ← RTX 4090 engines"
    echo "   ├── sm_100/  ← B200 engines"
    echo "   └── sm_120/  ← RTX 5090 engines"
    echo ""
    echo "🔄 Each GPU type gets its own cache directory"
    echo "✨ No more engine conflicts across different GPU pods!"
    echo ""
    echo "💡 Backup saved: $TRT_UTILITIES.backup.*"
    echo ""
else
    echo ""
    echo "❌ Patch failed! Restoring backup..."
    mv "$TRT_UTILITIES".backup.* "$TRT_UTILITIES" 2>/dev/null
    exit 1
fi

# Clean up
rm -f /tmp/patch_trt.py
