#!/bin/bash

echo "===================================="
echo "Google Drive Sync Failure Diagnosis"
echo "===================================="
echo "Checking why sync stops working after custom nodes installation"
echo
date
echo

# 1. Check rclone config
echo "1. RCLONE CONFIGURATION CHECK"
echo "------------------------------"
if [ -f "/root/.config/rclone/rclone.conf" ]; then
    echo "✅ Root config exists"
    echo "   Size: $(stat -c%s /root/.config/rclone/rclone.conf) bytes"
    echo "   Modified: $(stat -c%y /root/.config/rclone/rclone.conf)"
    echo "   First few lines:"
    head -3 /root/.config/rclone/rclone.conf 2>/dev/null | sed 's/token =.*/token = [HIDDEN]/'
else
    echo "❌ Root config MISSING!"
fi

if [ -f "/workspace/.config/rclone/rclone.conf" ]; then
    echo "✅ Workspace backup exists"
    echo "   Size: $(stat -c%s /workspace/.config/rclone/rclone.conf) bytes"
else
    echo "⚠️ No workspace backup"
fi

echo
echo "Testing rclone connection:"
if rclone lsd gdrive: 2>/tmp/rclone_error.txt; then
    echo "✅ Rclone can connect to Google Drive"
else
    echo "❌ Rclone CANNOT connect!"
    echo "Error:"
    cat /tmp/rclone_error.txt
fi
echo

# 2. Check sync process
echo "2. SYNC PROCESS CHECK"
echo "---------------------"
SYNC_PID=$(pgrep -f "rclone_sync_loop")
if [ -n "$SYNC_PID" ]; then
    echo "✅ Sync process running (PID: $SYNC_PID)"
    echo "   Running for: $(ps -o etime= -p $SYNC_PID | xargs)"
    echo "   Process details:"
    ps aux | grep -E "rclone_sync_loop|rclone sync|rclone copy" | grep -v grep
else
    echo "❌ NO sync process running!"

    # Check if the script exists
    if [ -f "/tmp/rclone_sync_loop.sh" ]; then
        echo "   Script exists at /tmp/rclone_sync_loop.sh"
        echo "   Trying to start it..."
        /tmp/rclone_sync_loop.sh &
        sleep 2
        if pgrep -f "rclone_sync_loop" >/dev/null; then
            echo "   ✅ Successfully restarted sync!"
        else
            echo "   ❌ Failed to restart"
        fi
    else
        echo "   ❌ Sync script not found at /tmp/rclone_sync_loop.sh"
    fi
fi
echo

# 3. Check sync log
echo "3. SYNC LOG ANALYSIS"
echo "--------------------"
if [ -f "/tmp/rclone_sync.log" ]; then
    echo "Log file exists. Last 20 lines:"
    tail -20 /tmp/rclone_sync.log
    echo
    echo "Errors in log:"
    grep -i "error\|fail\|denied\|unauthorized" /tmp/rclone_sync.log | tail -5
else
    echo "❌ No sync log found at /tmp/rclone_sync.log"
fi
echo

# 4. Check file locations
echo "4. FILE LOCATION CHECK"
echo "----------------------"
echo "Output directory structure:"
if [ -L "/workspace/ComfyUI/output" ]; then
    TARGET=$(readlink -f "/workspace/ComfyUI/output")
    echo "✅ /workspace/ComfyUI/output -> $TARGET (symlink)"
elif [ -d "/workspace/ComfyUI/output" ]; then
    echo "❌ /workspace/ComfyUI/output is REAL directory (breaks sync!)"
else
    echo "⚠️ /workspace/ComfyUI/output doesn't exist"
fi

echo
echo "Files in /workspace/output:"
find /workspace/output -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) 2>/dev/null | wc -l

echo "Files in Google Drive:"
rclone ls gdrive:ComfyUI-Output/output 2>/dev/null | wc -l
echo

# 5. Check environment variables
echo "5. ENVIRONMENT VARIABLES"
echo "------------------------"
if [ -n "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" ]; then
    echo "✅ RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT is set (${#RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT} chars)"
else
    echo "❌ RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT not set"
fi

if [ -n "$GOOGLE_SERVICE_ACCOUNT" ]; then
    echo "✅ GOOGLE_SERVICE_ACCOUNT is set (${#GOOGLE_SERVICE_ACCOUNT} chars)"
else
    echo "⚠️ GOOGLE_SERVICE_ACCOUNT not set"
fi
echo

# 6. Check init.sh behavior
echo "6. INIT SCRIPT BEHAVIOR"
echo "-----------------------"
echo "Checking if init.sh overwrites config..."

# Save current config
if [ -f "/root/.config/rclone/rclone.conf" ]; then
    cp /root/.config/rclone/rclone.conf /tmp/rclone_backup.conf
    echo "Current config saved to /tmp/rclone_backup.conf"
fi

# Check what init.sh would do
if [ -f "/app/init.sh" ]; then
    echo "Init script exists. Checking for config overwrites..."
    grep -n "rclone.conf" /app/init.sh | head -10
else
    echo "⚠️ No init script at /app/init.sh"
fi
echo

# 7. Try to fix common issues
echo "7. ATTEMPTING AUTOMATIC FIXES"
echo "------------------------------"

# Fix 1: Restore rclone config if missing
if [ ! -f "/root/.config/rclone/rclone.conf" ] && [ -f "/workspace/.config/rclone/rclone.conf" ]; then
    echo "Restoring rclone config from backup..."
    mkdir -p /root/.config/rclone
    cp /workspace/.config/rclone/rclone.conf /root/.config/rclone/
    if [ -f "/workspace/.config/rclone/service_account.json" ]; then
        cp /workspace/.config/rclone/service_account.json /root/.config/rclone/
    fi
    echo "✅ Config restored"
fi

# Fix 2: Restart sync if not running
if ! pgrep -f "rclone_sync_loop" >/dev/null; then
    echo "Restarting sync process..."

    # Create a minimal sync script if it doesn't exist
    if [ ! -f "/tmp/rclone_sync_loop.sh" ]; then
        cat > /tmp/rclone_sync_loop.sh << 'EOF'
#!/bin/bash
while true; do
    sleep 60
    if [ -d "/workspace/output" ]; then
        rclone copy /workspace/output gdrive:ComfyUI-Output/output \
            --exclude "*.tmp" --exclude "*.partial" \
            --min-age 30s --ignore-existing \
            --transfers 2 --checkers 2 >> /tmp/rclone_sync.log 2>&1
    fi
done
EOF
        chmod +x /tmp/rclone_sync_loop.sh
    fi

    /tmp/rclone_sync_loop.sh &
    echo "✅ Sync restarted"
fi

# Fix 3: Fix broken symlinks
if [ -d "/workspace/ComfyUI/output" ] && [ ! -L "/workspace/ComfyUI/output" ]; then
    echo "Fixing output directory (converting to symlink)..."
    if [ -f "/workspace/user_data/.current_user" ]; then
        CURRENT_USER=$(cat /workspace/user_data/.current_user)
    else
        CURRENT_USER="serhii"
    fi

    # Move files if any
    if [ "$(ls -A /workspace/ComfyUI/output 2>/dev/null)" ]; then
        mkdir -p "/workspace/output/$CURRENT_USER"
        mv /workspace/ComfyUI/output/* "/workspace/output/$CURRENT_USER/" 2>/dev/null || true
    fi

    rm -rf /workspace/ComfyUI/output
    ln -sf "/workspace/output/$CURRENT_USER" /workspace/ComfyUI/output
    echo "✅ Fixed symlink"
fi

echo
echo "===================================="
echo "DIAGNOSIS COMPLETE"
echo "===================================="

# Summary
echo
echo "SUMMARY:"
echo "--------"

ISSUES=0

if [ ! -f "/root/.config/rclone/rclone.conf" ]; then
    echo "❌ CRITICAL: Rclone config missing"
    ((ISSUES++))
fi

if ! pgrep -f "rclone_sync_loop" >/dev/null; then
    echo "❌ CRITICAL: Sync process not running"
    ((ISSUES++))
fi

if [ -d "/workspace/ComfyUI/output" ] && [ ! -L "/workspace/ComfyUI/output" ]; then
    echo "❌ CRITICAL: Output is real directory, not symlink"
    ((ISSUES++))
fi

if ! rclone lsd gdrive: >/dev/null 2>&1; then
    echo "❌ CRITICAL: Cannot connect to Google Drive"
    ((ISSUES++))
fi

if [ $ISSUES -eq 0 ]; then
    echo "✅ No critical issues found. Sync should be working."
    echo
    echo "Check if files are being created:"
    echo "  ls -la /workspace/output/"
    echo
    echo "Monitor sync log:"
    echo "  tail -f /tmp/rclone_sync.log"
else
    echo
    echo "Found $ISSUES critical issues. Fixes were attempted above."
    echo
    echo "To manually fix, run:"
    echo "  /app/scripts/fix_gdrive_sync.sh"
fi