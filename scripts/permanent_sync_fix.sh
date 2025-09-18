#!/bin/bash

echo "=========================================="
echo "PERMANENT SYNC FIX"
echo "=========================================="
echo "Creating a sync solution that survives everything"
echo

# Create all necessary directories first
echo "0. Creating required directories..."
mkdir -p /workspace/.permanent_sync
mkdir -p /root/.config/rclone
echo "   ✅ Directories created"
echo

# Step 1: Capture current working state
echo "1. Capturing current working state..."

# First, try to setup rclone from environment if not working
if [ -n "$GOOGLE_SERVICE_ACCOUNT" ] && [ ! -f /root/.config/rclone/service_account.json ]; then
    echo "   Found GOOGLE_SERVICE_ACCOUNT in environment, setting up..."
    echo "$GOOGLE_SERVICE_ACCOUNT" > /root/.config/rclone/service_account.json
    chmod 600 /root/.config/rclone/service_account.json

    # Create rclone config
    cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive =
EOF
    echo "   ✅ Setup from GOOGLE_SERVICE_ACCOUNT environment variable"
elif [ -n "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" ] && [ ! -f /root/.config/rclone/service_account.json ]; then
    echo "   Found RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT, setting up..."
    echo "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" > /root/.config/rclone/service_account.json
    chmod 600 /root/.config/rclone/service_account.json

    # Create rclone config
    cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive =
EOF
    echo "   ✅ Setup from RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT"
fi

if rclone lsd gdrive: >/dev/null 2>&1; then
    echo "   ✅ Rclone is currently working"

    # Save EVERYTHING needed for sync to workspace
    echo "   Saving all credentials to workspace..."

    # Save rclone config
    cp /root/.config/rclone/rclone.conf /workspace/.permanent_sync/rclone.conf 2>/dev/null

    # Save service account if exists
    if [ -f /root/.config/rclone/service_account.json ]; then
        cp /root/.config/rclone/service_account.json /workspace/.permanent_sync/service_account.json
    fi

    # Save any available secrets
    if [ -n "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" ]; then
        echo "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" > /workspace/.permanent_sync/runpod_secret.json
    elif [ -n "$GOOGLE_SERVICE_ACCOUNT" ]; then
        echo "$GOOGLE_SERVICE_ACCOUNT" > /workspace/.permanent_sync/runpod_secret.json
    fi

    # Save environment variables that might be needed
    env | grep -E "RUNPOD|GOOGLE|RCLONE" > /workspace/.permanent_sync/env_vars.txt

    echo "   ✅ Credentials saved to /workspace/.permanent_sync/"
else
    echo "   ❌ Rclone not working currently"

    # Check if we have saved credentials
    if [ -f /workspace/.permanent_sync/rclone.conf ]; then
        echo "   Found saved credentials, restoring..."
        mkdir -p /root/.config/rclone
        cp /workspace/.permanent_sync/* /root/.config/rclone/ 2>/dev/null

        if rclone lsd gdrive: >/dev/null 2>&1; then
            echo "   ✅ Restored from permanent backup!"
        fi
    fi
fi
echo

# Step 2: Create self-contained sync script
echo "2. Creating self-contained sync script..."

cat > /workspace/.permanent_sync/self_contained_sync.sh << 'SYNC_SCRIPT'
#!/bin/bash

# Self-contained sync that includes everything needed

echo "[$(date)] Self-contained sync starting..."

# Function to ensure rclone works
setup_rclone() {
    # First try existing config
    if rclone lsd gdrive: >/dev/null 2>&1; then
        return 0
    fi

    # Try to restore from permanent backup
    if [ -f /workspace/.permanent_sync/rclone.conf ]; then
        mkdir -p /root/.config/rclone
        cp /workspace/.permanent_sync/rclone.conf /root/.config/rclone/

        if [ -f /workspace/.permanent_sync/service_account.json ]; then
            cp /workspace/.permanent_sync/service_account.json /root/.config/rclone/
        elif [ -f /workspace/.permanent_sync/runpod_secret.json ]; then
            cp /workspace/.permanent_sync/runpod_secret.json /root/.config/rclone/service_account.json
        fi

        if rclone lsd gdrive: >/dev/null 2>&1; then
            echo "[$(date)] Restored from permanent backup"
            return 0
        fi
    fi

    # Try to use saved RunPod secret
    if [ -f /workspace/.permanent_sync/runpod_secret.json ]; then
        mkdir -p /root/.config/rclone
        cp /workspace/.permanent_sync/runpod_secret.json /root/.config/rclone/service_account.json

        # Create basic config
        cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive =
EOF

        # Auto-detect shared drive
        DRIVES_JSON=$(rclone backend drives gdrive: 2>/dev/null || echo "[]")
        if [ "$DRIVES_JSON" != "[]" ] && [ -n "$DRIVES_JSON" ]; then
            TEAM_DRIVE_ID=$(echo "$DRIVES_JSON" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
            if [ -n "$TEAM_DRIVE_ID" ]; then
                echo "[$(date)] Found shared drive: $TEAM_DRIVE_ID"
                sed -i "s/team_drive =$/team_drive = $TEAM_DRIVE_ID/" /root/.config/rclone/rclone.conf
            fi
        fi

        if rclone lsd gdrive: >/dev/null 2>&1; then
            echo "[$(date)] Setup using saved secret"
            return 0
        fi
    fi

    # Check environment variables
    if [ -n "$GOOGLE_SERVICE_ACCOUNT" ]; then
        mkdir -p /root/.config/rclone
        echo "$GOOGLE_SERVICE_ACCOUNT" > /root/.config/rclone/service_account.json

        # Create basic config
        cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive =
EOF

        # Auto-detect shared drive
        DRIVES_JSON=$(rclone backend drives gdrive: 2>/dev/null || echo "[]")
        if [ "$DRIVES_JSON" != "[]" ] && [ -n "$DRIVES_JSON" ]; then
            TEAM_DRIVE_ID=$(echo "$DRIVES_JSON" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
            if [ -n "$TEAM_DRIVE_ID" ]; then
                echo "[$(date)] Found shared drive: $TEAM_DRIVE_ID"
                sed -i "s/team_drive =$/team_drive = $TEAM_DRIVE_ID/" /root/.config/rclone/rclone.conf
            fi
        fi

        if rclone lsd gdrive: >/dev/null 2>&1; then
            echo "[$(date)] Setup using GOOGLE_SERVICE_ACCOUNT env"
            # Save for next time
            mkdir -p /workspace/.permanent_sync
            cp /root/.config/rclone/service_account.json /workspace/.permanent_sync/runpod_secret.json
            return 0
        fi
    elif [ -n "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" ]; then
        mkdir -p /root/.config/rclone
        echo "$RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT" > /root/.config/rclone/service_account.json

        # Create basic config
        cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive =
EOF

        # Auto-detect shared drive
        DRIVES_JSON=$(rclone backend drives gdrive: 2>/dev/null || echo "[]")
        if [ "$DRIVES_JSON" != "[]" ] && [ -n "$DRIVES_JSON" ]; then
            TEAM_DRIVE_ID=$(echo "$DRIVES_JSON" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
            if [ -n "$TEAM_DRIVE_ID" ]; then
                echo "[$(date)] Found shared drive: $TEAM_DRIVE_ID"
                sed -i "s/team_drive =$/team_drive = $TEAM_DRIVE_ID/" /root/.config/rclone/rclone.conf
            fi
        fi

        if rclone lsd gdrive: >/dev/null 2>&1; then
            echo "[$(date)] Setup using RUNPOD_SECRET env"
            # Save for next time
            mkdir -p /workspace/.permanent_sync
            cp /root/.config/rclone/service_account.json /workspace/.permanent_sync/runpod_secret.json
            return 0
        fi
    fi

    echo "[$(date)] ERROR: Could not setup rclone"
    return 1
}

# Main loop
while true; do
    # Ensure rclone is set up
    if ! setup_rclone; then
        echo "[$(date)] Rclone not working, waiting..." >> /tmp/sync_error.log
        sleep 60
        continue
    fi

    # Sync output files
    if [ -d "/workspace/output" ]; then
        FILE_COUNT=$(find /workspace/output -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) 2>/dev/null | wc -l)
        if [ "$FILE_COUNT" -gt 0 ]; then
            echo "[$(date)] Syncing $FILE_COUNT files" >> /tmp/rclone_sync.log

            rclone copy /workspace/output gdrive:ComfyUI-Output/output \
                --exclude "*.tmp" \
                --exclude "*.partial" \
                --min-age 30s \
                --ignore-existing \
                --transfers 2 \
                --checkers 2 >> /tmp/rclone_sync.log 2>&1
        fi
    fi

    sleep 60
done
SYNC_SCRIPT

chmod +x /workspace/.permanent_sync/self_contained_sync.sh
echo "   ✅ Created self-contained sync script"
echo

# Step 3: Create boot starter
echo "3. Creating boot starter..."

cat > /workspace/.permanent_sync/start_on_boot.sh << 'BOOT_SCRIPT'
#!/bin/bash

# This runs on every pod start

echo "[$(date)] Boot starter running..."

# Kill any old sync
pkill -f self_contained_sync 2>/dev/null

# Start the self-contained sync
/workspace/.permanent_sync/self_contained_sync.sh &

echo "[$(date)] Sync started with PID $!"
BOOT_SCRIPT

chmod +x /workspace/.permanent_sync/start_on_boot.sh
echo "   ✅ Created boot starter"
echo

# Step 4: Add to system startup
echo "4. Adding to system startup..."

# Create systemd service (if systemd available)
if command -v systemctl >/dev/null 2>&1; then
    cat > /tmp/gdrive-sync.service << 'SERVICE'
[Unit]
Description=Google Drive Sync
After=network.target

[Service]
Type=simple
ExecStart=/workspace/.permanent_sync/self_contained_sync.sh
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
SERVICE

    sudo cp /tmp/gdrive-sync.service /etc/systemd/system/ 2>/dev/null
    sudo systemctl daemon-reload 2>/dev/null
    sudo systemctl enable gdrive-sync 2>/dev/null
    echo "   ✅ Added systemd service"
fi

# Add to crontab
(crontab -l 2>/dev/null; echo "@reboot /workspace/.permanent_sync/start_on_boot.sh") | crontab - 2>/dev/null
echo "   ✅ Added to crontab"

# Add to bashrc for manual starts
echo "[ ! -f /tmp/sync_started ] && /workspace/.permanent_sync/start_on_boot.sh && touch /tmp/sync_started" >> /root/.bashrc
echo "   ✅ Added to bashrc"
echo

# Step 5: Start the sync now
echo "5. Starting sync now..."

pkill -f self_contained_sync 2>/dev/null
/workspace/.permanent_sync/self_contained_sync.sh &
SYNC_PID=$!

sleep 2
if kill -0 $SYNC_PID 2>/dev/null; then
    echo "   ✅ Sync running with PID $SYNC_PID"
else
    echo "   ❌ Failed to start"
fi
echo

echo "=========================================="
echo "PERMANENT FIX APPLIED"
echo "=========================================="
echo
echo "Everything needed for sync is now stored in:"
echo "  /workspace/.permanent_sync/"
echo
echo "This includes:"
echo "  - Rclone config"
echo "  - Service account credentials"
echo "  - Self-contained sync script"
echo "  - Auto-start mechanisms"
echo
echo "The sync will now:"
echo "  ✓ Survive pod restarts"
echo "  ✓ Work even if RunPod secrets are lost"
echo "  ✓ Auto-repair itself"
echo "  ✓ Start automatically on boot"
echo
echo "To check status:"
echo "  ps aux | grep self_contained"
echo "  tail -f /tmp/rclone_sync.log"
echo
echo "To manually restart:"
echo "  /workspace/.permanent_sync/self_contained_sync.sh &"