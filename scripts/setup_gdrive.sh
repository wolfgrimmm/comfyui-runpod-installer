#!/bin/bash

# Setup Google Drive for first time
echo "=========================================="
echo "☁️  Google Drive Setup for ComfyUI"
echo "=========================================="

# Check if rclone is installed
if ! command -v rclone &> /dev/null; then
    echo "❌ rclone not found! Installing..."
    curl https://rclone.org/install.sh | bash
fi

echo ""
echo "📝 Setting up Google Drive connection..."
echo ""
echo "INSTRUCTIONS:"
echo "1. Type: n (new remote)"
echo "2. Name: gdrive"
echo "3. Storage: Select 'Google Drive' (usually option 18)"
echo "4. Client ID: Press Enter (leave blank)"
echo "5. Client Secret: Press Enter (leave blank)"
echo "6. Scope: 1 (full access)"
echo "7. Service Account: Press Enter (leave blank)"
echo "8. Edit advanced config: n"
echo "9. Auto config: n (we're on a remote server)"
echo "10. Copy the link to your browser"
echo "11. Authorize with your Google account"
echo "12. Copy the code back here"
echo "13. Configure as team drive: n"
echo "14. Confirm: y"
echo ""
echo "Press Enter to start configuration..."
read

rclone config

echo ""
echo "✅ Setup complete!"
echo ""
echo "📚 Quick Commands:"
echo ""
echo "Download models from Google Drive:"
echo "  ./sync_from_gdrive.sh"
echo ""
echo "Upload outputs to Google Drive:"
echo "  ./sync_to_gdrive.sh"
echo ""
echo "Mount Google Drive (real-time access):"
echo "  mkdir -p /workspace/gdrive"
echo "  rclone mount gdrive:ComfyUI /workspace/gdrive --daemon --allow-non-empty"
echo ""
echo "Auto-sync every 30 minutes (add to crontab -e):"
echo "  */30 * * * * /workspace/scripts/sync_to_gdrive.sh"