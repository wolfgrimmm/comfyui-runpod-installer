# Build Optimization Guide

## Build Methods Comparison

### 1. 🚀 **RunPod-Optimized Build** (FASTEST)
```bash
./build-runpod.sh
```

**Base Image:** `runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04`

**Advantages:**
- ✅ PyTorch pre-installed (saves 5-10 min build time)
- ✅ CUDA/cuDNN pre-installed 
- ✅ Cached on RunPod servers (instant pulls)
- ✅ Optimized for RunPod infrastructure
- ✅ Smallest final image (~5GB)
- ✅ Instant startup on RunPod

**Build Time:** ~2-3 minutes
**Image Size:** ~5GB
**First Start:** Instant

---

### 2. ⚡ **Layered Build** (Best for Development)
```bash
./dev.sh
```

**Base Image:** `nvidia/cuda:12.4.0-devel-ubuntu22.04`

**Advantages:**
- ✅ Smart layer caching
- ✅ UI changes = 10 second rebuilds
- ✅ Live mount option for development
- ✅ Works anywhere (not RunPod-specific)

**Build Time:** 
- First: 5-10 minutes
- UI change: 10 seconds
- Script change: 30 seconds

**Image Size:** ~8GB
**First Start:** 2-5 minutes (if no venv)

---

### 3. 📦 **Universal Build** (Most Flexible)
```bash
./build.sh              # Fast mode (3GB, venv on demand)
./build.sh --traditional  # Full mode (15GB, everything included)
```

**Base Image:** `nvidia/cuda:12.4.0-devel-ubuntu22.04`

**Advantages:**
- ✅ Works everywhere
- ✅ Choice of size vs speed
- ✅ Persistent venv support

**Build Time:** 5-15 minutes
**Image Size:** 3GB (fast) or 15GB (traditional)
**First Start:** 5-10 min (fast) or instant (traditional)

---

## Build Time Improvements Summary

| Method | Build Time | Image Size | RunPod Start | Best For |
|--------|------------|------------|--------------|----------|
| RunPod-Optimized | 2-3 min | 5GB | Instant | Production on RunPod |
| Layered/Dev | 10 sec* | 8GB | 2-5 min | Development iteration |
| Universal Fast | 5 min | 3GB | 5-10 min | General use |
| Universal Traditional | 15 min | 15GB | Instant | No persistent storage |

*After initial build, for UI changes only

---

## Docker Layer Optimization

The layered approach organizes from least to most frequently changing:

```dockerfile
# Layer 1: Base OS (rarely changes) - CACHED
FROM nvidia/cuda:12.4.0-devel-ubuntu22.04

# Layer 2: System packages (occasionally) - CACHED
RUN apt-get install python git ...

# Layer 3: Python packages (occasionally) - CACHED  
RUN pip install torch ...

# Layer 4: Scripts (sometimes) - CACHED
COPY scripts /app/scripts

# Layer 5: Config (sometimes) - CACHED
COPY config /app/config  

# Layer 6: UI (frequently) - REBUILDS
COPY ui /app/ui
```

**Result:** UI changes only rebuild the last layer!

---

## RunPod Base Images Available

RunPod provides optimized base images:

- `runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04`
- `runpod/pytorch:2.2.0-py3.10-cuda12.1.0-devel-ubuntu22.04`
- `runpod/stable-diffusion:web-ui-10.2.1`

These images are:
- Pre-cached on RunPod infrastructure
- Include PyTorch, CUDA, cuDNN
- Optimized for RunPod's GPUs
- Start instantly

---

## Recommendations

### For RunPod Production:
Use **RunPod-optimized build** - it's specifically designed for their infrastructure and starts instantly.

### For Development:
Use **Layered build with dev.sh** - UI changes take seconds to test.

### For Other Platforms:
Use **Universal build** - works anywhere with flexible options.

---

## Quick Commands

```bash
# RunPod production (fastest on RunPod)
./build-runpod.sh
docker push yourusername/comfyui:runpod

# Development (fastest iteration)
./dev.sh
./dev.sh --run  # Test locally
docker compose up  # Full dev environment

# Universal (works anywhere)
./build.sh  # Minimal 3GB
./build.sh --traditional  # Full 15GB
```