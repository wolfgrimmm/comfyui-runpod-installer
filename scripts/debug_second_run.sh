#!/bin/bash

echo "===================================="
echo "Second Run Failure Deep Debug"
echo "===================================="
echo "Comparing first run vs second run states"
echo
date
echo

# Function to save state
save_state() {
    local state_file="$1"
    echo "Saving current state to $state_file..."

    {
        echo "=== TIMESTAMP ==="
        date

        echo -e "\n=== ENVIRONMENT VARIABLES ==="
        env | grep -E "RUNPOD|GOOGLE|RCLONE" | sort

        echo -e "\n=== RCLONE CONFIG FILES ==="
        echo "Root config:"
        ls -la /root/.config/rclone/ 2>/dev/null || echo "Directory doesn't exist"
        if [ -f /root/.config/rclone/rclone.conf ]; then
            echo "Content (sanitized):"
            cat /root/.config/rclone/rclone.conf | sed 's/token =.*/token = [HIDDEN]/'
            echo "MD5: $(md5sum /root/.config/rclone/rclone.conf)"
        fi

        echo -e "\nWorkspace config:"
        ls -la /workspace/.config/rclone/ 2>/dev/null || echo "Directory doesn't exist"
        if [ -f /workspace/.config/rclone/rclone.conf ]; then
            echo "MD5: $(md5sum /workspace/.config/rclone/rclone.conf)"
        fi

        echo -e "\n=== PROCESSES ==="
        ps aux | grep -E "rclone|sync" | grep -v grep

        echo -e "\n=== SYNC SCRIPTS ==="
        echo "/tmp/rclone_sync_loop.sh:"
        ls -la /tmp/rclone_sync_loop.sh 2>/dev/null || echo "Not found"

        echo "/workspace/.sync/rclone_sync_loop.sh:"
        ls -la /workspace/.sync/rclone_sync_loop.sh 2>/dev/null || echo "Not found"

        echo -e "\n=== STATUS FILES ==="
        echo ".gdrive_configured: $(ls -la /workspace/.gdrive_configured 2>/dev/null || echo 'Not found')"
        echo ".gdrive_status: $(cat /workspace/.gdrive_status 2>/dev/null || echo 'Not found')"

        echo -e "\n=== RCLONE TEST ==="
        echo "Testing rclone connection:"
        if timeout 10 rclone lsd gdrive: 2>&1; then
            echo "SUCCESS: Can list Google Drive"
        else
            echo "FAILED: Cannot connect to Google Drive"
            echo "Error output:"
            timeout 10 rclone lsd gdrive: 2>&1
        fi

        echo -e "\n=== DIRECTORY STRUCTURE ==="
        echo "ComfyUI/output:"
        ls -la /workspace/ComfyUI/output 2>/dev/null || echo "Not found"

        echo "workspace/output:"
        ls -la /workspace/output/ 2>/dev/null | head -5

        echo -e "\n=== INIT SCRIPT CHECK ==="
        echo "Checking if init.sh modifies config..."
        grep -n "rclone\|gdrive\|GOOGLE\|RUNPOD_SECRET" /app/init.sh 2>/dev/null | head -20

    } > "$state_file" 2>&1

    echo "State saved to $state_file"
}

# Save current state
STATE_FILE="/workspace/debug_state_$(date +%Y%m%d_%H%M%S).txt"
save_state "$STATE_FILE"

echo
echo "===================================="
echo "Checking Previous States"
echo "===================================="

# List all previous state files
echo "Previous debug states:"
ls -la /workspace/debug_state_*.txt 2>/dev/null || echo "No previous states found"

# If this is second run, compare with first
FIRST_STATE=$(ls /workspace/debug_state_*.txt 2>/dev/null | head -1)
LATEST_STATE=$(ls /workspace/debug_state_*.txt 2>/dev/null | tail -1)

if [ "$FIRST_STATE" != "$LATEST_STATE" ] && [ -n "$FIRST_STATE" ]; then
    echo
    echo "===================================="
    echo "Comparing First vs Latest State"
    echo "===================================="

    echo "First run state: $FIRST_STATE"
    echo "Latest state: $LATEST_STATE"
    echo

    # Compare key differences
    echo "Key differences:"

    # Check if rclone config changed
    if [ -f "$FIRST_STATE" ] && [ -f "$LATEST_STATE" ]; then
        FIRST_MD5=$(grep "MD5:.*rclone.conf" "$FIRST_STATE" | head -1)
        LATEST_MD5=$(grep "MD5:.*rclone.conf" "$LATEST_STATE" | head -1)
        if [ "$FIRST_MD5" != "$LATEST_MD5" ]; then
            echo "❌ RCLONE CONFIG CHANGED!"
            echo "   First:  $FIRST_MD5"
            echo "   Latest: $LATEST_MD5"
        else
            echo "✅ Rclone config unchanged"
        fi

        # Check processes
        FIRST_SYNC=$(grep "rclone_sync_loop" "$FIRST_STATE" | wc -l)
        LATEST_SYNC=$(grep "rclone_sync_loop" "$LATEST_STATE" | wc -l)
        echo "Sync processes - First run: $FIRST_SYNC, Latest: $LATEST_SYNC"
    fi
fi

echo
echo "===================================="
echo "Testing Theories"
echo "===================================="

# Theory 1: Environment variables lost
echo "1. Checking if secrets are available..."
if [ -n "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" ]; then
    echo "   ✅ RunPod secret present"
else
    echo "   ❌ RunPod secret MISSING!"
    echo "   All RUNPOD vars:"
    env | grep RUNPOD | head -10
fi

# Theory 2: Init script overwrites config
echo
echo "2. Testing if init.sh breaks config..."
if [ -f /root/.config/rclone/rclone.conf ]; then
    cp /root/.config/rclone/rclone.conf /tmp/rclone_backup.conf
    echo "   Backed up current config"

    # Check what init.sh does
    if grep -q "sed -i.*service_account" /app/init.sh; then
        echo "   ⚠️ WARNING: init.sh modifies rclone config with sed!"
        grep "sed.*rclone" /app/init.sh
    fi
fi

# Theory 3: Sync script not starting
echo
echo "3. Checking sync script startup..."
if [ -f /workspace/.sync/rclone_sync_loop.sh ]; then
    echo "   ✅ Persistent sync script exists"
    echo "   Attempting to start it..."

    # Kill any existing
    pkill -f rclone_sync_loop 2>/dev/null || true
    sleep 1

    # Start it
    /workspace/.sync/rclone_sync_loop.sh &
    NEW_PID=$!
    sleep 2

    if kill -0 $NEW_PID 2>/dev/null; then
        echo "   ✅ Sync started successfully (PID: $NEW_PID)"
    else
        echo "   ❌ Sync failed to start"
        echo "   Trying with bash explicitly:"
        bash /workspace/.sync/rclone_sync_loop.sh &
    fi
else
    echo "   ❌ No persistent sync script found!"
fi

# Theory 4: Service account issues
echo
echo "4. Checking service account setup..."
if [ -f /root/.config/rclone/service_account.json ]; then
    echo "   Service account file exists"
    SA_EMAIL=$(grep -o '"client_email"[[:space:]]*:[[:space:]]*"[^"]*"' /root/.config/rclone/service_account.json | cut -d'"' -f4)
    echo "   Email: $SA_EMAIL"
else
    echo "   No service account file"
fi

# Theory 5: Wrong config is being used
echo
echo "5. Testing different rclone configs..."
echo "   Available configs:"
find / -name "rclone.conf" 2>/dev/null | head -10

# Try to force correct config
export RCLONE_CONFIG=/workspace/.config/rclone/rclone.conf
echo "   Testing with workspace config:"
rclone lsd gdrive: --config /workspace/.config/rclone/rclone.conf 2>&1 | head -5

export RCLONE_CONFIG=/root/.config/rclone/rclone.conf
echo "   Testing with root config:"
rclone lsd gdrive: --config /root/.config/rclone/rclone.conf 2>&1 | head -5

echo
echo "===================================="
echo "Attempted Fixes"
echo "===================================="

# Fix 1: Restore config from workspace
if [ ! -f /root/.config/rclone/rclone.conf ] && [ -f /workspace/.config/rclone/rclone.conf ]; then
    echo "Restoring config from workspace..."
    mkdir -p /root/.config/rclone
    cp /workspace/.config/rclone/rclone.conf /root/.config/rclone/
    [ -f /workspace/.config/rclone/service_account.json ] && \
        cp /workspace/.config/rclone/service_account.json /root/.config/rclone/
    echo "✅ Config restored"
fi

# Fix 2: Recreate from secret if available
if [ -n "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" ] && ! rclone lsd gdrive: >/dev/null 2>&1; then
    echo "Recreating config from RunPod secret..."

    mkdir -p /root/.config/rclone /workspace/.config/rclone
    echo "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" > /root/.config/rclone/service_account.json
    echo "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" > /workspace/.config/rclone/service_account.json

    cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive =

EOF

    cp /root/.config/rclone/rclone.conf /workspace/.config/rclone/
    echo "✅ Config recreated from secret"
fi

echo
echo "===================================="
echo "FINAL DIAGNOSIS"
echo "===================================="

if rclone lsd gdrive: >/dev/null 2>&1; then
    echo "✅ Rclone is now working"

    if pgrep -f rclone_sync_loop >/dev/null; then
        echo "✅ Sync is running"
        echo
        echo "PROBLEM SOLVED!"
    else
        echo "❌ Sync not running"
        echo
        echo "Run: /workspace/.sync/rclone_sync_loop.sh &"
    fi
else
    echo "❌ Rclone still not working"
    echo
    echo "Check the state file for details: $STATE_FILE"
    echo
    echo "Possible causes:"
    echo "1. RunPod secret not available on second run"
    echo "2. Init script breaking the config"
    echo "3. Wrong rclone config path being used"
    echo "4. Service account permissions changed"
fi