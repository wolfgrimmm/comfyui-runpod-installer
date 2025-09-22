# RunPod Setup Guide

## Step 1: Build the Docker Image
```bash
./build.sh
```
This creates a clean image without any embedded credentials.

## Step 2: Push to Docker Hub
```bash
docker tag comfyui-runpod:latest yourusername/comfyui-runpod:latest
docker push yourusername/comfyui-runpod:latest
```

## Step 3: Add Secret to RunPod
1. Go to [RunPod Dashboard](https://www.runpod.io/console/secrets)
2. Click "Add Secret"
3. Name: `GOOGLE_SERVICE_ACCOUNT`
4. Value: Paste your entire service account JSON content
5. Click "Save"

## Step 4: Create Pod Template
1. Go to Pod Templates
2. Create new template with:
   - Container Image: `yourusername/comfyui-runpod:latest`
   - Exposed Ports: `7777, 8188, 8888`
   - Volume Mount Path: `/workspace`
   - Volume Size: 100GB+ recommended

## Step 5: Deploy Pod
1. Create new pod from your template
2. The secret will be automatically injected as `$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT`
3. Google Drive will auto-configure on startup

## Access Your Pod

Once deployed, access your services:
- **Control Panel**: `http://[pod-ip]:7777`
- **ComfyUI**: `http://[pod-ip]:8188` (or click Start in Control Panel)
- **JupyterLab**: `http://[pod-ip]:8888`

## Google Drive Features
- Auto-sync every minute
- User folders: `/workspace/output/[username]`
- Direct Drive access via "Open in Google Drive" button
- Bandwidth limited to 50MB/s
- Smart sync (only files older than 5 seconds)

## Troubleshooting

### Pod doesn't start
- Check RunPod logs for errors
- Verify Docker image is public or you're logged in

### Google Drive not connecting
- Verify secret name is exactly `GOOGLE_SERVICE_ACCOUNT`
- Check secret value is valid JSON
- Look for "Found service account in RunPod Secret" in logs

### ComfyUI Manager missing
- Wait 1-2 minutes after pod starts
- Check `/workspace/ComfyUI/custom_nodes/` directory
- Review logs for installation errors