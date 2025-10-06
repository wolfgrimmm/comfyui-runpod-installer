#!/bin/bash

echo "🧪 Testing sync monitor functionality..."
echo ""

# Check if sync is currently running
echo "1. Checking current sync status..."
if pgrep -f "sync_loop\|permanent_sync\|rclone_sync" > /dev/null 2>&1; then
    SYNC_PID=$(pgrep -f "sync_loop\|permanent_sync\|rclone_sync" | head -1)
    echo "   ✅ Sync is running (PID: $SYNC_PID)"

    # Kill it to test restart
    echo ""
    echo "2. Killing sync process to test monitor..."
    pkill -f "sync_loop\|permanent_sync\|rclone_sync"
    sleep 2

    if pgrep -f "sync_loop\|permanent_sync\|rclone_sync" > /dev/null 2>&1; then
        echo "   ⚠️ Sync still running after kill attempt"
    else
        echo "   ✅ Sync stopped"
    fi
else
    echo "   ℹ️ Sync not running"
fi

echo ""
echo "3. Starting sync monitor..."
if [ -f "/app/scripts/monitor_sync.sh" ]; then
    /app/scripts/monitor_sync.sh > /tmp/sync_monitor_test.log 2>&1 &
    MONITOR_PID=$!
    echo "   ✅ Monitor started (PID: $MONITOR_PID)"
elif [ -f "./monitor_sync.sh" ]; then
    ./monitor_sync.sh > /tmp/sync_monitor_test.log 2>&1 &
    MONITOR_PID=$!
    echo "   ✅ Monitor started (PID: $MONITOR_PID)"
else
    echo "   ❌ monitor_sync.sh not found"
    exit 1
fi

echo ""
echo "4. Manually triggering ensure_sync..."
if [ -f "/app/scripts/ensure_sync.sh" ]; then
    /app/scripts/ensure_sync.sh
elif [ -f "./ensure_sync.sh" ]; then
    ./ensure_sync.sh
else
    echo "   ❌ ensure_sync.sh not found"
fi

echo ""
echo "5. Checking if sync is now running..."
sleep 5
if pgrep -f "sync_loop\|permanent_sync\|rclone" > /dev/null 2>&1; then
    SYNC_PID=$(pgrep -f "sync_loop" | head -1)
    RCLONE_PID=$(pgrep -f "rclone copy" | head -1)
    echo "   ✅ Sync is running (sync_loop PID: $SYNC_PID)"
    if [ -n "$RCLONE_PID" ]; then
        echo "   ✅ rclone is actively copying files (PID: $RCLONE_PID)"
    fi
else
    echo "   ❌ Sync failed to start"
    echo ""
    echo "Monitor log:"
    cat /tmp/sync_monitor_test.log
    exit 1
fi

echo ""
echo "6. Testing if rclone works..."
if rclone lsd gdrive: >/dev/null 2>&1; then
    echo "   ✅ rclone is working"
else
    echo "   ❌ rclone is not working"
fi

echo ""
echo "🎉 Test complete! Sync monitor is working."
echo ""
echo "To check monitor logs: tail -f /tmp/sync_monitor.log"
echo "To check sync logs: tail -f /tmp/sync.log"
