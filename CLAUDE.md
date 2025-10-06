# Bug Fixes & Solutions Log

This document tracks all bugs found and their solutions for future reference.

---

## 1. UI Not Updating After ComfyUI Initialization

### Problem
- Control panel shows "Initializing" even after ComfyUI is fully ready
- User had to manually reload the page to see the "Open ComfyUI" button
- UI stayed stuck on initialization status indefinitely

### Root Cause
- Race condition in JavaScript status checking
- Initialization timer (`counterInterval`) kept running after ComfyUI became ready
- Periodic status check (every 5s) was skipping updates when counter was active
- Both polling loop and periodic check failed to clear all timers

### Solution
**Files Modified:** `ui/templates/control_panel.html`

1. **In polling loop (line 1382-1387):** Clear both `checkInterval` and `counterInterval` when ready state detected
2. **In periodic status check (line 1593-1598):** Always clear `counterInterval` when status is ready, regardless of other state
3. **Changed periodic check interval:** From 5s to 3s for faster UI updates
4. **Removed blocking guard:** Periodic check no longer skips updates during initialization

**Key Changes:**
```javascript
// Clear ALL initialization timers when ready
initializationStartTime = null;
if (counterInterval) {
    clearInterval(counterInterval);
    counterInterval = null;
}
```

**Result:** UI now updates automatically within 3 seconds of ComfyUI becoming ready.

---

## 2. FFmpeg Missing After Pod Restart

### Problem
- FFmpeg not found error: "ffmpeg is required for video outputs and could not be found"
- Error occurred every time pod restarted
- Previously fixed by manual installation, but not persistent

### Root Cause
- FFmpeg was installed manually in the ephemeral pod environment
- Not included in the Docker image
- Pod restart = fresh container = no ffmpeg

### Solution
**Files Modified:** `Dockerfile`

Added `ffmpeg` to system dependencies (line 12):
```dockerfile
RUN apt-get update && apt-get install -y \
    git wget curl psmisc lsof unzip \
    python3.11-dev python3.11-venv python3-pip \
    build-essential software-properties-common \
    ffmpeg \
    && curl -O https://downloads.rclone.org/rclone-current-linux-amd64.deb \
    ...
```

**Result:** FFmpeg now permanently available in all pods.

---

## 3. Google Drive Sync Stops Working After a While

### Problem
- Sync process would start but die after some time
- No automatic restart when sync died
- Files stopped syncing to Google Drive without user knowing

### Root Cause
- Sync process not monitored
- No watchdog to detect and restart failed sync
- Sync could fail silently and stay dead

### Solution
**Files Created:**
- `scripts/monitor_sync.sh` - Monitors sync every 5 minutes and restarts if dead
- `scripts/test_sync_monitor.sh` - Test script to verify monitor works

**Files Modified:**
- `Dockerfile` - Added monitor startup in `/start.sh` (line 1054-1058)

**Monitor Script Logic:**
```bash
while true; do
    sleep 300  # Check every 5 minutes

    if ! pgrep -f "sync_loop|permanent_sync|rclone_sync" > /dev/null 2>&1; then
        echo "[SYNC MONITOR] ⚠️ Sync process died, restarting..."
        /app/scripts/ensure_sync.sh >> /tmp/sync_monitor.log 2>&1
    fi
done
```

**Result:** Sync automatically restarts if it dies, ensuring continuous operation.

---

## 4. Google Drive Quota Exceeded - Wrong Shared Drive ID

### Problem
- Massive quota errors: "Service Accounts do not have storage quota"
- 100% of file uploads failing with `storageQuotaExceeded` error
- Config had wrong Shared Drive ID

### Root Cause
Multiple issues:
1. **Wrong field used:** Config used `root_folder_id = 0ABFT2ECfnjL3Uk9PVA` instead of `team_drive`
2. **Wrong ID:** `0ABFT2ECfnjL3Uk9PVA` was incorrect
3. **Correct ID:** `0AGZhU5X0GM32Uk9PVA` (from `rclone backend drives gdrive:`)

Service Accounts cannot use personal Drive storage - they MUST use Shared Drives via `team_drive` field.

### Solution
**Files Modified:**
- `scripts/ensure_sync.sh` - Fixed to use `team_drive` instead of `root_folder_id`
- `scripts/init_sync.sh` - Fixed to use `team_drive` instead of `root_folder_id`

**Before (WRONG):**
```bash
cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive =
root_folder_id = 0ABFT2ECfnjL3Uk9PVA  # WRONG: Not a Shared Drive ID
EOF
```

**After (CORRECT):**
```bash
cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive = 0AGZhU5X0GM32Uk9PVA  # CORRECT: Real Shared Drive ID

EOF
```

**How to Find Correct Shared Drive ID:**
```bash
# This returns the actual Shared Drive ID:
rclone backend drives gdrive:
# Output: [{"id": "0AGZhU5X0GM32Uk9PVA", "kind": "drive#drive", "name": "6th_Base_AI_Content"}]
```

**Result:** All files now sync successfully to Shared Drive without quota errors.

---

## 5. Sync Loop Script Has Wrong Config Template

### Problem
- Even after fixing config manually, sync_loop.sh would recreate bad config
- Script had old template with `root_folder_id` instead of `team_drive`
- Auto-restore feature would restore broken config

### Root Cause
- `sync_loop.sh` created by `init_sync.sh` contained hardcoded wrong config template
- When rclone failed, it would try to fix itself but create the same broken config
- Hardcoded wrong Shared Drive ID in template

### Solution
**Files Modified:** `scripts/init_sync.sh`

Fixed the config template inside sync_loop.sh (lines 231-238):
```bash
# OLD (WRONG):
cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive =
root_folder_id = 0ABFT2ECfnjL3Uk9PVA
EOF

# NEW (CORRECT):
cat > /root/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
service_account_file = /root/.config/rclone/service_account.json
team_drive = 0AGZhU5X0GM32Uk9PVA
EOF
```

**Result:** Sync can now auto-recover with correct config.

---

## 6. Sync Process Dies Immediately After Start

### Problem
- `ensure_sync.sh` would report "Sync started (PID: XXXX)"
- But checking immediately after showed no sync running
- Process was starting but dying within 2 seconds

### Root Cause
- `sync_loop.sh` didn't exist when `ensure_sync.sh` tried to run it
- `ensure_sync.sh` assumed script existed, but `init_sync.sh` creates it
- No fallback to create the script if missing

### Solution
**Files Modified:** `scripts/ensure_sync.sh`

Added automatic creation of `sync_loop.sh` if missing (lines 135-186):
```bash
# Create the sync script if it doesn't exist
if [ ! -f "/workspace/.permanent_sync/sync_loop.sh" ]; then
    echo "[ENSURE SYNC] Creating sync_loop.sh..."
    mkdir -p /workspace/.permanent_sync

    cat > /workspace/.permanent_sync/sync_loop.sh << 'SYNC_SCRIPT'
    #!/bin/bash
    # ... complete sync loop script ...
    SYNC_SCRIPT

    chmod +x /workspace/.permanent_sync/sync_loop.sh
fi
```

**Result:** Sync starts reliably even if script was deleted or never created.

---

## Summary of Files Changed

### New Files Created:
- `scripts/monitor_sync.sh` - Monitors and restarts sync every 5 minutes
- `scripts/test_sync_monitor.sh` - Test script for sync monitor
- `scripts/update_ui_fix.sh` - Script to update UI on running pods

### Modified Files:
- `ui/templates/control_panel.html` - Fixed UI update race condition
- `Dockerfile` - Added ffmpeg, added sync monitor startup
- `scripts/ensure_sync.sh` - Fixed Shared Drive config, added sync_loop.sh creation
- `scripts/init_sync.sh` - Fixed Shared Drive config in all templates

### Key Lessons:
1. **Always use Shared Drives for Service Accounts** - They have no personal storage
2. **Monitor long-running processes** - They can die silently
3. **Clear all timers when state changes** - Prevents race conditions
4. **Include system dependencies in Docker image** - Not in ephemeral pods
5. **Auto-detect Shared Drive ID** - Don't hardcode IDs that might be wrong
6. **Create scripts if missing** - Don't assume they exist

---

## Testing Commands

### Test UI Fix:
```bash
# Visit control panel, start ComfyUI
# UI should update automatically when ready (no reload needed)
```

### Test FFmpeg:
```bash
ffmpeg -version
# Should show version, not "command not found"
```

### Test Sync Monitor:
```bash
./test_sync_monitor.sh
# Should show sync starting and running
```

### Test Google Drive Config:
```bash
rclone lsd gdrive:
# Should list directories without errors

tail -f /tmp/rclone_sync.log
# Should show successful transfers, no quota errors
```

### Verify Shared Drive ID:
```bash
rclone backend drives gdrive:
# Returns: [{"id": "0AGZhU5X0GM32Uk9PVA", ...}]

cat /root/.config/rclone/rclone.conf
# Should show: team_drive = 0AGZhU5X0GM32Uk9PVA
```
