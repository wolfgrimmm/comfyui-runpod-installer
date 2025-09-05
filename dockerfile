# Single stage with aggressive cleanup to save storage
FROM runpod/pytorch:2.8.0-py3.11-cuda12.8.1-cudnn-devel-ubuntu22.04
WORKDIR /workspace
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies, run script, and cleanup all in one layer
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl git python3.11-dev build-essential psmisc && \
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
