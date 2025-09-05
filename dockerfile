FROM ubuntu:22.04
WORKDIR /workspace
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends wget curl ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
RUN wget https://raw.githubusercontent.com/wolfgrimmm/comfyui-runpod-installer/main/comfy_install_script.sh && \
    chmod +x comfy_install_script.sh
EXPOSE 8188
CMD ["bash", "-c", "./comfy_install_script.sh && tail -f /dev/null"]
