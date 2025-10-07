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

## 7. Shared Drive ID Auto-Detection Not Working on Pod Restart

### Problem
- Hardcoded wrong Shared Drive ID in scripts
- Auto-detection code existed but was bypassed
- After pod restart, sync would fail with quota errors again
- ID `0ABFT2ECfnjL3Uk9PVA` was wrong, correct is `0AGZhU5X0GM32Uk9PVA`

### Root Cause
- Scripts had hardcoded `team_drive = 0ABFT2ECfnjL3Uk9PVA` in config template
- Auto-detection tried to replace `team_drive =` but value was already set
- The `sed` pattern `s/team_drive =$/` only matches empty values
- Auto-detection would run but fail to update the wrong ID

### Solution
**Files Modified:**
- `scripts/ensure_sync.sh` - Use empty `team_drive =` then auto-detect
- `scripts/init_sync.sh` - Use empty `team_drive =` then auto-detect

**Before (WRONG):**
```bash
cat > /root/.config/rclone/rclone.conf << 'EOF'
team_drive = 0ABFT2ECfnjL3Uk9PVA  # Hardcoded wrong ID
EOF

# Auto-detect (but sed won't match because value already set)
sed -i "s/team_drive =$/team_drive = $TEAM_DRIVE_ID/"
```

**After (CORRECT):**
```bash
cat > /root/.config/rclone/rclone.conf << 'EOF'
team_drive =  # Empty, ready for auto-detection
EOF

# Auto-detect (sed will match and fill in correct ID)
TEAM_DRIVE_ID=$(rclone backend drives gdrive: 2>/dev/null | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
sed -i "s/team_drive =$/team_drive = $TEAM_DRIVE_ID/"
```

**Result:** Shared Drive ID is auto-detected correctly on every pod restart.

---

## 8. Symlink Already Exists Error on ComfyUI Start

### Problem
- ComfyUI fails to start with error: `FileExistsError: [Errno 17] File exists: '/workspace/workflows/serhii' -> '/workspace/ComfyUI/user/workflows'`
- Happens when trying to start ComfyUI after pod restart
- Control panel shows error 500

### Root Cause
- `app.py` tries to create symlink without checking if it exists first
- Symlink from previous session still exists
- `os.symlink()` fails if target already exists

### Solution
**Quick Fix (Manual):**
```bash
rm -rf /workspace/ComfyUI/user/workflows
# Then restart ComfyUI from control panel
```

**Root Issue:**
The code already handles symlinks (line 253-254) but the error still occurs. This suggests:
1. The path exists but is not detected as a symlink or directory
2. Possible file (not dir/symlink) at that location
3. Race condition between removal and creation

**Better Fix:** Add force removal before symlink creation
```python
# ui/app.py line 263-265
# Remove any existing file/symlink/dir with -rf to be safe
import subprocess
subprocess.run(['rm', '-rf', comfy_input], check=False)
subprocess.run(['rm', '-rf', comfy_output], check=False)
subprocess.run(['rm', '-rf', comfy_workflows], check=False)

os.symlink(user_input, comfy_input)
os.symlink(user_output, comfy_output)
os.symlink(user_workflows, comfy_workflows)
```

**Status:** Quick fix provided, permanent fix needed in app.py

---

## 9. Backend Errors (524 Timeout) Not Shown to User

### Problem
- When backend times out or fails (HTTP 524, 500, etc.), user gets no error message
- Button stays stuck on "Starting..." forever with no feedback
- User doesn't know if ComfyUI is actually starting or if backend is down
- Initial report was about "Unexpected token" errors, but real issue is errors being HIDDEN

### Root Cause
- Issue was actually that errors from `/api/start` endpoint were NOT being shown
- When backend times out (HTTP 524) or returns error, user gets no feedback
- Original attempt to silence JSON errors was too aggressive
- Need to distinguish between:
  - Real errors from start command → MUST show to user
  - Expected errors from background status checks → can be silent

### Solution
**Files Modified:** `ui/templates/control_panel.html`

**1. Check response validity BEFORE parsing JSON** (lines 1170-1174):
```javascript
const response = await fetch('/api/start', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({username: username})
});

// Check if response is valid BEFORE trying to parse JSON
// This catches HTTP errors (524, 500, etc.) before JSON parsing
if (!response.ok) {
    throw new Error(`Server error: ${response.status} ${response.statusText}`);
}

const data = await response.json();
```

**2. Always show errors from start request** (lines 1432-1447):
```javascript
} catch (error) {
    // Don't silently ignore errors from the start request - show them to user
    // (Silent handling is only for background status checks, not the initial start command)
    const statusDot = document.getElementById('statusDot');
    const statusText = document.getElementById('statusText');
    statusDot.className = 'status-dot error';
    statusText.textContent = `Error • ${error.message}`;

    showLoading(false);
    showToast('Error: ' + error.message, 'error');
    // ... [reset button state]
}
```

**Why this works:**
- HTTP errors (524, 500) → caught by `!response.ok` → shown with clear message
- HTML error pages → caught by JSON parse → shown with clear message
- Background status checks still have silent error handling (separate code paths)
- User gets immediate feedback when start command fails

**Result:** Real errors are shown to user, no more silent failures when backend is down.

---

## 10. Status Shows "System Inactive" During Initialization

### Problem
- Control panel status indicator shows "System Inactive" during ComfyUI startup
- Happens even though ComfyUI is actively initializing in the background
- Status flickers between "Initializing" and "System Inactive"
- Initialization countdown timer starts but then dies after a few seconds
- Confusing for users - looks like ComfyUI failed when it's actually loading fine

### Root Cause
- Periodic status check (every 3 seconds) calls `/api/status` endpoint
- During startup, endpoint sometimes:
  - Returns errors (Flask not ready yet)
  - Returns `data.running = false` (race condition - ComfyUI process starting but not detected yet)
  - Returns HTML instead of JSON (causes parse errors)
- When this happens, the periodic check immediately sets status to "System Inactive" (line 1644-1649)
- **The check didn't remember that we JUST started ComfyUI** - it treated temporary API failures as "not running"
- No concept of "startup window" - expected time for ComfyUI to initialize

### Solution
**Files Modified:** `ui/templates/control_panel.html`

1. **Added startup tracking variable** (line 925):
```javascript
let lastStartTime = null;  // Track when ComfyUI was last started
```

2. **Set tracking when starting ComfyUI** (line 1173-1174):
```javascript
if (data.success) {
    // Track when we started ComfyUI to prevent premature "System Inactive" status
    lastStartTime = Date.now();
    // ...
}
```

3. **Updated periodic check to respect startup window** (lines 1644-1669):
```javascript
} else {
    // Not running - but check if we recently started ComfyUI
    const STARTUP_WINDOW = 5 * 60 * 1000; // 5 minutes in milliseconds
    const withinStartupWindow = lastStartTime && (Date.now() - lastStartTime < STARTUP_WINDOW);

    if (withinStartupWindow) {
        // We recently started ComfyUI - keep showing "Initializing" even if API says not running
        // This prevents premature "System Inactive" during normal startup delays
        if (statusDot && statusText) {
            const elapsed = Math.floor((Date.now() - lastStartTime) / 1000);
            const minutes = Math.floor(elapsed / 60);
            const seconds = elapsed % 60;
            const timeStr = minutes > 0 ? `${minutes}m ${seconds}s` : `${seconds}s`;

            statusDot.className = 'status-dot initializing';
            statusText.textContent = `Initializing • ${timeStr} elapsed`;
        }
    } else {
        // Not within startup window - actually inactive
        if (statusDot && statusText) {
            statusDot.className = 'status-dot inactive';
            statusText.textContent = 'System Inactive';
        }
        // Clear tracking variables since we're actually inactive
        lastStartTime = null;
    }
}
```

4. **Clear tracking when ComfyUI is ready** (line 1613):
```javascript
// Clear ALL initialization timers and tracking first
initializationStartTime = null;
lastStartTime = null;  // ComfyUI is ready, no longer need startup window
```

**How it works:**
- When user clicks "Launch ComfyUI", we record `lastStartTime`
- For the next 5 minutes, even if status API fails or returns "not running", we keep showing "Initializing"
- After 5 minutes without successful startup, we accept that it's actually inactive
- Once ComfyUI is fully ready, we clear `lastStartTime`

**Result:** Initialization countdown continues reliably, no premature "System Inactive" status.

---

## 11. UX Improvements: Auto-Open, Green Button, and Success Sound

### Problem
- After ComfyUI finishes initializing, user needs to manually click "Open ComfyUI" button
- "Open ComfyUI" button looks the same as other buttons - not clear that ComfyUI is actually ready
- No audio feedback when initialization completes - user might not notice if tab is in background

### User Requirements
- Checkbox to auto-open ComfyUI when ready (simple, no persistence to avoid complexity/bugs)
- Green "Open ComfyUI" button matching the animated status dot color
- Simple beep/ding sound when ComfyUI is ready
- Sound only plays if tab is active (no background notifications)

### Solution
**Files Modified:** `ui/templates/control_panel.html`

#### 1. Auto-Open Checkbox
Added checkbox between username dropdown and action buttons (lines 870-875):
```html
<div class="auto-open-section">
    <label class="checkbox-label">
        <input type="checkbox" id="autoOpenCheckbox" class="checkbox-input">
        <span class="checkbox-text">Auto-open ComfyUI when ready</span>
    </label>
</div>
```

CSS styling (lines 434-464):
```css
.auto-open-section {
    margin: 20px 0;
    padding: 16px 0;
}

.checkbox-label {
    display: flex;
    align-items: center;
    gap: 12px;
    cursor: pointer;
}

.checkbox-input {
    width: 20px;
    height: 20px;
    accent-color: #10b981; /* Same green as status dot */
}
```

Auto-open logic in `updateUIForRunningState()` (lines 1029-1036):
```javascript
// Auto-open if checkbox is checked
const autoOpenCheckbox = document.getElementById('autoOpenCheckbox');
if (autoOpenCheckbox && autoOpenCheckbox.checked) {
    // Small delay to let user see the success state
    setTimeout(() => {
        openComfyUI();
    }, 500);
}
```

#### 2. Green Button Styling
Added `.btn-success` class with status dot colors (lines 598-619):
```css
.btn-success {
    background: linear-gradient(135deg, #10b981, #34d399);
    border: 2px solid #10b981;
    color: white;
    box-shadow: 0 0 20px rgba(16, 185, 129, 0.6);
    animation: successPulse 2s infinite;
}

.btn-success:hover:not(:disabled) {
    transform: translateY(-3px) scale(1.02);
    box-shadow: 0 0 30px rgba(16, 185, 129, 0.8);
    background: linear-gradient(135deg, #34d399, #10b981);
}

@keyframes successPulse {
    0%, 100% { box-shadow: 0 0 20px rgba(16, 185, 129, 0.6); }
    50% { box-shadow: 0 0 30px rgba(16, 185, 129, 0.8); }
}
```

Applied to both static and dynamic buttons:
- Static: `{% if running %}` template (line 937)
- Dynamic: Created in `updateUIForRunningState()` (line 1020)

#### 3. Success Sound Notification
Added `playSuccessSound()` function using Web Audio API (lines 1201-1247):
```javascript
function playSuccessSound() {
    try {
        // Only play if tab is active
        if (document.hidden) return;

        const audioContext = new (window.AudioContext || window.webkitAudioContext)();

        // First tone: C5 (523.25 Hz)
        const oscillator = audioContext.createOscillator();
        const gainNode = audioContext.createGain();
        oscillator.connect(gainNode);
        gainNode.connect(audioContext.destination);
        oscillator.frequency.value = 523.25;
        oscillator.type = 'sine';

        // Fade in/out
        gainNode.gain.setValueAtTime(0, audioContext.currentTime);
        gainNode.gain.linearRampToValueAtTime(0.3, audioContext.currentTime + 0.05);
        gainNode.gain.linearRampToValueAtTime(0, audioContext.currentTime + 0.2);

        oscillator.start(audioContext.currentTime);
        oscillator.stop(audioContext.currentTime + 0.2);

        // Second tone: E5 (659.25 Hz) after 100ms
        setTimeout(() => {
            // Similar setup for second tone
        }, 100);
    } catch (error) {
        // Silently fail if audio not supported
        console.log('Audio not available:', error);
    }
}
```

Called in `updateUIForRunningState()` when button is created (line 1027).

### Why This Works
- **Auto-open**: Simple checkbox state, no localStorage (reduces bugs), 500ms delay lets user see success
- **Green button**: Matches status dot (visual consistency), pulsing animation draws attention
- **Sound**: Two-tone (C5→E5) pleasant notification, only plays if tab active, gracefully fails if unsupported
- **User control**: Checkbox is opt-in, sound is automatic but subtle, respects tab visibility

**Result:** Much better UX - users know immediately when ComfyUI is ready, can auto-open if desired, clear visual feedback.

---

## 12. Switch Back to rclone sync for Reliability

### Problem
- After switching to `rclone copy` for safety, sync became unreliable
- "Only works on one block, then after pod restart, need to run through all issues again and again"
- `rclone copy` kept failing after 100+ fixes, requiring constant re-setup
- Original `rclone sync` worked reliably without persistent restart issues
- User wants true mirror behavior: deletions on pod should delete from Google Drive too

### Root Cause
Looking at git history:
```
commit 1409171: "Change output sync from 'sync' to 'copy' to prevent file deletion"
commit 7dc2adf: "Replace rclone sync with rclone copy for safer Google Drive operations"
```

**Timeline:**
1. Originally used `rclone sync` → worked reliably
2. Switched to `rclone copy` for safety → introduced persistent failures
3. User wants reliability over safety

**Why `rclone copy` caused issues:**
- Only adds new files, never updates or deletes
- Can create state mismatches between pod and Drive
- With `--ignore-existing` flag, doesn't re-check existing files
- Over time, inconsistencies accumulate causing sync failures

**Why `rclone sync` works better:**
- Makes destination exactly match source (true mirror)
- Rechecks all files on each run
- Self-correcting - fixes inconsistencies automatically
- More reliable for continuous operation

### Solution
**Files Modified:**
- `scripts/init_sync.sh` (line 264)
- `scripts/ensure_sync.sh` (line 178)

Changed automatic background sync for output folder:
```bash
# OLD (copy - unreliable)
rclone copy "/workspace/output" "gdrive:ComfyUI-Output/output" \
    --exclude "*.tmp" --exclude "*.partial" \
    --min-age 30s \
    --ignore-existing \
    --transfers 2 --checkers 2 \
    --no-update-modtime

# NEW (sync - reliable, true mirror)
rclone sync "/workspace/output" "gdrive:ComfyUI-Output/output" \
    --exclude "*.tmp" --exclude "*.partial" \
    --min-age 30s \
    --transfers 2 --checkers 2 \
    --no-update-modtime
```

**Key changes:**
- `copy` → `sync` for output folder
- Removed `--ignore-existing` flag (sync doesn't need it)
- Input and workflows still use `copy` (less critical, safer)

**Persistence across pod restarts:**
- Template is in Docker image → every pod gets it
- `init_sync.sh` runs on every pod start → recreates sync_loop.sh
- `/workspace/.permanent_sync/` on network volume → survives restarts
- `ensure_sync.sh` can recreate if missing

**Trade-off:**
- ✅ Reliable sync that works after restarts
- ✅ True mirror - deletions sync both ways
- ⚠️ Files deleted from `/workspace/output` will be deleted from Google Drive
- ✅ But this is what user wants ("whatever I delete from there, it was deleted from Google Drive as well")

**Result:** Reliable sync that persists across pod restarts, with true mirror behavior.

---

## 13. UI Layout Improvements: Model Manager Icon, Loading State, Button Scaling

### Problem
User reported 3 UI issues based on screenshot:
1. **Large MODEL MANAGER button** - Takes up full width at top of actions grid, too prominent
2. **Launch button needs loading state** - Should show gray tint while ComfyUI is initializing
3. **Open ComfyUI button scaling wrong** - Button appears improperly sized in grid layout

### User Requirements
- Move Model Manager to top-left corner as small icon (like JupyterLab/Docs icons)
- Use SVG illustration icons, not emojis (matching existing icon style)
- Gray out Launch button during loading
- Fix Open ComfyUI button to scale properly in grid

### Solution
**Files Modified:** `ui/templates/control_panel.html`

#### 1. Added Model Manager Icon to Quick Actions
Moved to `.quick-actions` section with other utility buttons (lines 869-873):
```html
<button class="action-btn" onclick="openModelManager()">
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round"
              d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4"/>
    </svg>
</button>
```
- Uses cube/package SVG icon (represents models)
- Same styling as JupyterLab and Docs buttons
- Small, subtle, always visible in top-left

#### 2. Removed Large Model Manager Button
Deleted from actions grid (previously at line 947-949):
```html
<!-- REMOVED -->
<button class="btn btn-primary" id="modelBtn" onclick="openModelManager()">
    Model Manager
</button>
```

#### 3. Added Gray Loading State for Launch Button
CSS for loading state (lines 646-657):
```css
.btn-loading {
    background: linear-gradient(135deg, rgba(100, 100, 100, 0.3), rgba(80, 80, 80, 0.2)) !important;
    color: rgba(255, 255, 255, 0.5) !important;
    border-color: rgba(150, 150, 150, 0.3) !important;
    cursor: wait !important;
    pointer-events: none;
}

.btn-loading:hover {
    transform: none !important;
    box-shadow: none !important;
}
```

JavaScript to apply/remove class (lines 1273, 1028, 1440, 1574, 1590):
```javascript
// When starting
primaryBtn.classList.add('btn-loading');

// When ready/error/cancelled
primaryBtn.classList.remove('btn-loading');
```

#### 4. Fixed Open ComfyUI Button Scaling
Added `grid-column: 1 / -1` to `.btn-success` (line 599):
```css
.btn-success {
    grid-column: 1 / -1;  /* Span full width like Launch button */
    background: linear-gradient(135deg, #10b981, #34d399);
    /* ... */
}
```

**Why it was broken:**
- `.btn-primary` had `grid-column: 1 / -1` (full width)
- `.btn-success` didn't have this property
- Caused green button to only span 1 column in 2-column grid
- Now both buttons span full width properly

**Result:** Cleaner UI with Model Manager as subtle icon, visual loading feedback, and proper button sizing.

---

## Summary of Files Changed

### New Files Created:
- `scripts/monitor_sync.sh` - Monitors and restarts sync every 5 minutes
- `scripts/test_sync_monitor.sh` - Test script for sync monitor
- `scripts/update_ui_fix.sh` - Script to update UI on running pods

### Modified Files:
- `ui/templates/control_panel.html` - Fixed UI update race condition, HTTP error handling, startup window tracking, auto-open checkbox, green button styling, success sound, Model Manager icon, loading state, button scaling
- `Dockerfile` - Added ffmpeg, added sync monitor startup
- `scripts/ensure_sync.sh` - Fixed Shared Drive config, added sync_loop.sh creation, switched to rclone sync
- `scripts/init_sync.sh` - Fixed Shared Drive config in all templates, switched to rclone sync

### Key Lessons:
1. **Always use Shared Drives for Service Accounts** - They have no personal storage
2. **Monitor long-running processes** - They can die silently
3. **Clear all timers when state changes** - Prevents race conditions
4. **Include system dependencies in Docker image** - Not in ephemeral pods
5. **Auto-detect Shared Drive ID** - Don't hardcode IDs that might be wrong
6. **Create scripts if missing** - Don't assume they exist
7. **Check response.ok before parsing JSON** - Catch HTTP errors before parse errors
8. **Distinguish error sources** - Silence background errors, but always show command errors
9. **Track state transitions** - Remember when processes start to handle transient failures gracefully
10. **Provide clear visual feedback** - Color coding, animations, and sounds help users understand state
11. **Keep features simple** - No persistence = fewer bugs (user's insight)
12. **Reliability over theoretical safety** - rclone sync is self-correcting and reliable, even if it can delete files

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

---

## 14. Users' Output Files Getting Mixed Together (CRITICAL SECURITY BUG)

### Problem
- **CRITICAL:** All users seeing each other's rendered files
- Serhii had Antonia's videos in his output folder
- Vlad had Antonia's videos in his output folder
- Antonia had other users' images in her folder
- Complete privacy breach - all users' work being synced to everyone's Google Drive

### Root Cause
The automatic background sync scripts were syncing **the entire `/workspace/output` directory** to a **single shared folder** on Google Drive:

```bash
# WRONG - This syncs everything to one folder
rclone sync "/workspace/output" "gdrive:ComfyUI-Output/output"
```

This meant:
1. User structure on pod: `/workspace/output/serhii/`, `/workspace/output/vlad/`, `/workspace/output/antonia/`
2. But sync sent ALL of it to: `gdrive:ComfyUI-Output/output` (single folder)
3. `rclone sync` made destination match source exactly
4. Result: Everyone's files mixed together in one place
5. Then when syncing DOWN, everyone got everyone else's files

**Two conflicting sync systems:**
- ❌ **Automatic sync** (in `init_sync.sh` and `ensure_sync.sh`): Synced entire `/workspace/output` to single folder
- ✅ **Manual sync** (in `sync_to_gdrive.sh`): Correctly synced per-user folders separately

The automatic sync was overriding the manual sync and mixing everything!

### Solution
**Files Modified:**
- `scripts/init_sync.sh` (lines 258-306)
- `scripts/ensure_sync.sh` (lines 174-211)

Changed the automatic sync to iterate through each user's folder and sync them separately:

**Before (WRONG):**
```bash
# Synced entire output folder to single location
if [ -d "/workspace/output" ]; then
    FILE_COUNT=$(find /workspace/output -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) 2>/dev/null | wc -l)
    if [ "$FILE_COUNT" -gt 0 ]; then
        rclone sync "/workspace/output" "gdrive:ComfyUI-Output/output" \
            --exclude "*.tmp" --exclude "*.partial" \
            --min-age 30s --transfers 2 --checkers 2 --no-update-modtime
    fi
fi
```

**After (CORRECT):**
```bash
# Sync each user folder separately to avoid mixing files
if [ -d "/workspace/output" ]; then
    for user_dir in /workspace/output/*/; do
        if [ -d "$user_dir" ]; then
            username=$(basename "$user_dir")
            FILE_COUNT=$(find "$user_dir" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) 2>/dev/null | wc -l)

            if [ "$FILE_COUNT" -gt 0 ]; then
                echo "[SYNC] Syncing $FILE_COUNT files for user $username..."

                rclone sync "$user_dir" "gdrive:ComfyUI-Output/output/$username" \
                    --exclude "*.tmp" --exclude "*.partial" \
                    --min-age 30s --transfers 2 --checkers 2 --no-update-modtime

                if [ $? -eq 0 ]; then
                    echo "[SYNC] Sync completed successfully for $username"
                fi
            fi
        fi
    done
fi
```

**Same fix applied to input and workflows:**
```bash
# Input folders - per user
if [ -d "/workspace/input" ]; then
    for user_dir in /workspace/input/*/; do
        if [ -d "$user_dir" ]; then
            username=$(basename "$user_dir")
            rclone copy "$user_dir" "gdrive:ComfyUI-Output/input/$username" \
                --transfers 2 --ignore-existing --no-update-modtime >/dev/null 2>&1
        fi
    done
fi

# Workflows folders - per user
if [ -d "/workspace/workflows" ]; then
    for user_dir in /workspace/workflows/*/; do
        if [ -d "$user_dir" ]; then
            username=$(basename "$user_dir")
            rclone copy "$user_dir" "gdrive:ComfyUI-Output/workflows/$username" \
                --transfers 2 --no-update-modtime >/dev/null 2>&1
        fi
    done
fi
```

**How it works now:**
1. Pod structure: `/workspace/output/{username}/`
2. Sync destination: `gdrive:ComfyUI-Output/output/{username}/`
3. Each user gets their own isolated folder on Google Drive
4. Files never mix between users

**Result:** Complete user isolation - each user only sees their own files, critical privacy bug fixed.

---

## 15. Status Shows "System Inactive" During ComfyUI Startup

### Problem
- After clicking "Launch ComfyUI", status immediately shows "System Inactive"
- Initialization countdown timer starts but dies after a few seconds
- Status flickers between "Initializing" and "System Inactive"
- Confusing for users - looks like ComfyUI failed when it's actually loading fine
- Happens even though ComfyUI is actively initializing in background

### Root Cause
Two status-checking functions with inconsistent behavior:

1. **Periodic status check** (every 3 seconds) - Had startup window tracking:
   ```javascript
   // Correctly checked if we recently started ComfyUI
   const withinStartupWindow = lastStartTime && (Date.now() - lastStartTime < STARTUP_WINDOW);
   if (withinStartupWindow) {
       // Keep showing "Initializing"
   }
   ```

2. **checkComfyUIStatus()** function - Did NOT have startup window tracking:
   ```javascript
   } else {
       // ComfyUI is not running
       statusDot.className = 'status-dot inactive';
       statusText.textContent = 'System Inactive';  // ❌ Immediate "inactive"!
       return data;
   }
   ```

When `checkComfyUIStatus()` ran during startup (before ComfyUI HTTP server was ready), it would:
- Get "not running" response from API
- Immediately set status to "System Inactive"
- Ignore the fact that we JUST started ComfyUI seconds ago

This created confusing flickering as the two functions fought each other.

### Solution
**Files Modified:** `ui/templates/control_panel.html` (lines 1180-1200)

Made `checkComfyUIStatus()` respect the startup window, just like the periodic check:

**Before (WRONG):**
```javascript
} else {
    // ComfyUI is not running
    statusDot.className = 'status-dot inactive';
    statusText.textContent = 'System Inactive';
    return data;
}
```

**After (CORRECT):**
```javascript
} else {
    // ComfyUI is not running - but check if we recently started it
    const STARTUP_WINDOW = 5 * 60 * 1000; // 5 minutes
    const withinStartupWindow = lastStartTime && (Date.now() - lastStartTime < STARTUP_WINDOW);

    if (withinStartupWindow) {
        // Recently started - keep showing initializing
        const elapsed = Math.floor((Date.now() - lastStartTime) / 1000);
        const minutes = Math.floor(elapsed / 60);
        const seconds = elapsed % 60;
        const timeStr = minutes > 0 ? `${minutes}m ${seconds}s` : `${seconds}s`;

        statusDot.className = 'status-dot initializing';
        statusText.textContent = `Initializing • ${timeStr} elapsed`;
    } else {
        // Not within startup window - actually inactive
        statusDot.className = 'status-dot inactive';
        statusText.textContent = 'System Inactive';
    }
    return data;
}
```

**How it works:**
- When user clicks "Launch ComfyUI", we set `lastStartTime = Date.now()`
- For the next 5 minutes, both functions keep showing "Initializing" with elapsed time
- Even if API returns errors or "not running", we trust that startup is in progress
- After 5 minutes without success, we accept it's actually inactive
- Once ComfyUI is ready, we clear `lastStartTime` (line 1613)

**Result:** No more premature "System Inactive" status - initialization countdown runs reliably until ComfyUI is ready.

---

## 16. Green "Open ComfyUI" Button Too Glowing

### Problem
- "Open ComfyUI" button had constant pulsing animation
- Bright glowing effect even when not hovering
- Too distracting compared to other buttons
- User requested it match the subtle glow style of red buttons

### Root Cause
The success button styling included:
1. Constant bright box-shadow (`0 0 20px rgba(16, 185, 129, 0.6)`)
2. Pulsing animation (`animation: successPulse 2s infinite`)
3. Very bright hover glow (`0 0 30px rgba(16, 185, 129, 0.8)` - 0.8 opacity)

In contrast, red buttons had:
1. No default glow
2. No animation
3. Subtle hover glow (`0 0 30px rgba(231, 51, 29, 0.25)` - only 0.25 opacity)

### Solution
**Files Modified:** `ui/templates/control_panel.html` (lines 598-609)

Removed the constant glow, animation, and reduced hover glow to match red buttons:

**Before (TOO BRIGHT):**
```css
.btn-success {
    grid-column: 1 / -1;
    background: linear-gradient(135deg, #10b981, #34d399);
    border: 2px solid #10b981;
    color: white;
    box-shadow: 0 0 20px rgba(16, 185, 129, 0.6);  /* ❌ Constant bright glow */
    animation: successPulse 2s infinite;            /* ❌ Pulsing animation */
}

.btn-success:hover:not(:disabled) {
    transform: translateY(-3px) scale(1.02);
    box-shadow: 0 0 30px rgba(16, 185, 129, 0.8);  /* ❌ Very bright hover */
    background: linear-gradient(135deg, #34d399, #10b981);
}

@keyframes successPulse {
    0%, 100% { box-shadow: 0 0 20px rgba(16, 185, 129, 0.6); }
    50% { box-shadow: 0 0 30px rgba(16, 185, 129, 0.8); }
}
```

**After (SUBTLE):**
```css
.btn-success {
    grid-column: 1 / -1;
    background: linear-gradient(135deg, #10b981, #34d399);
    border: 2px solid #10b981;
    color: white;
    /* No default glow, no animation */
}

.btn-success:hover:not(:disabled) {
    transform: translateY(-3px) scale(1.02);
    box-shadow: 0 0 30px rgba(16, 185, 129, 0.25);  /* ✅ Subtle hover only */
    background: linear-gradient(135deg, #34d399, #10b981);
}
```

**What was removed:**
1. Default `box-shadow` on button
2. `animation: successPulse`
3. `@keyframes successPulse` animation definition
4. Bright hover glow (0.8 opacity → 0.25 opacity)

**Result:** Button now has same subtle glow style as red buttons - clean, professional, not distracting.
- Claude.md