#!/bin/bash

# Automatic Google Drive setup with embedded credentials
# This runs on container start and sets up everything automatically

echo "🔧 Auto-configuring Google Drive..."

# Check if already configured
if [ -f "/workspace/.gdrive_configured" ]; then
    echo "✅ Google Drive already configured"
    exit 0
fi

# Create config directories
mkdir -p /root/.config/rclone
mkdir -p /workspace/.config/rclone

# Create service account file from embedded credentials
cat > /root/.config/rclone/service_account.json << 'SERVICEACCOUNT'
{
  "type": "service_account",
  "project_id": "ageless-answer-466112-s1",
  "private_key_id": "PLACEHOLDER_PRIVATE_KEY_ID",
  "private_key": "PLACEHOLDER_PRIVATE_KEY",
  "client_email": "comfyui-sync@ageless-answer-466112-s1.iam.gserviceaccount.com",
  "client_id": "115324799941663429004",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/comfyui-sync%40ageless-answer-466112-s1.iam.gserviceaccount.com",
  "universe_domain": "googleapis.com"
}
SERVICEACCOUNT

# Copy to workspace location
cp /root/.config/rclone/service_account.json /workspace/.config/rclone/service_account.json

# Set secure permissions
chmod 600 /root/.config/rclone/service_account.json
chmod 600 /workspace/.config/rclone/service_account.json

# Create rclone config
cat > /root/.config/rclone/rclone.conf << EOF
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive = 

EOF

# Copy config to workspace
cp /root/.config/rclone/rclone.conf /workspace/.config/rclone/rclone.conf

# Test configuration
if rclone lsd gdrive: 2>/dev/null; then
    echo "✅ Google Drive connected successfully"
    
    # Create folder structure
    echo "📁 Setting up folder structure..."
    rclone mkdir gdrive:ComfyUI-Output/outputs
    rclone mkdir gdrive:ComfyUI-Output/models  
    rclone mkdir gdrive:ComfyUI-Output/workflows
    
    # Create user folders
    for user in serhii marcin vlad ksenija max ivan; do
        rclone mkdir gdrive:ComfyUI-Output/outputs/$user
    done
    
    # Mark as configured
    touch /workspace/.gdrive_configured
    
    # Store the public link for UI
    echo "https://drive.google.com/drive/search?q=ComfyUI-Output" > /workspace/.gdrive_url
    
    echo "✅ Google Drive setup complete!"
    echo "📂 Folder: ComfyUI-Output"
    echo "🔗 Access at: https://drive.google.com/drive/search?q=ComfyUI-Output"
else
    echo "⚠️  Google Drive connection failed"
    echo "   Make sure the ComfyUI-Output folder is shared with:"
    echo "   comfyui-sync@ageless-answer-466112-s1.iam.gserviceaccount.com"
fi

exit 0