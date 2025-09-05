# Use minimal CUDA 12.9 runtime base for RTX 5090 support
FROM nvidia/cuda:12.9.0-runtime-ubuntu22.04
WORKDIR /workspace
ENV DEBIAN_FRONTEND=noninteractive

# Install Python and dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3.11 python3.11-pip python3.11-venv curl git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy and run script
COPY comfy_install_script.sh /workspace/
RUN chmod +x /workspace/comfy_install_script.sh && \
    bash /workspace/comfy_install_script.sh

EXPOSE 8188
CMD ["bash", "/workspace/start_comfyui.sh"]
