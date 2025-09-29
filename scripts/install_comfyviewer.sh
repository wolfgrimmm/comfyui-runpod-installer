#!/bin/bash

# ComfyViewer Installation Script
# Installs ComfyViewer as an optional service for browsing AI-generated images

set -e

VIEWER_DIR="/app/comfyviewer"
WORKSPACE_DIR="/workspace"
LOG_FILE="/workspace/comfyviewer_install.log"

echo "🎨 Installing ComfyViewer..." | tee -a $LOG_FILE
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a $LOG_FILE

# Check if already installed
if [ -d "$VIEWER_DIR" ] && [ -f "$VIEWER_DIR/.next/BUILD_ID" ]; then
    echo "✅ ComfyViewer already installed at $VIEWER_DIR" | tee -a $LOG_FILE
    exit 0
fi

# Check for Node.js
if ! command -v node &> /dev/null; then
    echo "📦 Installing Node.js..." | tee -a $LOG_FILE
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >> $LOG_FILE 2>&1
    apt-get install -y nodejs >> $LOG_FILE 2>&1
fi

echo "Node.js version: $(node --version)" | tee -a $LOG_FILE

# Remove old installation if exists
if [ -d "$VIEWER_DIR" ]; then
    echo "Removing incomplete installation..." | tee -a $LOG_FILE
    rm -rf "$VIEWER_DIR"
fi

# Clone the original ComfyViewer
echo "📥 Cloning ComfyViewer repository..." | tee -a $LOG_FILE
cd /app

# Clone the base ComfyViewer
if ! git clone https://github.com/christian-saldana/ComfyViewer.git comfyviewer >> $LOG_FILE 2>&1; then
    echo "❌ Failed to clone ComfyViewer repository" | tee -a $LOG_FILE
    exit 1
fi

# Apply extended components for video support (but keep base package.json)
if [ -d "/app/comfyviewer-extended" ]; then
    echo "🎬 Adding video support components..." | tee -a $LOG_FILE

    # Copy extended source components (VideoPlayer, BulkDownloader, etc.)
    if [ -d "/app/comfyviewer-extended/src" ]; then
        echo "   Copying video player and download components..." | tee -a $LOG_FILE
        cp -r /app/comfyviewer-extended/src/components/* "$VIEWER_DIR/src/components/" 2>/dev/null || true
        cp -r /app/comfyviewer-extended/src/lib/* "$VIEWER_DIR/src/lib/" 2>/dev/null || true
    fi

    # DO NOT copy the broken package.json - just add missing dependencies manually
    echo "   Adding video dependencies..." | tee -a $LOG_FILE
    cd "$VIEWER_DIR"

    # Add video-related dependencies that are missing
    npm install --save file-saver jszip >> $LOG_FILE 2>&1 || true

    echo "✅ Video support components added" | tee -a $LOG_FILE
fi

cd "$VIEWER_DIR"

# Install dependencies
echo "📦 Installing dependencies (this may take 2-3 minutes)..." | tee -a $LOG_FILE
npm install >> $LOG_FILE 2>&1

# Create custom configuration for RunPod
echo "🔧 Configuring for RunPod environment..." | tee -a $LOG_FILE

# Create next.config.js override for RunPod proxy
cat > next.config.runpod.js << 'EOF'
/** @type {import('next').NextConfig} */
const nextConfig = {
  // Allow RunPod proxy URLs
  async headers() {
    return [
      {
        source: '/:path*',
        headers: [
          {
            key: 'Access-Control-Allow-Origin',
            value: '*',
          },
          {
            key: 'Access-Control-Allow-Methods',
            value: 'GET, POST, OPTIONS',
          },
        ],
      },
    ];
  },
  // Configure for subfolder serving if needed
  basePath: process.env.BASE_PATH || '',
  assetPrefix: process.env.ASSET_PREFIX || '',

  // Image optimization for local files
  images: {
    domains: ['localhost'],
    unoptimized: true,
  },
};

module.exports = nextConfig;
EOF

# Build the application
echo "🔨 Building ComfyViewer (this may take 3-5 minutes)..." | tee -a $LOG_FILE
NODE_ENV=production npm run build >> $LOG_FILE 2>&1

# Create startup script
cat > /app/start_comfyviewer.sh << 'EOF'
#!/bin/bash

# ComfyViewer Startup Script

VIEWER_DIR="/app/comfyviewer"
WORKSPACE_DIR="/workspace"
PORT="${COMFYVIEWER_PORT:-3001}"
USER="${COMFYUI_USER:-default}"

# Check if installed
if [ ! -d "$VIEWER_DIR" ] || [ ! -f "$VIEWER_DIR/.next/BUILD_ID" ]; then
    echo "❌ ComfyViewer not installed. Please run install first."
    exit 1
fi

# Stop any existing instance
pkill -f "next.*3001" 2>/dev/null || true

# Set environment variables
export NODE_ENV=production
export PORT=$PORT
export HOSTNAME=0.0.0.0

# For RunPod proxy compatibility
if [ -n "$RUNPOD_POD_ID" ]; then
    export BASE_PATH=""
    export ASSET_PREFIX=""
fi

echo "🎨 Starting ComfyViewer on port $PORT..."
echo "📁 Serving images from: $WORKSPACE_DIR/output/$USER"

cd "$VIEWER_DIR"

# Start the server
nohup npm start > /workspace/comfyviewer.log 2>&1 &
PID=$!

# Wait and check if started
sleep 5
if kill -0 $PID 2>/dev/null; then
    echo "✅ ComfyViewer started successfully (PID: $PID)"
    echo "🌐 Access at: http://localhost:$PORT"
    echo $PID > /tmp/comfyviewer.pid
else
    echo "❌ Failed to start ComfyViewer"
    tail -20 /workspace/comfyviewer.log
    exit 1
fi
EOF

chmod +x /app/start_comfyviewer.sh

# Create stop script
cat > /app/stop_comfyviewer.sh << 'EOF'
#!/bin/bash

# Stop ComfyViewer
if [ -f /tmp/comfyviewer.pid ]; then
    PID=$(cat /tmp/comfyviewer.pid)
    if kill -0 $PID 2>/dev/null; then
        echo "Stopping ComfyViewer (PID: $PID)..."
        kill $PID
        rm /tmp/comfyviewer.pid
        echo "✅ ComfyViewer stopped"
    else
        echo "ComfyViewer not running (stale PID)"
        rm /tmp/comfyviewer.pid
    fi
else
    # Try to find and kill by port
    pkill -f "next.*3001" 2>/dev/null && echo "✅ ComfyViewer stopped" || echo "ComfyViewer not running"
fi
EOF

chmod +x /app/stop_comfyviewer.sh

echo "" | tee -a $LOG_FILE
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a $LOG_FILE
echo "✅ ComfyViewer installation complete!" | tee -a $LOG_FILE
echo "   Location: $VIEWER_DIR" | tee -a $LOG_FILE
echo "   Start with: /app/start_comfyviewer.sh" | tee -a $LOG_FILE
echo "   Stop with: /app/stop_comfyviewer.sh" | tee -a $LOG_FILE
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a $LOG_FILE