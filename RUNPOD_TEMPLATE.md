# RunPod Template Configuration

## Updated Template Settings for ComfyUI with UI

When creating or updating your RunPod template, use these settings:

### Container Configuration
- **Container Image**: `wolfgrimmm/comfyui-runpod:latest`
- **Container Start Command**: `/app/start.sh` (or leave blank for default CMD)

### Disk Configuration
- **Container Disk**: 30-50 GB (for ComfyUI, models, and dependencies)
- **Volume Disk**: 50-200 GB (for persistent storage of models and user data)
- **Volume Mount Path**: `/workspace`

### Port Configuration
You need to expose THREE ports now:
- **7777** - User Interface (for user selection)
- **8188** - ComfyUI (main application)
- **8888** - JupyterLab (for notebook access)

In RunPod template, set:
```
Expose HTTP Ports: 7777,8188,8888
```

### Environment Variables (Optional)
```
HF_HOME=/workspace
COMFYUI_USER=default
```

### Startup Behavior
The container will automatically start:
1. **UI on port 7777** - Visit this FIRST to select your user
2. **JupyterLab on port 8888** - For file management and notebooks
3. **ComfyUI** - Does NOT auto-start, must be started through UI

### Access URLs After Deployment
Once your pod is running, you'll have:
- **UI**: `https://[pod-id]-7777.proxy.runpod.net`
- **JupyterLab**: `https://[pod-id]-8888.proxy.runpod.net`  
- **ComfyUI**: `https://[pod-id]-8188.proxy.runpod.net` (after starting via UI)

### Workflow for Users
1. Deploy pod with updated template
2. Visit UI at port 7777
3. Select or create username
4. Click "Start ComfyUI"
5. UI redirects to ComfyUI on port 8188
6. All work saves to user-specific folders:
   - `/workspace/input/[username]/`
   - `/workspace/output/[username]/`
   - `/workspace/workflows/[username]/`

### Network Volume Structure
The `/workspace` directory will contain:
```
/workspace/
├── ComfyUI/          # Main ComfyUI installation
├── models/           # Shared models (checkpoints, loras, vae, etc.)
├── input/            # User-specific input folders
│   └── [username]/
├── output/           # User-specific output folders
│   └── [username]/
├── workflows/        # User-specific workflow folders
│   └── [username]/
└── user_data/        # User configuration and settings
```

### Template JSON (for API/Advanced Users)
```json
{
  "name": "ComfyUI with User Management",
  "imageName": "wolfgrimmm/comfyui-runpod:latest",
  "dockerArgs": "",
  "ports": "7777/http,8188/http,8888/http",
  "volumeInGb": 100,
  "containerDiskInGb": 30,
  "env": [
    {
      "key": "HF_HOME",
      "value": "/workspace"
    }
  ]
}
```

### Important Notes
- The UI must be accessed first to start ComfyUI
- Each user gets separate folders for organization
- Models are shared between all users (in `/workspace/models/`)
- JupyterLab has no authentication by default (suitable for single-user pods)

Made by Serhii Yashyn