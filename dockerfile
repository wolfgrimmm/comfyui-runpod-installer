FROM runpod/pytorch:2.8.0-py3.11-cuda12.8.1-cudnn-devel-ubuntu22.04
WORKDIR /workspace
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends wget curl ca-certificates git python3.11-dev build-essential && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
COPY comfy_install_script.sh /workspace/
RUN chmod +x /workspace/comfy_install_script.sh
EXPOSE 8188
CMD ["bash", "-c", "cd /workspace && ls -la && ./comfy_install_script.sh && tail -f /dev/null"]
