#!/bin/bash

# Trace exactly what happens between first and second run

echo "=========================================="
echo "SYNC FAILURE ROOT CAUSE ANALYSIS"
echo "=========================================="
echo "Tracing why sync fails on second pod run"
echo
date
echo

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. CHECK RUNPOD SECRETS
echo -e "${YELLOW}1. RUNPOD SECRETS CHECK${NC}"
echo "----------------------------------------"
echo "Checking if RunPod secrets are available..."

# Check all possible secret variations
FOUND_SECRET=0
if [ -n "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" ]; then
    echo -e "${GREEN}✓ RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT exists (${#RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT} chars)${NC}"
    FOUND_SECRET=1
else
    echo -e "${RED}✗ RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT not found${NC}"
fi

if [ -n "$GOOGLE_SERVICE_ACCOUNT" ]; then
    echo -e "${GREEN}✓ GOOGLE_SERVICE_ACCOUNT exists (${#GOOGLE_SERVICE_ACCOUNT} chars)${NC}"
    FOUND_SECRET=1
else
    echo -e "${RED}✗ GOOGLE_SERVICE_ACCOUNT not found${NC}"
fi

echo
echo "All environment variables with RUNPOD:"
env | grep RUNPOD | grep -v SECRET | head -5
echo

# 2. CHECK WHAT'S IN WORKSPACE
echo -e "${YELLOW}2. WORKSPACE PERSISTENCE CHECK${NC}"
echo "----------------------------------------"

# Check workspace files that should persist
echo "Files that should persist between runs:"
echo

echo "/workspace/.gdrive_configured:"
if [ -f /workspace/.gdrive_configured ]; then
    echo -e "${GREEN}✓ Exists (created: $(stat -c %y /workspace/.gdrive_configured))${NC}"
else
    echo -e "${RED}✗ Missing${NC}"
fi

echo "/workspace/.gdrive_status:"
if [ -f /workspace/.gdrive_status ]; then
    STATUS=$(cat /workspace/.gdrive_status)
    echo -e "${GREEN}✓ Exists: $STATUS${NC}"
else
    echo -e "${RED}✗ Missing${NC}"
fi

echo "/workspace/.config/rclone/rclone.conf:"
if [ -f /workspace/.config/rclone/rclone.conf ]; then
    SIZE=$(stat -c%s /workspace/.config/rclone/rclone.conf)
    echo -e "${GREEN}✓ Exists ($SIZE bytes)${NC}"
else
    echo -e "${RED}✗ Missing${NC}"
fi

echo "/workspace/.sync/:"
if [ -d /workspace/.sync ]; then
    echo -e "${GREEN}✓ Directory exists${NC}"
    ls -la /workspace/.sync/ 2>/dev/null | head -5
else
    echo -e "${RED}✗ Directory missing${NC}"
fi
echo

# 3. TRACE INIT SCRIPT EXECUTION
echo -e "${YELLOW}3. INIT SCRIPT EXECUTION TRACE${NC}"
echo "----------------------------------------"

# Check what init.sh does
if [ -f /app/init.sh ]; then
    echo "Init script exists. Checking critical sections..."
    echo

    echo "Lines that restore config:"
    grep -n "Restoring rclone config" /app/init.sh
    echo

    echo "Lines that might break config:"
    grep -n "sed.*rclone\|rm.*rclone" /app/init.sh
    echo

    # Test what happens when we run the config restoration part
    echo "Testing config restoration logic..."

    # Simulate the restoration
    if [ -f "/workspace/.config/rclone/rclone.conf" ] && [ ! -f "/root/.config/rclone/rclone.conf" ]; then
        echo -e "${YELLOW}Would restore config from workspace${NC}"
    else
        echo -e "${GREEN}Config already in /root or not in workspace${NC}"
    fi
fi
echo

# 4. CHECK SYNC PROCESS
echo -e "${YELLOW}4. SYNC PROCESS STATUS${NC}"
echo "----------------------------------------"

SYNC_RUNNING=0
if pgrep -f "rclone_sync_loop" > /dev/null; then
    echo -e "${GREEN}✓ Sync process is running${NC}"
    ps aux | grep rclone_sync_loop | grep -v grep
    SYNC_RUNNING=1
else
    echo -e "${RED}✗ No sync process running${NC}"
fi

echo
echo "Checking for sync scripts:"
for script in /tmp/rclone_sync_loop.sh /workspace/.sync/rclone_sync_loop.sh /workspace/.sync/bulletproof_sync.sh; do
    if [ -f "$script" ]; then
        echo -e "${GREEN}✓ $script exists${NC}"
    else
        echo -e "${RED}✗ $script missing${NC}"
    fi
done
echo

# 5. TEST RCLONE CONNECTION
echo -e "${YELLOW}5. RCLONE CONNECTION TEST${NC}"
echo "----------------------------------------"

echo "Testing with default config:"
if timeout 5 rclone lsd gdrive: 2>&1 | head -2; then
    echo -e "${GREEN}✓ Rclone works with default config${NC}"
else
    echo -e "${RED}✗ Rclone fails with default config${NC}"

    echo
    echo "Error details:"
    timeout 5 rclone lsd gdrive: 2>&1 | head -10
fi

echo
echo "Testing with explicit workspace config:"
if [ -f /workspace/.config/rclone/rclone.conf ]; then
    if timeout 5 rclone --config /workspace/.config/rclone/rclone.conf lsd gdrive: 2>&1 | head -2; then
        echo -e "${GREEN}✓ Works with workspace config${NC}"
    else
        echo -e "${RED}✗ Fails with workspace config${NC}"
    fi
fi
echo

# 6. ATTEMPT RECOVERY
echo -e "${YELLOW}6. ATTEMPTING RECOVERY${NC}"
echo "----------------------------------------"

if [ $FOUND_SECRET -eq 0 ]; then
    echo -e "${RED}CRITICAL: No RunPod secret found!${NC}"
    echo "This is likely the root cause."
    echo
    echo "Checking if service account is saved in workspace..."

    if [ -f /workspace/.config/rclone/service_account.json ]; then
        echo "Found saved service account, restoring..."
        mkdir -p /root/.config/rclone
        cp /workspace/.config/rclone/service_account.json /root/.config/rclone/
        cp /workspace/.config/rclone/rclone.conf /root/.config/rclone/

        if rclone lsd gdrive: >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Restored from workspace backup!${NC}"
        else
            echo -e "${RED}✗ Restoration failed${NC}"
        fi
    else
        echo -e "${RED}No service account backup found${NC}"
    fi
elif [ $SYNC_RUNNING -eq 0 ]; then
    echo "Secret exists but sync not running. Starting it..."

    # Create minimal sync script
    cat > /tmp/emergency_sync.sh << 'EOF'
#!/bin/bash
while true; do
    sleep 60
    if [ -d /workspace/output ]; then
        rclone copy /workspace/output gdrive:ComfyUI-Output/output \
            --exclude "*.tmp" --min-age 30s --ignore-existing \
            --transfers 2 >> /tmp/rclone_sync.log 2>&1
    fi
done
EOF
    chmod +x /tmp/emergency_sync.sh
    /tmp/emergency_sync.sh &

    sleep 2
    if pgrep -f emergency_sync > /dev/null; then
        echo -e "${GREEN}✓ Emergency sync started${NC}"
    fi
fi
echo

# 7. ROOT CAUSE ANALYSIS
echo -e "${YELLOW}7. ROOT CAUSE ANALYSIS${NC}"
echo "----------------------------------------"

echo "SUMMARY OF FINDINGS:"
echo

if [ $FOUND_SECRET -eq 0 ]; then
    echo -e "${RED}★ ROOT CAUSE: RunPod secret not available on second run${NC}"
    echo "  The RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT environment variable"
    echo "  is not being passed to the pod on subsequent runs."
    echo
    echo "  SOLUTION:"
    echo "  1. Check RunPod dashboard - is the secret still configured?"
    echo "  2. Try removing and re-adding the secret"
    echo "  3. Make sure secret name is exactly: GOOGLE_SERVICE_ACCOUNT"
    echo "  4. RunPod will prefix it as: RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT"
elif [ ! -f /workspace/.config/rclone/rclone.conf ]; then
    echo -e "${RED}★ ROOT CAUSE: Config not persisting in workspace${NC}"
    echo "  The rclone configuration is not being saved properly."
elif [ $SYNC_RUNNING -eq 0 ]; then
    echo -e "${YELLOW}★ ROOT CAUSE: Sync process not starting${NC}"
    echo "  Config exists but sync isn't running."
else
    echo -e "${GREEN}Everything appears to be working${NC}"
fi

echo
echo "----------------------------------------"
echo "DIAGNOSTIC DATA SAVED TO:"
echo "/workspace/sync_trace_$(date +%Y%m%d_%H%M%S).log"

# Save full diagnostic output
{
    echo "=== FULL DIAGNOSTIC OUTPUT ==="
    echo "Date: $(date)"
    echo
    echo "Environment:"
    env | sort
    echo
    echo "Rclone configs found:"
    find / -name "rclone.conf" 2>/dev/null
    echo
    echo "Process list:"
    ps aux
} > /workspace/sync_trace_$(date +%Y%m%d_%H%M%S).log