#!/usr/bin/env python3
"""
Simple Flask server to test Lottie animations
"""
from flask import Flask, render_template, send_from_directory
import os

app = Flask(__name__)

@app.route('/')
def index():
    return render_template('control_panel.html')

@app.route('/static/<path:filename>')
def static_files(filename):
    return send_from_directory('static', filename)

if __name__ == '__main__':
    print("🚀 Starting Lottie test server on http://localhost:5001")
    print("📁 Serving static files from:", os.path.join(os.path.dirname(__file__), 'static'))
    app.run(host='0.0.0.0', port=5001, debug=True)
