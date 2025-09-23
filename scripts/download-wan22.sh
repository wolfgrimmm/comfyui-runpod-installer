#!/bin/bash

echo "========================================="
echo "WAN 2.2 Model Download Script"
echo "========================================="

# Check dependencies
if ! python3 -c "import huggingface_hub" 2>/dev/null; then
    echo "📦 Installing huggingface_hub..."
    pip install huggingface_hub hf_transfer
fi

# Enable hf_transfer for faster downloads
export HF_HUB_ENABLE_HF_TRANSFER=1

# Check if HF_TOKEN is set
if [ -z "$HF_TOKEN" ]; then
    echo "⚠️  Warning: HF_TOKEN not set. Some models may not download."
    echo "Set it with: export HF_TOKEN='hf_your_token_here'"
    echo ""
fi

# Set directories
MODELS_DIR="/workspace/models"
DIFFUSION_DIR="$MODELS_DIR/diffusion_models"
VAE_DIR="$MODELS_DIR/vae"
CLIP_DIR="$MODELS_DIR/clip"

# Create directories
echo "📁 Creating model directories..."
mkdir -p "$DIFFUSION_DIR"
mkdir -p "$VAE_DIR"
mkdir -p "$CLIP_DIR"

echo ""
echo "🔍 Downloading WAN 2.2 models..."
echo ""

# Python download script
cat > /tmp/download_wan.py << 'EOF'
import os
import sys
from huggingface_hub import hf_hub_download
from pathlib import Path

def download_model(repo_id, filename, local_dir, local_filename=None, description=""):
    """Download a model from HuggingFace Hub."""
    print(f"📥 {description}")
    print(f"   Repository: {repo_id}")
    print(f"   File: {filename}")

    try:
        # Use HF_TOKEN from environment if available
        token = os.environ.get('HF_TOKEN', None)

        # Download the file
        downloaded_path = hf_hub_download(
            repo_id=repo_id,
            filename=filename,
            local_dir=local_dir,
            local_dir_use_symlinks=False,
            token=token
        )

        # Rename if needed
        if local_filename:
            final_path = Path(local_dir) / local_filename
            if Path(downloaded_path).exists():
                Path(downloaded_path).rename(final_path)
                print(f"   ✅ Saved as: {final_path}")
            else:
                print(f"   ✅ Downloaded to: {downloaded_path}")
        else:
            print(f"   ✅ Downloaded to: {downloaded_path}")

        return True
    except Exception as e:
        print(f"   ❌ Failed: {str(e)}")
        return False

# Main downloads
models = [
    # WAN 2.2 FP8 Diffusion Models
    {
        "repo": "Comfy-Org/Wan_2.2_ComfyUI_Repackaged",
        "file": "split_files/diffusion_models/wan2.2_i2v_high_noise_14b_fp8_scaled.safetensors",
        "dir": "/workspace/models/diffusion_models",
        "name": "wan2.2_i2v_high_noise_14b_fp8_scaled.safetensors",
        "desc": "WAN 2.2 I2V High Noise FP8 (13.5 GB)"
    },
    {
        "repo": "Comfy-Org/Wan_2.2_ComfyUI_Repackaged",
        "file": "split_files/diffusion_models/wan2.2_i2v_low_noise_14b_fp8_scaled.safetensors",
        "dir": "/workspace/models/diffusion_models",
        "name": "wan2.2_i2v_low_noise_14b_fp8_scaled.safetensors",
        "desc": "WAN 2.2 I2V Low Noise FP8 (13.5 GB)"
    },
    {
        "repo": "Comfy-Org/Wan_2.2_ComfyUI_Repackaged",
        "file": "split_files/diffusion_models/wan2.2_t2v_high_noise_14b_fp8_scaled.safetensors",
        "dir": "/workspace/models/diffusion_models",
        "name": "wan2.2_t2v_high_noise_14b_fp8_scaled.safetensors",
        "desc": "WAN 2.2 T2V High Noise FP8 (13.5 GB)"
    },
    {
        "repo": "Comfy-Org/Wan_2.2_ComfyUI_Repackaged",
        "file": "split_files/diffusion_models/wan2.2_t2v_low_noise_14b_fp8_scaled.safetensors",
        "dir": "/workspace/models/diffusion_models",
        "name": "wan2.2_t2v_low_noise_14b_fp8_scaled.safetensors",
        "desc": "WAN 2.2 T2V Low Noise FP8 (13.5 GB)"
    },
    # WAN 2.2 VAE
    {
        "repo": "Comfy-Org/Wan_2.2_ComfyUI_Repackaged",
        "file": "split_files/vae/wan2.2_vae.safetensors",
        "dir": "/workspace/models/vae",
        "name": "wan2.2_vae.safetensors",
        "desc": "WAN 2.2 VAE (335 MB)"
    },
    # Text Encoder - try from WAN 2.1 repo since 2.2 might not have it
    {
        "repo": "Comfy-Org/Wan_2.1_ComfyUI_repackaged",
        "file": "split_files/text_encoders/umt5_xxl_fp16.safetensors",
        "dir": "/workspace/models/clip",
        "name": "umt5_xxl_fp16.safetensors",
        "desc": "UMT5 XXL FP16 Text Encoder (23.7 GB)"
    }
]

print("=" * 50)
print("Downloading WAN 2.2 Models")
print("=" * 50)
print()

success_count = 0
for model in models:
    if download_model(
        repo_id=model["repo"],
        filename=model["file"],
        local_dir=model["dir"],
        local_filename=model["name"],
        description=model["desc"]
    ):
        success_count += 1
    print()

# Try alternative sources if main downloads failed
if success_count < 4:
    print("=" * 50)
    print("Trying alternative sources...")
    print("=" * 50)
    print()

    alt_models = [
        # Alternative from OpenGVLab repo
        {
            "repo": "OpenGVLab/InternVideo2",
            "file": "wan2.2_i2v_high_noise_14b_fp8_scaled.safetensors",
            "dir": "/workspace/models/diffusion_models",
            "name": None,
            "desc": "WAN 2.2 I2V High Noise (Alternative Source)"
        },
        {
            "repo": "OpenGVLab/InternVideo2",
            "file": "wan2.2_t2v_high_noise_14b_fp8_scaled.safetensors",
            "dir": "/workspace/models/diffusion_models",
            "name": None,
            "desc": "WAN 2.2 T2V High Noise (Alternative Source)"
        },
        {
            "repo": "OpenGVLab/InternVideo2",
            "file": "wan2.2_vae.safetensors",
            "dir": "/workspace/models/vae",
            "name": None,
            "desc": "WAN 2.2 VAE (Alternative Source)"
        }
    ]

    for model in alt_models:
        download_model(
            repo_id=model["repo"],
            filename=model["file"],
            local_dir=model["dir"],
            local_filename=model["name"],
            description=model["desc"]
        )
        print()

print("=" * 50)
print("Download Summary")
print("=" * 50)

# Check what was downloaded
import glob

diffusion_files = glob.glob("/workspace/models/diffusion_models/*wan*")
vae_files = glob.glob("/workspace/models/vae/*wan*") + glob.glob("/workspace/models/vae/*vae*")
clip_files = glob.glob("/workspace/models/clip/umt5*")

if diffusion_files:
    print("\n✅ Diffusion Models:")
    for f in diffusion_files:
        size = os.path.getsize(f) / (1024**3)
        print(f"   • {os.path.basename(f)} ({size:.1f} GB)")
else:
    print("\n❌ No WAN diffusion models found")

if vae_files:
    print("\n✅ VAE Models:")
    for f in vae_files:
        size = os.path.getsize(f) / (1024**3)
        print(f"   • {os.path.basename(f)} ({size:.1f} GB)")
else:
    print("\n❌ No WAN VAE found")

if clip_files:
    print("\n✅ Text Encoders:")
    for f in clip_files:
        size = os.path.getsize(f) / (1024**3)
        print(f"   • {os.path.basename(f)} ({size:.1f} GB)")
else:
    print("\n❌ No UMT5 text encoder found")

print("\n✅ Script completed!")
EOF

# Run the Python script
python3 /tmp/download_wan.py

# Clean up
rm -f /tmp/download_wan.py

echo ""
echo "========================================="
echo "✅ WAN 2.2 Download Complete!"
echo "========================================="
echo ""
echo "If downloads failed:"
echo "1. Ensure huggingface_hub is installed: pip install huggingface_hub"
echo "2. Set your HF token: export HF_TOKEN='hf_...'"
echo "3. Check repository access permissions"
echo ""
echo "Repository URLs:"
echo "• https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged"
echo "• https://huggingface.co/OpenGVLab/InternVideo2"