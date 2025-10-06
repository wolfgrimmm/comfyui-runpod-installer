#!/bin/bash

# Monitor and restart Google Drive sync if it stops
# This runs continuously in the background

echo "[SYNC MONITOR] Starting sync monitor..."

while true; do
    sleep 300  # Check every 5 minutes

    # Check if sync process is running
    if ! pgrep -f "sync_loop\|permanent_sync\|rclone_sync" > /dev/null 2>&1; then
        echo "[SYNC MONITOR] ⚠️ Sync process died, restarting..."

        # Try to restart using ensure_sync script
        if [ -f "/app/scripts/ensure_sync.sh" ]; then
            /app/scripts/ensure_sync.sh >> /tmp/sync_monitor.log 2>&1
        elif [ -f "/workspace/.permanent_sync/sync_loop.sh" ]; then
            /workspace/.permanent_sync/sync_loop.sh > /tmp/sync.log 2>&1 &
        fi

        # Log the restart
        echo "[$(date)] Sync restarted" >> /tmp/sync_monitor.log
    fi
done
