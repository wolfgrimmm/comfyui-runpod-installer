#!/usr/bin/env python3
"""Simple preview server for the stunning UI"""
from flask import Flask, render_template

app = Flask(__name__)

@app.route('/')
def index():
    # Mock status data for preview
    status = {
        'running': False,
        'current_user': 'demo',
        'start_time': None,
        'gpu_info': {
            'name': 'NVIDIA GeForce RTX 4090',
            'memory_total': 24576,
            'memory_used': 0,
            'utilization': 0
        }
    }
    
    users = ['demo', 'serhii', 'antonia']
    
    return render_template(
        'control_panel.html',
        running=False,
        current_user='demo',
        users=users,
        gpu_name='NVIDIA GeForce RTX 4090',
        gpu_memory_total=24576,
        gpu_memory_used=0,
        gpu_utilization=0
    )

if __name__ == '__main__':
    print("🎨 Starting stunning UI preview server...")
    print("📱 Open: http://localhost:5001")
    print("✨ Hover buttons, click them, scroll - see the magic!")
    app.run(host='0.0.0.0', port=5001, debug=False)

