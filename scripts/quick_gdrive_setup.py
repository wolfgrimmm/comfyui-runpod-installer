#!/usr/bin/env python3
"""
Quick Google Drive setup script for service account
Run this on your RunPod to configure Google Drive sync
"""

import os
import sys
import json
import subprocess
from pathlib import Path

def setup_gdrive(json_path):
    """Setup Google Drive with service account JSON"""
    
    # Read the JSON file
    try:
        with open(json_path, 'r') as f:
            service_account = json.load(f)
    except Exception as e:
        print(f"❌ Error reading JSON file: {e}")
        return False
    
    # Extract client email
    client_email = service_account.get('client_email', 'unknown')
    print(f"📧 Using service account: {client_email}")
    
    # Create rclone config directory
    config_dir = Path.home() / '.config' / 'rclone'
    config_dir.mkdir(parents=True, exist_ok=True)
    
    # Save service account file
    sa_path = config_dir / 'service_account.json'
    with open(sa_path, 'w') as f:
        json.dump(service_account, f, indent=2)
    
    # Set secure permissions
    os.chmod(sa_path, 0o600)
    
    # Create rclone config
    config_path = config_dir / 'rclone.conf'
    config_content = f"""[gdrive]
type = drive
scope = drive
service_account_file = {sa_path}
team_drive = 

"""
    
    with open(config_path, 'w') as f:
        f.write(config_content)
    
    print("✅ Rclone configured")
    
    # Test connection
    print("🔍 Testing connection...")
    result = subprocess.run(
        ['rclone', 'lsd', 'gdrive:'],
        capture_output=True,
        text=True
    )
    
    if result.returncode != 0:
        print(f"⚠️  Connection failed. Make sure you've shared your Google Drive folder with:")
        print(f"    {client_email}")
        print("\nSteps to share:")
        print("1. Open Google Drive")
        print("2. Create a folder called 'ComfyUI-Output'")
        print("3. Right-click → Share")
        print(f"4. Add: {client_email}")
        print("5. Set permission to 'Editor'")
        return False
    
    print("✅ Connection successful!")
    
    # Create folder structure
    print("📁 Creating folder structure...")
    folders = [
        'gdrive:ComfyUI-Output/outputs',
        'gdrive:ComfyUI-Output/models',
        'gdrive:ComfyUI-Output/workflows'
    ]
    
    # User folders
    users = ['serhii', 'marcin', 'vlad', 'ksenija', 'max', 'ivan']
    for user in users:
        folders.append(f'gdrive:ComfyUI-Output/outputs/{user}')
    
    for folder in folders:
        subprocess.run(['rclone', 'mkdir', folder], capture_output=True)
        print(f"  ✓ {folder.split(':')[1]}")
    
    print("\n✅ Setup complete!")
    print("\n📊 Your Google Drive structure:")
    print("   ComfyUI-Output/")
    print("   ├── outputs/")
    for user in users:
        print(f"   │   ├── {user}/")
    print("   ├── models/")
    print("   └── workflows/")
    
    # Create a flag file to indicate setup is complete
    flag_file = Path('/workspace/.gdrive_configured')
    flag_file.touch()
    
    return True

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 quick_gdrive_setup.py /path/to/service-account.json")
        print("\nExample:")
        print("  python3 quick_gdrive_setup.py ~/service-account.json")
        sys.exit(1)
    
    json_path = sys.argv[1]
    
    if not os.path.exists(json_path):
        print(f"❌ File not found: {json_path}")
        sys.exit(1)
    
    success = setup_gdrive(json_path)
    sys.exit(0 if success else 1)