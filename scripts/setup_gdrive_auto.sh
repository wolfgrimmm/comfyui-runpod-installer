#!/bin/bash

# Automated Google Drive Setup with Service Account
echo "=========================================="
echo "🔧 Automated Google Drive Setup"
echo "=========================================="

# Check if service account file is provided
if [ -z "$1" ]; then
    echo "❌ Error: Please provide the path to your service account JSON file"
    echo "Usage: $0 /path/to/service-account.json"
    exit 1
fi

SERVICE_ACCOUNT_FILE="$1"

# Check if file exists
if [ ! -f "$SERVICE_ACCOUNT_FILE" ]; then
    echo "❌ Error: Service account file not found: $SERVICE_ACCOUNT_FILE"
    exit 1
fi

# Extract client email from JSON
CLIENT_EMAIL=$(grep -o '"client_email"\s*:\s*"[^"]*"' "$SERVICE_ACCOUNT_FILE" | sed 's/.*: *"\(.*\)"/\1/')

echo "📧 Using service account: $CLIENT_EMAIL"

# Check if rclone is installed
if ! command -v rclone &> /dev/null; then
    echo "📦 Installing rclone..."
    curl -O https://downloads.rclone.org/rclone-current-linux-amd64.zip
    unzip -q rclone-current-linux-amd64.zip
    cd rclone-*-linux-amd64
    sudo cp rclone /usr/bin/
    sudo chmod 755 /usr/bin/rclone
    cd ..
    rm -rf rclone-*
    echo "✅ rclone installed"
fi

# Create rclone config directory
mkdir -p ~/.config/rclone

# Copy service account file securely
cp "$SERVICE_ACCOUNT_FILE" ~/.config/rclone/service_account.json
chmod 600 ~/.config/rclone/service_account.json

# Create rclone config
cat > ~/.config/rclone/rclone.conf << EOF
[gdrive]
type = drive
scope = drive
service_account_file = $HOME/.config/rclone/service_account.json
team_drive = 

EOF

echo "✅ Service account configured"

# Test the connection
echo "🔍 Testing Google Drive connection..."
if rclone lsd gdrive: 2>/dev/null; then
    echo "✅ Successfully connected to Google Drive!"
else
    echo "⚠️  Connection test failed. Please ensure you've shared the ComfyUI-Output folder with:"
    echo "    $CLIENT_EMAIL"
    exit 1
fi

# Create folder structure
echo "📁 Creating folder structure on Google Drive..."
rclone mkdir gdrive:ComfyUI-Output/outputs
rclone mkdir gdrive:ComfyUI-Output/models
rclone mkdir gdrive:ComfyUI-Output/workflows

# Create user folders
for user in serhii marcin vlad ksenija max ivan; do
    echo "  Creating folder for $user..."
    rclone mkdir gdrive:ComfyUI-Output/outputs/$user
done

echo ""
echo "✅ Google Drive setup complete!"
echo ""
echo "📊 Structure created:"
echo "   ComfyUI-Output/"
echo "   ├── outputs/"
echo "   │   ├── serhii/"
echo "   │   ├── marcin/"
echo "   │   ├── vlad/"
echo "   │   ├── ksenija/"
echo "   │   ├── max/"
echo "   │   └── ivan/"
echo "   ├── models/"
echo "   └── workflows/"
echo ""
echo "🔄 Auto-sync will start when ComfyUI launches"
echo ""
echo "⚠️  IMPORTANT: Make sure you've shared the ComfyUI-Output folder with:"
echo "    $CLIENT_EMAIL"