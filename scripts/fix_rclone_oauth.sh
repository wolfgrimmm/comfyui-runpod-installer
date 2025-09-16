#!/bin/bash

# Fix rclone config to use OAuth instead of broken service account
echo "=========================================="
echo "🔧 Fixing Rclone OAuth Configuration"
echo "=========================================="

# Check if workspace config exists
if [ -f "/workspace/.config/rclone/rclone.conf" ]; then
    echo "📋 Found workspace config, fixing it..."

    # Remove service_account_file line if no service account exists
    if grep -q "service_account_file" /workspace/.config/rclone/rclone.conf && [ ! -f "/root/.config/rclone/service_account.json" ]; then
        echo "🔧 Removing broken service account reference..."
        sed -i '/service_account_file/d' /workspace/.config/rclone/rclone.conf
    fi

    # Copy fixed config to root
    mkdir -p /root/.config/rclone
    cp /workspace/.config/rclone/rclone.conf /root/.config/rclone/
    echo "✅ Config fixed and copied to /root/.config/rclone/"
else
    echo "❌ No config found at /workspace/.config/rclone/rclone.conf"
    echo "   You need to run: rclone config"
    exit 1
fi

# Test the config
echo "🔍 Testing rclone configuration..."
if rclone lsd gdrive: 2>/dev/null; then
    echo "✅ Rclone is working!"

    # Restart auto-sync with fixed config
    echo "🔄 Restarting auto-sync..."
    pkill -f "auto_sync_gdrive.sh" 2>/dev/null || true

    # Start new auto-sync
    if [ -f "/workspace/scripts/auto_sync_gdrive.sh" ]; then
        nohup /workspace/scripts/auto_sync_gdrive.sh >> /workspace/gdrive_sync.log 2>&1 &
        echo "✅ Auto-sync restarted"
    fi

    echo ""
    echo "✅ All fixed! You can now run:"
    echo "   /app/scripts/sync_to_gdrive.sh"
else
    echo "❌ Rclone test failed. Your config may need to be recreated."
    echo "   Run: rclone config"
fi