#!/usr/bin/env python3
"""
S3 Storage module for ComfyUI
Handles direct S3 access using RunPod's S3-compatible API
"""

import os
import subprocess
import json
import time
import threading
from pathlib import Path
from datetime import datetime

class S3Storage:
    def __init__(self, workspace_dir="/workspace"):
        self.workspace_dir = workspace_dir
        self.output_base = f"{workspace_dir}/output"
        self.input_base = f"{workspace_dir}/input"
        self.workflows_base = f"{workspace_dir}/workflows"
        
        # RunPod S3 configuration
        self.s3_endpoint = os.environ.get('RUNPOD_S3_ENDPOINT', 'https://s3api-eu-ro-1.runpod.io')
        self.s3_access_key = os.environ.get('RUNPOD_S3_ACCESS_KEY')
        self.s3_secret_key = os.environ.get('RUNPOD_S3_SECRET_KEY')
        self.s3_bucket = os.environ.get('RUNPOD_S3_BUCKET', '3nyrlhftk8')
        self.s3_region = os.environ.get('RUNPOD_S3_REGION', 'eu-ro-1')
        
        # Check if S3FS is installed
        self.s3fs_available = self.check_s3fs()
        self.rclone_available = self.check_rclone()
        
        # Track active mounts
        self.active_mounts = {}
        
    def check_s3fs(self):
        """Check if S3FS is installed"""
        try:
            result = subprocess.run(['which', 's3fs'], capture_output=True, text=True)
            return result.returncode == 0
        except:
            return False
    
    def check_rclone(self):
        """Check if rclone is installed"""
        try:
            result = subprocess.run(['which', 'rclone'], capture_output=True, text=True)
            return result.returncode == 0
        except:
            return False
    
    def is_s3_configured(self):
        """Check if S3 credentials are configured"""
        return bool(self.s3_access_key and self.s3_secret_key)
    
    def create_s3fs_password_file(self):
        """Create S3FS password file"""
        try:
            s3fs_passwd_file = f"{self.workspace_dir}/.s3fs_passwd"
            with open(s3fs_passwd_file, 'w') as f:
                f.write(f"{self.s3_access_key}:{self.s3_secret_key}")
            os.chmod(s3fs_passwd_file, 0o600)
            return s3fs_passwd_file
        except Exception as e:
            raise Exception(f"Failed to create S3FS password file: {str(e)}")
    
    def create_s3_output_symlink(self, username):
        """Create symlink using S3FS to mount RunPod S3 storage directly"""
        if not self.is_s3_configured():
            return False, "S3 credentials not configured. Please set RUNPOD_S3_ACCESS_KEY and RUNPOD_S3_SECRET_KEY environment variables."
        
        if not self.s3fs_available:
            return False, "S3FS not installed. Please install s3fs package."
        
        try:
            # 1. Create S3FS password file
            s3fs_passwd_file = self.create_s3fs_password_file()
            
            # 2. Create mount point for user's output folder
            user_mount_point = f"{self.workspace_dir}/s3_{username}"
            os.makedirs(user_mount_point, exist_ok=True)
            
            # 3. Check if already mounted
            if os.path.ismount(user_mount_point):
                return False, f"S3 mount already exists at {user_mount_point}"
            
            # 4. Mount S3 bucket using S3FS
            mount_cmd = [
                's3fs', self.s3_bucket,
                user_mount_point,
                '-o', f'passwd_file={s3fs_passwd_file}',
                '-o', f'url={self.s3_endpoint}',
                '-o', 'use_path_request_style',
                '-o', 'allow_other',
                '-o', 'umask=000',
                '-o', 'retries=5',
                '-o', 'cache=/tmp/s3fs_cache',
                '-o', f'region={self.s3_region}',
                '-o', 'multipart_size=10485760',  # 10MB chunks
                '-o', 'parallel_count=4',
                '-o', 'max_stat_cache_size=100000'
            ]
            
            print(f"Mounting S3 bucket {self.s3_bucket} to {user_mount_point}")
            result = subprocess.run(mount_cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                # 5. Create user output directory in S3 mount
                s3_output_path = f"{user_mount_point}/output/{username}"
                os.makedirs(s3_output_path, exist_ok=True)
                
                # 6. Backup existing local folder
                local_output = f"{self.output_base}/{username}"
                if os.path.exists(local_output) and not os.path.islink(local_output):
                    backup_dir = f"{local_output}_backup_{int(time.time())}"
                    os.rename(local_output, backup_dir)
                    print(f"Backed up existing folder to: {backup_dir}")
                
                # 7. Create symlink
                if os.path.islink(local_output):
                    os.unlink(local_output)
                
                os.symlink(s3_output_path, local_output)
                
                # 8. Track active mount
                self.active_mounts[username] = {
                    'mount_point': user_mount_point,
                    's3_path': s3_output_path,
                    'local_path': local_output,
                    'created_at': time.time()
                }
                
                return True, f"S3 symlink created: {local_output} -> {s3_output_path}"
            else:
                return False, f"S3FS mount failed: {result.stderr}"
                
        except Exception as e:
            return False, f"Failed to create S3 symlink: {str(e)}"
    
    def create_rclone_s3_symlink(self, username):
        """Create symlink using rclone to mount S3 storage"""
        if not self.is_s3_configured():
            return False, "S3 credentials not configured"
        
        if not self.rclone_available:
            return False, "rclone not installed"
        
        try:
            # 1. Configure rclone for S3
            s3_config = f"""[s3]
type = s3
provider = Other
access_key_id = {self.s3_access_key}
secret_access_key = {self.s3_secret_key}
endpoint = {self.s3_endpoint}
region = {self.s3_region}
"""
            
            config_file = f"{self.workspace_dir}/.config/rclone/rclone.conf"
            os.makedirs(os.path.dirname(config_file), exist_ok=True)
            
            # Append to existing config or create new
            if os.path.exists(config_file):
                with open(config_file, 'r') as f:
                    existing_config = f.read()
                if '[s3]' not in existing_config:
                    with open(config_file, 'a') as f:
                        f.write(s3_config)
            else:
                with open(config_file, 'w') as f:
                    f.write(s3_config)
            
            # 2. Mount S3 bucket
            user_mount_point = f"{self.workspace_dir}/s3_{username}"
            os.makedirs(user_mount_point, exist_ok=True)
            
            mount_cmd = [
                'rclone', 'mount',
                f"s3:{self.s3_bucket}/output/{username}",
                user_mount_point,
                '--daemon',
                '--vfs-cache-mode', 'writes',
                '--vfs-cache-max-size', '1G',
                '--allow-other',
                '--config', config_file
            ]
            
            result = subprocess.run(mount_cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                # Create symlink
                local_output = f"{self.output_base}/{username}"
                if os.path.exists(local_output) and not os.path.islink(local_output):
                    backup_dir = f"{local_output}_backup_{int(time.time())}"
                    os.rename(local_output, backup_dir)
                
                if os.path.islink(local_output):
                    os.unlink(local_output)
                
                os.symlink(user_mount_point, local_output)
                
                # Track active mount
                self.active_mounts[username] = {
                    'mount_point': user_mount_point,
                    's3_path': f"s3:{self.s3_bucket}/output/{username}",
                    'local_path': local_output,
                    'created_at': time.time(),
                    'method': 'rclone'
                }
                
                return True, f"Rclone S3 symlink created: {local_output} -> {user_mount_point}"
            else:
                return False, f"Rclone S3 mount failed: {result.stderr}"
                
        except Exception as e:
            return False, f"Failed to create rclone S3 symlink: {str(e)}"
    
    def unmount_s3(self, username):
        """Unmount S3 storage for user"""
        if username not in self.active_mounts:
            return False, f"No active S3 mount found for user {username}"
        
        try:
            mount_info = self.active_mounts[username]
            mount_point = mount_info['mount_point']
            
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
            
            if result.returncode == 0:
                # Remove symlink
                local_output = f"{self.output_base}/{username}"
                if os.path.islink(local_output):
                    os.unlink(local_output)
                
                # Remove mount point
                if os.path.exists(mount_point):
                    os.rmdir(mount_point)
                
                # Remove from active mounts
                del self.active_mounts[username]
                
                return True, f"S3 mount unmounted for user {username}"
            else:
                return False, f"Failed to unmount: {result.stderr}"
                
        except Exception as e:
            return False, f"Failed to unmount S3: {str(e)}"
    
    def get_s3_status(self):
        """Get S3 storage status"""
        return {
            'configured': self.is_s3_configured(),
            's3fs_available': self.s3fs_available,
            'rclone_available': self.rclone_available,
            'endpoint': self.s3_endpoint,
            'bucket': self.s3_bucket,
            'region': self.s3_region,
            'active_mounts': len(self.active_mounts),
            'mounts': self.active_mounts
        }
    
    def test_s3_connection(self):
        """Test S3 connection"""
        if not self.is_s3_configured():
            return False, "S3 credentials not configured"
        
        try:
            # Test with AWS CLI if available
            test_cmd = [
                'aws', 's3', 'ls',
                f's3://{self.s3_bucket}',
                '--region', self.s3_region,
                '--endpoint-url', self.s3_endpoint
            ]
            
            result = subprocess.run(test_cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                return True, "S3 connection successful"
            else:
                return False, f"S3 connection failed: {result.stderr}"
                
        except Exception as e:
            return False, f"S3 connection test failed: {str(e)}"
