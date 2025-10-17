#!/bin/bash

# S3 Storage Setup Script for RunPod
# This script helps configure S3 credentials for direct output folder linking

echo "🗄️ S3 Storage Setup for RunPod"
echo "================================"
echo ""

# Check if we're on RunPod
if [ -z "$RUNPOD_POD_ID" ]; then
    echo "⚠️ This script is designed for RunPod pods"
    echo "   You can still use it to test S3 configuration locally"
    echo ""
fi

# Display current S3 configuration
echo "📋 Current S3 Configuration:"
echo "   RUNPOD_S3_ENDPOINT: ${RUNPOD_S3_ENDPOINT:-'Not set'}"
echo "   RUNPOD_S3_ACCESS_KEY: ${RUNPOD_S3_ACCESS_KEY:+'***SET***'}"
echo "   RUNPOD_S3_SECRET_KEY: ${RUNPOD_S3_SECRET_KEY:+'***SET***'}"
echo "   RUNPOD_S3_BUCKET: ${RUNPOD_S3_BUCKET:-'Not set'}"
echo "   RUNPOD_S3_REGION: ${RUNPOD_S3_REGION:-'Not set'}"
echo ""

# Check if S3FS is installed
if command -v s3fs >/dev/null 2>&1; then
    echo "✅ S3FS is installed"
else
    echo "❌ S3FS is not installed"
    echo "   Installing S3FS..."
    apt-get update && apt-get install -y s3fs
    if command -v s3fs >/dev/null 2>&1; then
        echo "✅ S3FS installed successfully"
    else
        echo "❌ Failed to install S3FS"
        exit 1
    fi
fi

# Check if rclone is installed
if command -v rclone >/dev/null 2>&1; then
    echo "✅ rclone is installed"
else
    echo "❌ rclone is not installed"
    exit 1
fi

# Test S3 connection if credentials are set
if [ -n "$RUNPOD_S3_ACCESS_KEY" ] && [ -n "$RUNPOD_S3_SECRET_KEY" ]; then
    echo ""
    echo "🔍 Testing S3 connection..."
    
    # Create temporary password file for S3FS
    TEMP_PASSWD="/tmp/s3fs_test_passwd"
    echo "${RUNPOD_S3_ACCESS_KEY}:${RUNPOD_S3_SECRET_KEY}" > "$TEMP_PASSWD"
    chmod 600 "$TEMP_PASSWD"
    
    # Test with S3FS
    TEST_MOUNT="/tmp/s3fs_test_mount"
    mkdir -p "$TEST_MOUNT"
    
    echo "   Testing S3FS mount..."
    s3fs "${RUNPOD_S3_BUCKET:-3nyrlhftk8}" "$TEST_MOUNT" \
        -o "passwd_file=$TEMP_PASSWD" \
        -o "url=${RUNPOD_S3_ENDPOINT:-https://s3api-eu-ro-1.runpod.io}" \
        -o "use_path_request_style" \
        -o "retries=1" \
        -o "connect_timeout=10" \
        -o "readwrite_timeout=10" >/dev/null 2>&1 &
    
    S3FS_PID=$!
    sleep 3
    
    if kill -0 $S3FS_PID 2>/dev/null; then
        echo "✅ S3FS connection successful"
        kill $S3FS_PID 2>/dev/null
        fusermount -u "$TEST_MOUNT" 2>/dev/null || umount "$TEST_MOUNT" 2>/dev/null
    else
        echo "❌ S3FS connection failed"
    fi
    
    # Test with rclone
    echo "   Testing rclone connection..."
    RCLONE_CONFIG="/tmp/rclone_test.conf"
    cat > "$RCLONE_CONFIG" << EOF
[s3]
type = s3
provider = Other
access_key_id = $RUNPOD_S3_ACCESS_KEY
secret_access_key = $RUNPOD_S3_SECRET_KEY
endpoint = ${RUNPOD_S3_ENDPOINT:-https://s3api-eu-ro-1.runpod.io}
region = ${RUNPOD_S3_REGION:-eu-ro-1}
EOF
    
    if rclone --config "$RCLONE_CONFIG" lsd "s3:${RUNPOD_S3_BUCKET:-3nyrlhftk8}" >/dev/null 2>&1; then
        echo "✅ rclone connection successful"
    else
        echo "❌ rclone connection failed"
    fi
    
    # Cleanup
    rm -f "$TEMP_PASSWD" "$RCLONE_CONFIG"
    rmdir "$TEST_MOUNT" 2>/dev/null || true
    
else
    echo ""
    echo "⚠️ S3 credentials not configured"
    echo ""
    echo "To configure S3 storage:"
    echo "1. Go to RunPod Console → Storage → Your Network Volume"
    echo "2. Generate S3 API access keys"
    echo "3. Set these environment variables in your pod template:"
    echo ""
    echo "   RUNPOD_S3_ENDPOINT=https://s3api-eu-ro-1.runpod.io"
    echo "   RUNPOD_S3_ACCESS_KEY=your_access_key_here"
    echo "   RUNPOD_S3_SECRET_KEY=your_secret_key_here"
    echo "   RUNPOD_S3_BUCKET=3nyrlhftk8"
    echo "   RUNPOD_S3_REGION=eu-ro-1"
    echo ""
fi

echo ""
echo "🎯 Next Steps:"
echo "1. Start ComfyUI from the control panel"
echo "2. Go to the S3 Storage panel"
echo "3. Click 'Test S3 Connection' to verify"
echo "4. Click 'Link to S3 (S3FS)' to create direct symlink"
echo "5. Your output files will now appear directly in S3!"
echo ""
echo "📚 Benefits of S3 linking:"
echo "   • Real-time file access (no sync delays)"
echo "   • Direct integration with ComfyUI"
echo "   • High performance and reliability"
echo "   • Automatic backup to S3 storage"
echo ""
