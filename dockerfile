FROM nvidia/cuda:12.8-cudnn9-devel-ubuntu22.04
WORKDIR /workspace
RUN apt-get update && apt-get install -y python3 python3-pip git curl wget
COPY comfy_install_script.sh /workspace/
RUN chmod +x comfy_install_script.sh
EXPOSE 8188
CMD ["/bin/bash"]
