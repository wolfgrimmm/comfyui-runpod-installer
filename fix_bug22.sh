#!/bin/bash

echo "🔧 Applying Bug #22 fix to control panel..."
echo "   - Fix Launch button timeout (HTTP 524 error)"
echo "   - Remove blocking wait loop from /api/start endpoint"
echo "   - Increase startup window from 5 to 20 minutes"
echo ""

# Download the fixed files
curl -o /app/ui/app.py https://raw.githubusercontent.com/wolfgrimmm/comfyui-runpod-installer/main/ui/app.py && \
echo "✅ Downloaded latest app.py with Bug #22 fix" && \
curl -o /app/ui/templates/control_panel.html https://raw.githubusercontent.com/wolfgrimmm/comfyui-runpod-installer/main/ui/templates/control_panel.html && \
echo "✅ Downloaded latest control_panel.html with 20-minute startup window" && \
pkill -f "python.*app.py" && \
echo "✅ Stopped old Flask app" && \
cd /app/ui && python -u app.py > /workspace/ui.log 2>&1 & \
echo "✅ Started new Flask app" && \
echo "" && \
echo "🎉 Fix complete! Refresh your browser to see changes." && \
echo "" && \
echo "What changed:" && \
echo "  - /api/start endpoint now returns immediately after launching ComfyUI" && \
echo "  - Frontend polls /api/status to track initialization progress" && \
echo "  - Startup window increased to 20 minutes (for heavy video workflows)" && \
echo "  - No more 'System Inactive' status during long ComfyUI loads"
