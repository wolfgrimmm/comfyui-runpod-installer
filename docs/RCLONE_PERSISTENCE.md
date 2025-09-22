# Rclone Configuration Persistence Guide

## How Rclone Config Persists on RunPod

### One-Time Setup ✅
**You only need to configure rclone ONCE per pod instance.** The configuration persists as long as your pod is running.

### Where Config is Stored

Rclone configuration is stored in **TWO locations** for redundancy:
1. `/root/.config/rclone/rclone.conf` - Container filesystem (persists during pod lifecycle)
2. `/workspace/.config/rclone/rclone.conf` - Workspace volume (persists across restarts)

### Configuration Methods

#### Method 1: Manual OAuth Setup (What You Did)
```bash
rclone config
# Follow prompts, authenticate with Google
# Config is saved to both locations automatically
```

#### Method 2: Service Account (Automatic)
- Add `GOOGLE_SERVICE_ACCOUNT` secret in RunPod
- Container automatically configures rclone on startup
- No manual intervention needed

### Persistence Scenarios

| Scenario | Config Persists? | Auto-Sync Continues? |
|----------|-----------------|---------------------|
| Stop/Start Pod | ✅ Yes | ✅ Yes (restarts automatically) |
| Restart Container | ✅ Yes | ✅ Yes (restarts automatically) |
| Pod Running | ✅ Yes | ✅ Yes (every 5 minutes) |
| Recreate Pod | ❌ No* | ❌ No |

*Unless using Service Account method or workspace config backup

### How Auto-Sync Works

1. **On UI Startup**: Checks if rclone is configured
2. **If Configured**: Automatically starts sync every 5 minutes
3. **Smart Sync**: Only syncs files that changed since last sync
4. **Logging**: All activity logged to `/workspace/gdrive_sync.log`

### Verify Configuration

Check if rclone is configured:
```bash
# Check if config exists
ls -la /root/.config/rclone/rclone.conf

# Test connection
rclone lsd gdrive:

# Check auto-sync logs
tail -f /workspace/gdrive_sync.log
```

### Backup Your Config (Optional)

To ensure config survives pod recreation:
```bash
# Backup to workspace (already done automatically)
cp /root/.config/rclone/rclone.conf /workspace/.config/rclone/

# The UI will restore from workspace on next startup
```

### Troubleshooting

**Config Lost After Pod Recreation?**
- Normal behavior - rclone config is in container filesystem
- Solution: Use Service Account method for automatic setup
- Or: Reconfigure once with `rclone config`

**Auto-Sync Not Starting?**
- Check logs: `tail -f /workspace/ui.log`
- Verify config: `rclone listremotes`
- Restart UI: `pkill -f app.py && python /app/ui/app.py &`

**Want to Change Sync Interval?**
- Default is 5 minutes
- Edit `/app/ui/app.py` line 1015: `interval_minutes=5`
- Restart UI to apply changes

### Summary

✅ **You're all set!** Your rclone configuration will persist as long as your pod is running.
- Auto-sync runs every 5 minutes
- Config survives container restarts
- Only needs reconfiguration if you recreate the entire pod
- Logs available at `/workspace/gdrive_sync.log`