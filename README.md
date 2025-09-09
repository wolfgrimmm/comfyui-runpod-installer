# ComfyUI RunPod Installer

Optimized Docker image for deploying ComfyUI on RunPod with web-based control panel.

## Features

- 🚀 **RunPod Optimized** - Uses RunPod's PyTorch base image for fastest deployment
- 🎛️ **Web Control Panel** - Manage ComfyUI through browser interface (port 7777)
- 📦 **On-Demand Installation** - ComfyUI installs only when you need it
- 💾 **Persistent Storage** - All data saved in `/workspace` volume
- 🔧 **ComfyUI Manager** - Pre-configured with essential custom nodes
- 📊 **JupyterLab** - Included for advanced workflows (port 8888)
- ☁️ **Google Drive Sync** - Optional integration for model storage

## Quick Deploy

### 1. Build & Push Image

```bash
./build.sh
docker tag comfyui-runpod:latest wolfgrimmm/comfyui-runpod:latest
docker push wolfgrimmm/comfyui-runpod:latest
```

### 2. Create RunPod Template

- **Container Image:** `wolfgrimmm/comfyui-runpod:latest`
- **Container Disk:** 20-50 GB
- **Volume Mount Path:** `/workspace`
- **Exposed HTTP Ports:** `7777,8188,8888`
- **Volume Size:** 50-100 GB (for models)

### 3. Deploy Pod & Access

1. Launch pod from template
2. Access Control Panel: `https://[pod-id]-7777.proxy.runpod.net`
3. Click "Install ComfyUI" then "Start ComfyUI"
4. Access ComfyUI: `https://[pod-id]-8188.proxy.runpod.net`
5. JupyterLab available at: `https://[pod-id]-8888.proxy.runpod.net`

## How It Works

1. **Pod Starts** → Control Panel launches on port 7777
2. **You Visit Control Panel** → Install/manage ComfyUI
3. **Start ComfyUI** → Runs on port 8188
4. **All Data Persists** → Models, workflows, outputs in `/workspace`

## Google Drive Integration (Optional)

### Method 1: RunPod Secrets (Automatic)
Add these secrets in RunPod:
- `GDRIVE_SERVICE_ACCOUNT` - Service account JSON
- `GDRIVE_FOLDER_ID` - Your Google Drive folder ID

### Method 2: Manual Setup
```bash
# In JupyterLab terminal
cd /app/scripts
./setup_gdrive.sh  # Follow OAuth instructions
./sync_from_gdrive.sh  # Download models
./sync_to_gdrive.sh  # Backup outputs
```

## Persistent Storage Structure

```
/workspace/
├── ComfyUI/          # ComfyUI installation
├── models/           # All model files
│   ├── checkpoints/  # SD models
│   ├── loras/        # LoRA models
│   ├── vae/          # VAE models
│   └── controlnet/   # ControlNet models
├── output/           # Generated images
├── input/            # Input images
└── workflows/        # Saved workflows
```

## Troubleshooting

**ComfyUI won't start:**
- Use Control Panel to restart
- Check logs in JupyterLab terminal

**Out of memory:**
- Reduce batch size in ComfyUI
- Clear outputs: Control Panel → Clear Outputs

**Models not showing:**
- Refresh ComfyUI page after adding models
- Check `/workspace/models/` structure

## Tips

- **Save Money:** Stop pod when not using
- **Fast Resume:** Use "Resume" instead of new pod
- **Share Models:** Use network volumes between pods

Source: https://github.com/wolfgrimmm/comfyui-runpod-installer