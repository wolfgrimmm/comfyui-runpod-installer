# ComfyUI RunPod Installer - Overview

## What This Is

A production-ready Docker container for deploying ComfyUI on RunPod with enterprise features.

## Core Components

### Control Panel (Port 7777)
Web-based management interface for ComfyUI operations, user management, and system monitoring.

### Model Manager
Integrated HuggingFace downloader with automatic organization and 2-5x faster speeds via hf_transfer.

### GPU Optimization
Automatic detection and configuration of optimal attention mechanisms based on hardware.

### Google Drive Integration
Optional automatic synchronization of outputs to Google Drive for backup and sharing.

## Architecture

```
Docker Container (PyTorch 2.8.0 + CUDA 12.9)
├── Control Panel (Flask)
├── ComfyUI (Main Application)
├── Model Manager (HuggingFace Integration)
└── Sync Services (Google Drive)
```

## Supported GPUs

- **Hopper**: H100, H200 (Flash Attention 3)
- **Blackwell**: RTX 5090, B200 (Sage Attention 2.2.0)
- **Ampere**: A100, RTX 30xx (Flash Attention 2)
- **Ada Lovelace**: RTX 40xx, L40S (xformers)

## Key Features

- Pre-compiled attention mechanisms for faster startup
- Persistent storage in `/workspace` volume
- Multi-user support with usage tracking
- Resource monitoring and management
- Automatic model organization
- GGUF quantized model support

## Use Cases

- AI art generation studios
- Research and development
- Production rendering pipelines
- Multi-user creative teams
- Cloud-based AI services

## Technology Stack

- **Base**: Ubuntu 22.04 + Python 3.10
- **ML Framework**: PyTorch 2.8.0 with CUDA 12.9
- **Web Framework**: Flask + Bootstrap
- **Storage**: Persistent volumes + optional cloud sync
- **Optimization**: Pre-compiled wheels, UV package manager