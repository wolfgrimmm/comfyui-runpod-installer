# GPU Support and Attention Mechanisms

This document describes the automatic GPU detection and attention mechanism selection for optimal performance on RunPod.

## Supported GPUs and Architectures

### Blackwell Architecture (Latest Generation)
- **B200** - Uses Sage Attention 2.2.0 for maximum performance
- **RTX 5090/5080** (when available) - Will use Sage Attention

### Hopper Architecture
- **H200 SXM** - Uses Flash Attention 3 (pre-compiled)
- **H100 NVL** - Uses Flash Attention 3 (pre-compiled)
- **H100 SXM** - Uses Flash Attention 3 (pre-compiled)
- **H100 PCIe** - Uses Flash Attention 3 (pre-compiled)

### Ada Lovelace Architecture
- **L4, L40, L40S** - Uses Flash Attention 2 + xformers
- **RTX 4090, 4080, 4070, 4060** - Uses Flash Attention 2 + xformers
- **RTX 6000 Ada, RTX 4000 Ada, RTX 2000 Ada** - Uses Flash Attention 2 + xformers
- **RTX PRO 6000, RTX 6000 WK** - Uses Flash Attention 2 + xformers

### Ampere Architecture
- **A40, A100** - Uses Flash Attention 2 + xformers
- **RTX 3090, 3080, 3070, 3060** - Uses Flash Attention 2 + xformers

## Attention Mechanisms

### Flash Attention 3
- **Optimized for**: Hopper GPUs (H100/H200)
- **Performance**: Up to 2.5x faster than Flash Attention 2
- **Installation**: Pre-compiled during Docker build to avoid runtime delays

### Sage Attention 2.2.0
- **Optimized for**: Blackwell GPUs (B200)
- **Performance**: Next-generation optimization for latest hardware
- **Installation**: Pre-installed wheel package

### Flash Attention 2
- **Optimized for**: Ada Lovelace and Ampere GPUs
- **Performance**: Excellent performance for RTX 40/30 series and data center GPUs
- **Installation**: Pre-installed during Docker build

### xformers 0.33
- **Universal fallback**: Works on all GPUs
- **Performance**: Good baseline performance
- **Installation**: Pre-installed wheel package

## Automatic Detection

The system automatically:
1. Detects your GPU model at container startup
2. Identifies the GPU architecture (Blackwell, Hopper, Ada, Ampere)
3. Selects the optimal attention mechanism
4. Configures ComfyUI to use the selected mechanism

## Manual Override

If you need to override the automatic selection, you can set the environment variable:
```bash
export COMFYUI_ATTENTION_MECHANISM=flash3  # or flash2, sage, xformers, auto
```

## Verification

To verify which attention mechanism is active:
1. Check the startup logs for "GPU Configuration Summary"
2. Look for the "Selected Mechanism" line
3. Check `/workspace/venv/.env_settings` for the configuration

## Troubleshooting

### Flash Attention 3 Not Working
- Ensure you have a Hopper GPU (H100/H200)
- Check CUDA version is 12.9 or higher
- Verify PyTorch 2.8.0 is installed

### Sage Attention Not Loading
- Requires Blackwell GPU (B200)
- Check Python version compatibility (3.10 or 3.11)

### Performance Issues
- Clear Triton cache: `/workspace/scripts/clear_triton_cache.sh`
- Check GPU memory usage with `nvidia-smi`
- Verify correct attention mechanism is selected for your GPU

## Performance Tips

1. **Hopper GPUs**: Flash Attention 3 provides the best performance
2. **Ada/Ampere GPUs**: Flash Attention 2 is optimal, xformers as fallback
3. **Blackwell GPUs**: Sage Attention provides cutting-edge optimizations
4. **Memory Usage**: Different attention mechanisms have different memory footprints
5. **Batch Size**: Adjust based on GPU memory and attention mechanism