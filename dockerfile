FROM runpod/pytorch:0.7.0-cu1241-torch240-ubuntu2004
WORKDIR /workspace
COPY comfy_install_script.sh /workspace/
RUN chmod +x comfy_install_script.sh && apt-get update && apt-get install -y git curl
EXPOSE 8188
CMD ["/bin/bash"]
