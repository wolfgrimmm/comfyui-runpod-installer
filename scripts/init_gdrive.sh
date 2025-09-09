#!/bin/bash

# Automatic Google Drive setup on container start
# This runs before the UI starts, configuring rclone from environment variables

echo "🔧 Initializing Google Drive configuration..."

# Check if already configured
if [ -f "/workspace/.gdrive_configured" ]; then
    echo "✅ Google Drive already configured"
    exit 0
fi

# Check for RunPod Secret
if [ -n "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" ]; then
    echo "📝 Found service account in RunPod Secret"
    export GOOGLE_SERVICE_ACCOUNT_JSON="$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT"
    
    # Create config directories
    mkdir -p /root/.config/rclone
    mkdir -p /workspace/.config/rclone
    
    # Save service account JSON
    echo "$GOOGLE_SERVICE_ACCOUNT_JSON" > /root/.config/rclone/service_account.json
    echo "$GOOGLE_SERVICE_ACCOUNT_JSON" > /workspace/.config/rclone/service_account.json
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
    
    # Copy to workspace location too
    cp /root/.config/rclone/rclone.conf /workspace/.config/rclone/rclone.conf
    
    # Test configuration
    if rclone lsd gdrive: 2>/dev/null; then
        echo "✅ Google Drive configured successfully"
        
        # Create folder structure
        echo "📁 Creating folder structure..."
        rclone mkdir gdrive:ComfyUI-Output/outputs
        rclone mkdir gdrive:ComfyUI-Output/models
        rclone mkdir gdrive:ComfyUI-Output/workflows
        
        # Create user folders
        for user in serhii marcin vlad ksenija max ivan; do
            rclone mkdir gdrive:ComfyUI-Output/outputs/$user
        done
        
        # Mark as configured
        touch /workspace/.gdrive_configured
        
        # Store the Drive ID for UI access
        DRIVE_ID=$(echo "$GOOGLE_SERVICE_ACCOUNT_JSON" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('project_id', 'unknown'))")
        echo "$DRIVE_ID" > /workspace/.gdrive_id
        
        echo "✅ Google Drive setup complete"
    else
        echo "⚠️  Failed to connect to Google Drive"
        echo "   Please check your service account permissions"
        exit 1
    fi
    
else
    echo "⚠️  No Google Drive configuration found"
    echo "   Please add GOOGLE_SERVICE_ACCOUNT secret in RunPod dashboard"
    echo "   Secret name must be exactly: GOOGLE_SERVICE_ACCOUNT"
    echo "   It will be available as: RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT"
    
    # Create a status file for the UI
    echo "missing_secret" > /workspace/.gdrive_status
fi

exit 0