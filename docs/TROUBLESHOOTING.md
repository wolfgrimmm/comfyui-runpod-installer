# Troubleshooting Guide

## Common Issues & Solutions

### ComfyUI Issues

#### ComfyUI won't start
- **Solution 1**: Use Control Panel to restart
  ```
  Access: https://[pod-id]-7777.proxy.runpod.net
  Click: Restart button
  ```
- **Solution 2**: Check logs in JupyterLab terminal
  ```bash
  docker logs $(docker ps -q)
  ```
- **Solution 3**: Ensure virtual environment is activated
  ```bash
  source /workspace/venv/bin/activate
  python /workspace/ComfyUI/main.py --listen
  ```

#### Out of Memory (OOM) Errors
- Reduce batch size in ComfyUI settings
- Clear outputs via Control Panel → Clear Outputs
- Use lower resolution for testing
- Enable CPU offloading for large models

#### Models not showing in ComfyUI
- Refresh ComfyUI page (F5)
- Check model directory structure:
  ```bash
  ls -la /workspace/ComfyUI/models/
  ```
- Ensure models are in correct subfolders (checkpoints, loras, vae, etc.)
- Restart ComfyUI after adding new models

### Google Drive Sync Issues

#### Service Account Not Connecting
- **Check Secret Format**: Ensure JSON is valid
  ```json
  {
    "type": "service_account",
    "project_id": "...",
    ...
  }
  ```
- **Verify Folder Sharing**: Folder must be shared with service account email
- **Check Logs**:
  ```bash
  cat /tmp/gdrive_sync.log
  ```

#### Files Not Syncing
- Wait at least 60 seconds (sync interval)
- Check if files exist:
  ```bash
  ls -la /workspace/output/
  ```
- Verify sync is running:
  ```bash
  ps aux | grep sync_to_gdrive
  ```
- Manual sync test:
  ```bash
  cd /app/scripts
  ./sync_to_gdrive.sh
  ```

#### RunPod Secret Not Working
- **Secret Name**: Must be exactly `GDRIVE_SERVICE_ACCOUNT`
- **Secret Value**: Entire JSON content (not file path)
- **Check Environment**:
  ```bash
  echo $RUNPOD_SECRET_GDRIVE_SERVICE_ACCOUNT | head -c 50
  ```

### Model Manager Issues

#### Model downloads failing
- Check disk space:
  ```bash
  df -h /workspace
  ```
- Verify HuggingFace connectivity:
  ```python
  from huggingface_hub import HfApi
  api = HfApi()
  api.list_models(limit=1)
  ```
- Check hf_transfer status in logs

#### Slow download speeds
- Ensure hf_transfer is enabled (should show in logs)
- Check network connectivity
- Try downloading smaller models first

### RunPod Specific Issues

#### Pod doesn't start
- Check RunPod logs in dashboard
- Verify Docker image is accessible
- Ensure volume is properly mounted at `/workspace`

#### Can't access services
- **URL Format**: `https://[pod-id]-[port].proxy.runpod.net`
- **Ports**:
  - 7777: Control Panel
  - 8188: ComfyUI
  - 8888: JupyterLab
- Check firewall/exposed ports in template

#### Volume not persisting
- Ensure volume mount path is `/workspace`
- Check volume size (minimum 50GB recommended)
- Verify pod is using persistent volume, not container disk

### Performance Issues

#### Slow generation
- Check GPU utilization:
  ```bash
  nvidia-smi
  ```
- Verify correct attention mechanism:
  - H100/H200: Should use Flash Attention 3
  - RTX 5090: Should use Sage Attention
  - Others: Should use xformers or Flash Attention 2
- Clear VRAM:
  ```bash
  nvidia-smi --gpu-reset
  ```

#### High VRAM usage
- Use GGUF quantized models for FLUX
- Enable sequential CPU offload
- Reduce batch size
- Clear ComfyUI cache

### Installation Issues

#### Custom nodes not installing
- Check ComfyUI Manager is installed:
  ```bash
  ls /workspace/ComfyUI/custom_nodes/ComfyUI-Manager
  ```
- Install manually:
  ```bash
  cd /workspace/ComfyUI/custom_nodes
  git clone https://github.com/ltdrdata/ComfyUI-Manager
  ```
- Check Python dependencies

#### PyTorch version issues
- Verify PyTorch 2.8.0 is installed:
  ```python
  import torch
  print(torch.__version__)
  ```
- Reinstall if needed:
  ```bash
  pip install torch==2.8.0 --index-url https://download.pytorch.org/whl/cu129
  ```

## Getting Help

### Logs Location
- Control Panel logs: Browser console (F12)
- ComfyUI logs: `/tmp/comfyui.log`
- Sync logs: `/tmp/gdrive_sync.log`
- System logs: `journalctl -xe`

### Debug Commands
```bash
# Check all services
ps aux | grep -E "comfyui|sync|jupyter"

# Check disk usage
df -h /workspace

# Check GPU
nvidia-smi

# Check network
curl -I https://huggingface.co

# Check Python environment
which python
python --version
pip list | grep torch
```

### Support Resources
- GitHub Issues: [Report bugs here](https://github.com/wolfgrimmm/comfyui-runpod-installer/issues)
- RunPod Discord: [Community support](https://discord.gg/runpod)
- ComfyUI Discord: [ComfyUI help](https://discord.gg/comfyui)