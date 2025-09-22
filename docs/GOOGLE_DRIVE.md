# Google Drive Auto-Sync Setup Guide

For ComfyUI RunPod - Automatic Output Synchronization

This guide will help you set up automatic Google Drive sync for ComfyUI outputs. Once configured, all generated images will automatically sync to Google Drive every 60 seconds with zero user interaction required.

## Step 1: Create Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Click "Select a project" (top bar) → "New Project"
3. Enter project details:
   - Project name: `ComfyUI-Sync` (or any name you prefer)
   - Leave organization as is
   - Click "Create"
4. Wait for project creation (takes ~10 seconds)

## Step 2: Enable Google Drive API

1. Make sure your new project is selected (check top bar)
2. Navigate to "APIs & Services" → "Enable APIs and Services"
   - Or use [direct link](https://console.cloud.google.com/apis/library)
3. Search for "Google Drive API"
4. Click on "Google Drive API" from results
5. Click the blue "Enable" button
6. Wait for API to be enabled (takes ~5 seconds)

## Step 3: Create Service Account

1. Go to "APIs & Services" → "Credentials"
   - Or use [direct link](https://console.cloud.google.com/apis/credentials)
2. Click "Create Credentials" → "Service Account"
3. Service account details:
   - Name: `comfyui-sync`
   - ID: (auto-filled)
   - Description: `Service account for ComfyUI output sync`
   - Click "Create and Continue"
4. Grant role (REQUIRED):
   - Click "Select a role"
   - Search for "Editor"
   - Select "Editor" role
   - Click "Continue"
5. Click "Done" (skip optional third step)

## Step 4: Create Service Account Key

1. In the Credentials page, find your service account
2. Click on the service account email
3. Go to "Keys" tab
4. Click "Add Key" → "Create new key"
5. Select "JSON" format
6. Click "Create"
7. **IMPORTANT**: Save the downloaded JSON file safely

## Step 5: Create Google Drive Folder

1. Go to [Google Drive](https://drive.google.com)
2. Create a new folder named `ComfyUI-Outputs` (or your preference)
3. Right-click the folder → "Share"
4. Add your service account email:
   - Email: `comfyui-sync@YOUR-PROJECT-ID.iam.gserviceaccount.com`
   - Role: Editor
   - Click "Send"
5. Copy the folder ID from the URL:
   - Example URL: `https://drive.google.com/drive/folders/1ABC-XYZ123`
   - Folder ID: `1ABC-XYZ123`

## Step 6: Configure RunPod

### Option 1: RunPod Secrets (Recommended)

1. Go to [RunPod Secrets](https://www.runpod.io/console/secrets)
2. Add two secrets:
   - **GDRIVE_SERVICE_ACCOUNT**: Paste entire JSON content
   - **GDRIVE_FOLDER_ID**: Your folder ID from Step 5
3. Deploy pod - auto-sync starts automatically!

### Option 2: Manual Configuration

1. Access JupyterLab terminal
2. Run setup script:
   ```bash
   cd /app/scripts
   ./setup_gdrive.sh
   ```
3. Follow prompts to configure

## Verification

Once configured, check these indicators:

- **Control Panel**: Shows "Google Drive: Connected ✅"
- **Logs**: Look for "Google Drive sync configured successfully"
- **Test**: Generate an image and check your Drive folder after 60 seconds

## Features

- **Automatic sync**: Every 60 seconds
- **User folders**: Organized by username
- **Smart sync**: Only syncs files older than 5 seconds
- **Bandwidth limited**: 50MB/s to prevent API limits
- **Direct Drive access**: "Open in Google Drive" button in Control Panel

## Troubleshooting

### Service Account Not Working
- Verify Editor role is granted
- Check folder is shared with service account email
- Ensure JSON is valid (no extra spaces/characters)

### No Files Syncing
- Wait at least 60 seconds after generation
- Check `/workspace/output/` has files
- Review logs in JupyterLab terminal

### API Limits
- Sync is rate-limited to prevent issues
- Large files may take multiple sync cycles
- Consider using network volume for very large datasets