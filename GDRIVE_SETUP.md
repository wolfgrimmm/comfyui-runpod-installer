# Google Drive Setup Instructions

## Prerequisites
1. Google Cloud service account JSON file with Drive API access
2. A Google Drive folder shared with the service account email

## Building the Docker Image with Embedded Credentials

### Step 1: Build the image with your service account
```bash
./build_with_gdrive.sh /path/to/your-service-account.json
```

Example:
```bash
./build_with_gdrive.sh ~/Downloads/ageless-answer-466112-s1-f9cd403e242b.json
```

This will:
- Embed your credentials securely in the Docker image
- Create an image tagged as `comfyui-gdrive:latest`
- Automatically configure Google Drive on container startup

### Step 2: Push to Docker Hub (optional)
```bash
docker tag comfyui-gdrive:latest yourusername/comfyui-gdrive:latest
docker push yourusername/comfyui-gdrive:latest
```

## Running on RunPod

### Step 1: Deploy the container
Use your Docker image when creating a RunPod instance:
- Image: `yourusername/comfyui-gdrive:latest` (or local if testing)
- Expose ports: 7777, 8188, 8888

### Step 2: Automatic Setup
When the container starts, it will automatically:
1. Install ComfyUI and ComfyUI Manager
2. Configure Google Drive access
3. Create folder structure: `ComfyUI-Output/outputs/[username]`
4. Enable 1-minute auto-sync

### Step 3: Access the UI
- Control Panel: `http://[pod-ip]:7777`
- ComfyUI: Click "Start ComfyUI" in the control panel or visit `http://[pod-ip]:8188`
- JupyterLab: `http://[pod-ip]:8888`

## Google Drive Folder Structure
```
ComfyUI-Output/
├── outputs/
│   ├── serhii/
│   ├── marcin/
│   ├── vlad/
│   ├── ksenija/
│   ├── max/
│   └── ivan/
├── models/
└── workflows/
```

## Features
- **Auto-sync**: Files sync to Google Drive every minute
- **User isolation**: Each user has their own output folder
- **Smart sync**: Only syncs changed files (5+ seconds old)
- **Bandwidth limiting**: 50MB/s to prevent overload
- **Direct access**: Click "Open in Google Drive" button in the UI

## Troubleshooting

### "Checking status" loop
- The container needs 10-30 seconds to initialize on first run
- Check container logs: `docker logs [container-id]`
- Verify the service account has access to the Google Drive folder

### ComfyUI Manager not appearing
- It's installed automatically from `/app/config/baseline-nodes.txt`
- After container starts, wait 1-2 minutes for installation to complete
- Check ComfyUI logs in the UI for installation progress

### Google Drive not syncing
- Verify service account email has edit access to the Drive folder
- Check sync status in the UI control panel
- View logs: Control Panel → Google Drive tab → Sync Status

## Security Notes
- Credentials are embedded in the Docker image
- Only share the image with trusted users
- The service account should only have access to the ComfyUI-Output folder
- Never commit the service account JSON to git