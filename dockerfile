# Optimized Dockerfile for ComfyUI with RTX 5090 support
# Uses minimal base and --no-cache-dir to reduce build storage usage

FROM nvidia/cuda:12.9.0-runtime-ubuntu22.04
WORKDIR /workspace
ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_NO_CACHE_DIR=1

# Install Python and essential runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.10 python3.10-dev python3-pip python3.10-venv \
    curl git psmisc \
    gcc g++ make \
    libgomp1 libquadmath0 libgfortran5 libopenblas0-pthread && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy and run installation script
COPY comfy_install_script.sh /workspace/
RUN chmod +x /workspace/comfy_install_script.sh && \
    bash /workspace/comfy_install_script.sh && \
    # Clean up after installation to reduce layer size
    rm -rf /root/.cache/pip/* && \
    apt-get remove -y gcc g++ make && \
    apt-get autoremove -y && \
    apt-get clean

EXPOSE 8188
CMD ["bash", "/workspace/start_comfyui.sh"]