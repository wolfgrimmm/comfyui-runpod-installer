FROM runpod/pytorch:2.8.0-py3.11-cuda12.8.1-devel-ubuntu22.04
WORKDIR /workspace
COPY comfy_install_script.sh /workspace/
RUN chmod +x comfy_install_script.sh && apt-get update && apt-get install -y git curl
EXPOSE 8188
CMD ["/bin/bash"]
