#!/bin/bash

# WAN 2.2 Fun Control Model Downloader for RunPod
# Downloads all required models for WAN 2.2 Fun Control workflows
# Source: https://docs.comfy.org/tutorials/video/wan/wan2-2-fun-control

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎬 WAN 2.2 Fun Control Model Downloader"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Base directory (RunPod uses /workspace/models which is symlinked from ComfyUI)
BASE_DIR="/workspace/models"

# Create directories
echo "📁 Creating model directories..."
mkdir -p "$BASE_DIR/diffusion_models"
mkdir -p "$BASE_DIR/loras"
mkdir -p "$BASE_DIR/vae"
mkdir -p "$BASE_DIR/text_encoders"
echo "✅ Directories created"
echo ""

# Function to download file with resume support
download_file() {
    local url="$1"
    local output_path="$2"
    local filename=$(basename "$output_path")

    # Check if file already exists and is complete
    if [ -f "$output_path" ]; then
        echo "   ℹ️  File already exists: $filename"

        # Get expected size from server
        EXPECTED_SIZE=$(curl -sI "$url" | grep -i content-length | awk '{print $2}' | tr -d '\r')
        ACTUAL_SIZE=$(stat -f%z "$output_path" 2>/dev/null || stat -c%s "$output_path" 2>/dev/null)

        if [ "$ACTUAL_SIZE" = "$EXPECTED_SIZE" ]; then
            echo "   ✅ File is complete, skipping download"
            return 0
        else
            echo "   ⚠️  File size mismatch, re-downloading..."
            rm -f "$output_path"
        fi
    fi

    echo "   📥 Downloading: $filename"
    echo "   URL: $url"

    # Download with progress bar and resume support
    wget --continue --progress=bar:force:noscroll \
         --timeout=30 --tries=5 --retry-connrefused \
         -O "$output_path" "$url" 2>&1 | \
         grep --line-buffered "%" | \
         sed -u 's/.*\[\(.*\)\].*/   Progress: \1/' || {
        echo "   ❌ Download failed: $filename"
        return 1
    }

    echo "   ✅ Downloaded: $filename"
    echo ""
}

# Total files to download
TOTAL_FILES=7
CURRENT_FILE=0

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Downloading Diffusion Models (2 files, ~28GB each)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

CURRENT_FILE=$((CURRENT_FILE + 1))
echo "[$CURRENT_FILE/$TOTAL_FILES] High Noise Model..."
download_file \
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_fun_control_high_noise_14B_fp8_scaled.safetensors" \
    "$BASE_DIR/diffusion_models/wan2.2_fun_control_high_noise_14B_fp8_scaled.safetensors"

CURRENT_FILE=$((CURRENT_FILE + 1))
echo "[$CURRENT_FILE/$TOTAL_FILES] Low Noise Model..."
download_file \
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_fun_control_low_noise_14B_fp8_scaled.safetensors" \
    "$BASE_DIR/diffusion_models/wan2.2_fun_control_low_noise_14B_fp8_scaled.safetensors"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎨 Downloading LoRA Models (2 files, ~200MB each)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

CURRENT_FILE=$((CURRENT_FILE + 1))
echo "[$CURRENT_FILE/$TOTAL_FILES] Low Noise LoRA..."
download_file \
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors" \
    "$BASE_DIR/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors"

CURRENT_FILE=$((CURRENT_FILE + 1))
echo "[$CURRENT_FILE/$TOTAL_FILES] High Noise LoRA..."
download_file \
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors" \
    "$BASE_DIR/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🖼️  Downloading VAE Model (1 file, ~350MB)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

CURRENT_FILE=$((CURRENT_FILE + 1))
echo "[$CURRENT_FILE/$TOTAL_FILES] WAN 2.1 VAE..."
download_file \
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" \
    "$BASE_DIR/vae/wan_2.1_vae.safetensors"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📝 Downloading Text Encoder (1 file, ~4.7GB)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

CURRENT_FILE=$((CURRENT_FILE + 1))
echo "[$CURRENT_FILE/$TOTAL_FILES] UMT5-XXL Text Encoder..."
download_file \
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
    "$BASE_DIR/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Download Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Verify all files exist
echo "🔍 Verifying downloaded files..."
echo ""

ALL_GOOD=true

check_file() {
    local file_path="$1"
    local file_name=$(basename "$file_path")

    if [ -f "$file_path" ]; then
        FILE_SIZE=$(du -h "$file_path" | cut -f1)
        echo "   ✅ $file_name ($FILE_SIZE)"
    else
        echo "   ❌ MISSING: $file_name"
        ALL_GOOD=false
    fi
}

echo "📂 Diffusion Models:"
check_file "$BASE_DIR/diffusion_models/wan2.2_fun_control_high_noise_14B_fp8_scaled.safetensors"
check_file "$BASE_DIR/diffusion_models/wan2.2_fun_control_low_noise_14B_fp8_scaled.safetensors"
echo ""

echo "📂 LoRA Models:"
check_file "$BASE_DIR/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors"
check_file "$BASE_DIR/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors"
echo ""

echo "📂 VAE:"
check_file "$BASE_DIR/vae/wan_2.1_vae.safetensors"
echo ""

echo "📂 Text Encoders:"
check_file "$BASE_DIR/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
echo ""

# Calculate total size
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL_SIZE=$(du -sh "$BASE_DIR/diffusion_models" "$BASE_DIR/loras" "$BASE_DIR/vae" "$BASE_DIR/text_encoders" 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo "Unknown")
echo "💾 Total disk space used: ~$(du -sh $BASE_DIR | cut -f1)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$ALL_GOOD" = true ]; then
    echo "🎉 All WAN 2.2 Fun Control models are ready!"
    echo ""
    echo "📖 Next steps:"
    echo "   1. Load the WAN 2.2 Fun Control workflow in ComfyUI"
    echo "   2. Tutorial: https://docs.comfy.org/tutorials/video/wan/wan2-2-fun-control"
    echo "   3. Models will appear automatically in ComfyUI model selectors"
    echo ""
    echo "🗂️  Model locations:"
    echo "   Diffusion: /workspace/models/diffusion_models/"
    echo "   LoRAs:     /workspace/models/loras/"
    echo "   VAE:       /workspace/models/vae/"
    echo "   T5:        /workspace/models/text_encoders/"
    echo ""
    exit 0
else
    echo "⚠️  Some files are missing. Please re-run the script to retry failed downloads."
    exit 1
fi
