#!/usr/bin/env python3
"""
ComfyUI Control Panel - Local Preview Version
Simplified version for local testing without RunPod dependencies
"""

from flask import Flask, render_template, request, jsonify
import os
import json
import time
import threading
from datetime import datetime

app = Flask(__name__)
app.config['TEMPLATES_AUTO_RELOAD'] = True
app.config['SEND_FILE_MAX_AGE_DEFAULT'] = 0

# Mock configuration for local preview
WORKSPACE_DIR = "/tmp/workspace_preview"
COMFYUI_DIR = f"{WORKSPACE_DIR}/ComfyUI"
INPUT_BASE = f"{WORKSPACE_DIR}/input"
OUTPUT_BASE = f"{WORKSPACE_DIR}/output"
WORKFLOWS_BASE = f"{WORKSPACE_DIR}/workflows"
USERS_FILE = f"{WORKSPACE_DIR}/user_data/users.json"
CURRENT_USER_FILE = f"{WORKSPACE_DIR}/user_data/.current_user"
START_TIME_FILE = f"{WORKSPACE_DIR}/user_data/.start_time"

# Create mock directories
os.makedirs(f"{WORKSPACE_DIR}/user_data", exist_ok=True)
os.makedirs(f"{INPUT_BASE}/demo", exist_ok=True)
os.makedirs(f"{OUTPUT_BASE}/demo", exist_ok=True)
os.makedirs(f"{WORKFLOWS_BASE}/demo", exist_ok=True)

# Mock user data
users_data = {
    "users": [
        {"name": "demo", "display_name": "Demo User", "created_at": "2024-01-01T00:00:00Z"}
    ],
    "current_user": "demo"
}

# Write mock data
with open(USERS_FILE, 'w') as f:
    json.dump(users_data, f, indent=2)

with open(CURRENT_USER_FILE, 'w') as f:
    f.write("demo")

class MockComfyUIManager:
    def __init__(self):
        self.comfyui_process = None
        self.current_user = "demo"
        self.start_time = None
        self.gpu_info = {
            "name": "NVIDIA GeForce RTX 4090",
            "memory_total": "24576 MB",
            "memory_used": "2048 MB",
            "utilization": "15%"
        }
        self.running = False
        self.startup_progress = {"stage": "idle", "message": "Ready to start", "percent": 0}

    def get_status(self):
        return {
            "running": self.running,
            "current_user": self.current_user,
            "start_time": self.start_time,
            "gpu_info": self.gpu_info,
            "startup_progress": self.startup_progress
        }

    def start_comfyui(self, username):
        self.running = True
        self.start_time = time.time()
        self.startup_progress = {"stage": "starting", "message": "Starting ComfyUI...", "percent": 25}
        
        # Simulate startup progress
        def simulate_startup():
            stages = [
                {"stage": "loading", "message": "Loading models...", "percent": 50},
                {"stage": "initializing", "message": "Initializing ComfyUI...", "percent": 75},
                {"stage": "ready", "message": "ComfyUI is ready!", "percent": 100}
            ]
            
            for stage in stages:
                time.sleep(2)
                self.startup_progress = stage
                
        threading.Thread(target=simulate_startup, daemon=True).start()
        
        return True, "ComfyUI started successfully"

    def stop_comfyui(self):
        self.running = False
        self.start_time = None
        self.startup_progress = {"stage": "idle", "message": "Stopped", "percent": 0}
        return True, "ComfyUI stopped"

    def get_users(self):
        return [{"name": "demo", "display_name": "Demo User"}]

# Initialize manager
manager = MockComfyUIManager()

@app.route('/')
def index():
    status = manager.get_status()
    users = manager.get_users()
    
    return render_template('control_panel.html',
                         running=status['running'],
                         current_user=status['current_user'],
                         users=users,
                         gpu_info=status['gpu_info'],
                         startup_progress=status['startup_progress'])

@app.route('/api/status')
def api_status():
    status = manager.get_status()
    return jsonify({
        "success": True,
        "running": status['running'],
        "current_user": status['current_user'],
        "start_time": status['start_time'],
        "gpu_info": status['gpu_info'],
        "startup_progress": status['startup_progress']
    })

@app.route('/api/start', methods=['POST'])
def api_start():
    data = request.get_json()
    username = data.get('username', 'demo')
    
    success, message = manager.start_comfyui(username)
    
    return jsonify({
        "success": success,
        "message": message
    })

@app.route('/api/stop', methods=['POST'])
def api_stop():
    success, message = manager.stop_comfyui()
    
    return jsonify({
        "success": success,
        "message": message
    })

@app.route('/api/restart', methods=['POST'])
def api_restart():
    manager.stop_comfyui()
    time.sleep(1)
    success, message = manager.start_comfyui(manager.current_user)
    
    return jsonify({
        "success": success,
        "message": message
    })

@app.route('/api/users')
def api_users():
    users = manager.get_users()
    return jsonify({
        "success": True,
        "users": users,
        "current_user": manager.current_user
    })

@app.route('/models')
def models():
    """Model Manager preview page"""
    return render_template('model_manager.html')

@app.route('/api/gdrive/status')
def gdrive_status():
    """Mock Google Drive status"""
    return jsonify({
        "configured": True,
        "rclone_installed": True,
        "drive_url": "https://drive.google.com/drive/folders/mock-folder-id"
    })

if __name__ == '__main__':
    print("🚀 Starting ComfyUI Control Panel Preview...")
    print("📍 Access at: http://localhost:7777")
    print("🎨 Enhanced with Huly.io-style animations!")
    print("✨ Features: Interactive particles, mouse tracking, glow effects")
    print("\nPress Ctrl+C to stop")
    
    app.run(host='0.0.0.0', port=7777, debug=True)


