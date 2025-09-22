#!/bin/bash
# Test script for GPU detection logic

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 GPU Detection Test Script"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Test GPUs from RunPod
test_gpus=(
    "NVIDIA B200"
    "NVIDIA H200 SXM"
    "NVIDIA H100 NVL"
    "NVIDIA H100 SXM"
    "NVIDIA H100 PCIe"
    "NVIDIA A40"
    "NVIDIA RTX 5090"
    "NVIDIA RTX 4090"
    "NVIDIA L40"
    "NVIDIA L40S"
    "NVIDIA L4"
    "NVIDIA RTX 6000 Ada"
    "NVIDIA RTX 4000 Ada"
    "NVIDIA RTX 2000 Ada"
    "NVIDIA RTX PRO 6000"
    "RTX 6000 WK"
)

for gpu in "${test_gpus[@]}"; do
    echo ""
    echo "Testing GPU: $gpu"
    GPU_NAME="$gpu"

    # Determine GPU type - Same logic as in Dockerfile
    if echo "$GPU_NAME" | grep -qE "B200|NVIDIA B200"; then
        GPU_TYPE="blackwell"
        EXPECTED_ATTENTION="Sage Attention"
    elif echo "$GPU_NAME" | grep -qE "H100|H200|H800|NVIDIA H100|NVIDIA H200"; then
        GPU_TYPE="hopper"
        EXPECTED_ATTENTION="Flash Attention 3"
    elif echo "$GPU_NAME" | grep -qE "RTX 4090|RTX 4080|RTX 4070|RTX 4060"; then
        GPU_TYPE="ada"
        EXPECTED_ATTENTION="Flash Attention 2 / xformers"
    elif echo "$GPU_NAME" | grep -qE "L40|L40S|L4|NVIDIA L40|NVIDIA L4"; then
        GPU_TYPE="ada"
        EXPECTED_ATTENTION="Flash Attention 2 / xformers"
    elif echo "$GPU_NAME" | grep -qE "RTX 6000 Ada|RTX 5000 Ada|RTX 4000 Ada|RTX 2000 Ada|RTX Ada"; then
        GPU_TYPE="ada"
        EXPECTED_ATTENTION="Flash Attention 2 / xformers"
    elif echo "$GPU_NAME" | grep -qE "RTX PRO 6000|RTX 6000 WK|RTX 6000"; then
        GPU_TYPE="ada"
        EXPECTED_ATTENTION="Flash Attention 2 / xformers"
    elif echo "$GPU_NAME" | grep -qE "A100|A40|A30|A10|NVIDIA A100|NVIDIA A40"; then
        GPU_TYPE="ampere"
        EXPECTED_ATTENTION="Flash Attention 2 / xformers"
    elif echo "$GPU_NAME" | grep -qE "RTX 3090|RTX 3080|RTX 3070|RTX 3060"; then
        GPU_TYPE="ampere"
        EXPECTED_ATTENTION="Flash Attention 2 / xformers"
    elif echo "$GPU_NAME" | grep -qE "RTX 5090|RTX 5080|RTX 5070|RTX 5060"; then
        GPU_TYPE="blackwell"
        EXPECTED_ATTENTION="Sage Attention"
    elif echo "$GPU_NAME" | grep -qE "A800|A6000"; then
        GPU_TYPE="ampere"
        EXPECTED_ATTENTION="Flash Attention 2 / xformers"
    else
        GPU_TYPE="generic"
        EXPECTED_ATTENTION="xformers"
    fi

    echo "  → Architecture: $GPU_TYPE"
    echo "  → Recommended: $EXPECTED_ATTENTION"
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ GPU Detection Test Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"