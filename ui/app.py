#!/usr/bin/env python3
"""
ComfyUI Control Panel - Modern UI for user selection and system management
Single user per pod model with resource monitoring
"""

from flask import Flask, render_template, request, jsonify, redirect
import os
import subprocess
import json
import time
import psutil
from pathlib import Path

app = Flask(__name__)

# Configuration
WORKSPACE_DIR = "/workspace"
COMFYUI_DIR = f"{WORKSPACE_DIR}/ComfyUI"  # ComfyUI is in /workspace/ComfyUI
INPUT_BASE = f"{WORKSPACE_DIR}/input"
OUTPUT_BASE = f"{WORKSPACE_DIR}/output"
WORKFLOWS_BASE = f"{WORKSPACE_DIR}/workflows"
USERS_FILE = f"{WORKSPACE_DIR}/user_data/users.json"
CURRENT_USER_FILE = f"{WORKSPACE_DIR}/user_data/.current_user"
START_TIME_FILE = f"{WORKSPACE_DIR}/user_data/.start_time"

class ComfyUIManager:
    def __init__(self):
        self.comfyui_process = None
        self.current_user = None
        self.start_time = None
        self.auto_update = False  # Not used but kept for compatibility
        self.init_system()
    
    def init_system(self):
        """Initialize directories and default users"""
        os.makedirs(INPUT_BASE, exist_ok=True)
        os.makedirs(OUTPUT_BASE, exist_ok=True)
        os.makedirs(f"{WORKSPACE_DIR}/user_data", exist_ok=True)
        
        # Load or create users list
        if os.path.exists(USERS_FILE):
            with open(USERS_FILE, 'r') as f:
                self.users = json.load(f)
        else:
            # Default users
            self.users = ["serhii", "marcin", "vlad", "ksenija", "max", "ivan"]
            self.save_users()
        
        # Check if user was previously selected
        if os.path.exists(CURRENT_USER_FILE):
            with open(CURRENT_USER_FILE, 'r') as f:
                self.current_user = f.read().strip()
        
        # Check if ComfyUI is running and load start time
        if self.is_comfyui_running():
            if os.path.exists(START_TIME_FILE):
                try:
                    with open(START_TIME_FILE, 'r') as f:
                        self.start_time = float(f.read().strip())
                except:
                    self.start_time = time.time()
            else:
                self.start_time = time.time()
                with open(START_TIME_FILE, 'w') as f:
                    f.write(str(self.start_time))
    
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
        os.makedirs(f"{WORKFLOWS_BASE}/{username}", exist_ok=True)
        print(f"Created folders for user: {username}")
    
    def setup_symlinks(self, username):
        """Setup ComfyUI symlinks to user folders"""
        # Define paths
        comfy_input = f"{COMFYUI_DIR}/input"
        comfy_output = f"{COMFYUI_DIR}/output"
        comfy_workflows = f"{COMFYUI_DIR}/user/workflows"
        
        # Remove existing symlinks/directories
        for path in [comfy_input, comfy_output, comfy_workflows]:
            if os.path.islink(path) or os.path.exists(path):
                os.system(f"rm -rf {path}")
        
        # Create user folders if they don't exist
        user_input = f"{INPUT_BASE}/{username}"
        user_output = f"{OUTPUT_BASE}/{username}"
        user_workflows = f"{WORKFLOWS_BASE}/{username}"
        os.makedirs(user_input, exist_ok=True)
        os.makedirs(user_output, exist_ok=True)
        os.makedirs(user_workflows, exist_ok=True)
        
        # Ensure parent directory exists for workflows
        os.makedirs(f"{COMFYUI_DIR}/user", exist_ok=True)
        
        # Create symlinks to user folders
        os.symlink(user_input, comfy_input)
        os.symlink(user_output, comfy_output)
        os.symlink(user_workflows, comfy_workflows)
        
        print(f"Symlinks created: ComfyUI input/output/workflows -> {username} folders")
    
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
        try:
            os.system("fuser -k 8188/tcp 2>/dev/null || true")
        except:
            # Try alternative method if fuser not available
            os.system("pkill -f 'python.*main.py.*8188' || true")
        time.sleep(1)
        
        # Start ComfyUI
        try:
            # Always ensure ComfyUI is installed first
            if not os.path.exists("/workspace/ComfyUI/main.py"):
                print("ComfyUI not found, running init script...")
                result = os.system("/app/init_workspace.sh")
                if result != 0:
                    return False, "Failed to initialize workspace"
                
                # Double-check it was installed
                if not os.path.exists("/workspace/ComfyUI/main.py"):
                    return False, "ComfyUI installation failed - main.py not found"
            
            # Check if script exists
            script_path = "/app/start_comfyui.sh"
            if not os.path.exists(script_path):
                # Fallback to direct command
                cmd = ["python", "/workspace/ComfyUI/main.py", "--listen", "0.0.0.0", "--port", "8188"]
            else:
                cmd = [script_path]
            
            self.comfyui_process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={**os.environ, "COMFYUI_USER": username},
                cwd="/workspace/ComfyUI"
            )
            
            # Wait for ComfyUI to actually start listening
            max_wait = 60  # Increased to 60 seconds for full initialization
            for i in range(max_wait):
                time.sleep(1)
                
                # Check if process died
                if self.comfyui_process.poll() is not None:
                    stderr = self.comfyui_process.stderr.read().decode() if self.comfyui_process.stderr else ""
                    return False, f"ComfyUI process died: {stderr[:200]}"
                
                # Check if port is listening
                if self.is_comfyui_running():
                    # More thorough check - try to actually get a valid response
                    import urllib.request
                    import urllib.error
                    consecutive_success = 0
                    required_success = 3  # Need 3 consecutive successful checks
                    
                    for retry in range(5):
                        try:
                            response = urllib.request.urlopen('http://127.0.0.1:8188', timeout=2)
                            if response.getcode() in [200, 301, 302]:
                                consecutive_success += 1
                                if consecutive_success >= required_success:
                                    # ComfyUI is consistently responding
                                    print(f"ComfyUI fully initialized after {i+1} seconds")
                                    self.start_time = time.time()
                                    # Save start time to file
                                    with open(START_TIME_FILE, 'w') as f:
                                        f.write(str(self.start_time))
                                    return True, "ComfyUI started successfully"
                            time.sleep(0.5)
                        except urllib.error.HTTPError as e:
                            if e.code in [301, 302]:  # Redirects are OK
                                consecutive_success += 1
                                if consecutive_success >= required_success:
                                    print(f"ComfyUI fully initialized after {i+1} seconds")
                                    self.start_time = time.time()
                                    # Save start time to file
                                    with open(START_TIME_FILE, 'w') as f:
                                        f.write(str(self.start_time))
                                    return True, "ComfyUI started successfully"
                        except:
                            consecutive_success = 0  # Reset on failure
                            time.sleep(0.5)
                
                # Show progress
                if i % 5 == 0:
                    print(f"Waiting for ComfyUI to start... {i}s")
            
            return False, "ComfyUI took too long to start (60s timeout)"
        except Exception as e:
            return False, f"Error starting ComfyUI: {str(e)}"
    
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
        
        # Clear start time
        self.start_time = None
        if os.path.exists(START_TIME_FILE):
            os.remove(START_TIME_FILE)
        
        return True
    
    def is_comfyui_running(self):
        """Check if ComfyUI is running"""
        # First check our process handle
        if self.comfyui_process and self.comfyui_process.poll() is None:
            return True
        
        # Check if port 8188 is actually listening
        import socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            result = sock.connect_ex(('127.0.0.1', 8188))
            sock.close()
            return result == 0
        except:
            return False
    
    def get_status(self):
        """Get current status"""
        is_running = self.is_comfyui_running()
        return {
            "running": is_running,
            "ready": is_running,  # Additional ready check
            "current_user": self.current_user,
            "users": self.users,
            "uptime": self.get_uptime() if is_running and self.start_time else "0m",
            "start_time": self.start_time  # Pass timestamp for JS
        }
    
    def get_uptime(self):
        """Get uptime in human-readable format"""
        if not self.start_time:
            return "0m"
        
        elapsed = time.time() - self.start_time
        hours = int(elapsed // 3600)
        minutes = int((elapsed % 3600) // 60)
        
        if hours > 0:
            return f"{hours}h {minutes}m"
        return f"{minutes}m"
    
    def get_resource_usage(self):
        """Get system resource usage"""
        try:
            memory = psutil.virtual_memory()
            disk = psutil.disk_usage('/workspace') if os.path.exists('/workspace') else psutil.disk_usage('/')
            
            return {
                "mem_usage": f"{memory.used / (1024**3):.1f} GB",
                "disk_usage": f"{disk.used / (1024**3):.0f} GB"
            }
        except Exception as e:
            print(f"Error getting resources: {e}")
            return {
                "mem_usage": "0 GB",
                "disk_usage": "0 GB"
            }
    
    def count_models(self):
        """Count the number of models"""
        models_dir = f"{WORKSPACE_DIR}/models/checkpoints"
        if os.path.exists(models_dir):
            return len([f for f in os.listdir(models_dir) if os.path.isfile(os.path.join(models_dir, f))])
        return 0
    

# Initialize manager
manager = ComfyUIManager()

@app.route('/')
def index():
    """Main UI page - new control panel"""
    status = manager.get_status()
    resources = manager.get_resource_usage()
    models_count = manager.count_models()
    
    # Pass all data to template (start_time is already in status dict)
    return render_template('control_panel.html', 
                         **status, 
                         **resources,
                         models_count=models_count,
                         queue_size=0,
                         is_admin=os.environ.get('COMFYUI_ADMIN_KEY') is not None)

@app.route('/classic')
def classic_ui():
    """Classic UI page (old design)"""
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
    if success:
        return jsonify({"success": success, "message": message})
    else:
        return jsonify({"success": success, "error": message})

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

@app.route('/api/resources')
def get_resources():
    """Get system resource usage"""
    return jsonify(manager.get_resource_usage())

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=7777, debug=False)