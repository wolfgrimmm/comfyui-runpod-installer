#!/bin/bash

# Install CUDA 12.9 Toolkit
# This script installs CUDA 12.9 alongside existing CUDA installation

set -e

echo "=========================================="
echo "Installing CUDA 12.9 Toolkit"
echo "=========================================="

# Add NVIDIA package repositories
apt-get update
apt-get install -y wget software-properties-common

# Add CUDA repository for Ubuntu 22.04
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
rm cuda-keyring_1.1-1_all.deb

# Update package lists
apt-get update

# Install CUDA 12.9 toolkit (without driver - we'll use RunPod's driver)
# Note: cuda-toolkit-12-9 installs just the toolkit without driver
apt-get install -y cuda-toolkit-12-9 --no-install-recommends

# Install cuDNN 9 for CUDA 12
apt-get install -y libcudnn9-cuda-12 libcudnn9-dev-cuda-12

# Set up environment variables
echo 'export PATH=/usr/local/cuda-12.9/bin:$PATH' >> /etc/profile.d/cuda-12.9.sh
echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.9/lib64:$LD_LIBRARY_PATH' >> /etc/profile.d/cuda-12.9.sh
echo 'export CUDA_HOME=/usr/local/cuda-12.9' >> /etc/profile.d/cuda-12.9.sh

# Create symlink for default CUDA
if [ -L /usr/local/cuda ]; then
    rm /usr/local/cuda
fi
ln -s /usr/local/cuda-12.9 /usr/local/cuda

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "✅ CUDA 12.9 installation complete"
echo "CUDA Version:"
/usr/local/cuda-12.9/bin/nvcc --version || echo "nvcc not found"

echo ""
echo "To verify installation:"
echo "  nvcc --version"
echo "  nvidia-smi"