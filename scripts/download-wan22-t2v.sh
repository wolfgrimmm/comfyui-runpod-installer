#!/bin/bash

echo "========================================="
echo "WAN 2.2 Complete Models Download Script"
echo "========================================="
echo ""

# Check for huggingface_hub
if ! python3 -c "import huggingface_hub" 2>/dev/null; then
    echo "📦 Installing huggingface_hub..."
    pip install --upgrade huggingface_hub hf_transfer
fi

# Enable hf_transfer for faster downloads
export HF_HUB_ENABLE_HF_TRANSFER=1

# Check for HuggingFace token from multiple sources
# 1. RunPod secret (if user set HF_TOKEN={{ RUNPOD_SECRET_HF_TOKEN }} in pod template)
if [ -n "$HF_TOKEN" ]; then
    echo "✅ Using HuggingFace token from environment (length: ${#HF_TOKEN})"
elif [ -n "$RUNPOD_SECRET_HF_TOKEN" ]; then
    export HF_TOKEN="$RUNPOD_SECRET_HF_TOKEN"
    echo "✅ Using HuggingFace token from RunPod secret"
elif [ -n "$HUGGING_FACE_HUB_TOKEN" ]; then
    export HF_TOKEN="$HUGGING_FACE_HUB_TOKEN"
    echo "✅ Using HuggingFace token from HUGGING_FACE_HUB_TOKEN"
else
    echo "⚠️  Warning: HF_TOKEN not set. Downloads might be rate-limited."
    echo "   Set it with one of these methods:"
    echo "   • RunPod secret: Create secret 'HF_TOKEN' in RunPod dashboard"
    echo "   • Pod template: HF_TOKEN={{ RUNPOD_SECRET_HF_TOKEN }}"
    echo "   • Manual: export HF_TOKEN='hf_your_token_here'"
    echo ""
fi

# Set directories according to the documentation structure
MODELS_DIR="/workspace/models"
DIFFUSION_DIR="$MODELS_DIR/diffusion_models"
VAE_DIR="$MODELS_DIR/vae"
LORAS_DIR="$MODELS_DIR/loras"
TEXT_ENCODERS_DIR="$MODELS_DIR/text_encoders"

# For compatibility with older structures that use 'clip' for text encoders
CLIP_DIR="$MODELS_DIR/clip"

# Create directories
echo "📁 Creating model directories..."
mkdir -p "$DIFFUSION_DIR"
mkdir -p "$VAE_DIR"
mkdir -p "$LORAS_DIR"
mkdir -p "$TEXT_ENCODERS_DIR"
mkdir -p "$CLIP_DIR"

echo ""

# Function to check if file already exists
check_file_exists() {
    local dir=$1
    local filename=$2

    if [ -f "$dir/$filename" ]; then
        local size=$(du -h "$dir/$filename" | cut -f1)
        echo "   ✅ Already exists: $filename ($size) - Skipping"
        return 0
    fi
    return 1
}

# Python download function
download_model() {
    local repo=$1
    local filepath=$2
    local target_dir=$3
    local filename=$(basename "$filepath")

    # Check if file already exists
    if check_file_exists "$target_dir" "$filename"; then
        return 0
    fi

    echo "   ⬇️  Downloading: $filename..."

    python3 << EOF
import os
import sys
from pathlib import Path
import shutil

try:
    from huggingface_hub import hf_hub_download

    token = os.environ.get('HF_TOKEN', None)

    # Download the file to cache first
    downloaded_path = hf_hub_download(
        repo_id='$repo',
        filename='$filepath',
        token=token
    )

    # Copy to target directory with just the filename (no subdirs)
    target_file = os.path.join('$target_dir', '$filename')
    shutil.copy2(downloaded_path, target_file)

    print(f"   ✅ Downloaded: $filename")

except Exception as e:
    print(f"   ❌ Failed: {e}")
    sys.exit(1)
EOF
}

# Clean up any existing split_files directories
echo "🧹 Cleaning up any incorrect directory structures..."
for dir in "$DIFFUSION_DIR" "$VAE_DIR" "$LORAS_DIR" "$TEXT_ENCODERS_DIR" "$CLIP_DIR"; do
    if [ -d "$dir/split_files" ]; then
        echo "   Removing $dir/split_files..."
        rm -rf "$dir/split_files"
    fi
done

echo ""
echo "========================================="
echo "1. WAN 2.2 Diffusion Models (FP8)"
echo "========================================="

echo "T2V Models (Text-to-Video):"
download_model \
    "Comfy-Org/Wan_2.2_ComfyUI_Repackaged" \
    "split_files/diffusion_models/wan2.2_t2v_high_noise_14B_fp8_scaled.safetensors" \
    "$DIFFUSION_DIR"

download_model \
    "Comfy-Org/Wan_2.2_ComfyUI_Repackaged" \
    "split_files/diffusion_models/wan2.2_t2v_low_noise_14B_fp8_scaled.safetensors" \
    "$DIFFUSION_DIR"

echo ""
echo "Inpainting Models (Video Inpainting):"
download_model \
    "Comfy-Org/Wan_2.2_ComfyUI_Repackaged" \
    "split_files/diffusion_models/wan2.2_fun_inpaint_high_noise_14B_fp8_scaled.safetensors" \
    "$DIFFUSION_DIR"

download_model \
    "Comfy-Org/Wan_2.2_ComfyUI_Repackaged" \
    "split_files/diffusion_models/wan2.2_fun_inpaint_low_noise_14B_fp8_scaled.safetensors" \
    "$DIFFUSION_DIR"

echo ""
echo "========================================="
echo "2. WAN 2.2 LoRAs (4-step generation)"
echo "========================================="

echo "T2V LoRAs:"
download_model \
    "Comfy-Org/Wan_2.2_ComfyUI_Repackaged" \
    "split_files/loras/wan2.2_t2v_lightx2v_4steps_lora_v1.1_high_noise.safetensors" \
    "$LORAS_DIR"

download_model \
    "Comfy-Org/Wan_2.2_ComfyUI_Repackaged" \
    "split_files/loras/wan2.2_t2v_lightx2v_4steps_lora_v1.1_low_noise.safetensors" \
    "$LORAS_DIR"

echo ""
echo "I2V LoRAs:"
download_model \
    "Comfy-Org/Wan_2.2_ComfyUI_Repackaged" \
    "split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors" \
    "$LORAS_DIR"

download_model \
    "Comfy-Org/Wan_2.2_ComfyUI_Repackaged" \
    "split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors" \
    "$LORAS_DIR"

echo ""
echo "========================================="
echo "3. VAE Model"
echo "========================================="

download_model \
    "Comfy-Org/Wan_2.2_ComfyUI_Repackaged" \
    "split_files/vae/wan_2.1_vae.safetensors" \
    "$VAE_DIR"

echo ""
echo "========================================="
echo "4. Text Encoder (UMT5 XXL FP8)"
echo "========================================="

# Download to text_encoders directory
download_model \
    "Comfy-Org/Wan_2.1_ComfyUI_repackaged" \
    "split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
    "$TEXT_ENCODERS_DIR"

# Also create a symlink in clip directory for compatibility
if [ -f "$TEXT_ENCODERS_DIR/umt5_xxl_fp8_e4m3fn_scaled.safetensors" ] && [ ! -f "$CLIP_DIR/umt5_xxl_fp8_e4m3fn_scaled.safetensors" ]; then
    echo "   Creating symlink in clip directory for compatibility..."
    ln -sf "$TEXT_ENCODERS_DIR/umt5_xxl_fp8_e4m3fn_scaled.safetensors" "$CLIP_DIR/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
fi

echo ""
echo "========================================="
echo "📊 Download Summary"
echo "========================================="
echo ""

# Check what was successfully downloaded
echo "Checking downloaded files..."
echo ""

if ls "$DIFFUSION_DIR"/wan2.2_*.safetensors >/dev/null 2>&1; then
    echo "✅ Diffusion Models ($DIFFUSION_DIR):"
    for f in "$DIFFUSION_DIR"/wan2.2_*.safetensors; do
        if [ -f "$f" ]; then
            size=$(du -h "$f" | cut -f1)
            echo "   • $(basename "$f") ($size)"
        fi
    done
else
    echo "❌ No WAN 2.2 diffusion models found"
fi

echo ""

if ls "$LORAS_DIR"/wan2.2_*.safetensors >/dev/null 2>&1; then
    echo "✅ LoRAs ($LORAS_DIR):"
    for f in "$LORAS_DIR"/wan2.2_*.safetensors; do
        if [ -f "$f" ]; then
            size=$(du -h "$f" | cut -f1)
            echo "   • $(basename "$f") ($size)"
        fi
    done
else
    echo "❌ No WAN 2.2 LoRAs found"
fi

echo ""

if ls "$VAE_DIR"/wan*.safetensors >/dev/null 2>&1; then
    echo "✅ VAE Models ($VAE_DIR):"
    for f in "$VAE_DIR"/wan*.safetensors; do
        if [ -f "$f" ]; then
            size=$(du -h "$f" | cut -f1)
            echo "   • $(basename "$f") ($size)"
        fi
    done
else
    echo "❌ No WAN VAE found"
fi

echo ""

if ls "$TEXT_ENCODERS_DIR"/umt5*.safetensors >/dev/null 2>&1 || ls "$CLIP_DIR"/umt5*.safetensors >/dev/null 2>&1; then
    echo "✅ Text Encoders:"
    for dir in "$TEXT_ENCODERS_DIR" "$CLIP_DIR"; do
        for f in "$dir"/umt5*.safetensors 2>/dev/null; do
            if [ -f "$f" ]; then
                size=$(du -h "$f" | cut -f1)
                echo "   • $(basename "$f") in $(basename "$dir") ($size)"
                break  # Only show once if symlinked
            fi
        done
    done
else
    echo "❌ No UMT5 text encoder found"
fi

echo ""
echo "========================================="
echo "✅ WAN 2.2 Download Complete!"
echo "========================================="
echo ""
echo "File locations match ComfyUI structure:"
echo "• Diffusion models → $DIFFUSION_DIR"
echo "• LoRAs → $LORAS_DIR"
echo "• VAE → $VAE_DIR"
echo "• Text Encoder → $TEXT_ENCODERS_DIR"
echo ""
echo "Downloaded models support:"
echo "• Text-to-Video generation (T2V)"
echo "• Image-to-Video generation (I2V) with LoRAs"
echo "• Video Inpainting (fun_inpaint models)"
echo "• 4-step fast generation with LoRAs"
echo "• High and low noise variants"
echo ""
echo "Total: 4 diffusion models, 4 LoRAs, 1 VAE, 1 text encoder"
echo ""
echo "Tutorial: https://docs.comfy.org/tutorials/video/wan/wan2_2"