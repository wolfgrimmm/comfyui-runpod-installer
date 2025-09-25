# ComfyUI RunPod Installer - Confirmed Fixes

This document tracks all confirmed working fixes applied to resolve issues with the ComfyUI RunPod installer.

## Fix History

### 2025-09-25: Missing Python Modules

**Problem:** ComfyUI failed to start with ModuleNotFoundError for 'av' and 'sentencepiece'

**Solution:** Added to Dockerfile:
```dockerfile
# Video processing support (required by ComfyUI for video input)
uv pip install av

# Text processing support (required for tokenization in many models)
uv pip install sentencepiece
```

**Status:** ✅ Confirmed working by user

---

### 2025-09-25: Triton Compilation Errors on RTX 5090 / A100

**Problem:** Triton compilation failed with FP8 dtype errors:
```
ValueError("type fp8e4nv not supported in this architecture. The supported fp8 dtypes are ('fp8e4b15', 'fp8e5')")
```

**Solution:** Added to Dockerfile startup script:
```bash
# Disable torch inductor/Triton compilation to prevent errors on newer GPUs
# This won't affect Sage Attention which has its own optimized kernels
export TORCH_COMPILE_DISABLE=1
export TORCHINDUCTOR_DISABLE=1
echo "🔧 Torch inductor disabled (Sage Attention still active for RTX 5090)"
```

**Manual Fix for Running Pods:**
```bash
export TORCH_COMPILE_DISABLE=1
export TORCHINDUCTOR_DISABLE=1
echo 'export TORCH_COMPILE_DISABLE=1' >> ~/.bashrc
echo 'export TORCHINDUCTOR_DISABLE=1' >> ~/.bashrc
```

**Status:** ✅ Confirmed working on RTX 5090 by user

---

### 2025-09-25: TensorRT Engine Incompatibility

**Problem:** TensorRT engines built on one GPU architecture fail on another:
```
The engine plan file is generated on an incompatible device, expecting compute X.X got compute Y.Y
```

**Solution 1 - Automatic Cleanup:** Added to Dockerfile startup script:
```bash
# Clean up incompatible TensorRT engines
if [ -d "/workspace/ComfyUI/models/tensorrt" ]; then
    echo "🔍 Checking for incompatible TensorRT engines..."

    # Get current GPU compute capability
    GPU_COMPUTE_CAP=$(python -c "import torch; cc = torch.cuda.get_device_capability(); print(f'{cc[0]}.{cc[1]}'))" 2>/dev/null || echo "unknown")

    # Remove incompatible engines
    # ... (full cleanup logic in Dockerfile)
fi
```

**Solution 2 - Manual Cleanup Script:** Created `/scripts/cleanup_tensorrt.sh`

**Manual Fix for Running Pods:**
```bash
# Remove specific incompatible engine
rm /workspace/ComfyUI/models/tensorrt/upscaler/[engine_name].trt

# Or remove all to rebuild
rm -rf /workspace/ComfyUI/models/tensorrt/upscaler/*.trt
```

**Status:** ✅ Confirmed working on multiple GPU switches

---

### 2025-09-25: Google Drive Sync Not Working Since Sept 23

**Problem:** Google Drive sync stopped working, likely due to Google API changes

**Solutions Applied:**

1. **Updated rclone installation** in Dockerfile:
```dockerfile
# Install latest rclone for Google Drive sync (fixes 2024/2025 API changes)
&& curl -O https://downloads.rclone.org/rclone-current-linux-amd64.deb \
&& dpkg -i rclone-current-linux-amd64.deb \
&& rm rclone-current-linux-amd64.deb \
```

2. **Added better error logging** in `/scripts/init_sync.sh`
3. **Added OAuth token refresh handling** for 7-day expiration

**Status:** ⏳ Awaiting user confirmation

---

### 2025-09-25: PyTorch Version Mismatch (std::bad_alloc)

**Problem:** ComfyUI crashed with std::bad_alloc due to PyTorch 2.9.0-dev installed instead of 2.8.0

**Solution:** Reinstalled correct PyTorch version:
```bash
pip uninstall torch torchvision torchaudio -y
pip install torch==2.8.0+cu129 torchvision==0.23.0+cu129 torchaudio==2.8.0+cu129 --index-url https://download.pytorch.org/whl/cu129
```

**Status:** ✅ Confirmed working - ComfyUI started successfully

---

## GPU-Specific Information

### Supported GPUs and Optimizations

| GPU | Architecture | Compute | Optimization | Status |
|-----|-------------|---------|--------------|---------|
| RTX 5090 | Blackwell | 12.0 | Sage Attention 2.2.0 | ✅ Confirmed |
| RTX 4090 | Ada Lovelace | 8.9 | xformers | ✅ Working |
| A100 | Ampere | 8.0 | Flash Attention 2 | ✅ Confirmed |
| H100 | Hopper | 9.0 | Flash Attention 3 | ⏳ Untested |

### Key Environment Variables

```bash
# For Triton issues
export TORCH_COMPILE_DISABLE=1
export TORCHINDUCTOR_DISABLE=1

# For VRAM optimization (RTX 5090, A100)
export COMFYUI_VRAM_MODE="highvram"  # or "gpu_only"
```

---

## How to Apply Fixes

### For New Builds
All fixes are incorporated into the Dockerfile. Simply rebuild:
```bash
./build.sh
docker push yourusername/comfyui-runpod:latest
```

### For Running Pods
Apply the manual fixes listed above for each issue.

---

## Contributing

When adding new fixes:
1. Document the problem clearly
2. Include the exact error message
3. Provide both Dockerfile changes and manual fixes
4. Wait for user confirmation before marking as ✅ Confirmed

---

Last Updated: 2025-09-25