# ComfyUI RunPod Deployment Guide

## Quick Start

### 1. Deploy on RunPod

1. Go to [RunPod](https://runpod.io)
2. Click "Deploy" → "Pods" → "GPU Pod"
3. Select GPU (RTX 4090, A100, etc.)
4. In Template section:
   - Container Image: `wolfgrimmm/comfyui-runpod:latest`
   - Container Disk: 20-50 GB (depending on models)
   - Volume Disk: 50-100 GB (for persistent storage)
   - Expose HTTP Ports: `8188,8888`
5. Deploy Pod

### 2. Access Your Pod

Once running, you have 3 options:

#### Option A: Web Terminal (Easiest)
1. Click "Connect" → "Connect to Web Terminal"
2. Run: `./start_comfyui.sh`
3. Click "Connect to HTTP Service [Port 8188]"

#### Option B: JupyterLab
1. Click "Connect" → "Connect to HTTP Service [Port 8888]"
2. Open Terminal in JupyterLab
3. Run: `./start_comfyui.sh`
4. Access ComfyUI at: `https://[pod-id]-8188.proxy.runpod.net`

#### Option C: SSH
1. Add SSH key in RunPod settings
2. Click "Connect" → Get SSH command
3. SSH into pod and run: `./start_comfyui.sh`

### 3. Install Flash Attention (Optional - First Run)

Flash Attention provides 2-3x speedup but may fail during Docker build. Install it on first run:

```bash
# Via JupyterLab or SSH terminal
./install_flash_attention.sh

# Or it auto-installs when you run:
./start_comfyui.sh
```

### 4. Google Drive Integration

#### First-time setup:
```bash
./setup_gdrive.sh
# Follow the instructions to connect your Google account
```

#### Sync models FROM Google Drive:
```bash
./sync_from_gdrive.sh
# Downloads models, workflows, and inputs from your Drive
```

#### Backup outputs TO Google Drive:
```bash
./sync_to_gdrive.sh  
# Uploads your generated images and workflows to Drive
```

#### Google Drive folder structure:
```
Google Drive/
└── ComfyUI/
    ├── models/
    │   ├── checkpoints/   # Your SD models
    │   ├── loras/         # LoRA models
    │   ├── vae/           # VAE models
    │   └── controlnet/    # ControlNet models
    ├── workflows/         # Your saved workflows
    ├── output/           # Generated images backup
    └── input/            # Input images for img2img

### 5. Persistent Storage

RunPod volumes persist at `/workspace/`. Structure:
```
/workspace/
├── ComfyUI/          # Main installation
├── models/           # Your models (symlink to ComfyUI/models)
├── output/           # Generated images
├── workflows/        # Saved workflows
└── venv/            # Python environment
```

## Troubleshooting

### ComfyUI won't start
```bash
# Kill existing process
fuser -k 8188/tcp

# Check logs
./start_comfyui.sh
```

### Out of memory
- Reduce batch size in ComfyUI
- Use lower resolution
- Clear output folder: `rm -rf /workspace/output/*`

### Slow generation
- Install Flash Attention: `./install_flash_attention.sh`
- Ensure you selected GPU pod (not CPU)
- Check GPU: `nvidia-smi`

### Models not showing
- Check models directory: `ls /workspace/models/`
- Restart ComfyUI after adding models
- Ensure correct folder structure (checkpoints/, loras/, etc.)

## Custom Nodes

Pre-installed:
- ComfyUI Manager
- IPAdapter Plus  
- GGUF support

Install more via Manager or manually:
```bash
cd /workspace/ComfyUI/custom_nodes
git clone [custom-node-repo]
pip install -r requirements.txt  # if needed
```

## Tips

1. **Save money**: Stop pod when not using, RunPod only charges for active time
2. **Faster startup**: Use "Resume" instead of creating new pod
3. **Model management**: Use network volumes to share models between pods
4. **Workflows**: Save important workflows to `/workspace/workflows/`

## Docker Image Details

- Base: CUDA 12.9, Ubuntu 22.04, Python 3.10
- PyTorch: 2.7.1 with CUDA 12.8
- Includes: ComfyUI, essential custom nodes, AI packages
- Flash Attention: Installs on first run (avoids build failures)

Source: https://github.com/wolfgrimmm/comfyui-runpod-installer