#!/bin/bash

# Fix workflow symlink to ensure ComfyUI saves to /workspace/workflows

echo "==========================================="
echo "FIXING WORKFLOW SYMLINK"
echo "==========================================="
echo

# Create the workspace workflows directory if it doesn't exist
mkdir -p /workspace/workflows

# Check current state
echo "1. Current state check:"
echo "-----------------------"

if [ -L "/workspace/ComfyUI/user/default/workflows" ]; then
    echo "✅ Workflows is already a symlink pointing to: $(readlink -f /workspace/ComfyUI/user/default/workflows)"
elif [ -d "/workspace/ComfyUI/user/default/workflows" ]; then
    echo "⚠️ Workflows is a real directory (not a symlink)"

    # Count existing workflows
    WORKFLOW_COUNT=$(find /workspace/ComfyUI/user/default/workflows -name "*.json" 2>/dev/null | wc -l)
    echo "   Found $WORKFLOW_COUNT workflow files"
else
    echo "ℹ️ Workflows directory doesn't exist yet"
fi

echo
echo "2. Migrating existing workflows:"
echo "---------------------------------"

# If ComfyUI/user/default/workflows exists and is not a symlink
if [ -d "/workspace/ComfyUI/user/default/workflows" ] && [ ! -L "/workspace/ComfyUI/user/default/workflows" ]; then
    echo "Migrating existing workflows to /workspace/workflows..."

    # Copy any existing workflows to the workspace
    if [ "$(ls -A /workspace/ComfyUI/user/default/workflows 2>/dev/null)" ]; then
        cp -r /workspace/ComfyUI/user/default/workflows/* /workspace/workflows/ 2>/dev/null || true
        echo "✅ Copied existing workflows to /workspace/workflows"
    fi

    # Remove the old directory
    rm -rf /workspace/ComfyUI/user/default/workflows
    echo "✅ Removed old workflows directory"
fi

echo
echo "3. Creating symlink:"
echo "--------------------"

# Ensure the parent directory exists
mkdir -p /workspace/ComfyUI/user/default

# Create the symlink
if [ ! -e "/workspace/ComfyUI/user/default/workflows" ]; then
    ln -sf /workspace/workflows /workspace/ComfyUI/user/default/workflows
    echo "✅ Created symlink: /workspace/ComfyUI/user/default/workflows → /workspace/workflows"
elif [ -L "/workspace/ComfyUI/user/default/workflows" ]; then
    # Remove and recreate to ensure it points to the right place
    rm /workspace/ComfyUI/user/default/workflows
    ln -sf /workspace/workflows /workspace/ComfyUI/user/default/workflows
    echo "✅ Recreated symlink: /workspace/ComfyUI/user/default/workflows → /workspace/workflows"
else
    echo "❌ Could not create symlink - workflows exists and is not a symlink"
fi

echo
echo "4. Creating symlinks for other ComfyUI directories:"
echo "----------------------------------------------------"

# Also symlink output if needed
if [ -d "/workspace/ComfyUI/output" ] && [ ! -L "/workspace/ComfyUI/output" ]; then
    # Migrate existing outputs
    if [ "$(ls -A /workspace/ComfyUI/output 2>/dev/null)" ]; then
        cp -r /workspace/ComfyUI/output/* /workspace/output/ 2>/dev/null || true
        echo "✅ Migrated existing outputs"
    fi
    rm -rf /workspace/ComfyUI/output
fi

if [ ! -e "/workspace/ComfyUI/output" ]; then
    ln -sf /workspace/output /workspace/ComfyUI/output
    echo "✅ Created output symlink: /workspace/ComfyUI/output → /workspace/output"
fi

# Also symlink input if needed
if [ -d "/workspace/ComfyUI/input" ] && [ ! -L "/workspace/ComfyUI/input" ]; then
    # Migrate existing inputs
    if [ "$(ls -A /workspace/ComfyUI/input 2>/dev/null)" ]; then
        cp -r /workspace/ComfyUI/input/* /workspace/input/ 2>/dev/null || true
        echo "✅ Migrated existing inputs"
    fi
    rm -rf /workspace/ComfyUI/input
fi

if [ ! -e "/workspace/ComfyUI/input" ]; then
    ln -sf /workspace/input /workspace/ComfyUI/input
    echo "✅ Created input symlink: /workspace/ComfyUI/input → /workspace/input"
fi

echo
echo "5. Verification:"
echo "----------------"

# Verify all symlinks
echo "Checking symlinks:"
for path in /workspace/ComfyUI/user/default/workflows /workspace/ComfyUI/output /workspace/ComfyUI/input /workspace/ComfyUI/models; do
    if [ -L "$path" ]; then
        echo "✅ $path → $(readlink -f $path)"
    elif [ -e "$path" ]; then
        echo "⚠️ $path exists but is not a symlink"
    else
        echo "❌ $path does not exist"
    fi
done

echo
echo "==========================================="
echo "WORKFLOW SYMLINK FIX COMPLETE"
echo "==========================================="
echo
echo "Workflows will now be saved to: /workspace/workflows"
echo "This location persists across pod restarts and syncs to Google Drive"
echo
echo "To test:"
echo "1. Save a workflow in ComfyUI"
echo "2. Check if it appears in: ls /workspace/workflows/"