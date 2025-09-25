#!/bin/bash

# TensorRT Engine Cleanup Script
# Removes incompatible TensorRT engines when switching GPUs

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧹 TensorRT Engine Cleanup Tool"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Activate venv to get PyTorch
if [ -f "/workspace/venv/bin/activate" ]; then
    source /workspace/venv/bin/activate
fi

# Get current GPU info
echo "📊 Current GPU Information:"
python3 -c "
import torch
if torch.cuda.is_available():
    gpu_name = torch.cuda.get_device_name(0)
    compute_cap = torch.cuda.get_device_capability(0)
    print(f'  GPU: {gpu_name}')
    print(f'  Compute Capability: {compute_cap[0]}.{compute_cap[1]}')
else:
    print('  No GPU detected!')
" 2>/dev/null || echo "  Unable to detect GPU"

# Function to check TRT engine compatibility
check_trt_engine() {
    local engine_file="$1"

    python3 -c "
import sys
try:
    import tensorrt as trt

    # Create logger and runtime
    logger = trt.Logger(trt.Logger.ERROR)
    runtime = trt.Runtime(logger)

    # Try to load the engine
    with open('$engine_file', 'rb') as f:
        engine_data = f.read()
        engine = runtime.deserialize_cuda_engine(engine_data)

    if engine is None:
        sys.exit(1)  # Incompatible
    else:
        sys.exit(0)  # Compatible
except Exception as e:
    sys.exit(1)  # Error = incompatible
" 2>/dev/null

    return $?
}

# Find all TensorRT directories
TRT_DIRS=(
    "/workspace/ComfyUI/models/tensorrt"
    "/workspace/ComfyUI/models/tensorrt/upscaler"
    "/workspace/ComfyUI/custom_nodes/ComfyUI-Upscaler-Tensorrt/engines"
)

TOTAL_REMOVED=0
TOTAL_KEPT=0

echo ""
echo "🔍 Scanning for TensorRT engines..."
echo ""

for dir in "${TRT_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "📁 Checking: $dir"

        # Find all .trt and .engine files
        while IFS= read -r -d '' engine_file; do
            filename=$(basename "$engine_file")

            # Check if engine is compatible
            if check_trt_engine "$engine_file"; then
                echo "  ✅ Compatible: $filename"
                ((TOTAL_KEPT++))
            else
                echo "  ❌ Incompatible: $filename (removing...)"
                rm -f "$engine_file"
                ((TOTAL_REMOVED++))
            fi
        done < <(find "$dir" -type f \( -name "*.trt" -o -name "*.engine" \) -print0 2>/dev/null)
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Cleanup Summary:"
echo "  • Removed: $TOTAL_REMOVED incompatible engines"
echo "  • Kept: $TOTAL_KEPT compatible engines"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $TOTAL_REMOVED -gt 0 ]; then
    echo ""
    echo "💡 Note: Removed engines will be automatically"
    echo "   rebuilt when you run your workflows."
fi

echo ""