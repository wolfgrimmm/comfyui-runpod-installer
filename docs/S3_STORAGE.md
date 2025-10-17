# S3 Direct Output Folder Linking

This feature allows you to create a **direct symlink** from your RunPod output folder to your S3-compatible storage, enabling real-time file access without sync delays.

## 🎯 What This Does

Instead of syncing files to S3 every few minutes, this creates a **direct filesystem link** where:
- ComfyUI writes files directly to S3 storage
- Files appear instantly in your S3 bucket
- No background sync processes needed
- Real-time access to your generated content

## 🚀 Quick Setup

### 1. Get S3 Credentials from RunPod

1. Go to **RunPod Console** → **Storage** → **Your Network Volume**
2. Click **"S3 API Access"** section
3. Generate access keys and note:
   - **Bucket name**: `3nyrlhftk8` (your volume ID)
   - **Endpoint URL**: `https://s3api-eu-ro-1.runpod.io`
   - **Access Key**: `your_access_key_here`
   - **Secret Key**: `your_secret_key_here`

### 2. Set Environment Variables

Add these to your **RunPod Pod Template**:

```bash
RUNPOD_S3_ENDPOINT=https://s3api-eu-ro-1.runpod.io
RUNPOD_S3_ACCESS_KEY=your_access_key_here
RUNPOD_S3_SECRET_KEY=your_secret_key_here
RUNPOD_S3_BUCKET=3nyrlhftk8
RUNPOD_S3_REGION=eu-ro-1
```

### 3. Use the Control Panel

1. Start your pod and open the **Control Panel**
2. Go to the **S3 Storage** panel
3. Click **"Test S3 Connection"** to verify setup
4. Click **"Link to S3 (S3FS)"** to create the symlink
5. Your output folder is now directly linked to S3!

## 🔧 How It Works

### S3FS Method (Recommended)
```bash
# Mounts S3 bucket as local filesystem
s3fs 3nyrlhftk8 /workspace/s3_username \
    -o passwd_file=/workspace/.s3fs_passwd \
    -o url=https://s3api-eu-ro-1.runpod.io \
    -o use_path_request_style

# Creates symlink
ln -s /workspace/s3_username/output/username /workspace/output/username
```

### Rclone Method (Alternative)
```bash
# Mounts specific S3 folder
rclone mount s3:3nyrlhftk8/output/username /workspace/s3_username --daemon

# Creates symlink
ln -s /workspace/s3_username /workspace/output/username
```

## 📁 File Structure

**Before (Local Storage):**
```
/workspace/output/username/
├── image1.png
├── image2.png
└── video1.mp4
```

**After (S3 Direct Link):**
```
/workspace/output/username/ → /workspace/s3_username/output/username/
├── image1.png (stored in S3)
├── image2.png (stored in S3)
└── video1.mp4 (stored in S3)
```

## 🎛️ Control Panel Features

### S3 Storage Panel
- **Status Indicator**: Shows if S3 is configured and active
- **Test Connection**: Verifies S3 credentials and connectivity
- **Link to S3 (S3FS)**: Creates symlink using S3FS (recommended)
- **Link to S3 (Rclone)**: Creates symlink using rclone (alternative)
- **Unmount S3**: Removes symlink and unmounts S3 storage

### Status Messages
- 🟢 **Green**: S3 configured and active
- 🟡 **Yellow**: S3 not configured
- 🔴 **Red**: S3 connection failed

## 🔍 Troubleshooting

### "S3 credentials not configured"
- Check environment variables are set correctly
- Verify access keys are valid
- Ensure bucket name matches your volume ID

### "S3FS mount failed"
- Check network connectivity
- Verify endpoint URL is correct
- Try rclone method instead

### "Files not appearing in S3"
- Check if symlink is active: `ls -la /workspace/output/username`
- Verify mount point: `mount | grep s3fs`
- Test S3 connection from control panel

### Performance Issues
- S3FS may be slower than local storage
- Large files (>100MB) may have delays
- Consider using rclone method for better performance

## 🆚 Comparison: Sync vs Direct Link

| Feature | Background Sync | Direct S3 Link |
|---------|----------------|----------------|
| **File Access** | 1-5 minute delay | Instant |
| **Performance** | Fast local writes | Slightly slower |
| **Reliability** | Can fail silently | Real-time feedback |
| **Storage** | Local + S3 copies | S3 only |
| **Setup** | Automatic | Manual setup |
| **Cost** | Higher (duplicate storage) | Lower (single copy) |

## 🛠️ Advanced Configuration

### Custom S3FS Options
You can modify the S3FS mount options in `ui/s3_storage.py`:

```python
mount_cmd = [
    's3fs', self.s3_bucket,
    user_mount_point,
    '-o', f'passwd_file={s3fs_passwd_file}',
    '-o', f'url={self.s3_endpoint}',
    '-o', 'use_path_request_style',
    '-o', 'allow_other',
    '-o', 'umask=000',
    '-o', 'retries=5',
    '-o', 'cache=/tmp/s3fs_cache',
    '-o', f'region={self.s3_region}',
    '-o', 'multipart_size=10485760',  # 10MB chunks
    '-o', 'parallel_count=4',         # 4 parallel uploads
    '-o', 'max_stat_cache_size=100000' # Cache size
]
```

### Multiple Users
Each user gets their own S3 mount:
- User A: `/workspace/s3_usera/` → `/workspace/output/usera/`
- User B: `/workspace/s3_userb/` → `/workspace/output/userb/`

## 📊 Monitoring

### Check Active Mounts
```bash
# List S3FS mounts
mount | grep s3fs

# Check symlinks
ls -la /workspace/output/

# Monitor S3FS processes
ps aux | grep s3fs
```

### Logs
- S3FS logs: `/tmp/s3fs_cache/` (if enabled)
- Application logs: Check control panel for error messages
- System logs: `journalctl -f` for mount/unmount events

## 🔒 Security Notes

- S3 credentials are stored in `/workspace/.s3fs_passwd` (600 permissions)
- Mount points are user-specific to prevent conflicts
- Files are stored directly in S3 (no local copies)
- Access is controlled by S3 bucket permissions

## 🎉 Benefits

✅ **Real-time Access**: Files appear instantly in S3  
✅ **No Sync Delays**: Direct filesystem integration  
✅ **Cost Effective**: Single storage location  
✅ **Reliable**: No background processes to fail  
✅ **Scalable**: Works with any number of users  
✅ **Simple**: One-click setup from control panel  

---

**Ready to try it?** Start your pod, open the control panel, and click "Link to S3 (S3FS)"!
