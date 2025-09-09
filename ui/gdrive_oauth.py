#!/usr/bin/env python3
"""
Google Drive OAuth setup module for automatic configuration
Handles OAuth flow for rclone configuration
"""

import os
import json
import subprocess
import requests
import time
import secrets
from urllib.parse import urlencode, parse_qs
from pathlib import Path

class GDriveOAuth:
    def __init__(self, workspace_dir="/workspace"):
        self.workspace_dir = workspace_dir
        self.rclone_config_file = f"{workspace_dir}/.config/rclone/rclone.conf"
        
        # OAuth endpoints
        self.auth_url = "https://accounts.google.com/o/oauth2/auth"
        self.token_url = "https://oauth2.googleapis.com/token"
        
        # Use rclone's client ID (public, no secret needed)
        # This is the official rclone OAuth app
        self.client_id = "202264815644.apps.googleusercontent.com"
        self.client_secret = ""  # No secret for installed apps
        
        # Scopes needed for Google Drive
        self.scopes = "https://www.googleapis.com/auth/drive"
        
        # Store auth state
        self.auth_state = {}
    
    def get_auth_url(self, redirect_uri="http://localhost:8080"):
        """Generate OAuth authorization URL with localhost redirect"""
        state = secrets.token_urlsafe(32)
        
        params = {
            "client_id": self.client_id,
            "redirect_uri": redirect_uri,
            "response_type": "code",
            "scope": self.scopes,
            "access_type": "offline",
            "prompt": "consent",
            "state": state
        }
        
        auth_url = f"{self.auth_url}?{urlencode(params)}"
        
        # Store state for verification
        self.auth_state[state] = {
            "timestamp": time.time(),
            "redirect_uri": redirect_uri
        }
        
        return auth_url, state
    
    def exchange_code_for_token(self, code, state, redirect_uri="http://localhost:8080"):
        """Exchange authorization code for access token"""
        
        # Verify state
        if state not in self.auth_state:
            return None, "Invalid state parameter"
        
        # Clean up old states (older than 10 minutes)
        current_time = time.time()
        self.auth_state = {
            s: data for s, data in self.auth_state.items() 
            if current_time - data["timestamp"] < 600
        }
        
        data = {
            "code": code,
            "client_id": self.client_id,
            "client_secret": self.client_secret,
            "redirect_uri": redirect_uri,
            "grant_type": "authorization_code"
        }
        
        try:
            response = requests.post(self.token_url, data=data)
            response.raise_for_status()
            token_data = response.json()
            
            # Format token for rclone
            rclone_token = {
                "access_token": token_data.get("access_token"),
                "token_type": token_data.get("token_type", "Bearer"),
                "refresh_token": token_data.get("refresh_token"),
                "expiry": self._calculate_expiry(token_data.get("expires_in", 3599))
            }
            
            return rclone_token, None
        except Exception as e:
            return None, str(e)
    
    def _calculate_expiry(self, expires_in):
        """Calculate token expiry time in rclone format"""
        from datetime import datetime, timedelta
        expiry = datetime.now() + timedelta(seconds=expires_in)
        return expiry.isoformat() + "Z"
    
    def save_rclone_config(self, token, remote_name="gdrive"):
        """Save rclone configuration with OAuth token"""
        try:
            # Create config directory
            config_dir = os.path.dirname(self.rclone_config_file)
            os.makedirs(config_dir, exist_ok=True)
            
            # Create rclone config
            config = f"""[{remote_name}]
type = drive
scope = drive
token = {json.dumps(token)}
team_drive = 
root_folder_id = 

"""
            
            # Check if config already exists
            existing_config = ""
            if os.path.exists(self.rclone_config_file):
                with open(self.rclone_config_file, 'r') as f:
                    existing_config = f.read()
                
                # Remove existing gdrive config if present
                import re
                existing_config = re.sub(
                    r'\[gdrive\].*?(?=\[|$)', 
                    '', 
                    existing_config, 
                    flags=re.DOTALL
                )
            
            # Write new config
            with open(self.rclone_config_file, 'w') as f:
                f.write(existing_config + config)
            
            # Test configuration
            result = subprocess.run(
                ['rclone', 'lsd', f'{remote_name}:'],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode == 0:
                # Create folder structure
                self.create_folder_structure(remote_name)
                return True, "Configuration saved successfully"
            else:
                return False, f"Configuration test failed: {result.stderr}"
                
        except Exception as e:
            return False, str(e)
    
    def create_folder_structure(self, remote_name="gdrive"):
        """Create ComfyUI-Output folder structure on Google Drive"""
        try:
            base_path = f"{remote_name}:ComfyUI-Output"
            
            # Create base folders
            folders = [
                f"{base_path}/outputs",
                f"{base_path}/models",
                f"{base_path}/workflows"
            ]
            
            # Create user folders
            users = ["serhii", "marcin", "vlad", "ksenija", "max", "ivan"]
            for user in users:
                folders.append(f"{base_path}/outputs/{user}")
            
            # Create all folders
            for folder in folders:
                subprocess.run(
                    ['rclone', 'mkdir', folder],
                    capture_output=True,
                    timeout=5
                )
            
            return True
        except Exception as e:
            print(f"Error creating folder structure: {e}")
            return False
    
    def get_simple_auth_instructions(self):
        """Get simple instructions for manual setup"""
        auth_url, state = self.get_auth_url()
        
        instructions = {
            "step1": "Click the link below to authorize Google Drive access",
            "auth_url": auth_url,
            "step2": "Sign in with your Google account",
            "step3": "Copy the authorization code",
            "step4": "Paste the code in the input field",
            "state": state
        }
        
        return instructions
    
    def setup_from_service_account(self, service_account_json):
        """Setup using service account credentials (for automated setup)"""
        try:
            # Parse service account JSON
            sa_data = json.loads(service_account_json)
            
            # Create rclone config for service account
            config = f"""[gdrive]
type = drive
scope = drive
service_account_file = {self.workspace_dir}/.config/rclone/service_account.json
team_drive = 

"""
            
            # Save service account file
            sa_path = f"{self.workspace_dir}/.config/rclone/service_account.json"
            os.makedirs(os.path.dirname(sa_path), exist_ok=True)
            
            with open(sa_path, 'w') as f:
                json.dump(sa_data, f)
            
            # Save rclone config
            with open(self.rclone_config_file, 'w') as f:
                f.write(config)
            
            # Test configuration
            result = subprocess.run(
                ['rclone', 'lsd', 'gdrive:'],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode == 0:
                self.create_folder_structure()
                return True, "Service account configured successfully"
            else:
                return False, f"Configuration test failed: {result.stderr}"
                
        except Exception as e:
            return False, str(e)
    
    def check_existing_config(self):
        """Check if rclone is already configured"""
        try:
            if not os.path.exists(self.rclone_config_file):
                return False, "No configuration found"
            
            # Check if gdrive remote exists
            result = subprocess.run(
                ['rclone', 'listremotes'],
                capture_output=True,
                text=True
            )
            
            if "gdrive:" in result.stdout:
                # Test if it works
                test = subprocess.run(
                    ['rclone', 'lsd', 'gdrive:'],
                    capture_output=True,
                    text=True,
                    timeout=10
                )
                
                if test.returncode == 0:
                    return True, "Google Drive is already configured and working"
                else:
                    return False, "Google Drive is configured but not working"
            else:
                return False, "Google Drive remote not found"
                
        except Exception as e:
            return False, str(e)