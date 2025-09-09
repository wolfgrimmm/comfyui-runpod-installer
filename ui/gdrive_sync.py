#!/usr/bin/env python3
"""
Google Drive sync module for ComfyUI
Handles syncing output folders with Google Drive using rclone
"""

import os
import subprocess
import json
import time
import threading
from pathlib import Path
from datetime import datetime

class GDriveSync:
    def __init__(self, workspace_dir="/workspace"):
        self.workspace_dir = workspace_dir
        self.comfyui_dir = f"{workspace_dir}/ComfyUI"
        self.output_base = f"{workspace_dir}/output"
        self.input_base = f"{workspace_dir}/input"
        self.workflows_base = f"{workspace_dir}/workflows"
        self.gdrive_remote = "gdrive"
        self.sync_status = {}
        self.sync_threads = {}
        self.rclone_config_file = f"{workspace_dir}/.config/rclone/rclone.conf"
        
        # Company Google Drive root folder
        self.company_drive_root = "ComfyUI-Output"
        
        # Check if rclone is installed
        self.rclone_available = self.check_rclone()
        
    def check_rclone(self):
        """Check if rclone is installed and configured"""
        try:
            # Check if rclone command exists
            result = subprocess.run(['which', 'rclone'], capture_output=True, text=True)
            if result.returncode != 0:
                return False
            
            # Check if gdrive remote is configured
            result = subprocess.run(['rclone', 'listremotes'], capture_output=True, text=True)
            return f"{self.gdrive_remote}:" in result.stdout
        except:
            return False
    
    def install_rclone(self):
        """Install rclone if not present"""
        try:
            # Download and install rclone
            cmd = "curl https://rclone.org/install.sh | bash"
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
            return result.returncode == 0
        except Exception as e:
            print(f"Error installing rclone: {e}")
            return False
    
    def configure_rclone(self, config_data):
        """Configure rclone with provided credentials"""
        try:
            # Create config directory
            config_dir = os.path.dirname(self.rclone_config_file)
            os.makedirs(config_dir, exist_ok=True)
            
            # Write config file
            config_content = f"""[{self.gdrive_remote}]
type = drive
scope = drive
token = {json.dumps(config_data.get('token', {}))}
team_drive = {config_data.get('team_drive', '')}
"""
            
            with open(self.rclone_config_file, 'w') as f:
                f.write(config_content)
            
            # Test configuration
            result = subprocess.run(
                ['rclone', 'lsd', f'{self.gdrive_remote}:'],
                capture_output=True, text=True
            )
            return result.returncode == 0
        except Exception as e:
            print(f"Error configuring rclone: {e}")
            return False
    
    def get_oauth_url(self):
        """Get OAuth URL for Google Drive authentication"""
        try:
            # Run rclone config create with OAuth flow
            cmd = [
                'rclone', 'config', 'create', self.gdrive_remote, 'drive',
                'scope', 'drive', '--non-interactive'
            ]
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            # Extract OAuth URL from output
            for line in result.stderr.split('\n'):
                if 'https://accounts.google.com/o/oauth2/' in line:
                    return line.strip()
            
            return None
        except Exception as e:
            print(f"Error getting OAuth URL: {e}")
            return None
    
    def sync_user_output(self, username, direction='to_gdrive'):
        """Sync user's output folder with Google Drive"""
        if not self.rclone_available:
            return False, "rclone not configured"
        
        user_output = f"{self.output_base}/{username}"
        # All users sync to company Drive with user subfolders
        gdrive_path = f"{self.gdrive_remote}:{self.company_drive_root}/outputs/{username}"
        
        # Set sync status
        self.sync_status[username] = {
            'status': 'syncing',
            'direction': direction,
            'start_time': time.time()
        }
        
        try:
            if direction == 'to_gdrive':
                # Upload to Google Drive
                cmd = ['rclone', 'sync', user_output, gdrive_path, '--progress']
            else:
                # Download from Google Drive
                cmd = ['rclone', 'sync', gdrive_path, user_output, '--progress']
            
            # Run sync in thread
            thread = threading.Thread(
                target=self._run_sync,
                args=(cmd, username, direction)
            )
            thread.start()
            self.sync_threads[username] = thread
            
            return True, f"Sync started for {username}"
        except Exception as e:
            self.sync_status[username] = {
                'status': 'error',
                'error': str(e),
                'end_time': time.time()
            }
            return False, str(e)
    
    def _run_sync(self, cmd, username, direction):
        """Run sync command in background"""
        try:
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                self.sync_status[username] = {
                    'status': 'completed',
                    'direction': direction,
                    'end_time': time.time(),
                    'output': result.stdout
                }
            else:
                self.sync_status[username] = {
                    'status': 'error',
                    'direction': direction,
                    'error': result.stderr,
                    'end_time': time.time()
                }
        except Exception as e:
            self.sync_status[username] = {
                'status': 'error',
                'direction': direction,
                'error': str(e),
                'end_time': time.time()
            }
    
    def sync_all_users(self, users, direction='to_gdrive'):
        """Sync all users' output folders"""
        results = {}
        for user in users:
            success, message = self.sync_user_output(user, direction)
            results[user] = {'success': success, 'message': message}
        return results
    
    def mount_gdrive(self, mount_point=None):
        """Mount Google Drive as filesystem"""
        if not self.rclone_available:
            return False, "rclone not configured"
        
        if mount_point is None:
            mount_point = f"{self.workspace_dir}/gdrive"
        
        try:
            # Create mount point
            os.makedirs(mount_point, exist_ok=True)
            
            # Mount Google Drive folder
            cmd = [
                'rclone', 'mount',
                f'{self.gdrive_remote}:{self.company_drive_root}',
                mount_point,
                '--daemon',
                '--allow-non-empty',
                '--vfs-cache-mode', 'writes'
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                return True, f"Google Drive mounted at {mount_point}"
            else:
                return False, result.stderr
        except Exception as e:
            return False, str(e)
    
    def unmount_gdrive(self, mount_point=None):
        """Unmount Google Drive"""
        if mount_point is None:
            mount_point = f"{self.workspace_dir}/gdrive"
        
        try:
            # Try fusermount first
            result = subprocess.run(
                ['fusermount', '-u', mount_point],
                capture_output=True, text=True
            )
            
            if result.returncode != 0:
                # Fallback to umount
                result = subprocess.run(
                    ['umount', mount_point],
                    capture_output=True, text=True
                )
            
            return result.returncode == 0, "Unmounted successfully"
        except Exception as e:
            return False, str(e)
    
    def get_sync_status(self, username=None):
        """Get sync status for user or all users"""
        if username:
            return self.sync_status.get(username, {'status': 'idle'})
        return self.sync_status
    
    def list_gdrive_files(self, path=''):
        """List files in Google Drive"""
        if not self.rclone_available:
            return None, "rclone not configured"
        
        try:
            full_path = f"{self.gdrive_remote}:{self.company_drive_root}/{path}" if path else f"{self.gdrive_remote}:{self.company_drive_root}"
            cmd = ['rclone', 'lsjson', full_path]
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                files = json.loads(result.stdout)
                return files, None
            else:
                return None, result.stderr
        except Exception as e:
            return None, str(e)
    
    def create_symlink_to_gdrive(self, username):
        """Create symlink from user output folder to Google Drive mount"""
        if not os.path.exists(f"{self.workspace_dir}/gdrive"):
            success, message = self.mount_gdrive()
            if not success:
                return False, f"Failed to mount Google Drive: {message}"
        
        try:
            user_output = f"{self.output_base}/{username}"
            # Google Drive structure with user folders
            gdrive_output = f"{self.workspace_dir}/gdrive/outputs/{username}"
            
            # Create Google Drive directory if it doesn't exist
            os.makedirs(gdrive_output, exist_ok=True)
            
            # Remove existing directory and create symlink
            if os.path.exists(user_output) and not os.path.islink(user_output):
                # Backup existing files
                backup_dir = f"{user_output}_backup_{int(time.time())}"
                os.rename(user_output, backup_dir)
            
            # Create symlink
            if os.path.islink(user_output):
                os.unlink(user_output)
            
            os.symlink(gdrive_output, user_output)
            
            return True, f"Symlink created: {user_output} -> {gdrive_output}"
        except Exception as e:
            return False, str(e)
    
    def setup_auto_sync(self, interval_minutes=1):
        """Setup automatic sync to Google Drive with smart sync"""
        try:
            # Create sync script with incremental sync and performance optimizations
            sync_script = f"""#!/bin/bash
# Auto-sync ComfyUI outputs to Google Drive with smart sync
LAST_SYNC_FILE="/tmp/last_gdrive_sync"
MIN_INTERVAL={interval_minutes}

while true; do
    for user_dir in {self.output_base}/*/; do
        if [ -d "$user_dir" ]; then
            username=$(basename "$user_dir")
            
            # Check if files changed since last sync
            if [ -f "$LAST_SYNC_FILE.$username" ]; then
                changed=$(find "$user_dir" -newer "$LAST_SYNC_FILE.$username" -type f | head -1)
                if [ -z "$changed" ]; then
                    echo "No changes for $username, skipping sync"
                    continue
                fi
            fi
            
            echo "Syncing $username outputs to Google Drive..."
            # Use incremental sync with bandwidth limit and minimal checks
            rclone sync "$user_dir" "{self.gdrive_remote}:{self.company_drive_root}/outputs/$username" \\
                --exclude "*.tmp" \\
                --exclude "*.partial" \\
                --transfers 4 \\
                --checkers 2 \\
                --bwlimit 50M \\
                --fast-list \\
                --min-age 5s
            
            # Mark last sync time
            touch "$LAST_SYNC_FILE.$username"
        fi
    done
    sleep {interval_minutes * 60}
done
"""
            
            script_path = f"{self.workspace_dir}/scripts/auto_sync_gdrive.sh"
            os.makedirs(os.path.dirname(script_path), exist_ok=True)
            
            with open(script_path, 'w') as f:
                f.write(sync_script)
            
            os.chmod(script_path, 0o755)
            
            # Start sync in background
            subprocess.Popen([script_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            
            return True, f"Auto-sync started (every {interval_minutes} minutes)"
        except Exception as e:
            return False, str(e)
    
    def get_storage_stats(self, username=None):
        """Get storage statistics for Google Drive"""
        if not self.rclone_available:
            return None, "rclone not configured"
        
        try:
            if username:
                path = f"{self.gdrive_remote}:{self.company_drive_root}/outputs/{username}"
            else:
                path = f"{self.gdrive_remote}:{self.company_drive_root}"
            
            cmd = ['rclone', 'size', path, '--json']
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                stats = json.loads(result.stdout)
                return {
                    'total_size': stats.get('bytes', 0),
                    'total_files': stats.get('count', 0),
                    'human_size': self._format_bytes(stats.get('bytes', 0))
                }, None
            else:
                return None, result.stderr
        except Exception as e:
            return None, str(e)
    
    def _format_bytes(self, bytes):
        """Format bytes to human readable size"""
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if bytes < 1024.0:
                return f"{bytes:.2f} {unit}"
            bytes /= 1024.0
        return f"{bytes:.2f} PB"