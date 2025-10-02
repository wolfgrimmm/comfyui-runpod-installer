#!/bin/bash

# Automatic Google Drive setup on container start
# This runs before the UI starts, configuring rclone from environment variables

echo "🔧 Initializing Google Drive configuration..."

# Check if already configured
if [ -f "/workspace/.gdrive_configured" ]; then
    echo "✅ Google Drive already configured"
    exit 0
fi

# Debug: Show available RunPod environment variables
echo "🔍 Checking for Google Drive credentials..."
echo "Available RUNPOD variables:"
env | grep ^RUNPOD | grep -v SECRET | head -5
echo ""
echo "Checking for secrets..."
# List all RUNPOD_SECRET_* variable names (not values)
for var in $(env | grep '^RUNPOD_SECRET_' | cut -d= -f1); do
    echo "  Found secret: $var (value hidden)"
done
if ! env | grep -q "RUNPOD_SECRET"; then
    echo "  No RUNPOD_SECRET_* variables found"
fi

# Function to find Google Service Account from various sources
find_service_account() {
    # Check multiple possible environment variable names
    if [ -n "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" ]; then
        echo "📝 Found service account in RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT"
        echo "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT"
        return 0
    elif [ -n "$GOOGLE_SERVICE_ACCOUNT" ]; then
        echo "📝 Found service account in GOOGLE_SERVICE_ACCOUNT"
        echo "$GOOGLE_SERVICE_ACCOUNT"
        return 0
    elif [ -n "$RUNPOD_SECRET_GDRIVE" ]; then
        echo "📝 Found service account in RUNPOD_SECRET_GDRIVE"
        echo "$RUNPOD_SECRET_GDRIVE"
        return 0
    elif [ -n "$GDRIVE_SERVICE_ACCOUNT" ]; then
        echo "📝 Found service account in GDRIVE_SERVICE_ACCOUNT"
        echo "$GDRIVE_SERVICE_ACCOUNT"
        return 0
    fi
    
    # Check all RUNPOD_SECRET_* variables
    for var in $(env | grep '^RUNPOD_SECRET_' | cut -d= -f1); do
        value="${!var}"
        # Check if it looks like a service account JSON (contains "type" and "project_id")
        if echo "$value" | grep -q '"type".*"service_account"' 2>/dev/null; then
            echo "📝 Found service account in $var"
            echo "$value"
            return 0
        fi
    done
    
    return 1
}

# Check for RunPod Secret
GOOGLE_SERVICE_ACCOUNT_JSON=$(find_service_account)
if [ -n "$GOOGLE_SERVICE_ACCOUNT_JSON" ]; then
    
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
        rclone mkdir gdrive:ComfyUI-Output/output
        rclone mkdir gdrive:ComfyUI-Output/models
        rclone mkdir gdrive:ComfyUI-Output/workflows

        # Create user folders
        for user in serhii marcin vlad ksenija max ivan; do
            rclone mkdir gdrive:ComfyUI-Output/output/$user
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
    echo "   Checked for:"
    echo "   - RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT"
    echo "   - GOOGLE_SERVICE_ACCOUNT"
    echo "   - RUNPOD_SECRET_GDRIVE"
    echo "   - GDRIVE_SERVICE_ACCOUNT"
    echo "   - Any RUNPOD_SECRET_* variable containing service account JSON"
    echo ""
    echo "   Please add GOOGLE_SERVICE_ACCOUNT secret in RunPod dashboard"
    echo "   Secret name must be exactly: GOOGLE_SERVICE_ACCOUNT"
    
    # Create a status file for the UI
    echo "missing_secret" > /workspace/.gdrive_status
fi

exit 0