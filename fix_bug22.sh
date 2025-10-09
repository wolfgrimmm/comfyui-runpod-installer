#!/bin/bash

echo "🔧 Applying Bug #22 fix to control panel..."
echo "   - Fix Launch button timeout (HTTP 524 error)"
echo "   - Remove blocking wait loop from /api/start endpoint"
echo ""

# Download the fixed app.py
curl -o /app/ui/app.py https://raw.githubusercontent.com/wolfgrimmm/comfyui-runpod-installer/main/ui/app.py && \
echo "✅ Downloaded latest app.py with Bug #22 fix" && \
pkill -f "python.*app.py" && \
echo "✅ Stopped old Flask app" && \
cd /app/ui && python -u app.py > /workspace/ui.log 2>&1 & \
echo "✅ Started new Flask app" && \
echo "" && \
echo "🎉 Fix complete! The Launch button should now work without timing out." && \
echo "" && \
echo "What changed:" && \
echo "  - /api/start endpoint now returns immediately after launching ComfyUI" && \
echo "  - Frontend polls /api/status to track initialization progress" && \
echo "  - No more 30-minute blocking wait that caused 524 timeouts"
