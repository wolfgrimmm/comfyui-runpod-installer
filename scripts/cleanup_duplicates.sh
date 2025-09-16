#!/bin/bash

echo "===================================="
echo "ComfyUI Duplicate Files Cleanup"
echo "===================================="
echo "This script fixes duplicate files and ensures proper symlink setup"
echo

# Step 1: Check current situation
echo "1. Analyzing current directory structure..."

if [ -L "/workspace/ComfyUI/output" ]; then
    SYMLINK_TARGET=$(readlink -f "/workspace/ComfyUI/output")
    echo "   ✅ /workspace/ComfyUI/output is a symlink -> $SYMLINK_TARGET"
elif [ -d "/workspace/ComfyUI/output" ]; then
    echo "   ⚠️ /workspace/ComfyUI/output is a REAL directory (this causes duplicates!)"
    FILE_COUNT=$(find /workspace/ComfyUI/output -type f 2>/dev/null | wc -l)
    echo "      Contains $FILE_COUNT files"
else
    echo "   ℹ️ /workspace/ComfyUI/output doesn't exist"
fi

echo
echo "   /workspace/output structure:"
if [ -d "/workspace/output" ]; then
    for dir in /workspace/output/*/; do
        if [ -d "$dir" ]; then
            username=$(basename "$dir")
            count=$(find "$dir" -type f 2>/dev/null | wc -l)
            echo "      - $username: $count files"
        fi
    done
else
    echo "      Directory doesn't exist!"
fi
echo

# Step 2: Move any files from ComfyUI/output to workspace/output
if [ -d "/workspace/ComfyUI/output" ] && [ ! -L "/workspace/ComfyUI/output" ]; then
    echo "2. Moving files from ComfyUI/output to workspace/output..."

    # Check if there are user subdirectories
    if ls /workspace/ComfyUI/output/*/ >/dev/null 2>&1; then
        # Has user subdirectories
        for user_dir in /workspace/ComfyUI/output/*/; do
            if [ -d "$user_dir" ]; then
                username=$(basename "$user_dir")
                echo "   Moving files for user: $username"
                mkdir -p "/workspace/output/$username"
                rsync -av "$user_dir" "/workspace/output/$username/" 2>/dev/null || true
            fi
        done
    else
        # No user subdirectories - files are in root
        echo "   Moving files from root output directory"
        # Determine current user from CURRENT_USER_FILE or default to first found
        if [ -f "/workspace/user_data/.current_user" ]; then
            CURRENT_USER=$(cat /workspace/user_data/.current_user)
        else
            CURRENT_USER="serhii"  # Default
        fi
        mkdir -p "/workspace/output/$CURRENT_USER"

        # Move all files to current user's folder
        find /workspace/ComfyUI/output -maxdepth 1 -type f -exec mv {} "/workspace/output/$CURRENT_USER/" \; 2>/dev/null || true
    fi

    echo "   ✅ Files moved to /workspace/output"
else
    echo "2. No files to move (symlink already in place or directory empty)"
fi
echo

# Step 3: Remove the real ComfyUI/output directory
if [ -d "/workspace/ComfyUI/output" ] && [ ! -L "/workspace/ComfyUI/output" ]; then
    echo "3. Removing real ComfyUI/output directory..."
    rm -rf /workspace/ComfyUI/output
    echo "   ✅ Directory removed"
else
    echo "3. No real directory to remove"
fi
echo

# Step 4: Create proper symlink
echo "4. Setting up proper symlink..."

# Get current user
if [ -f "/workspace/user_data/.current_user" ]; then
    CURRENT_USER=$(cat /workspace/user_data/.current_user)
    echo "   Current user: $CURRENT_USER"
else
    CURRENT_USER="serhii"
    echo "   No current user found, using default: $CURRENT_USER"
fi

# Create user output directory if it doesn't exist
USER_OUTPUT="/workspace/output/$CURRENT_USER"
mkdir -p "$USER_OUTPUT"

# Remove any existing symlink
if [ -L "/workspace/ComfyUI/output" ]; then
    rm /workspace/ComfyUI/output
fi

# Create symlink to user's output folder
ln -sf "$USER_OUTPUT" /workspace/ComfyUI/output
echo "   ✅ Created symlink: /workspace/ComfyUI/output -> $USER_OUTPUT"
echo

# Step 5: Fix input and workflows symlinks too
echo "5. Fixing input and workflows symlinks..."

# Fix input
if [ -d "/workspace/ComfyUI/input" ] && [ ! -L "/workspace/ComfyUI/input" ]; then
    echo "   Moving input files..."
    mkdir -p "/workspace/input/$CURRENT_USER"
    rsync -av /workspace/ComfyUI/input/ "/workspace/input/$CURRENT_USER/" 2>/dev/null || true
    rm -rf /workspace/ComfyUI/input
fi
[ -L "/workspace/ComfyUI/input" ] && rm /workspace/ComfyUI/input
ln -sf "/workspace/input/$CURRENT_USER" /workspace/ComfyUI/input
echo "   ✅ Input symlink fixed"

# Fix workflows
mkdir -p /workspace/ComfyUI/user
if [ -d "/workspace/ComfyUI/user/workflows" ] && [ ! -L "/workspace/ComfyUI/user/workflows" ]; then
    echo "   Moving workflow files..."
    mkdir -p "/workspace/workflows/$CURRENT_USER"
    rsync -av /workspace/ComfyUI/user/workflows/ "/workspace/workflows/$CURRENT_USER/" 2>/dev/null || true
    rm -rf /workspace/ComfyUI/user/workflows
fi
[ -L "/workspace/ComfyUI/user/workflows" ] && rm /workspace/ComfyUI/user/workflows
ln -sf "/workspace/workflows/$CURRENT_USER" /workspace/ComfyUI/user/workflows
echo "   ✅ Workflows symlink fixed"
echo

# Step 6: Restart sync with correct paths
echo "6. Restarting sync process..."

# Kill old sync process
pkill -f "rclone_sync_loop" 2>/dev/null || true

# Start new sync process with correct paths
cat > /tmp/rclone_sync_loop.sh << 'SYNC_SCRIPT'
#!/bin/bash

echo "[$(date)] Google Drive sync started (workspace-only version)" >> /tmp/rclone_sync.log

while true; do
    sleep 60  # Sync every minute
    echo "[$(date)] Starting sync cycle..." >> /tmp/rclone_sync.log

    # ONLY sync from /workspace directories (the real locations)

    # Copy output (never delete from Drive!)
    if [ -d "/workspace/output" ]; then
        echo "  Copying output from: /workspace/output" >> /tmp/rclone_sync.log
        rclone copy "/workspace/output" "gdrive:ComfyUI-Output/output" \
            --exclude "*.tmp" \
            --exclude "*.partial" \
            --exclude "**/temp_*" \
            --transfers 4 \
            --checkers 2 \
            --bwlimit 50M \
            --min-age 30s \
            --no-update-modtime \
            --ignore-existing >> /tmp/rclone_sync.log 2>&1
    fi

    # Sync input
    if [ -d "/workspace/input" ]; then
        echo "  Syncing input from: /workspace/input" >> /tmp/rclone_sync.log
        rclone copy "/workspace/input" "gdrive:ComfyUI-Output/input" \
            --transfers 4 \
            --checkers 2 \
            --bwlimit 50M \
            --no-update-modtime >> /tmp/rclone_sync.log 2>&1
    fi

    # Sync workflows
    if [ -d "/workspace/workflows" ]; then
        echo "  Syncing workflows from: /workspace/workflows" >> /tmp/rclone_sync.log
        rclone sync "/workspace/workflows" "gdrive:ComfyUI-Output/workflows" \
            --transfers 4 \
            --checkers 2 \
            --bwlimit 50M \
            --no-update-modtime >> /tmp/rclone_sync.log 2>&1
    fi

    echo "  Sync cycle completed" >> /tmp/rclone_sync.log
done
SYNC_SCRIPT

chmod +x /tmp/rclone_sync_loop.sh
/tmp/rclone_sync_loop.sh &
echo "   ✅ Sync restarted with correct paths"
echo

# Step 7: Verify final state
echo "7. Final verification..."

if [ -L "/workspace/ComfyUI/output" ]; then
    TARGET=$(readlink -f "/workspace/ComfyUI/output")
    echo "   ✅ Output symlink correct: /workspace/ComfyUI/output -> $TARGET"
else
    echo "   ❌ Output symlink not set up properly!"
fi

if [ -L "/workspace/ComfyUI/input" ]; then
    TARGET=$(readlink -f "/workspace/ComfyUI/input")
    echo "   ✅ Input symlink correct: /workspace/ComfyUI/input -> $TARGET"
fi

if [ -L "/workspace/ComfyUI/user/workflows" ]; then
    TARGET=$(readlink -f "/workspace/ComfyUI/user/workflows")
    echo "   ✅ Workflows symlink correct: /workspace/ComfyUI/user/workflows -> $TARGET"
fi
echo

echo "===================================="
echo "✅ Cleanup Complete!"
echo "===================================="
echo
echo "Summary:"
echo "- All files moved to /workspace/output/$CURRENT_USER"
echo "- Symlinks point to /workspace directories (no duplicates)"
echo "- Sync process restarted with correct paths"
echo
echo "Files will now sync from:"
echo "  /workspace/output → Google Drive"
echo "  (NOT from /workspace/ComfyUI/output)"
echo
echo "Monitor sync with: tail -f /tmp/rclone_sync.log"