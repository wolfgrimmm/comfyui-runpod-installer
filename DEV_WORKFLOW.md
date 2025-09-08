# Development Workflow Guide

## Quick Development Methods (Avoid 15-20 min builds!)

### Option 1: Direct RunPod Pod Editing (Fastest for Testing)
1. Deploy your pod with current image
2. SSH into the running pod
3. Edit files directly:
   ```bash
   # SSH into your RunPod pod
   ssh root@[your-pod-ip] -p [your-ssh-port]
   
   # Edit UI files directly
   cd /app/ui
   nano app.py  # or vim, or use JupyterLab
   
   # Restart just the UI service
   pkill -f "python app.py"
   cd /app/ui && python app.py &
   ```
4. Test changes immediately (no rebuild!)
5. Once working, commit changes to GitHub

### Option 2: Local Development with Hot Reload

#### For UI-only changes:
```bash
# Run just the UI locally
cd ui
python app.py
# Visit http://localhost:7777
```

#### With Docker Compose (includes all services):
```bash
# Start development environment
docker-compose -f docker-compose.dev.yml up ui-only

# Or full stack with hot reload
docker-compose -f docker-compose.dev.yml up comfyui-dev
```

### Option 3: Push to Branch, Use Temporary Image
1. Create a dev branch:
   ```bash
   git checkout -b dev-feature
   ```

2. Build and push a dev image locally (faster):
   ```bash
   # Build only what changed
   docker build -t wolfgrimmm/comfyui-runpod:dev-test .
   docker push wolfgrimmm/comfyui-runpod:dev-test
   ```

3. Update RunPod pod to use `dev-test` tag temporarily

### Option 4: Mount Code via RunPod Network Volume
1. Create a RunPod network volume
2. Upload your code to the volume
3. Mount at `/app/ui-dev`
4. Modify start script to use mounted code:
   ```bash
   # In your pod
   ln -sf /app/ui-dev /app/ui
   pkill -f "python app.py"
   cd /app/ui && python app.py &
   ```

## Fastest Development Loop

### For UI Changes:
1. **Develop locally** → Test with `python ui/app.py`
2. **Test in pod** → SSH and edit directly
3. **Finalize** → Commit and push (triggers full build)

### Build Time Comparison:
- **Local Python**: Instant (0 seconds)
- **Docker Compose UI-only**: ~10 seconds
- **Local Docker build (cached)**: ~1-2 minutes
- **GitHub Actions (UI-only)**: ~2-3 minutes
- **GitHub Actions (full)**: ~15-20 minutes

## Pro Tips:

### 1. Use RunPod's Persistent Storage
```bash
# Save your development state
cd /workspace
git clone https://github.com/yourusername/comfyui-runpod-installer.git dev
cd dev
# Make changes here, they persist across pod restarts
```

### 2. Quick Sync Script
Create `/workspace/sync-ui.sh`:
```bash
#!/bin/bash
# Pull latest UI changes without rebuilding
cd /workspace/dev
git pull
cp -r ui/* /app/ui/
pkill -f "python app.py"
cd /app/ui && python app.py &
```

### 3. Use JupyterLab for Editing
- Access JupyterLab on port 8888
- Edit files directly in browser
- Terminal available for running commands
- Changes apply immediately

### 4. Skip Docker Hub
For testing, build and run locally:
```bash
# Build locally with your changes
docker build -t comfyui-test .

# Run locally
docker run -p 7777:7777 -p 8188:8188 -p 8888:8888 comfyui-test

# Or save image and upload to RunPod directly
docker save comfyui-test | gzip > comfyui-test.tar.gz
# Upload to RunPod via their file transfer
```

## Recommended Workflow:

1. **Initial Development**: Local Python (instant)
2. **Integration Testing**: Docker Compose (10 seconds)  
3. **RunPod Testing**: Direct SSH editing (instant)
4. **Production**: GitHub push → automated build (15-20 min)

This way, you only trigger the long GitHub Actions build when you're ready to deploy to production!

Made by Serhii Yashyn