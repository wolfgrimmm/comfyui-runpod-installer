#!/bin/bash

echo "🔧 Applying Bug #19 fixes to control panel..."
echo "   - Fix 'System Inactive' bug"
echo "   - Reduce green button glow"
echo "   - Remove GitHub/Docs button"
echo "   - Fix JavaScript error (openDocs)"
echo ""

curl -o /app/ui/templates/control_panel.html https://raw.githubusercontent.com/wolfgrimmm/comfyui-runpod-installer/main/ui/templates/control_panel.html && \
echo "✅ Downloaded latest control_panel.html" && \
pkill -f "python.*app.py" && \
echo "✅ Stopped old Flask app" && \
cd /app/ui && python -u app.py > /workspace/ui.log 2>&1 & \
echo "✅ Started new Flask app" && \
echo "" && \
echo "🎉 Fix complete! Refresh your browser to see changes."
