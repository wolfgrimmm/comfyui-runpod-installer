#!/bin/bash

# Script to automatically update control_panel.html with UI initialization fix
# This fixes the issue where UI shows "Initializing" even after ComfyUI is ready

echo "🔧 Updating control panel UI with initialization fix..."

# Try common installation locations
INSTALL_DIR=""
for dir in "/app/ui" "/app" "/comfyui-runpod-installer" "/workspace" "/opt/comfyui-runpod-installer"; do
    if [ -f "$dir/app.py" ] && [ -d "$dir/templates" ]; then
        INSTALL_DIR="$dir"
        break
    fi
done

if [ -z "$INSTALL_DIR" ]; then
    echo "❌ Cannot find installation directory"
    echo "📂 Searched: /app, /comfyui-runpod-installer, /workspace, /opt/comfyui-runpod-installer"
    echo ""
    echo "Please run this command to find it:"
    echo "  find / -name 'app.py' -path '*/ui/templates*' -o -name 'app.py' 2>/dev/null | head -5"
    exit 1
fi

echo "📂 Found installation at: $INSTALL_DIR"

# Download the updated control_panel.html from GitHub
echo "⬇️  Downloading updated file from GitHub..."
curl -sSL https://raw.githubusercontent.com/wolfgrimmm/comfyui-runpod-installer/main/ui/templates/control_panel.html -o /tmp/control_panel_new.html

if [ $? -ne 0 ]; then
    echo "❌ Failed to download updated file from GitHub"
    exit 1
fi

# Backup the current file
echo "💾 Creating backup..."
cp "$INSTALL_DIR/templates/control_panel.html" "$INSTALL_DIR/templates/control_panel.html.backup"

# Replace with updated version
echo "📝 Applying fix..."
mv /tmp/control_panel_new.html "$INSTALL_DIR/templates/control_panel.html"

echo "✅ Control panel updated successfully!"
echo "📋 Backup saved to: $INSTALL_DIR/templates/control_panel.html.backup"
echo ""

# Try to restart Flask app if it's running
FLASK_PID=$(pgrep -f "python.*app.py")
if [ -n "$FLASK_PID" ]; then
    echo "🔄 Restarting Flask app..."
    kill $FLASK_PID
    sleep 2
    cd "$INSTALL_DIR" && nohup python app.py > /tmp/flask.log 2>&1 &
    echo "✅ Flask app restarted!"
else
    echo "ℹ️  Flask app not running - changes will apply on next start"
fi

echo ""
echo "🎉 Fix applied! Refresh your browser to see the changes."
