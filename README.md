# ComfyUI RunPod Installer

🚀 Optimized Docker image for deploying ComfyUI on RunPod with advanced features and web control panel.

## ✨ Key Features

- **⚡ Ultra-Fast Setup** - 5-minute deployment with pre-compiled wheels
- **🎨 Model Manager** - Download models directly from HuggingFace with 2-5x faster speeds
- **🖼️ ComfyViewer** - Browse and search your generated images with metadata (NEW!)
- **🧠 GPU Auto-Optimization** - Automatic attention mechanism selection:
  - H100/H200: Flash Attention 3 (Hopper optimized)
  - RTX 5090/B200: Sage Attention 2.2.0 (Blackwell optimized)
  - A100/A40: Flash Attention 2.8.3
  - Others: xformers 0.33
- **📦 Latest Stack** - PyTorch 2.8.0 with CUDA 12.9 support
- **🎛️ Web Control Panel** - Full management interface (port 7777)
- **💾 Persistent Storage** - All data saved in `/workspace` volume
- **☁️ Google Drive Sync** - Automatic output synchronization
- **🔧 Pre-configured** - ComfyUI Manager + essential custom nodes

## 🚀 Quick Start

### 1. Deploy on RunPod

Use the pre-built image directly:
```
wolfgrimmm/comfyui-runpod:latest
```

Or build your own:
```bash
./build.sh
docker tag comfyui-runpod:latest yourusername/comfyui-runpod:latest
docker push yourusername/comfyui-runpod:latest
```

### 2. RunPod Template Settings

- **Container Image:** `wolfgrimmm/comfyui-runpod:latest`
- **Container Disk:** 20-50 GB
- **Volume Mount:** `/workspace`
- **Volume Size:** 50-100 GB (for models)
- **Exposed Ports:** `7777,8188,8888,3001`
- **Recommended GPU:** RTX 3090 minimum (24GB+ VRAM preferred)

### 3. Access Your Services

After pod starts:
- **Control Panel:** `https://[pod-id]-7777.proxy.runpod.net`
- **ComfyUI:** `https://[pod-id]-8188.proxy.runpod.net`
- **JupyterLab:** `https://[pod-id]-8888.proxy.runpod.net`
- **ComfyViewer:** `https://[pod-id]-3001.proxy.runpod.net` (after installation)

## 🎨 Model Manager

Access the Model Manager through the Control Panel to:
- **Search** models on HuggingFace Hub
- **Download** with 2-5x faster speeds (hf_transfer enabled)
- **Auto-organize** into correct ComfyUI folders
- **Monitor** download progress and disk usage
- **Delete** unwanted models to save space

Supports all model types: FLUX, SDXL, LoRA, ControlNet, VAE, CLIP, and more.

## 🖼️ ComfyViewer (Optional)

A modern web-based image viewer for browsing your AI-generated images with rich metadata.

### Features
- **100% Local** - All processing happens in your browser using IndexedDB
- **Rich Metadata** - View prompts, seeds, samplers, models, and full workflows
- **Advanced Search** - Filter by any metadata field (prompt keywords, models, etc.)
- **Fast Navigation** - Arrow keys support for quick browsing
- **Workflow View** - See the complete ComfyUI workflow for each image

### Installation & Usage
1. Click **"Install ComfyViewer"** in the Control Panel
2. Installation takes 3-5 minutes (one-time setup)
3. Click **"Start Viewer"** when ready
4. Access at `https://[pod-id]-3001.proxy.runpod.net`
5. Select your output folder to browse images

### Technical Details
- Built with Next.js, TypeScript, and Tailwind CSS
- Requires ~300MB disk space, ~200MB RAM when running
- Can be stopped when not needed to save resources
- Port 3001 (doesn't conflict with other services)

## ☁️ Google Drive Integration (Optional)

Automatic backup of generated outputs to Google Drive using service account authentication.

### Features
- Auto-sync every 60 seconds
- User-based output folders
- Smart sync (only completed files)
- Direct Drive access from Control Panel

## 📁 Directory Structure

```
/workspace/
├── ComfyUI/          # ComfyUI installation
│   ├── models/       # All model files
│   ├── custom_nodes/ # Extensions
│   └── web/          # UI files
├── output/           # Generated images
├── input/            # Input images
├── workflows/        # Saved workflows
└── venv/             # Python environment
```

## 🛠️ Advanced Features

### GPU-Optimized Attention
The installer automatically detects your GPU and installs the best attention mechanism:
- **H100/H200**: Compiles Flash Attention 3 from source
- **RTX 5090**: Uses pre-compiled Sage Attention 2.2.0
- **A100/RTX 40xx**: Pre-compiled Flash Attention 2.8.3
- **Others**: Falls back to xformers for compatibility

### Performance Tips
- Use GGUF quantized models for FLUX (lower VRAM usage)
- Enable hf_transfer for faster downloads (already configured)
- Clear outputs regularly to save disk space
- Use network volumes for model sharing between pods

## 🔧 Troubleshooting

### ComfyUI won't start
- Click "Restart" in Control Panel
- Check logs in JupyterLab terminal
- Ensure enough VRAM for your models

### Models not appearing
- Refresh ComfyUI after adding models
- Check `/workspace/ComfyUI/models/` structure
- Use Model Manager for proper organization

### Out of memory
- Reduce batch size or resolution
- Use quantized models (GGUF format)
- Clear VRAM: `nvidia-smi --gpu-reset`

Check documentation for detailed troubleshooting steps.

## 📚 Documentation

- [System Overview](docs/OVERVIEW.md) - Architecture and components
- Setup instructions available separately
- Troubleshooting guides available separately

## 💡 Tips & Tricks

- **Save money:** Stop pods when not in use
- **Fast resume:** Use "Resume" instead of creating new pods
- **Share models:** Use network volumes between pods
- **Backup workflows:** Enable Google Drive sync
- **Monitor usage:** Check Control Panel for resource stats

## 🤝 Contributing

Contributions welcome! Please submit PRs or issues on GitHub.

## 📄 License

MIT License - See LICENSE file for details.

---

**Source:** https://github.com/wolfgrimmm/comfyui-runpod-installer
**Docker Hub:** https://hub.docker.com/r/wolfgrimmm/comfyui-runpod
**Support:** [Open an issue](https://github.com/wolfgrimmm/comfyui-runpod-installer/issues)