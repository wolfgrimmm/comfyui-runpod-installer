# Use minimal CUDA 12.9 runtime base for RTX 5090 support
FROM nvidia/cuda:12.9.0-runtime-ubuntu22.04
WORKDIR /workspace
ENV DEBIAN_FRONTEND=noninteractive

# Install Python and dependencies, then install uv
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3.11 python3.11-venv python3.11-dev curl git build-essential psmisc && \
    # Install uv
    curl -LsSf https://astral.sh/uv/install.sh | sh && \
    # Cleanup apt immediately
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Copy script and run with cleanup
COPY comfy_install_script.sh /workspace/
RUN chmod +x /workspace/comfy_install_script.sh && \
    export PATH="/root/.cargo/bin:$PATH" && \
    export UV_LINK_MODE=copy && \
    bash /workspace/comfy_install_script.sh && \
    # Aggressive cleanup
    rm -rf /root/.cache /root/.cargo /tmp/* /var/tmp/* /workspace/comfy_install_script.sh && \
    apt-get remove -y python3.11-dev build-essential && \
    apt-get autoremove -y && \
    apt-get clean

EXPOSE 8188
CMD ["bash", "/workspace/start_comfyui.sh"]
