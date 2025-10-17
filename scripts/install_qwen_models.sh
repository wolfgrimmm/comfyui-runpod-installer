#!/bin/bash

# Script to download Qwen Image Edit models to RunPod network volume
# This script downloads all required models for Qwen Image Edit workflow

echo "========================================="
echo "  Qwen Image Edit Models Installer"
echo "========================================="
echo ""

# Base directory for models
BASE_DIR="/workspace/models"

# Create directory structure
echo "📁 Creating directory structure..."
mkdir -p "$BASE_DIR/diffusion_models"
mkdir -p "$BASE_DIR/loras"
mkdir -p "$BASE_DIR/text_encoders"
mkdir -p "$BASE_DIR/vae"

echo "✅ Directories created"
echo ""

# Function to download with progress
download_model() {
    local url="$1"
    local output_path="$2"
    local model_name=$(basename "$output_path")

    echo "⬇️  Downloading: $model_name"

    if [ -f "$output_path" ]; then
        echo "   ⚠️  File already exists, skipping: $model_name"
        return 0
    fi

    wget --show-progress --progress=bar:force:noscroll \
         -O "$output_path" "$url"

    if [ $? -eq 0 ]; then
        echo "   ✅ Downloaded: $model_name"
        # Show file size
        ls -lh "$output_path" | awk '{print "   📊 Size: " $5}'
    else
        echo "   ❌ Failed to download: $model_name"
        return 1
    fi
    echo ""
}

# Download diffusion model
echo "📦 Downloading Diffusion Model..."
download_model \
    "https://huggingface.co/Comfy-Org/Qwen-Image-Edit_ComfyUI/resolve/main/split_files/diffusion_models/qwen_image_edit_2509_fp8_e4m3fn.safetensors" \
    "$BASE_DIR/diffusion_models/qwen_image_edit_2509_fp8_e4m3fn.safetensors"

# Download LoRA
echo "📦 Downloading LoRA (Lightning 4-step)..."
download_model \
    "https://huggingface.co/lightx2v/Qwen-Image-Lightning/resolve/main/Qwen-Image-Edit-2509/Qwen-Image-Edit-2509-Lightning-4steps-V1.0-bf16.safetensors" \
    "$BASE_DIR/loras/Qwen-Image-Edit-2509-Lightning-4steps-V1.0-bf16.safetensors"

# Download text encoder
echo "📦 Downloading Text Encoder..."
download_model \
    "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors" \
    "$BASE_DIR/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors"

# Download VAE
echo "📦 Downloading VAE..."
download_model \
    "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/vae/qwen_image_vae.safetensors" \
    "$BASE_DIR/vae/qwen_image_vae.safetensors"

# Summary
echo ""
echo "========================================="
echo "  Installation Summary"
echo "========================================="
echo ""
echo "📂 Model Storage Location:"
echo "   $BASE_DIR/"
echo ""
echo "📋 Installed Models:"
echo ""

# Check each model and show status
check_model() {
    local path="$1"
    local name="$2"

    if [ -f "$path" ]; then
        local size=$(ls -lh "$path" | awk '{print $5}')
        echo "   ✅ $name ($size)"
    else
        echo "   ❌ $name (MISSING)"
    fi
}

check_model "$BASE_DIR/diffusion_models/qwen_image_edit_2509_fp8_e4m3fn.safetensors" "Diffusion Model"
check_model "$BASE_DIR/loras/Qwen-Image-Edit-2509-Lightning-4steps-V1.0-bf16.safetensors" "LoRA (Lightning 4-step)"
check_model "$BASE_DIR/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors" "Text Encoder"
check_model "$BASE_DIR/vae/qwen_image_vae.safetensors" "VAE"

echo ""
echo "========================================="
echo "✅ Installation complete!"
echo ""
echo "📖 Tutorial: https://docs.comfy.org/tutorials/image/qwen/qwen-image-edit"
echo "========================================="
