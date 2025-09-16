#!/bin/bash

echo "===================================="
echo "Google Drive Sync Diagnostic Tool"
echo "===================================="
echo

# Check environment variables
echo "1. Checking RunPod secrets..."
if [ -n "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" ]; then
    echo "✅ RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT is set (${#RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT} chars)"
else
    echo "❌ RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT not found"
fi

if [ -n "$RUNPOD_SECRET_RCLONE_TOKEN" ]; then
    echo "✅ RUNPOD_SECRET_RCLONE_TOKEN is set"
else
    echo "⚠️ RUNPOD_SECRET_RCLONE_TOKEN not found"
fi
echo

# Check rclone configuration
echo "2. Checking rclone configuration..."
if [ -f "/root/.config/rclone/rclone.conf" ]; then
    echo "✅ Root rclone config exists"
    echo "   Config remotes:"
    rclone listremotes 2>/dev/null || echo "   Error listing remotes"
else
    echo "❌ No rclone config at /root/.config/rclone/rclone.conf"
fi

if [ -f "/workspace/.config/rclone/rclone.conf" ]; then
    echo "✅ Workspace rclone config backup exists"
else
    echo "⚠️ No backup config at /workspace/.config/rclone/rclone.conf"
fi
echo

# Check Google Drive status files
echo "3. Checking status files..."
if [ -f "/workspace/.gdrive_configured" ]; then
    echo "✅ .gdrive_configured flag exists"
else
    echo "❌ .gdrive_configured flag missing"
fi

if [ -f "/workspace/.gdrive_status" ]; then
    echo "✅ .gdrive_status: $(cat /workspace/.gdrive_status)"
else
    echo "❌ .gdrive_status file missing"
fi
echo

# Check if sync process is running
echo "4. Checking sync process..."
if pgrep -f "rclone_sync_loop" > /dev/null; then
    echo "✅ Sync process is running (PID: $(pgrep -f rclone_sync_loop))"
    echo "   Recent sync log entries:"
    tail -5 /tmp/rclone_sync.log 2>/dev/null || echo "   No log file found"
else
    echo "❌ Sync process not running"
fi
echo

# Check output directories
echo "5. Checking output directories..."
echo "   /workspace/output:"
if [ -d "/workspace/output" ]; then
    echo "   ✅ Exists ($(ls -la /workspace/output | wc -l) items)"
else
    echo "   ❌ Does not exist"
fi

echo "   /workspace/ComfyUI/output:"
if [ -L "/workspace/ComfyUI/output" ]; then
    TARGET=$(readlink -f "/workspace/ComfyUI/output")
    echo "   ✅ Is symlink → $TARGET"
elif [ -d "/workspace/ComfyUI/output" ]; then
    echo "   ⚠️ Is real directory (not symlink) - $(ls -la /workspace/ComfyUI/output | wc -l) items"
    echo "      This may cause sync issues!"
else
    echo "   ❌ Does not exist"
fi
echo

# Test rclone connection
echo "6. Testing Google Drive connection..."
if rclone lsd gdrive: 2>/tmp/rclone_test_error.txt; then
    echo "✅ Successfully connected to Google Drive"
    echo "   Root folders:"
    rclone lsd gdrive: 2>/dev/null | head -5
else
    echo "❌ Failed to connect to Google Drive"
    echo "   Error:"
    cat /tmp/rclone_test_error.txt | head -5
fi
echo

# Check for ComfyUI-Output folder
echo "7. Checking ComfyUI-Output folder..."
if rclone lsd gdrive:ComfyUI-Output 2>/dev/null; then
    echo "✅ ComfyUI-Output folder exists"
    echo "   Subfolders:"
    rclone lsd gdrive:ComfyUI-Output 2>/dev/null
else
    echo "❌ ComfyUI-Output folder not found or not accessible"
fi
echo

# Suggest fixes
echo "===================================="
echo "Suggested Actions:"
echo "===================================="

ISSUES_FOUND=false

if [ ! -f "/workspace/.gdrive_configured" ] || [ ! -f "/root/.config/rclone/rclone.conf" ]; then
    ISSUES_FOUND=true
    echo "1. Reinitialize Google Drive configuration:"
    echo "   /app/init.sh"
    echo
fi

if ! pgrep -f "rclone_sync_loop" > /dev/null; then
    ISSUES_FOUND=true
    echo "2. Restart sync process:"
    echo "   /tmp/rclone_sync_loop.sh &"
    echo
fi

if [ -d "/workspace/ComfyUI/output" ] && [ ! -L "/workspace/ComfyUI/output" ]; then
    ISSUES_FOUND=true
    echo "3. Fix output directory (it should be a symlink):"
    echo "   rm -rf /workspace/ComfyUI/output"
    echo "   ln -sf /workspace/output /workspace/ComfyUI/output"
    echo
fi

if [ "$ISSUES_FOUND" = false ]; then
    echo "✅ No issues detected. Sync should be working."
    echo "   Check /tmp/rclone_sync.log for sync activity"
fi

echo
echo "For manual sync test, run:"
echo "rclone sync /workspace/output gdrive:ComfyUI-Output/output --dry-run --progress"