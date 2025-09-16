# Automated Google Drive Setup

## 🚀 Fully Automated Setup Options

### Option 1: Service Account (Recommended - 100% Automatic)
1. Follow [GOOGLE_DRIVE_SETUP.txt](./GOOGLE_DRIVE_SETUP.txt) to create service account
2. Add `GOOGLE_SERVICE_ACCOUNT` secret in RunPod with the JSON
3. Deploy pod - **everything automatic!**

### Option 2: OAuth Token (Semi-Automatic)
1. **One-time setup on any machine:**
   ```bash
   rclone authorize "drive" '{"scope":"drive"}'
   ```
2. Copy the token JSON
3. Add as RunPod secret: `RCLONE_TOKEN`
4. Deploy pod - uses saved token

### Option 3: Reuse Existing Config (Pod Restarts)
- Config auto-saved to `/workspace/.config/rclone/`
- Survives container restarts
- Auto-restored on startup

## How It Works

### On Pod Start:
```
1. Check /workspace/.config/rclone/rclone.conf
   ├─ Exists? → Restore & Use
   └─ Missing? → Check RunPod Secrets
       ├─ GOOGLE_SERVICE_ACCOUNT? → Auto-configure
       ├─ RCLONE_TOKEN? → Auto-configure
       └─ Nothing? → Manual setup needed
```

### Auto-Sync Flow:
```
Config Found → Start UI → Auto-sync every 5 min
     ↓
/workspace/output/* → gdrive:ComfyUI/outputs/*/
```

## Current Status

✅ **Working:**
- Service Account auto-setup (if secret provided)
- Config persistence in `/workspace/`
- Auto-sync when configured
- Multi-user support

⚠️ **Needs RunPod Secret:**
- Either `GOOGLE_SERVICE_ACCOUNT` (best)
- Or `RCLONE_TOKEN` (good)
- Without these, manual setup required

## To Make 100% Automatic

Add one of these RunPod secrets:

### For Service Account:
```
Name: GOOGLE_SERVICE_ACCOUNT
Value: {paste entire service account JSON}
```

### For OAuth Token:
```
Name: RCLONE_TOKEN
Value: {"access_token":"...","token_type":"Bearer",...}
```

Then every new pod will auto-configure!