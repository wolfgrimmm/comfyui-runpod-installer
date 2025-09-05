# Multi-stage build: use devel for compilation, runtime for final image
FROM nvidia/cuda:12.9.0-devel-ubuntu22.04 AS builder

WORKDIR /workspace
ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_NO_CACHE_DIR=1

# Install Python and build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.10 python3.10-dev python3-pip python3.10-venv \
    curl git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy and run installation script in builder
COPY comfy_install_script.sh /workspace/
RUN chmod +x /workspace/comfy_install_script.sh && \
    bash /workspace/comfy_install_script.sh

# Runtime stage with minimal image
FROM nvidia/cuda:12.9.0-runtime-ubuntu22.04

WORKDIR /workspace
ENV DEBIAN_FRONTEND=noninteractive

# Install only runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.10 python3.10-distutils \
    curl git psmisc \
    libgomp1 libquadmath0 libgfortran5 libopenblas0-pthread && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy everything from builder
COPY --from=builder /workspace /workspace

# Set environment variables
ENV PATH="/workspace/venv/bin:$PATH"
ENV VIRTUAL_ENV="/workspace/venv"
ENV HF_HOME="/workspace"
ENV HF_HUB_ENABLE_HF_TRANSFER=1
ENV PIP_NO_CACHE_DIR=1

EXPOSE 8188
CMD ["bash", "/workspace/start_comfyui.sh"]