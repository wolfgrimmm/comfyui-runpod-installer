#!/usr/bin/env python3
"""
Clear Triton cache and temporary files to fix attention mechanism issues
Especially important when switching between Sage Attention and Flash Attention
or after WAN 2.2 model updates
"""

import os
import shutil
from pathlib import Path
import tempfile
import subprocess

def get_directory_size(path):
    """Calculate total size of a directory"""
    total = 0
    try:
        for entry in os.scandir(path):
            if entry.is_file(follow_symlinks=False):
                total += entry.stat().st_size
            elif entry.is_dir(follow_symlinks=False):
                total += get_directory_size(entry.path)
    except:
        pass
    return total

def format_size(size_bytes):
    """Format bytes to human readable size"""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if size_bytes < 1024.0:
            return f"{size_bytes:.1f}{unit}"
        size_bytes /= 1024.0
    return f"{size_bytes:.1f}TB"

def clear_triton_cache():
    """Clear all Triton cache locations"""
    cleared_size = 0
    locations_cleared = []

    # List of potential Triton cache locations
    cache_paths = [
        Path.home() / ".triton",
        Path("/root/.triton"),
        Path("/workspace/.triton"),
        Path("/opt/.triton"),
    ]

    print("🧹 Clearing Triton cache for Sage Attention/WAN 2.2 optimization...")
    print("=" * 60)

    for cache_path in cache_paths:
        if cache_path.exists() and cache_path.is_dir():
            try:
                size = get_directory_size(cache_path)
                cleared_size += size
                print(f"📍 Found cache at: {cache_path}")
                print(f"   Size: {format_size(size)}")

                # Remove the cache directory
                shutil.rmtree(cache_path)
                locations_cleared.append(str(cache_path))
                print(f"   ✅ Cleared successfully")

            except PermissionError:
                print(f"   ⚠️ Permission denied: {cache_path}")
            except Exception as e:
                print(f"   ❌ Error: {e}")

    return cleared_size, locations_cleared

def clear_temp_triton_files():
    """Clear temporary Triton files from /tmp and other locations"""
    cleared_count = 0

    print("\n🗑️ Clearing temporary Triton files...")

    # Temporary directories to check
    temp_dirs = [
        Path("/tmp"),
        Path("/var/tmp"),
        Path(tempfile.gettempdir())
    ]

    patterns = ["triton_*", "tmp*triton*", "*kernel_cache*"]

    for temp_dir in temp_dirs:
        if not temp_dir.exists():
            continue

        for pattern in patterns:
            try:
                for item in temp_dir.glob(pattern):
                    try:
                        if item.is_file():
                            item.unlink()
                            cleared_count += 1
                        elif item.is_dir():
                            shutil.rmtree(item)
                            cleared_count += 1
                    except:
                        pass  # Skip files in use
            except:
                pass

    if cleared_count > 0:
        print(f"   ✅ Removed {cleared_count} temporary files")
    else:
        print(f"   ℹ️ No temporary Triton files found")

    return cleared_count

def clear_pytorch_caches():
    """Clear PyTorch and CUDA kernel caches"""
    cleared_size = 0

    print("\n🔧 Clearing PyTorch/CUDA caches...")

    cache_locations = [
        (Path.home() / ".cache/torch/kernels", "PyTorch kernels"),
        (Path.home() / ".cache/torch/hub", "PyTorch hub"),
        (Path.home() / ".nv/ComputeCache", "CUDA compute cache"),
        (Path("/root/.cache/torch/kernels"), "Root PyTorch kernels"),
    ]

    for cache_path, name in cache_locations:
        if cache_path.exists():
            try:
                size = get_directory_size(cache_path)
                cleared_size += size
                shutil.rmtree(cache_path)
                print(f"   ✅ Cleared {name}: {format_size(size)}")
            except:
                pass

    return cleared_size

def check_attention_mechanism():
    """Check current attention mechanism setting"""
    print("\n🔍 Checking attention mechanism configuration...")

    env_files = [
        "/workspace/venv/.env_settings",
        "/opt/venv/.env_settings",
    ]

    for env_file in env_files:
        if Path(env_file).exists():
            try:
                with open(env_file, 'r') as f:
                    content = f.read()
                    if 'COMFYUI_ATTENTION_MECHANISM' in content:
                        for line in content.split('\n'):
                            if 'COMFYUI_ATTENTION_MECHANISM' in line:
                                mechanism = line.split('=')[1].strip()
                                print(f"   Current mechanism: {mechanism}")

                                if mechanism == "sage":
                                    print("   🚀 Sage Attention configured (optimal for WAN 2.2 + RTX 5090)")
                                elif mechanism == "flash2":
                                    print("   ⚡ Flash Attention 2 configured")
                                elif mechanism == "xformers":
                                    print("   📦 xformers configured")
                                break
            except:
                pass

def restart_comfyui_advice():
    """Provide advice on restarting ComfyUI"""
    print("\n💡 Next steps:")
    print("   1. Restart ComfyUI from the control panel")
    print("   2. For WAN 2.2 on RTX 5090: Ensure Sage Attention is active")
    print("   3. If issues persist, try: touch /workspace/.comfyui_safe_mode")
    print("\n🚀 Performance tip for RTX 5090 + WAN 2.2:")
    print("   Sage Attention + Triton = 13x faster (40min → 3min)")

def main():
    print("=" * 60)
    print("🚀 Triton Cache Cleaner for WAN 2.2 + Sage Attention")
    print("=" * 60)

    # Clear Triton cache
    triton_size, triton_locations = clear_triton_cache()

    # Clear temporary files
    temp_count = clear_temp_triton_files()

    # Clear PyTorch caches
    pytorch_size = clear_pytorch_caches()

    # Total cleared
    total_cleared = triton_size + pytorch_size

    print("\n" + "=" * 60)
    print("📊 Summary:")
    print(f"   Total space freed: {format_size(total_cleared)}")
    print(f"   Triton locations cleared: {len(triton_locations)}")
    print(f"   Temporary files removed: {temp_count}")

    # Check current configuration
    check_attention_mechanism()

    # Provide next steps
    restart_comfyui_advice()

    print("=" * 60)
    print("✅ Cache clearing complete!")

    return 0

if __name__ == "__main__":
    try:
        exit(main())
    except KeyboardInterrupt:
        print("\n⚠️ Interrupted by user")
        exit(1)
    except Exception as e:
        print(f"\n❌ Error: {e}")
        exit(1)