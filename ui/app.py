#!/usr/bin/env python3
"""
ComfyUI Control Panel - Modern UI for user selection and system management
Single user per pod model with resource monitoring
"""

from flask import Flask, render_template, request, jsonify, redirect, Response
import os
import subprocess
import json
import time
import psutil
import threading
import queue
from pathlib import Path
from datetime import datetime, timedelta
from gdrive_sync import GDriveSync
from gdrive_oauth import GDriveOAuth

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
USAGE_LOG_FILE = f"{WORKSPACE_DIR}/user_data/usage_log.json"
USER_STATS_FILE = f"{WORKSPACE_DIR}/user_data/user_statistics.json"

class ComfyUIManager:
    def __init__(self):
        self.comfyui_process = None
        self.current_user = None
        self.start_time = None
        self.session_start = None  # Track session start for logging
        self.auto_update = False  # Not used but kept for compatibility
        self.gpu_info = None
        self.hourly_rate = float(os.environ.get('HOURLY_RATE', '0.74'))  # Default RunPod rate
        self.startup_logs = queue.Queue()  # Store startup logs
        self.startup_progress = {"stage": "idle", "message": "", "percent": 0}
        self.log_thread = None
        self.init_system()
        self.load_user_stats()
    
    def init_system(self):
        """Initialize directories and default users"""
        try:
            os.makedirs(INPUT_BASE, exist_ok=True)
            os.makedirs(OUTPUT_BASE, exist_ok=True)
            os.makedirs(f"{WORKSPACE_DIR}/user_data", exist_ok=True)
        except Exception as e:
            print(f"Warning: Could not create directories: {e}")
            # Continue anyway - directories might already exist
        
        # Detect GPU on startup
        self.detect_gpu()
        
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
        else:
            self.start_time = None
    
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
    
    def monitor_startup_logs(self):
        """Monitor ComfyUI startup logs in a separate thread"""
        if not self.comfyui_process:
            return

        def read_output():
            loaded_nodes = 0
            while self.comfyui_process and self.comfyui_process.poll() is None:
                try:
                    line = self.comfyui_process.stdout.readline()
                    if not line:
                        break

                    line = line.decode('utf-8', errors='ignore').strip()
                    if not line:
                        continue

                    # Parse progress from ComfyUI output
                    if "Loading" in line and "custom nodes" in line.lower():
                        self.startup_progress = {"stage": "loading_nodes", "message": "Loading custom nodes...", "percent": 15}
                    elif "Importing" in line or "import times" in line.lower():
                        loaded_nodes += 1
                        percent = min(75, 15 + loaded_nodes)  # Progress from 15% to 75%
                        node_name = line.split(":")[-1].strip() if ":" in line else line[:50]
                        self.startup_progress = {"stage": "importing", "message": f"Loading: {node_name}", "percent": percent}
                    elif "Starting server" in line or "0.0.0.0:8188" in line:
                        self.startup_progress = {"stage": "starting_server", "message": "Starting web server...", "percent": 85}
                    elif "To see the GUI go to" in line or "ComfyUI is running" in line:
                        self.startup_progress = {"stage": "ready", "message": "ComfyUI is ready!", "percent": 100}
                    elif "error" in line.lower() and "import" in line.lower():
                        # Don't fail on import errors, some nodes might be optional
                        self.startup_progress = {"stage": "importing", "message": f"Skipping failed node...", "percent": self.startup_progress.get('percent', 50)}
                    elif "Total time taken" in line or "Startup complete" in line:
                        self.startup_progress = {"stage": "finalizing", "message": "Finalizing startup...", "percent": 95}
                except Exception as e:
                    print(f"Error reading startup log: {e}")
                    break

            # If we exit the loop and haven't marked as ready, check if it's actually ready
            if self.startup_progress.get('stage') != 'ready' and self.is_comfyui_ready():
                self.startup_progress = {"stage": "ready", "message": "ComfyUI is ready!", "percent": 100}

        self.log_thread = threading.Thread(target=read_output, daemon=True)
        self.log_thread.start()

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
            # Only run init if ComfyUI is not installed
            if not os.path.exists("/workspace/ComfyUI/main.py"):
                print("ComfyUI not found, running init script...")
                result = os.system("/app/init.sh")
                if result != 0:
                    return False, "Failed to initialize workspace"
                
                # Double-check it was installed
                if not os.path.exists("/workspace/ComfyUI/main.py"):
                    return False, "ComfyUI installation failed - main.py not found"
            else:
                # ComfyUI exists, just ensure venv is activated (fast)
                print("ComfyUI already installed, skipping init")
            
            # Check if script exists
            script_path = "/app/start_comfyui.sh"
            if not os.path.exists(script_path):
                # Fallback to direct command
                cmd = ["python", "/workspace/ComfyUI/main.py", "--listen", "0.0.0.0", "--port", "8188"]
            else:
                cmd = [script_path]
            
            # Reset startup progress
            self.startup_progress = {"stage": "starting", "message": "Launching ComfyUI process...", "percent": 5}

            self.comfyui_process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,  # Combine stderr with stdout for better logging
                env={**os.environ, "COMFYUI_USER": username},
                cwd="/workspace/ComfyUI",
                bufsize=1,  # Line buffered
                universal_newlines=False  # We'll decode manually
            )

            # Start monitoring thread
            self.monitor_startup_logs()

            # Wait for ComfyUI to actually start - no fixed timeout!
            max_wait = 600  # 10 minutes max (for extremely heavy setups)
            for i in range(max_wait):
                time.sleep(1)
                
                # Check if process died
                if self.comfyui_process.poll() is not None:
                    stderr = self.comfyui_process.stderr.read().decode() if self.comfyui_process.stderr else ""
                    return False, f"ComfyUI process died: {stderr[:200]}"
                
                # Check startup progress
                if self.startup_progress.get('stage') == 'ready' or self.is_comfyui_ready():
                    # ComfyUI is ready!
                    print(f"ComfyUI fully initialized after {i+1} seconds")
                    self.start_time = time.time()
                    # Save start time to file
                    with open(START_TIME_FILE, 'w') as f:
                        f.write(str(self.start_time))

                    # Log session start
                    self.session_start = self.start_time
                    self.log_session_start(username)

                    # Ensure progress shows ready
                    self.startup_progress = {"stage": "ready", "message": "ComfyUI is ready!", "percent": 100}

                    return True, "ComfyUI started successfully"

                # Update progress message with elapsed time if still starting
                if i % 5 == 0 and self.startup_progress.get('stage') not in ['ready', 'failed']:
                    current_msg = self.startup_progress.get('message', 'Starting...')
                    self.startup_progress['message'] = f"{current_msg} ({i}s elapsed)"
                
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
        
        # Log session end before clearing
        if self.start_time and self.current_user:
            self.log_session_end()
        
        # Clear start time
        self.start_time = None
        self.session_start = None
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

    def is_comfyui_ready(self):
        """Check if ComfyUI is fully ready to accept connections"""
        if not self.is_comfyui_running():
            return False

        # Try to actually connect to ComfyUI's HTTP endpoint
        import urllib.request
        import urllib.error
        try:
            with urllib.request.urlopen('http://127.0.0.1:8188/', timeout=2) as response:
                # If we get any response, ComfyUI is ready
                return response.status == 200
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError):
            # ComfyUI is running but not yet accepting HTTP requests
            return False
        except:
            return False
    
    def get_status(self):
        """Get current status"""
        is_running = self.is_comfyui_running()
        is_ready = self.is_comfyui_ready() if is_running else False
        return {
            "running": is_running,
            "ready": is_ready,  # Now properly checks if HTTP is responding
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
    
    def detect_gpu(self):
        """Detect GPU information"""
        try:
            result = subprocess.run(
                ['nvidia-smi', '--query-gpu=name,memory.total', '--format=csv,noheader'],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                gpu_data = result.stdout.strip().split(', ')
                self.gpu_info = {
                    'name': gpu_data[0] if len(gpu_data) > 0 else 'Unknown',
                    'memory': gpu_data[1] if len(gpu_data) > 1 else 'Unknown'
                }
            else:
                self.gpu_info = {'name': 'Unknown', 'memory': 'Unknown'}
        except:
            self.gpu_info = {'name': 'Unknown', 'memory': 'Unknown'}
    
    def load_user_stats(self):
        """Load user statistics from file"""
        self.user_stats = {}
        if os.path.exists(USER_STATS_FILE):
            try:
                with open(USER_STATS_FILE, 'r') as f:
                    self.user_stats = json.load(f)
            except:
                self.user_stats = {}
    
    def save_user_stats(self):
        """Save user statistics to file"""
        try:
            with open(USER_STATS_FILE, 'w') as f:
                json.dump(self.user_stats, f, indent=2)
        except Exception as e:
            print(f"Error saving user stats: {e}")
    
    def log_session_start(self, username):
        """Log the start of a user session"""
        try:
            # Initialize user stats if not exists
            if username not in self.user_stats:
                self.user_stats[username] = {
                    'total_hours': 0,
                    'total_cost': 0,
                    'sessions': [],
                    'gpu_used': self.gpu_info['name'] if self.gpu_info else 'Unknown'
                }
            
            # Create session entry
            session_entry = {
                'start_time': self.session_start,
                'start_datetime': datetime.fromtimestamp(self.session_start).isoformat(),
                'gpu': self.gpu_info['name'] if self.gpu_info else 'Unknown',
                'hourly_rate': self.hourly_rate,
                'status': 'active'
            }
            
            # Add to usage log
            usage_log = []
            if os.path.exists(USAGE_LOG_FILE):
                try:
                    with open(USAGE_LOG_FILE, 'r') as f:
                        usage_log = json.load(f)
                except:
                    usage_log = []
            
            usage_log.append({
                'user': username,
                'action': 'start',
                'timestamp': self.session_start,
                'datetime': datetime.fromtimestamp(self.session_start).isoformat(),
                'gpu': self.gpu_info['name'] if self.gpu_info else 'Unknown'
            })
            
            with open(USAGE_LOG_FILE, 'w') as f:
                json.dump(usage_log, f, indent=2)
            
            # Store current session info
            self.current_session = session_entry
            
        except Exception as e:
            print(f"Error logging session start: {e}")
    
    def log_session_end(self):
        """Log the end of a user session and calculate costs"""
        try:
            if not self.session_start or not self.current_user:
                return
            
            end_time = time.time()
            duration_hours = (end_time - self.session_start) / 3600
            session_cost = duration_hours * self.hourly_rate
            
            # Update user stats
            if self.current_user in self.user_stats:
                self.user_stats[self.current_user]['total_hours'] += duration_hours
                self.user_stats[self.current_user]['total_cost'] += session_cost
                
                # Add completed session
                session_entry = {
                    'start_time': self.session_start,
                    'end_time': end_time,
                    'start_datetime': datetime.fromtimestamp(self.session_start).isoformat(),
                    'end_datetime': datetime.fromtimestamp(end_time).isoformat(),
                    'duration_hours': round(duration_hours, 3),
                    'cost': round(session_cost, 2),
                    'gpu': self.gpu_info['name'] if self.gpu_info else 'Unknown',
                    'hourly_rate': self.hourly_rate
                }
                
                self.user_stats[self.current_user]['sessions'].append(session_entry)
                
                # Keep only last 100 sessions per user
                if len(self.user_stats[self.current_user]['sessions']) > 100:
                    self.user_stats[self.current_user]['sessions'] = \
                        self.user_stats[self.current_user]['sessions'][-100:]
                
                self.save_user_stats()
            
            # Update usage log
            usage_log = []
            if os.path.exists(USAGE_LOG_FILE):
                try:
                    with open(USAGE_LOG_FILE, 'r') as f:
                        usage_log = json.load(f)
                except:
                    usage_log = []
            
            usage_log.append({
                'user': self.current_user,
                'action': 'stop',
                'timestamp': end_time,
                'datetime': datetime.fromtimestamp(end_time).isoformat(),
                'duration_hours': round(duration_hours, 3),
                'cost': round(session_cost, 2)
            })
            
            # Keep only last 1000 log entries
            if len(usage_log) > 1000:
                usage_log = usage_log[-1000:]
            
            with open(USAGE_LOG_FILE, 'w') as f:
                json.dump(usage_log, f, indent=2)
            
        except Exception as e:
            print(f"Error logging session end: {e}")
    
    def get_user_statistics(self):
        """Get statistics for all users"""
        return self.user_stats


# Initialize manager
manager = ComfyUIManager()

# Initialize Google Drive sync and OAuth
gdrive = GDriveSync(WORKSPACE_DIR)
gdrive_oauth = GDriveOAuth(WORKSPACE_DIR)

# Log Google Drive status at startup
print(f"Google Drive status at startup:")
print(f"  rclone available: {gdrive.rclone_available}")
print(f"  configured: {gdrive.check_gdrive_configured()}")
if os.path.exists('/workspace/.gdrive_status'):
    with open('/workspace/.gdrive_status', 'r') as f:
        print(f"  status file: {f.read().strip()}")
else:
    print(f"  status file: not found")

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({'status': 'ok', 'timestamp': time.time()})

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
    status = manager.get_status()
    # Add startup progress to status
    status['startup_progress'] = manager.startup_progress
    return jsonify(status)

@app.route('/api/startup-stream')
def startup_stream():
    """Stream startup progress via Server-Sent Events"""
    def generate():
        last_progress = None
        while True:
            # Get current progress
            progress = manager.startup_progress.copy()

            # Only send if changed
            if progress != last_progress:
                data = json.dumps(progress)
                yield f"data: {data}\n\n"
                last_progress = progress

            # Stop streaming once ready or failed
            if progress.get('stage') in ['ready', 'failed']:
                break

            time.sleep(0.5)  # Check every 500ms

    return Response(generate(), mimetype='text/event-stream')

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

@app.route('/api/user_stats')
def get_user_stats():
    """Get user statistics"""
    stats = manager.get_user_statistics()
    # Add current GPU info
    stats['current_gpu'] = manager.gpu_info
    stats['hourly_rate'] = manager.hourly_rate
    return jsonify(stats)

# Google Drive API endpoints
@app.route('/api/gdrive/status')
def gdrive_status():
    """Check Google Drive configuration status"""
    # Check if we have a stored Drive URL
    drive_url = None
    if os.path.exists('/workspace/.gdrive_url'):
        try:
            with open('/workspace/.gdrive_url', 'r') as f:
                drive_url = f.read().strip()
        except:
            pass
    
    # Check for RunPod secret (with debugging) - check multiple possible names
    has_secret = bool(
        os.environ.get('RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT') or
        os.environ.get('GOOGLE_SERVICE_ACCOUNT') or
        os.environ.get('RUNPOD_SECRET_GDRIVE') or
        os.environ.get('GDRIVE_SERVICE_ACCOUNT') or
        any(k.startswith('RUNPOD_SECRET_') and 'service_account' in v.lower() 
            for k, v in os.environ.items() if v)
    )
    
    # Debug: Check all RUNPOD environment variables
    runpod_vars = {k: '***' if 'SECRET' in k else v[:50] 
                   for k, v in os.environ.items() 
                   if k.startswith('RUNPOD')}
    
    # Get detailed configuration status
    config_details = {
        'has_runpod_secret': has_secret,
        'has_flag_file': os.path.exists('/workspace/.gdrive_configured'),
        'has_rclone_config': os.path.exists('/root/.config/rclone/rclone.conf') or os.path.exists('/workspace/.config/rclone/rclone.conf'),
        'runpod_vars': runpod_vars  # Show what RunPod vars are available
    }
    
    return jsonify({
        'rclone_installed': gdrive.rclone_available,
        'configured': gdrive.check_gdrive_configured(),
        'mount_point': f"{WORKSPACE_DIR}/gdrive",
        'sync_status': gdrive.get_sync_status(),
        'drive_url': drive_url or 'https://drive.google.com/drive/search?q=ComfyUI-Output',
        'config_details': config_details
    })

@app.route('/api/gdrive/sync', methods=['POST'])
def gdrive_sync():
    """Sync user output folder with Google Drive"""
    data = request.json
    username = data.get('username', manager.current_user)
    direction = data.get('direction', 'to_gdrive')  # 'to_gdrive' or 'from_gdrive'
    
    if not username:
        return jsonify({'success': False, 'error': 'No user selected'}), 400
    
    success, message = gdrive.sync_user_output(username, direction)
    return jsonify({'success': success, 'message': message})

@app.route('/api/gdrive/sync_all', methods=['POST'])
def gdrive_sync_all():
    """Sync all users' output folders"""
    data = request.json
    direction = data.get('direction', 'to_gdrive')
    
    results = gdrive.sync_all_users(manager.users, direction)
    return jsonify({'success': True, 'results': results})

@app.route('/api/gdrive/mount', methods=['POST'])
def gdrive_mount():
    """Mount Google Drive as filesystem"""
    success, message = gdrive.mount_gdrive()
    return jsonify({'success': success, 'message': message})

@app.route('/api/gdrive/unmount', methods=['POST'])
def gdrive_unmount():
    """Unmount Google Drive"""
    success, message = gdrive.unmount_gdrive()
    return jsonify({'success': success, 'message': message})

@app.route('/api/gdrive/symlink', methods=['POST'])
def gdrive_symlink():
    """Create symlink from user output to Google Drive mount"""
    data = request.json
    username = data.get('username', manager.current_user)
    
    if not username:
        return jsonify({'success': False, 'error': 'No user selected'}), 400
    
    success, message = gdrive.create_symlink_to_gdrive(username)
    return jsonify({'success': success, 'message': message})

@app.route('/api/gdrive/get_drive_url')
def gdrive_get_url():
    """Get the Google Drive folder URL"""
    try:
        # For local testing, just return the root Drive URL
        # In production on RunPod, this would check for actual folder IDs
        
        # Check if we have a stored Drive URL
        if os.path.exists('/workspace/.gdrive_url'):
            try:
                with open('/workspace/.gdrive_url', 'r') as f:
                    url = f.read().strip()
                    if url:
                        return jsonify({'success': True, 'url': url})
            except:
                pass
        
        # Try to find the ComfyUI-Output folder ID from rclone
        # This would be set during the Google Drive setup process
        config_files = [
            '/workspace/.config/rclone/rclone.conf',
            '/root/.config/rclone/rclone.conf',
            os.path.expanduser('~/.config/rclone/rclone.conf')
        ]
        
        for config_file in config_files:
            if os.path.exists(config_file):
                try:
                    with open(config_file, 'r') as f:
                        config = f.read()
                        # Look for team_drive ID (Shared Drive)
                        import re
                        match = re.search(r'team_drive\s*=\s*([^\s]+)', config)
                        if match and match.group(1):
                            drive_id = match.group(1)
                            # For Shared Drives, construct the URL differently
                            url = f'https://drive.google.com/drive/folders/ComfyUI-Output'
                            return jsonify({'success': True, 'url': url})
                except:
                    continue
        
        # Default to generic Drive URL
        return jsonify({'success': True, 'url': 'https://drive.google.com/drive/my-drive'})
    except Exception as e:
        print(f"Error getting Drive URL: {e}")
        return jsonify({'success': False, 'url': 'https://drive.google.com/drive/my-drive', 'error': str(e)})

@app.route('/api/gdrive/list')
def gdrive_list():
    """List files in Google Drive"""
    path = request.args.get('path', '')
    files, error = gdrive.list_gdrive_files(path)
    
    if error:
        return jsonify({'success': False, 'error': error}), 400
    
    return jsonify({'success': True, 'files': files})

@app.route('/api/gdrive/storage')
def gdrive_storage():
    """Get Google Drive storage statistics"""
    username = request.args.get('username')
    stats, error = gdrive.get_storage_stats(username)
    
    if error:
        return jsonify({'success': False, 'error': error}), 400
    
    return jsonify({'success': True, 'stats': stats})

@app.route('/api/gdrive/auto_sync', methods=['POST'])
def gdrive_auto_sync():
    """Setup automatic sync to Google Drive"""
    data = request.json
    interval = data.get('interval', 1)  # Default 1 minute for near real-time sync
    
    success, message = gdrive.setup_auto_sync(interval)
    return jsonify({'success': success, 'message': message})

@app.route('/api/gdrive/install_rclone', methods=['POST'])
def install_rclone():
    """Install rclone if not present"""
    success = gdrive.install_rclone()
    if success:
        gdrive.rclone_available = gdrive.check_rclone()
    return jsonify({'success': success, 'message': 'rclone installed' if success else 'Installation failed'})

@app.route('/api/gdrive/configure', methods=['POST'])
def configure_gdrive():
    """Configure Google Drive with provided credentials"""
    data = request.json
    success = gdrive.configure_rclone(data)
    if success:
        gdrive.rclone_available = True
    return jsonify({'success': success, 'message': 'Configuration saved' if success else 'Configuration failed'})

# OAuth setup endpoints
@app.route('/api/gdrive/oauth/start')
def oauth_start():
    """Start OAuth flow - get authorization URL"""
    # Check if already configured
    configured, message = gdrive_oauth.check_existing_config()
    if configured:
        return jsonify({
            'configured': True,
            'message': message
        })
    
    # Get OAuth URL
    instructions = gdrive_oauth.get_simple_auth_instructions()
    return jsonify({
        'configured': False,
        'instructions': instructions
    })

@app.route('/api/gdrive/oauth/callback', methods=['POST'])
def oauth_callback():
    """Handle OAuth callback with authorization code"""
    data = request.json
    code = data.get('code')
    state = data.get('state')
    
    if not code or not state:
        return jsonify({'success': False, 'error': 'Missing code or state'}), 400
    
    # Exchange code for token
    token, error = gdrive_oauth.exchange_code_for_token(code, state)
    
    if error:
        return jsonify({'success': False, 'error': error}), 400
    
    # Save rclone config
    success, message = gdrive_oauth.save_rclone_config(token)
    
    if success:
        # Update gdrive sync status
        gdrive.rclone_available = gdrive.check_rclone()
        return jsonify({
            'success': True,
            'message': 'Google Drive configured successfully!'
        })
    else:
        return jsonify({'success': False, 'error': message}), 400

@app.route('/api/gdrive/oauth/check')
def oauth_check():
    """Check if Google Drive is already configured"""
    configured, message = gdrive_oauth.check_existing_config()
    return jsonify({
        'configured': configured,
        'message': message,
        'rclone_available': gdrive.rclone_available
    })

@app.route('/api/gdrive/oauth/setup_service_account', methods=['POST'])
def setup_service_account():
    """Setup using service account JSON (for enterprise/automated setup)"""
    data = request.json
    service_account_json = data.get('service_account')
    
    if not service_account_json:
        return jsonify({'success': False, 'error': 'No service account data provided'}), 400
    
    success, message = gdrive_oauth.setup_from_service_account(service_account_json)
    
    if success:
        gdrive.rclone_available = gdrive.check_rclone()
        return jsonify({'success': True, 'message': message})
    else:
        return jsonify({'success': False, 'error': message}), 400

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=7777, debug=False)