#!/bin/bash

# Setup S3 (RunPod Network Volume) to Google Drive sync
echo "=========================================="
echo "🔧 Setting up S3 Network Volume Sync"
echo "=========================================="

# Check if rclone is installed
if ! command -v rclone &> /dev/null; then
    echo "Installing rclone..."
    curl https://rclone.org/install.sh | bash
fi

# Get S3 credentials from environment or prompt
S3_ENDPOINT="${RUNPOD_NETWORK_VOLUME_ENDPOINT:-}"
S3_ACCESS_KEY="${RUNPOD_NETWORK_VOLUME_ACCESS_KEY:-}"
S3_SECRET_KEY="${RUNPOD_NETWORK_VOLUME_SECRET_KEY:-}"
S3_BUCKET="${RUNPOD_NETWORK_VOLUME_BUCKET:-}"

if [ -z "$S3_ENDPOINT" ]; then
    echo "Enter your Network Volume S3 details:"
    read -p "Endpoint URL: " S3_ENDPOINT
    read -p "Access Key: " S3_ACCESS_KEY
    read -sp "Secret Key: " S3_SECRET_KEY
    echo
    read -p "Bucket Name: " S3_BUCKET
fi

# Create rclone config for S3
echo "📝 Configuring S3 remote..."
cat >> ~/.config/rclone/rclone.conf << EOF

[runpod-s3]
type = s3
provider = Other
access_key_id = $S3_ACCESS_KEY
secret_access_key = $S3_SECRET_KEY
endpoint = $S3_ENDPOINT
acl = private

EOF

echo "✅ S3 remote configured"

# Test S3 connection
echo "🔍 Testing S3 connection..."
if rclone lsd runpod-s3:$S3_BUCKET; then
    echo "✅ S3 connection successful"
else
    echo "❌ Failed to connect to S3"
    exit 1
fi

# Create sync script
cat > /workspace/sync_s3_to_gdrive.sh << 'SYNC_EOF'
#!/bin/bash
# Sync RunPod Network Volume (S3) to Google Drive

BUCKET="$1"
if [ -z "$BUCKET" ]; then
    echo "Usage: $0 <bucket-name>"
    exit 1
fi

echo "📤 Syncing S3 Network Volume to Google Drive..."

# Sync output folders
for user_dir in $(rclone lsd runpod-s3:$BUCKET/output/ 2>/dev/null | awk '{print $NF}'); do
    echo "  📁 Syncing $user_dir outputs..."
    rclone sync runpod-s3:$BUCKET/output/$user_dir gdrive:ComfyUI/outputs/$user_dir \
        --transfers 4 --checkers 4 --progress
done

# Sync input folders
for user_dir in $(rclone lsd runpod-s3:$BUCKET/input/ 2>/dev/null | awk '{print $NF}'); do
    echo "  📁 Syncing $user_dir inputs..."
    rclone sync runpod-s3:$BUCKET/input/$user_dir gdrive:ComfyUI/inputs/$user_dir \
        --transfers 4 --checkers 4 --progress
done

echo "✅ Sync complete!"
SYNC_EOF

chmod +x /workspace/sync_s3_to_gdrive.sh

echo ""
echo "✅ Setup complete! To sync your network volume to Google Drive:"
echo "   /workspace/sync_s3_to_gdrive.sh $S3_BUCKET"
echo ""
echo "To setup automatic sync every 5 minutes:"
echo "   (crontab -l 2>/dev/null; echo '*/5 * * * * /workspace/sync_s3_to_gdrive.sh $S3_BUCKET') | crontab -"