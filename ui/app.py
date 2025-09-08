#!/usr/bin/env python3
"""
Simple UI for ComfyUI user selection and startup
Single user per pod model - no conflicts
"""

from flask import Flask, render_template, request, jsonify, redirect
import os
import subprocess
import json
import time
from pathlib import Path

app = Flask(__name__)

# Configuration
WORKSPACE_DIR = "/workspace"
COMFYUI_DIR = "/app/ComfyUI"  # ComfyUI is installed in /app
INPUT_BASE = f"{WORKSPACE_DIR}/input"
OUTPUT_BASE = f"{WORKSPACE_DIR}/output"
USERS_FILE = f"{WORKSPACE_DIR}/users.json"
CURRENT_USER_FILE = f"{WORKSPACE_DIR}/.current_user"

class ComfyUIManager:
    def __init__(self):
        self.comfyui_process = None
        self.current_user = None
        self.init_system()
    
    def init_system(self):
        """Initialize directories and default users"""
        os.makedirs(INPUT_BASE, exist_ok=True)
        os.makedirs(OUTPUT_BASE, exist_ok=True)
        
        # Load or create users list
        if os.path.exists(USERS_FILE):
            with open(USERS_FILE, 'r') as f:
                self.users = json.load(f)
        else:
            # Default users
            self.users = ["serhii", "artist", "guest"]
            self.save_users()
        
        # Check if user was previously selected
        if os.path.exists(CURRENT_USER_FILE):
            with open(CURRENT_USER_FILE, 'r') as f:
                self.current_user = f.read().strip()
    
    def save_users(self):
        """Save users list"""
        with open(USERS_FILE, 'w') as f:
            json.dump(self.users, f)
    
    def add_user(self, username):
        """Add a new user"""
        username = username.strip().lower()
        if username and username not in self.users:
            self.users.append(username)
            self.save_users()
            self.setup_user_folders(username)
            return True
        return False
    
    def setup_user_folders(self, username):
        """Create user folders"""
        os.makedirs(f"{INPUT_BASE}/{username}", exist_ok=True)
        os.makedirs(f"{OUTPUT_BASE}/{username}", exist_ok=True)
        print(f"Created folders for user: {username}")
    
    def setup_symlinks(self, username):
        """Setup ComfyUI symlinks to user folders"""
        # Remove existing input/output in ComfyUI
        comfy_input = f"{COMFYUI_DIR}/input"
        comfy_output = f"{COMFYUI_DIR}/output"
        
        for path in [comfy_input, comfy_output]:
            if os.path.islink(path):
                os.unlink(path)
            elif os.path.exists(path):
                # Backup existing folder
                backup = f"{path}_backup"
                if os.path.exists(backup):
                    os.system(f"rm -rf {backup}")
                os.rename(path, backup)
        
        # Create symlinks to user folders
        user_input = f"{INPUT_BASE}/{username}"
        user_output = f"{OUTPUT_BASE}/{username}"
        
        os.symlink(user_input, comfy_input)
        os.symlink(user_output, comfy_output)
        
        print(f"Symlinks created: ComfyUI input/output -> {username} folders")
    
    def start_comfyui(self, username):
        """Start ComfyUI for specified user"""
        if self.is_comfyui_running():
            return False, "ComfyUI is already running"
        
        # Setup user
        username = username.strip().lower()
        if username not in self.users:
            self.add_user(username)
        
        self.setup_user_folders(username)
        self.setup_symlinks(username)
        
        # Save current user
        self.current_user = username
        with open(CURRENT_USER_FILE, 'w') as f:
            f.write(username)
        
        # Kill any existing process on port 8188
        os.system("fuser -k 8188/tcp 2>/dev/null || true")
        time.sleep(1)
        
        # Start ComfyUI
        try:
            self.comfyui_process = subprocess.Popen(
                ["/app/start_comfyui.sh"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={**os.environ, "COMFYUI_USER": username}
            )
            
            # Wait a bit for startup
            time.sleep(3)
            
            if self.comfyui_process.poll() is None:
                return True, "ComfyUI started successfully"
            else:
                return False, "ComfyUI failed to start"
        except Exception as e:
            return False, str(e)
    
    def stop_comfyui(self):
        """Stop ComfyUI"""
        if self.comfyui_process:
            self.comfyui_process.terminate()
            time.sleep(1)
            if self.comfyui_process.poll() is None:
                self.comfyui_process.kill()
            self.comfyui_process = None
        
        # Kill any remaining process on port
        os.system("fuser -k 8188/tcp 2>/dev/null || true")
        return True
    
    def is_comfyui_running(self):
        """Check if ComfyUI is running"""
        if self.comfyui_process and self.comfyui_process.poll() is None:
            return True
        
        # Check port
        result = os.system("lsof -i:8188 >/dev/null 2>&1")
        return result == 0
    
    def get_status(self):
        """Get current status"""
        return {
            "running": self.is_comfyui_running(),
            "current_user": self.current_user,
            "users": self.users
        }

# Initialize manager
manager = ComfyUIManager()

@app.route('/')
def index():
    """Main UI page"""
    status = manager.get_status()
    return render_template('index.html', **status)

@app.route('/api/start', methods=['POST'])
def start_comfyui():
    """Start ComfyUI for user"""
    data = request.json
    username = data.get('username', '').strip().lower()
    
    if not username:
        return jsonify({"success": False, "error": "Username required"}), 400
    
    success, message = manager.start_comfyui(username)
    return jsonify({"success": success, "message": message})

@app.route('/api/stop', methods=['POST'])
def stop_comfyui():
    """Stop ComfyUI"""
    manager.stop_comfyui()
    return jsonify({"success": True, "message": "ComfyUI stopped"})

@app.route('/api/status')
def get_status():
    """Get current status"""
    return jsonify(manager.get_status())

@app.route('/api/add_user', methods=['POST'])
def add_user():
    """Add new user"""
    data = request.json
    username = data.get('username', '').strip().lower()
    
    if not username:
        return jsonify({"success": False, "error": "Username required"}), 400
    
    if manager.add_user(username):
        return jsonify({"success": True, "message": f"User {username} added"})
    else:
        return jsonify({"success": False, "error": "User already exists"}), 400

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=7777, debug=False)