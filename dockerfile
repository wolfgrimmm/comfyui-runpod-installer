# Multi-stage build to optimize storage usage
# Build stage
FROM runpod/pytorch:2.8.0-py3.11-cuda12.8.1-cudnn-devel-ubuntu22.04 as builder
WORKDIR /build
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies and clean up immediately
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl git python3.11-dev build-essential && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Install uv for faster package installation
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.cargo/bin:$PATH"
ENV UV_LINK_MODE=copy

# Copy and run minimal install script
COPY comfy_install_script.sh /build/
RUN chmod +x /build/comfy_install_script.sh && \
    bash /build/comfy_install_script.sh && \
    # Clean up build artifacts
    rm -rf /root/.cache /tmp/* /var/tmp/*

# Runtime stage - start fresh with runtime base
FROM runpod/pytorch:2.8.0-py3.11-cuda12.8.1-cudnn-runtime-ubuntu22.04
WORKDIR /workspace
ENV DEBIAN_FRONTEND=noninteractive

# Install minimal runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl git psmisc && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy built ComfyUI from builder stage
COPY --from=builder /workspace/ComfyUI /workspace/ComfyUI
COPY --from=builder /workspace/venv /workspace/venv
COPY --from=builder /workspace/start_comfyui.sh /workspace/start_comfyui.sh

# Create symlinks
RUN ln -s /workspace/ComfyUI/models /workspace/models && \
    ln -s /workspace/ComfyUI/output /workspace/output && \
    mkdir -p /workspace/ComfyUI/user/default/workflows && \
    ln -s /workspace/ComfyUI/user/default/workflows /workspace/workflows

EXPOSE 8188
CMD ["bash", "/workspace/start_comfyui.sh"]
