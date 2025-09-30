#!/bin/bash

# Force Workspace Cleanup Script (No Confirmation)
# Use this for automated cleanup without prompts

set -e

echo "🧹 Force cleaning workspace..."

# Stop services
pkill -f "python.*app.py" 2>/dev/null || true
pkill -f "python.*main.py" 2>/dev/null || true
pkill -f "flask run" 2>/dev/null || true
pkill -f "jupyter" 2>/dev/null || true
sleep 1

# Clean up
rm -rf /workspace/venv
rm -f /workspace/.setup_complete
rm -f /workspace/.python_packages_installed
rm -rf /workspace/ui_cache
find /workspace -maxdepth 1 -name "*.log" -type f -delete 2>/dev/null || true
find /workspace -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find /workspace -type f -name "*.pyc" -delete 2>/dev/null || true
rm -rf /root/.cache/pip 2>/dev/null || true
rm -rf /workspace/.cache/pip 2>/dev/null || true

echo "✅ Cleanup complete - restart pod to rebuild"