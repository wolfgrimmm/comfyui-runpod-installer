# ComfyViewer Extended

An enhanced version of ComfyViewer with video playback support and comprehensive download capabilities for AI-generated media.

## 🎬 New Features

### Video Support
- **Playback** - Full HTML5 video player with custom controls
- **Frame Navigation** - Step through videos frame-by-frame for detailed analysis
- **Multiple Formats** - Supports MP4, WebM, GIF, AVI, MOV
- **Metadata Extraction** - Reads video properties and ComfyUI generation data
- **Thumbnail Generation** - Automatic thumbnail creation from video frames

### Download System
- **Single Downloads** - One-click download for any image or video
- **Bulk Operations** - Select multiple files and download as ZIP
- **Organization Options** - Organize downloads by date, model, or type
- **Metadata Export** - Include JSON sidecar files with generation parameters
- **Progress Tracking** - Real-time progress for large downloads

### Enhanced UI
- **Mixed Media Gallery** - View images and videos in the same interface
- **Advanced Filters** - Filter by media type, size, duration, resolution
- **Keyboard Shortcuts** - Quick navigation and actions
- **Responsive Design** - Works on all screen sizes

## 🚀 Installation

The extended version is automatically installed when you use the ComfyUI RunPod installer:

```bash
# In the Control Panel
1. Click "Install ComfyViewer"
2. The extended version will be installed automatically
3. Start the viewer and enjoy the new features!
```

## 🎮 Usage

### Video Playback
- Click any video thumbnail to open the player
- Use spacebar to play/pause
- Arrow keys to skip frames
- Numbers 1-6 for playback speed
- F for fullscreen

### Download Manager
1. Click the download icon in the toolbar
2. Select files using checkboxes
3. Choose organization method
4. Click "Download as ZIP"

### Keyboard Shortcuts
- `Space` - Play/pause video
- `D` - Download current file
- `Shift+D` - Add to download queue
- `Ctrl/Cmd+A` - Select all
- `←/→` - Navigate between items
- `↑/↓` - Frame-by-frame in videos

## 🛠️ Technical Details

### Supported Formats

**Images:**
- PNG (with ComfyUI metadata)
- JPEG/JPG
- WebP
- GIF (static)
- BMP

**Videos:**
- MP4 (H.264, H.265)
- WebM (VP8, VP9)
- GIF (animated)
- AVI
- MOV

### Metadata Extraction
The viewer automatically extracts and displays:
- ComfyUI workflow data from PNG files
- Video properties (duration, fps, resolution, codec)
- File information (size, creation date)
- Generation parameters (prompt, model, seed, etc.)

### Storage
- Uses IndexedDB for local storage
- Thumbnails cached for performance
- Original files streamed on-demand
- Configurable storage limits

## 🔧 Configuration

### Settings Available
- Maximum file size to index
- Video autoplay preference
- Thumbnail quality (low/medium/high)
- Download organization method
- Storage quota limits

## 📊 Performance

### Optimizations
- Lazy loading for large galleries
- Web Workers for thumbnail generation
- Streaming for video playback
- Efficient IndexedDB queries

### Recommended Limits
- Max 10,000 files per session
- Videos under 500MB for smooth playback
- Batch downloads up to 2GB

## 🐛 Troubleshooting

### Common Issues

**Videos not playing:**
- Check browser supports the codec
- Ensure file size is under limits
- Try converting to MP4/H.264

**Download fails:**
- Check browser storage quota
- Ensure sufficient disk space
- Try smaller batch sizes

**Slow performance:**
- Clear IndexedDB cache
- Reduce thumbnail quality
- Limit number of indexed files

## 📝 Development

### Building from Source

```bash
# Clone the extended version
git clone [your-fork]/comfyviewer-extended.git
cd comfyviewer-extended

# Install dependencies
npm install

# Run development server
npm run dev

# Build for production
npm run build
```

### Key Components
- `VideoPlayer.tsx` - Video playback component
- `BulkDownloader.tsx` - Download manager
- `fileHandler.ts` - Media processing utilities
- `MediaGallery.tsx` - Mixed media grid view

## 🤝 Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

## 📄 License

MIT License - same as original ComfyViewer

## 🙏 Credits

- Original ComfyViewer by [christian-saldana](https://github.com/christian-saldana)
- Extended features for ComfyUI RunPod installer
- Video player based on modern HTML5 standards
- Download system using JSZip and FileSaver.js