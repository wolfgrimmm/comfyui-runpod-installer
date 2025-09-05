FROM ubuntu:22.04
WORKDIR /workspace
RUN apt-get update && apt-get install -y wget curl && apt-get clean
RUN wget https://raw.githubusercontent.com/wolfgrimmm/comfyui-runpod-installer/main/comfy_install_script.sh && chmod +x comfy_install_script.sh
EXPOSE 8188
CMD ["./comfy_install_script.sh && tail -f /dev/null"]
