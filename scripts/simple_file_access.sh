#!/bin/bash

# 🐒 SUPER SIMPLE FILE ACCESS FOR NON-TECHNICAL USERS
# This script makes it super easy to access your files

echo "🐒 SUPER SIMPLE FILE ACCESS"
echo "=========================="
echo ""
echo "This script will help you access your files easily!"
echo ""

# Check if we're on RunPod
if [ -z "$RUNPOD_POD_ID" ]; then
    echo "⚠️ This script is designed for RunPod pods"
    echo "   You can still use it to test locally"
    echo ""
fi

echo "🎯 WHAT YOU CAN DO:"
echo ""
echo "1. 📥 DOWNLOAD ALL FILES"
echo "   - Click 'Download All Files' button in control panel"
echo "   - Gets everything as a ZIP file"
echo "   - Super easy - just one click!"
echo ""
echo "2. 👀 VIEW FILES IN BROWSER"
echo "   - Click 'My Files' panel in control panel"
echo "   - See all your files with previews"
echo "   - Click to download individual files"
echo ""
echo "3. 📁 OPEN FILE MANAGER"
echo "   - Click 'Open File Manager' button"
echo "   - Opens RunPod's web file manager"
echo "   - Browse files like Windows Explorer"
echo ""

echo "🚀 HOW TO USE:"
echo ""
echo "1. Start your ComfyUI pod"
echo "2. Open the Control Panel (the web interface)"
echo "3. Look for these panels:"
echo "   - 'My Files' - shows all your files"
echo "   - 'S3 Storage' - advanced options"
echo "4. Click the buttons to download or view files"
echo ""

echo "📱 MOBILE FRIENDLY:"
echo "   - Works on phones and tablets"
echo "   - Touch-friendly buttons"
echo "   - No technical knowledge needed"
echo ""

echo "🔧 IF SOMETHING GOES WRONG:"
echo "   - Refresh the page (F5 or Ctrl+R)"
echo "   - Try clicking 'Refresh' button"
echo "   - Check if you selected your username"
echo ""

echo "💡 TIPS:"
echo "   - Files are organized by date (newest first)"
echo "   - Images show previews"
echo "   - Videos can be played in browser"
echo "   - All files can be downloaded"
echo ""

echo "🎉 THAT'S IT! Super simple!"
echo "   No command line, no technical stuff, just click buttons!"
echo ""

# Check if control panel is running
if curl -s http://localhost:5000 >/dev/null 2>&1; then
    echo "✅ Control Panel is running!"
    echo "   Open: http://localhost:5000"
    echo "   (Or use the RunPod web interface)"
else
    echo "⚠️ Control Panel not running"
    echo "   Start ComfyUI first, then open the control panel"
fi

echo ""
echo "🐒 Happy file browsing!"
