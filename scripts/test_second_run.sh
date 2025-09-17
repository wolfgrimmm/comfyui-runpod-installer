#!/bin/bash

# Test script to verify Google Drive sync works on second pod run
# Run this on your existing volume to test the fix

echo "==========================================="
echo "TESTING GOOGLE DRIVE SYNC ON SECOND RUN"
echo "==========================================="
echo

# 1. Check environment
echo "1. Environment Check:"
echo "---------------------"
if [ -n "$GOOGLE_SERVICE_ACCOUNT" ]; then
    echo "✅ GOOGLE_SERVICE_ACCOUNT found (${#GOOGLE_SERVICE_ACCOUNT} chars)"
elif [ -n "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" ]; then
    echo "✅ RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT found"
else
    echo "❌ No Google service account in environment"
fi
echo

# 2. Check for saved credentials
echo "2. Saved Credentials Check:"
echo "---------------------------"
if [ -f /workspace/.permanent_sync/service_account.json ]; then
    echo "✅ Permanent backup: service_account.json exists"
elif [ -f /workspace/.permanent_sync/runpod_secret.json ]; then
    echo "✅ Permanent backup: runpod_secret.json exists"
else
    echo "❌ No permanent backup found"
fi

if [ -f /workspace/.config/rclone/service_account.json ]; then
    echo "✅ Workspace config: service_account.json exists"
else
    echo "⚠️ No workspace config backup"
fi
echo

# 3. Test current rclone
echo "3. Current Rclone Status:"
echo "-------------------------"
if rclone lsd gdrive: >/dev/null 2>&1; then
    echo "✅ Rclone is currently working!"
else
    echo "❌ Rclone not working"
fi
echo

# 4. Run the permanent fix
echo "4. Running Permanent Sync Fix:"
echo "-------------------------------"
if [ -f /app/scripts/permanent_sync_fix.sh ]; then
    /app/scripts/permanent_sync_fix.sh
elif [ -f ./permanent_sync_fix.sh ]; then
    ./permanent_sync_fix.sh
else
    echo "⚠️ permanent_sync_fix.sh not found, trying init_sync.sh..."

    if [ -f /app/scripts/init_sync.sh ]; then
        /app/scripts/init_sync.sh
    elif [ -f ./init_sync.sh ]; then
        ./init_sync.sh
    else
        echo "❌ No fix scripts found"
    fi
fi
echo

# 5. Verify sync is running
echo "5. Sync Process Check:"
echo "----------------------"
sleep 3
if pgrep -f "sync_loop\|permanent_sync" >/dev/null; then
    echo "✅ Sync process is running!"
    ps aux | grep -E "sync_loop|permanent_sync" | grep -v grep
else
    echo "❌ No sync process found"
fi
echo

# 6. Test sync functionality
echo "6. Testing Sync Functionality:"
echo "-------------------------------"
if [ -d /workspace/output ]; then
    # Create a test file
    TEST_FILE="/workspace/output/sync_test_$(date +%s).txt"
    echo "Test sync at $(date)" > "$TEST_FILE"
    echo "Created test file: $TEST_FILE"

    # Try to sync it
    echo "Attempting to sync test file..."
    if rclone copy "$TEST_FILE" "gdrive:ComfyUI-Output/output" --min-age 1s 2>/dev/null; then
        echo "✅ Test file synced successfully!"

        # Check if it exists on Drive
        if rclone ls "gdrive:ComfyUI-Output/output/$(basename $TEST_FILE)" 2>/dev/null; then
            echo "✅ Verified: File exists on Google Drive"
        fi
    else
        echo "❌ Failed to sync test file"
    fi

    # Clean up
    rm -f "$TEST_FILE" 2>/dev/null
fi
echo

echo "==========================================="
echo "TEST COMPLETE"
echo "==========================================="
echo
echo "Summary:"
if pgrep -f "sync_loop\|permanent_sync" >/dev/null && rclone lsd gdrive: >/dev/null 2>&1; then
    echo "✅ SYNC IS WORKING! Second run should work now."
    echo
    echo "Next steps:"
    echo "1. Stop this pod"
    echo "2. Start a new pod with the same network volume"
    echo "3. Check if sync still works"
else
    echo "❌ SYNC NOT FULLY WORKING"
    echo
    echo "Troubleshooting:"
    echo "1. Check if GOOGLE_SERVICE_ACCOUNT is in your RunPod secrets"
    echo "2. Try running: /app/scripts/init_sync.sh"
    echo "3. Check logs: tail -f /tmp/rclone_sync.log"
fi