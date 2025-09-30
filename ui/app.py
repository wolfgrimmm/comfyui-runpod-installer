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
import shutil
from pathlib import Path
from datetime import datetime, timedelta
from gdrive_sync import GDriveSync
from gdrive_oauth import GDriveOAuth

# Try to import model downloader
try:
    from model_downloader import ModelDownloader
    MODEL_DOWNLOADER_AVAILABLE = True
except ImportError:
    MODEL_DOWNLOADER_AVAILABLE = False
    print("Model downloader not available - install huggingface_hub for model management")

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

        # Try to initialize model downloader, but don't crash if it fails
        self.model_downloader = None
        if MODEL_DOWNLOADER_AVAILABLE:
            try:
                self.model_downloader = ModelDownloader()
                print("✅ Model downloader initialized successfully")
            except Exception as e:
                print(f"⚠️ Model downloader initialization failed: {e}")
                print("   Model Manager will not be available")
                self.model_downloader = None

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
            self.users = ["serhii", "marcin", "vlad", "ksenija", "max", "ivan", "antonia"]
            self.save_users()
        
        # Check if user was previously selected
        if os.path.exists(CURRENT_USER_FILE):
            with open(CURRENT_USER_FILE, 'r') as f:
                self.current_user = f.read().strip()
        
        # Check if ComfyUI is running and load start time
        if self.is_comfyui_running():
            # Found running ComfyUI, but we don't have a handle to it
            print("Found existing ComfyUI process on port 8188")
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
            # No ComfyUI running, clean up state files
            self.start_time = None
            if os.path.exists(START_TIME_FILE):
                os.remove(START_TIME_FILE)
            if os.path.exists(CURRENT_USER_FILE) and not self.is_comfyui_running():
                # Clear current user if ComfyUI isn't running
                os.remove(CURRENT_USER_FILE)
                self.current_user = None
    
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
            total_custom_nodes = 0
            while self.comfyui_process and self.comfyui_process.poll() is None:
                try:
                    line = self.comfyui_process.stdout.readline()
                    if not line:
                        break

                    line = line.decode('utf-8', errors='ignore').strip()
                    if not line:
                        continue

                    # Parse progress from ComfyUI output with better custom node tracking
                    if "Loading" in line and "custom nodes" in line.lower():
                        # Try to extract total number of custom nodes
                        import re
                        match = re.search(r'(\d+)\s+custom\s+node', line, re.IGNORECASE)
                        if match:
                            total_custom_nodes = int(match.group(1))
                        self.startup_progress = {"stage": "loading_nodes", "message": "Discovering custom nodes...", "percent": 10}
                    elif "Importing" in line or "import times" in line.lower() or "Loading:" in line:
                        loaded_nodes += 1
                        # Better progress calculation based on total nodes if known
                        if total_custom_nodes > 0:
                            percent = min(85, 10 + int((loaded_nodes / total_custom_nodes) * 75))
                        else:
                            # Estimate progress (assumes ~100-200 nodes for heavy setups)
                            percent = min(85, 10 + int(loaded_nodes * 0.5))

                        # Extract node name
                        node_name = line
                        if "Importing" in line:
                            node_name = line.split("Importing")[-1].strip()
                        elif ":" in line:
                            node_name = line.split(":")[-1].strip()

                        # Shorten long node names
                        if len(node_name) > 50:
                            node_name = node_name[:47] + "..."

                        self.startup_progress = {"stage": "importing", "message": f"Loading node {loaded_nodes}: {node_name}", "percent": percent}
                    elif "Starting server" in line or "0.0.0.0:8188" in line:
                        self.startup_progress = {"stage": "starting_server", "message": "Starting web server...", "percent": 90}
                    elif "To see the GUI go to" in line or "ComfyUI is running" in line or "Starting ComfyUI" in line:
                        self.startup_progress = {"stage": "ready", "message": "ComfyUI is ready!", "percent": 100}
                    elif "error" in line.lower() and "import" in line.lower():
                        # Don't fail on import errors, some nodes might be optional
                        failed_node = line.split(":")[-1].strip() if ":" in line else "unknown node"
                        self.startup_progress = {"stage": "importing", "message": f"Skipping incompatible: {failed_node[:40]}", "percent": self.startup_progress.get('percent', 50)}
                    elif "Total time taken" in line or "Startup complete" in line:
                        self.startup_progress = {"stage": "finalizing", "message": "Finalizing startup...", "percent": 95}
                    elif "Prestartup times" in line:
                        self.startup_progress = {"stage": "initializing", "message": "Initializing ComfyUI core...", "percent": 5}
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

        # Create user folders if they don't exist
        user_input = f"{INPUT_BASE}/{username}"
        user_output = f"{OUTPUT_BASE}/{username}"
        user_workflows = f"{WORKFLOWS_BASE}/{username}"
        os.makedirs(user_input, exist_ok=True)
        os.makedirs(user_output, exist_ok=True)
        os.makedirs(user_workflows, exist_ok=True)

        # CRITICAL: Remove any existing output directory/symlink to prevent duplicates
        if os.path.exists(comfy_output):
            if os.path.islink(comfy_output):
                # Remove existing symlink
                print(f"Removing existing symlink at {comfy_output}")
                os.unlink(comfy_output)
            else:
                # It's a real directory - move content and remove
                if os.path.isdir(comfy_output) and os.listdir(comfy_output):
                    print(f"Found real directory at {comfy_output}, moving contents...")
                    # Move any existing files to workspace
                    os.system(f"rsync -av {comfy_output}/ {user_output}/ 2>/dev/null || true")
                print(f"Removing directory {comfy_output}")
                os.system(f"rm -rf {comfy_output}")

        # Handle input directory
        if os.path.exists(comfy_input):
            if os.path.islink(comfy_input):
                os.unlink(comfy_input)
            elif os.path.isdir(comfy_input) and os.listdir(comfy_input):
                os.system(f"rsync -av {comfy_input}/ {user_input}/ 2>/dev/null || true")
                os.system(f"rm -rf {comfy_input}")

        # Handle workflows directory
        if os.path.exists(comfy_workflows):
            if os.path.islink(comfy_workflows):
                os.unlink(comfy_workflows)
            elif os.path.isdir(comfy_workflows) and os.listdir(comfy_workflows):
                os.system(f"rsync -av {comfy_workflows}/ {user_workflows}/ 2>/dev/null || true")
                os.system(f"rm -rf {comfy_workflows}")

        # Ensure parent directory exists for workflows
        os.makedirs(f"{COMFYUI_DIR}/user", exist_ok=True)

        # Create symlinks to user folders - ComfyUI will write through these to /workspace
        os.symlink(user_input, comfy_input)
        os.symlink(user_output, comfy_output)
        os.symlink(user_workflows, comfy_workflows)

        print(f"✅ Symlinks created (ComfyUI will save through these to /workspace):")
        print(f"  {comfy_output} -> {user_output}")
        print(f"  {comfy_input} -> {user_input}")
        print(f"  {comfy_workflows} -> {user_workflows}")

        # Verify symlinks are correct
        if os.path.islink(comfy_output):
            real_path = os.path.realpath(comfy_output)
            print(f"  Verified: output symlink points to {real_path}")
    
    def start_comfyui(self, username):
        """Start ComfyUI for specified user"""
        if self.is_comfyui_running():
            # Check if it's actually responding
            if self.is_comfyui_ready():
                return False, "ComfyUI is already running"
            else:
                # Port is taken but not responding, try to clean it up
                print("Found stale ComfyUI process, cleaning up...")
                self.stop_comfyui()
                time.sleep(3)  # Wait for cleanup
        
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

            # Setup environment first, before building command
            env_vars = {**os.environ, "COMFYUI_USER": username}

            # Add important paths
            env_vars["PATH"] = f"/workspace/venv/bin:{os.environ.get('PATH', '')}"
            env_vars["VIRTUAL_ENV"] = "/workspace/venv"
            env_vars["PYTHONPATH"] = "/workspace/ComfyUI"

            # Check GPU and set attention mechanism
            try:
                gpu_check = subprocess.run(["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"],
                                         capture_output=True, text=True, timeout=5)
                gpu_name = gpu_check.stdout.strip() if gpu_check.returncode == 0 else ""

                if "5090" in gpu_name or "RTX 5090" in gpu_name:
                    print(f"🎯 Detected RTX 5090 - using Sage Attention for optimal performance")
                    env_vars["COMFYUI_ATTENTION_MECHANISM"] = "sage"
            except:
                pass

            # Check if we should force safe mode
            if os.path.exists("/workspace/.comfyui_safe_mode"):
                print("🔒 Safe mode enabled - forcing xformers attention")
                env_vars["COMFYUI_ATTENTION_MECHANISM"] = "xformers"

            # Use direct command instead of complex script
            print(f"🔧 Starting ComfyUI with direct command")

            # Build the command based on attention mechanism
            attention_mechanism = env_vars.get("COMFYUI_ATTENTION_MECHANISM", "")
            base_cmd = "source /workspace/venv/bin/activate && cd /workspace/ComfyUI && python main.py --listen 0.0.0.0 --port 8188"

            # Add attention-specific flags if needed
            if attention_mechanism == "sage":
                # Sage doesn't need special flags, it's detected automatically
                base_cmd += " 2>&1 | tee /tmp/comfyui_start.log"
            else:
                base_cmd += " 2>&1 | tee /tmp/comfyui_start.log"

            cmd = ["/bin/bash", "-c", base_cmd]

            print(f"📝 Running command: {cmd}")

            # Reset startup progress
            self.startup_progress = {"stage": "starting", "message": "Launching ComfyUI process...", "percent": 5}

            print(f"📂 Starting from directory: /workspace/ComfyUI")
            print(f"🔧 Environment PATH: {env_vars.get('PATH', 'not set')}")
            print(f"🔧 VIRTUAL_ENV: {env_vars.get('VIRTUAL_ENV', 'not set')}")
            print(f"🔧 COMFYUI_ATTENTION_MECHANISM: {env_vars.get('COMFYUI_ATTENTION_MECHANISM', 'not set')}")

            self.comfyui_process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,  # Combine stderr with stdout for better logging
                env=env_vars,
                cwd="/workspace/ComfyUI",
                bufsize=1,  # Line buffered
                universal_newlines=False  # We'll decode manually
            )

            print(f"🚀 ComfyUI process started with PID: {self.comfyui_process.pid}")

            # Give it a moment to start
            time.sleep(2)

            # Check if it's still alive
            if self.comfyui_process.poll() is not None:
                exit_code = self.comfyui_process.poll()
                print(f"❌ ComfyUI died immediately with exit code: {exit_code}")

                # Try to get the error
                if self.comfyui_process.stdout:
                    output = self.comfyui_process.stdout.read().decode('utf-8', errors='ignore')
                    print(f"📋 Process output:\n{output}")

                # Check log file
                if os.path.exists("/tmp/comfyui_start.log"):
                    with open("/tmp/comfyui_start.log", "r") as f:
                        log = f.read()
                        print(f"📋 Log file contents:\n{log}")

                return False, f"ComfyUI failed to start with exit code {exit_code}"

            # Start monitoring thread
            self.monitor_startup_logs()

            # Wait for ComfyUI to actually start - adaptive timeout based on custom nodes
            max_wait = 1800  # 30 minutes max for heavy custom node setups
            readiness_check_interval = 3  # Check readiness every 3 seconds
            last_activity_time = time.time()
            last_progress_msg = ""

            for i in range(max_wait):
                time.sleep(1)

                # Check if process died
                if self.comfyui_process and self.comfyui_process.poll() is not None:
                    # Process died - mark as failed
                    exit_code = self.comfyui_process.poll()
                    self.startup_progress = {"stage": "failed", "message": f"ComfyUI process terminated with code {exit_code}", "percent": 0}

                    # Try to get error output
                    stderr = ""
                    if self.comfyui_process.stdout:
                        try:
                            stderr = self.comfyui_process.stdout.read().decode('utf-8', errors='ignore')
                            print(f"❌ ComfyUI stdout/stderr:\n{stderr}")
                        except:
                            pass

                    # Also check log file
                    log_content = ""
                    if os.path.exists("/tmp/comfyui_start.log"):
                        try:
                            with open("/tmp/comfyui_start.log", "r") as f:
                                log_content = f.read()[-1000:]  # Last 1000 chars
                                print(f"📋 ComfyUI log file:\n{log_content}")
                        except:
                            pass

                    error_msg = f"ComfyUI process died with exit code {exit_code}"
                    if stderr:
                        error_msg += f"\nOutput: {stderr[:500]}"
                    if log_content:
                        error_msg += f"\nLog: {log_content[:500]}"

                    return False, error_msg

                # Track if progress is still changing (activity indicator)
                current_progress_msg = self.startup_progress.get('message', '')
                if current_progress_msg != last_progress_msg:
                    last_activity_time = time.time()
                    last_progress_msg = current_progress_msg

                # Check readiness more frequently after initial startup phase
                should_check_ready = (i % readiness_check_interval == 0) and i > 30

                # Check startup progress - don't mark as ready too early
                if i < 5:
                    # Don't check readiness in first 5 seconds
                    continue

                if self.startup_progress.get('stage') == 'ready' or (should_check_ready and self.is_comfyui_ready()):
                    # Double-check that ComfyUI is actually ready
                    if self.is_comfyui_ready():
                        print(f"✅ ComfyUI fully initialized after {i+1} seconds")
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

                # If no activity for 5 minutes, assume stuck
                if time.time() - last_activity_time > 300:
                    # But still check if it's actually ready (might be loading silently)
                    if self.is_comfyui_ready():
                        print(f"ComfyUI ready after silent startup ({i+1} seconds)")
                        self.start_time = time.time()
                        with open(START_TIME_FILE, 'w') as f:
                            f.write(str(self.start_time))
                        self.session_start = self.start_time
                        self.log_session_start(username)
                        self.startup_progress = {"stage": "ready", "message": "ComfyUI is ready!", "percent": 100}
                        return True, "ComfyUI started successfully"
                    else:
                        self.startup_progress = {"stage": "failed", "message": "ComfyUI startup stalled (no progress for 5 minutes)", "percent": 0}
                        return False, "ComfyUI startup appears stuck"

                # Update progress message with elapsed time if still starting
                if i % 10 == 0 and self.startup_progress.get('stage') not in ['ready', 'failed']:
                    elapsed_min = i // 60
                    elapsed_sec = i % 60
                    if elapsed_min > 0:
                        time_str = f"{elapsed_min}m {elapsed_sec}s"
                    else:
                        time_str = f"{elapsed_sec}s"

                    base_msg = self.startup_progress.get('message', 'Starting...').split(' (')[0]  # Remove old time
                    self.startup_progress['message'] = f"{base_msg} ({time_str} elapsed)"

                # Show progress
                if i % 30 == 0:
                    print(f"Waiting for ComfyUI to start... {i}s (heavy custom nodes may take 10-20 minutes)")

            # Timeout - mark as failed
            self.startup_progress = {"stage": "failed", "message": "ComfyUI startup timeout (30 minutes)", "percent": 0}
            return False, "ComfyUI took too long to start (30 minute timeout)"
        except Exception as e:
            return False, f"Error starting ComfyUI: {str(e)}"
    
    def stop_comfyui(self):
        """Stop ComfyUI"""
        # Reset startup progress
        self.startup_progress = {"stage": "idle", "message": "", "percent": 0}

        # Try to terminate our subprocess first
        if self.comfyui_process:
            try:
                self.comfyui_process.terminate()
                time.sleep(2)  # Give more time for graceful shutdown
                if self.comfyui_process.poll() is None:
                    self.comfyui_process.kill()
                    time.sleep(1)
            except Exception as e:
                print(f"Error terminating ComfyUI process: {e}")
            finally:
                self.comfyui_process = None

        # Kill any remaining processes more aggressively
        # First try to kill by port
        os.system("fuser -k 8188/tcp 2>/dev/null || true")
        time.sleep(1)

        # Then kill any ComfyUI processes by name
        os.system("pkill -f 'python.*ComfyUI.*main.py' 2>/dev/null || true")
        os.system("pkill -f 'python.*main.py.*--listen.*8188' 2>/dev/null || true")

        # Kill any python process using port 8188 (more aggressive)
        os.system("lsof -ti:8188 | xargs kill -9 2>/dev/null || true")

        # Log session end before clearing
        if self.start_time and self.current_user:
            self.log_session_end()

        # Clear start time
        self.start_time = None
        self.session_start = None
        if os.path.exists(START_TIME_FILE):
            os.remove(START_TIME_FILE)

        # Clear current user file to indicate no active session
        if os.path.exists(CURRENT_USER_FILE):
            os.remove(CURRENT_USER_FILE)
        self.current_user = None  # Also clear the instance variable

        return True
    
    def is_comfyui_running(self):
        """Check if ComfyUI is running"""
        # First check our process handle
        if self.comfyui_process:
            poll_result = self.comfyui_process.poll()
            if poll_result is not None:
                # Process has terminated
                print(f"⚠️ ComfyUI process terminated with exit code: {poll_result}")
                return False
        else:
            # No process handle
            return False

        # Also check if port 8188 is actually listening
        import socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(1)  # Add timeout to avoid hanging
        try:
            result = sock.connect_ex(('127.0.0.1', 8188))
            sock.close()
            if result == 0:
                # Port is open, but we don't have a process handle
                # This could be from a previous session
                return True
            return False
        except Exception as e:
            print(f"Error checking port 8188: {e}")
            return False

    def is_comfyui_ready(self):
        """Check if ComfyUI is fully ready to accept connections"""
        if not self.is_comfyui_running():
            return False

        # Try to actually connect to ComfyUI's HTTP endpoint
        import urllib.request
        import urllib.error
        try:
            # Check both the main page and the API endpoint
            with urllib.request.urlopen('http://127.0.0.1:8188/', timeout=5) as response:
                if response.status != 200:
                    return False

            # Also check if the API is responding (better indicator of readiness)
            with urllib.request.urlopen('http://127.0.0.1:8188/system_stats', timeout=5) as response:
                # If API responds, ComfyUI is fully ready
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
    """Health check endpoint for monitoring"""
    return jsonify({
        'status': 'healthy',
        'service': 'control-panel',
        'timestamp': time.time()
    }), 200

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

@app.route('/api/clear_cache', methods=['POST'])
def clear_triton_cache():
    """Clear Triton cache for Sage Attention/WAN 2.2 optimization"""
    try:
        import subprocess

        # Run the cache clearing script
        result = subprocess.run(
            ["python3", "/app/scripts/clear_triton_cache.py"] if os.path.exists("/app/scripts/clear_triton_cache.py")
            else ["bash", "/app/scripts/clear_triton_cache.sh"],
            capture_output=True,
            text=True,
            timeout=30
        )

        # Parse output for summary
        output_lines = result.stdout.split('\n') if result.stdout else []
        summary = {
            "success": result.returncode == 0,
            "message": "Cache cleared successfully" if result.returncode == 0 else "Cache clearing failed",
            "details": output_lines[-5:] if output_lines else [],  # Last 5 lines for summary
            "full_output": result.stdout
        }

        # If ComfyUI is running, suggest restart
        if manager.is_comfyui_running():
            summary["restart_suggested"] = True
            summary["message"] += ". Restart ComfyUI to apply changes."

        return jsonify(summary)

    except subprocess.TimeoutExpired:
        return jsonify({
            "success": False,
            "message": "Cache clearing timed out",
            "error": "Operation took too long"
        })
    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to clear cache",
            "error": str(e)
        })

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
        try:
            # Send initial connection message to verify SSE is working
            yield f"data: {json.dumps({'stage': 'connecting', 'message': 'Monitoring startup...', 'percent': 0})}\n\n"

            last_progress = None
            max_iterations = 1200  # 10 minutes max (1200 * 0.5s)
            iterations = 0

            while iterations < max_iterations:
                iterations += 1

                # Get current progress safely
                try:
                    progress = manager.startup_progress.copy() if hasattr(manager, 'startup_progress') else {"stage": "initializing", "message": "Starting ComfyUI...", "percent": 5}
                except Exception as e:
                    print(f"Error getting startup progress: {e}")
                    progress = {"stage": "error", "message": "Error reading progress", "percent": 0}

                # Only send if changed
                if progress != last_progress:
                    try:
                        data = json.dumps(progress)
                        yield f"data: {data}\n\n"
                        last_progress = progress
                    except (TypeError, ValueError) as e:
                        print(f"Error serializing progress to JSON: {e}, progress: {progress}")
                        # Send a safe fallback message
                        safe_progress = {"stage": "unknown", "message": "Processing...", "percent": 0}
                        yield f"data: {json.dumps(safe_progress)}\n\n"

                # Stop streaming once ready or failed
                if progress.get('stage') in ['ready', 'failed']:
                    # Send final state and close
                    break

                # Also stop if ComfyUI is no longer starting but only after 10 seconds
                if iterations > 20 and (not manager.comfyui_process or manager.comfyui_process.poll() is not None):
                    # Process died, send failure
                    failure_progress = {"stage": "failed", "message": "ComfyUI process terminated", "percent": 0}
                    yield f"data: {json.dumps(failure_progress)}\n\n"
                    break

                time.sleep(0.5)  # Check every 500ms

            # If we hit max iterations, send timeout
            if iterations >= max_iterations:
                timeout_progress = {"stage": "failed", "message": "Startup monitoring timeout", "percent": 0}
                yield f"data: {json.dumps(timeout_progress)}\n\n"

        except Exception as e:
            # If any error occurs in the generator, send error as JSON
            print(f"Error in startup stream generator: {e}")
            error_progress = {"stage": "error", "message": f"Stream error: {str(e)}", "percent": 0}
            yield f"data: {json.dumps(error_progress)}\n\n"

    try:
        response = Response(generate(), mimetype='text/event-stream')
        response.headers['Cache-Control'] = 'no-cache'
        response.headers['X-Accel-Buffering'] = 'no'
        response.headers['Connection'] = 'keep-alive'
        response.headers['Content-Type'] = 'text/event-stream'
        return response
    except Exception as e:
        # If Response creation fails, return a JSON error instead of HTML
        print(f"Failed to create SSE response: {e}")
        return jsonify({"error": "Failed to create event stream", "message": str(e)}), 500

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

# ============= Model Manager Routes =============

@app.route('/models')
def model_manager():
    """Model manager page"""
    if not MODEL_DOWNLOADER_AVAILABLE:
        return "Model manager not available. Please install huggingface_hub.", 503
    return render_template('model_manager.html')

@app.route('/api/models/installed')
def get_installed_models():
    """Get list of installed models"""
    if not manager.model_downloader:
        return jsonify({'error': 'Model manager not available'}), 503

    models = manager.model_downloader.get_installed_models()
    return jsonify(models)

@app.route('/api/models/search', methods=['POST'])
def search_models():
    """Search for models on HuggingFace Hub"""
    if not manager.model_downloader:
        return jsonify({'error': 'Model manager not available'}), 503

    data = request.json
    query = data.get('query', '')

    if not query:
        return jsonify([])

    results = manager.model_downloader.search_models(query)
    return jsonify(results)

@app.route('/api/models/download', methods=['POST'])
def download_model():
    """Start downloading a model"""
    if not manager.model_downloader:
        return jsonify({'error': 'Model manager not available'}), 503

    data = request.json
    repo_id = data.get('repo_id')
    filename = data.get('filename')
    model_type = data.get('model_type')
    is_snapshot = data.get('is_snapshot', False)

    if not repo_id:
        return jsonify({'error': 'repo_id is required'}), 400

    try:
        download_id = manager.model_downloader.download_model(
            repo_id=repo_id,
            filename=filename,
            model_type=model_type,
            is_snapshot=is_snapshot
        )
        return jsonify({'download_id': download_id})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/models/downloads')
def get_downloads():
    """Get status of all downloads"""
    if not manager.model_downloader:
        return jsonify({'error': 'Model manager not available'}), 503

    downloads = manager.model_downloader.get_all_downloads()
    return jsonify(downloads)

@app.route('/api/models/delete', methods=['POST'])
def delete_model():
    """Delete a model"""
    if not manager.model_downloader:
        return jsonify({'error': 'Model manager not available'}), 503

    data = request.json
    model_path = data.get('path')

    if not model_path:
        return jsonify({'error': 'path is required'}), 400

    # Security check - ensure path is within models directory
    if not model_path.startswith('/workspace/ComfyUI/models/'):
        return jsonify({'error': 'Invalid model path'}), 403

    success = manager.model_downloader.delete_model(model_path)
    return jsonify({'success': success})

@app.route('/api/models/disk-usage')
def get_disk_usage():
    """Get disk usage information"""
    if not manager.model_downloader:
        return jsonify({'error': 'Model manager not available'}), 503

    usage = manager.model_downloader.get_disk_usage()
    return jsonify(usage)

@app.route('/api/models/bundles')
def get_bundles():
    """Get available model bundles"""
    if not manager.model_downloader:
        return jsonify({'error': 'Model manager not available'}), 503

    bundles = manager.model_downloader.get_bundles()
    return jsonify(bundles)

@app.route('/api/models/bundles/download', methods=['POST'])
def download_bundle():
    """Download a model bundle"""
    if not manager.model_downloader:
        return jsonify({'error': 'Model manager not available'}), 503

    data = request.json
    bundle_id = data.get('bundle_id')

    if not bundle_id:
        return jsonify({'error': 'bundle_id is required'}), 400

    try:
        bundle_download_id = manager.model_downloader.download_bundle(bundle_id)
        return jsonify({'bundle_download_id': bundle_download_id})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/models/bundles/status')
def get_bundle_downloads():
    """Get status of all bundle downloads"""
    if not manager.model_downloader:
        return jsonify({'error': 'Model manager not available'}), 503

    bundle_downloads = manager.model_downloader.get_all_bundle_downloads()
    return jsonify(bundle_downloads)

@app.route('/api/models/bundles/search', methods=['POST'])
def search_bundles():
    """Search bundles by query"""
    if not manager.model_downloader:
        return jsonify({'error': 'Model manager not available'}), 503

    data = request.json
    query = data.get('query', '')

    bundles = manager.model_downloader.search_bundles(query)
    return jsonify(bundles)

@app.route('/api/models/bundles/categories')
def get_bundle_categories():
    """Get list of bundle categories"""
    if not manager.model_downloader:
        return jsonify({'error': 'Model manager not available'}), 503

    categories = manager.model_downloader.get_bundle_categories()
    return jsonify({'categories': categories})

@app.route('/api/models/bundles/filter', methods=['POST'])
def filter_bundles():
    """Filter bundles by category"""
    if not manager.model_downloader:
        return jsonify({'error': 'Model manager not available'}), 503

    data = request.json
    category = data.get('category', 'all')

    bundles = manager.model_downloader.get_bundles_by_category(category)
    return jsonify(bundles)

# ============= CivitAI Integration Routes =============

@app.route('/api/civitai/search', methods=['POST'])
def search_civitai():
    """Search models on CivitAI"""
    try:
        data = request.json
        query = data.get('query', '')
        model_type = data.get('type', None)
        sort = data.get('sort', 'Highest Rated')
        nsfw = data.get('nsfw', False)
        page = data.get('page', 1)
        limit = data.get('limit', 20)
        cursor = data.get('cursor', None)  # Support cursor-based pagination

        results = manager.model_downloader.search_civitai_models(
            query=query,
            model_type=model_type,
            sort=sort,
            nsfw=nsfw,
            page=page,
            limit=limit,
            cursor=cursor
        )

        return jsonify(results)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/civitai/download', methods=['POST'])
def download_civitai():
    """Download a model from CivitAI"""
    try:
        data = request.json
        version_id = data.get('version_id')
        model_type = data.get('model_type')

        if not version_id:
            return jsonify({'error': 'version_id required'}), 400

        download_id = manager.model_downloader.download_civitai_model(
            version_id=int(version_id),
            model_type=model_type
        )

        return jsonify({'download_id': download_id})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/civitai/download-url', methods=['POST'])
def download_civitai_url():
    """Download a model from CivitAI using direct URL"""
    try:
        data = request.json
        url = data.get('url', '').strip()
        model_type = data.get('model_type', None)  # Optional model type override

        if not url:
            return jsonify({'error': 'URL required'}), 400

        # Check if it's a CivitAI URL
        if 'civitai.com' not in url.lower():
            return jsonify({'error': 'Not a CivitAI URL'}), 400

        # Use the CivitAI client to download from URL
        if not manager.model_downloader or not manager.model_downloader.civitai_client:
            return jsonify({'error': 'CivitAI integration not available'}), 500

        try:
            # Parse and download the model with optional type override
            result_path = manager.model_downloader.civitai_client.download_from_url(
                url,
                model_type=model_type if model_type and model_type != 'auto' else None
            )

            # Determine the actual folder it was saved to
            folder_name = 'downloads'  # default
            if '/checkpoints/' in result_path:
                folder_name = 'checkpoints'
            elif '/loras/' in result_path:
                folder_name = 'loras'
            elif '/vae/' in result_path:
                folder_name = 'vae'
            elif '/controlnet/' in result_path:
                folder_name = 'controlnet'
            elif '/embeddings/' in result_path:
                folder_name = 'embeddings'

            return jsonify({
                'success': True,
                'message': f'Model downloaded successfully to {folder_name}',
                'path': result_path,
                'folder': folder_name,
                'filename': os.path.basename(result_path) if result_path else None
            })
        except Exception as download_error:
            return jsonify({
                'success': False,
                'error': f'Download failed: {str(download_error)}'
            }), 500

    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/civitai/trending')
def get_civitai_trending():
    """Get trending models from CivitAI"""
    try:
        period = request.args.get('period', 'Week')
        limit = request.args.get('limit', 20, type=int)

        results = manager.model_downloader.get_civitai_trending(
            period=period,
            limit=limit
        )

        return jsonify(results)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/civitai/set-key', methods=['POST'])
def set_civitai_key():
    """Set CivitAI API key"""
    try:
        data = request.json
        api_key = data.get('api_key')

        if not api_key:
            return jsonify({'error': 'api_key required'}), 400

        # Save to env file for persistence
        env_file = '/workspace/.env'
        env_lines = []
        key_found = False

        if os.path.exists(env_file):
            with open(env_file, 'r') as f:
                for line in f:
                    if line.startswith('CIVITAI_API_KEY='):
                        env_lines.append(f'CIVITAI_API_KEY={api_key}\n')
                        key_found = True
                    else:
                        env_lines.append(line)

        if not key_found:
            env_lines.append(f'CIVITAI_API_KEY={api_key}\n')

        with open(env_file, 'w') as f:
            f.writelines(env_lines)

        # Verify the key
        is_valid = manager.model_downloader.set_civitai_api_key(api_key)

        return jsonify({
            'success': is_valid,
            'message': 'API key set successfully' if is_valid else 'Invalid API key'
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/civitai/verify-key')
def verify_civitai_key():
    """Verify CivitAI API key"""
    try:
        is_valid = manager.model_downloader.civitai_client.verify_api_key()
        has_key = bool(manager.model_downloader.civitai_client.api_key)

        return jsonify({
            'has_key': has_key,
            'is_valid': is_valid
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/civitai/model/<int:model_id>')
def get_civitai_model(model_id):
    """Get details about a specific CivitAI model"""
    try:
        import asyncio

        async def get_details():
            return await manager.model_downloader.civitai_client.get_model_details(model_id)

        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        details = loop.run_until_complete(get_details())
        loop.close()

        return jsonify(details)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# ============= End Model Manager Routes =============

# ComfyViewer removed - users can install ComfyUI-Gallery custom node from ComfyUI Manager instead

if __name__ == '__main__':
    # Restore rclone config from workspace if needed
    workspace_config = "/workspace/.config/rclone/rclone.conf"
    root_config = "/root/.config/rclone/rclone.conf"

    if os.path.exists(workspace_config) and not os.path.exists(root_config):
        print("📋 Restoring rclone config from workspace backup...")
        os.makedirs("/root/.config/rclone", exist_ok=True)
        import shutil
        shutil.copy2(workspace_config, root_config)
        print("✅ Rclone config restored")

    # Start auto-sync if Google Drive is configured
    if gdrive.check_gdrive_configured():
        success, message = gdrive.setup_auto_sync(interval_minutes=5)
        if success:
            print(f"✅ Google Drive auto-sync started: {message}")
            # Also backup config to workspace for persistence
            if os.path.exists(root_config) and not os.path.exists(workspace_config):
                os.makedirs("/workspace/.config/rclone", exist_ok=True)
                shutil.copy2(root_config, workspace_config)
                print("💾 Config backed up to workspace for persistence")
        else:
            print(f"⚠️ Could not start auto-sync: {message}")

    try:
        print("🚀 Starting Control Panel on http://0.0.0.0:7777")
        app.run(host='0.0.0.0', port=7777, debug=False, use_reloader=False)
    except Exception as e:
        print(f"❌ Failed to start Control Panel: {e}")
        import traceback
        traceback.print_exc()
        raise