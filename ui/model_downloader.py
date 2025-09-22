"""
Model Downloader module for ComfyUI
Handles HuggingFace model downloads with progress tracking
"""

import os
import json
import shutil
import threading
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import time

try:
    from huggingface_hub import snapshot_download, hf_hub_download, HfFileSystem
    from huggingface_hub.utils import HfHubHTTPError
    HF_AVAILABLE = True
except ImportError:
    HF_AVAILABLE = False

# Enable hf_transfer for faster downloads if available
try:
    import hf_transfer
    os.environ['HF_HUB_ENABLE_HF_TRANSFER'] = '1'
    print("✅ hf_transfer enabled for faster downloads (2-5x speed improvement)")
    HF_TRANSFER_AVAILABLE = True
except ImportError:
    HF_TRANSFER_AVAILABLE = False
    print("ℹ️ hf_transfer not available - downloads will use standard speed")

class ModelDownloader:
    def __init__(self, models_base_path="/workspace/ComfyUI/models"):
        """Initialize the model downloader with base paths."""
        self.models_base = models_base_path
        self.downloads = {}  # Track active downloads
        self.download_lock = threading.Lock()

        # Define model paths for ComfyUI
        self.model_paths = {
            'checkpoints': f'{self.models_base}/checkpoints',
            'diffusion_models': f'{self.models_base}/diffusion_models',  # For FLUX, GGUF models
            'loras': f'{self.models_base}/loras',
            'vae': f'{self.models_base}/vae',
            'clip': f'{self.models_base}/clip',
            'clip_vision': f'{self.models_base}/clip_vision',
            'controlnet': f'{self.models_base}/controlnet',
            'ipadapter': f'{self.models_base}/ipadapter',
            'embeddings': f'{self.models_base}/embeddings',
            'upscale_models': f'{self.models_base}/upscale_models',
            'inpaint': f'{self.models_base}/inpaint',
            'style_models': f'{self.models_base}/style_models',
            'photomaker': f'{self.models_base}/photomaker',
            'insightface': f'{self.models_base}/insightface',
            'facerestore_models': f'{self.models_base}/facerestore_models',
            'animatediff_models': f'{self.models_base}/animatediff_models',
            'animatediff_motion_lora': f'{self.models_base}/animatediff_motion_lora',
            'unclip': f'{self.models_base}/unclip',
            'gligen': f'{self.models_base}/gligen',
            'vae-approx': f'{self.models_base}/vae-approx',
            'blip': f'{self.models_base}/blip',
            'sams': f'{self.models_base}/sams',  # Segment Anything Models
            'onnx': f'{self.models_base}/onnx',
            'tensorrt': f'{self.models_base}/tensorrt',
            'text_encoders': f'{self.models_base}/text_encoders',
            'unet': f'{self.models_base}/unet',  # For separated unet models
            'custom_nodes': '/workspace/ComfyUI/custom_nodes',
        }

        # Create directories if they don't exist
        for path in self.model_paths.values():
            Path(path).mkdir(parents=True, exist_ok=True)

    def get_model_type_from_name(self, model_name: str, repo_id: str = "") -> str:
        """Determine model type from name and repo patterns."""
        name_lower = model_name.lower()
        repo_lower = repo_id.lower() if repo_id else ""

        # FLUX models -> diffusion_models
        if 'flux' in name_lower or 'flux' in repo_lower:
            return 'diffusion_models'

        # GGUF models -> diffusion_models
        if '.gguf' in name_lower or 'gguf' in repo_lower:
            return 'diffusion_models'

        # LoRA models
        if 'lora' in name_lower or 'lora' in repo_lower or 'lycoris' in name_lower:
            return 'loras'

        # VAE models
        if 'vae' in name_lower or 'vae' in repo_lower:
            return 'vae'

        # CLIP models
        if 'clip_vision' in name_lower or 'clip-vision' in repo_lower:
            return 'clip_vision'
        elif 'clip' in name_lower or 'clip' in repo_lower or 't5' in name_lower:
            return 'clip'

        # ControlNet
        if 'controlnet' in name_lower or 'control' in repo_lower:
            return 'controlnet'

        # IP-Adapter
        if 'ipadapter' in name_lower or 'ip-adapter' in name_lower or 'ip_adapter' in repo_lower:
            return 'ipadapter'

        # Upscale models
        if 'upscale' in name_lower or 'esrgan' in name_lower or 'real-esrgan' in repo_lower or '4x' in name_lower:
            return 'upscale_models'

        # AnimateDiff
        if 'animatediff' in name_lower or 'motion' in name_lower:
            if 'lora' in name_lower:
                return 'animatediff_motion_lora'
            return 'animatediff_models'

        # InsightFace
        if 'insightface' in name_lower or 'antelopev2' in name_lower or 'buffalo' in name_lower:
            return 'insightface'

        # FaceRestore
        if 'gfpgan' in name_lower or 'codeformer' in name_lower or 'facerestore' in repo_lower:
            return 'facerestore_models'

        # Photomaker
        if 'photomaker' in name_lower:
            return 'photomaker'

        # SAM models
        if 'sam_' in name_lower or 'segment-anything' in repo_lower or 'groundingdino' in name_lower:
            return 'sams'

        # Text encoders
        if 't5' in name_lower or 'text_encoder' in name_lower or 'text-encoder' in repo_lower:
            return 'text_encoders'

        # UNet models
        if 'unet' in name_lower and 'safetensors' in name_lower:
            return 'unet'

        # Default to checkpoints for main model files
        if '.safetensors' in name_lower or '.ckpt' in name_lower or '.pt' in name_lower:
            return 'checkpoints'

        # Embeddings
        if 'embedding' in name_lower or 'textual-inversion' in repo_lower:
            return 'embeddings'

        return 'checkpoints'  # Default

    def get_installed_models(self) -> Dict[str, List[Dict]]:
        """Get list of all installed models organized by type."""
        installed = {}

        for model_type, path in self.model_paths.items():
            if model_type == 'custom_nodes':
                continue

            models = []
            if os.path.exists(path):
                for file in os.listdir(path):
                    file_path = os.path.join(path, file)
                    if os.path.isfile(file_path):
                        # Check if it's a model file
                        if file.endswith(('.safetensors', '.ckpt', '.pt', '.pth', '.bin', '.gguf', '.onnx')):
                            size = os.path.getsize(file_path) / (1024**3)  # Size in GB
                            models.append({
                                'name': file,
                                'path': file_path,
                                'size': f"{size:.2f} GB",
                                'type': model_type
                            })
                    elif os.path.isdir(file_path):
                        # Check for model folders (like IP-Adapter, InsightFace)
                        dir_size = sum(
                            os.path.getsize(os.path.join(dirpath, filename))
                            for dirpath, dirnames, filenames in os.walk(file_path)
                            for filename in filenames
                        ) / (1024**3)
                        if dir_size > 0.01:  # Only show folders > 10MB
                            models.append({
                                'name': f"{file}/",
                                'path': file_path,
                                'size': f"{dir_size:.2f} GB",
                                'type': model_type
                            })

            if models:
                installed[model_type] = sorted(models, key=lambda x: x['name'])

        return installed

    def search_models(self, query: str, limit: int = 20) -> List[Dict]:
        """Search for models on HuggingFace Hub."""
        if not HF_AVAILABLE:
            return []

        try:
            from huggingface_hub import HfApi
            api = HfApi()

            # Search for models
            models = api.list_models(
                search=query,
                limit=limit,
                sort="downloads",
                direction=-1
            )

            results = []
            for model in models:
                # Filter for relevant model types
                tags = model.tags if hasattr(model, 'tags') else []

                # Check if it's a diffusion model or related
                is_relevant = any(tag in tags for tag in [
                    'diffusers', 'stable-diffusion', 'text-to-image',
                    'controlnet', 'lora', 'safetensors', 'gguf',
                    'image-to-image', 'flux', 'sdxl', 'sd3'
                ])

                if is_relevant or 'diffusion' in query.lower():
                    results.append({
                        'name': model.modelId,
                        'downloads': getattr(model, 'downloads', 0),
                        'likes': getattr(model, 'likes', 0),
                        'tags': tags[:5]  # Limit tags for display
                    })

            return results

        except Exception as e:
            print(f"Search error: {e}")
            return []

    def download_model(self, repo_id: str, filename: Optional[str] = None,
                      model_type: Optional[str] = None, is_snapshot: bool = False) -> str:
        """
        Download a model from HuggingFace Hub.

        Args:
            repo_id: HuggingFace repository ID
            filename: Specific file to download (None for full repo)
            model_type: Type of model for organizing in folders
            is_snapshot: Whether to download the entire repository

        Returns:
            Download ID for tracking progress
        """
        if not HF_AVAILABLE:
            raise ImportError("huggingface_hub is not installed")

        # Generate download ID
        download_id = f"{repo_id}_{filename or 'snapshot'}_{int(time.time())}"

        # Determine destination
        if not model_type:
            model_type = self.get_model_type_from_name(filename or repo_id, repo_id)

        dest_path = self.model_paths.get(model_type, self.model_paths['checkpoints'])

        # Initialize download tracking
        with self.download_lock:
            self.downloads[download_id] = {
                'repo_id': repo_id,
                'filename': filename,
                'model_type': model_type,
                'status': 'starting',
                'progress': 0,
                'error': None,
                'dest_path': dest_path,
                'started_at': time.time()
            }

        # Start download in background thread
        thread = threading.Thread(
            target=self._download_worker,
            args=(download_id, repo_id, filename, dest_path, is_snapshot)
        )
        thread.daemon = True
        thread.start()

        return download_id

    def _download_worker(self, download_id: str, repo_id: str,
                        filename: Optional[str], dest_path: str, is_snapshot: bool):
        """Worker thread for downloading models."""
        try:
            with self.download_lock:
                self.downloads[download_id]['status'] = 'downloading'

            if is_snapshot or filename is None:
                # Download entire repository
                local_path = snapshot_download(
                    repo_id=repo_id,
                    local_dir=os.path.join(dest_path, repo_id.split('/')[-1]),
                    local_dir_use_symlinks=False,
                    resume_download=True
                )
            else:
                # Download specific file
                local_path = hf_hub_download(
                    repo_id=repo_id,
                    filename=filename,
                    local_dir=dest_path,
                    local_dir_use_symlinks=False,
                    resume_download=True
                )

            with self.download_lock:
                self.downloads[download_id]['status'] = 'completed'
                self.downloads[download_id]['progress'] = 100
                self.downloads[download_id]['local_path'] = local_path

        except Exception as e:
            with self.download_lock:
                self.downloads[download_id]['status'] = 'error'
                self.downloads[download_id]['error'] = str(e)

    def get_download_status(self, download_id: str) -> Optional[Dict]:
        """Get status of a specific download."""
        with self.download_lock:
            return self.downloads.get(download_id, None)

    def get_all_downloads(self) -> Dict:
        """Get status of all downloads."""
        with self.download_lock:
            return self.downloads.copy()

    def cancel_download(self, download_id: str) -> bool:
        """Cancel a download (placeholder - actual cancellation needs more work)."""
        with self.download_lock:
            if download_id in self.downloads:
                self.downloads[download_id]['status'] = 'cancelled'
                return True
        return False

    def get_disk_usage(self) -> Dict:
        """Get disk usage information for the models directory."""
        try:
            stat = shutil.disk_usage(self.models_base)
            return {
                'total': stat.total / (1024**3),  # GB
                'used': stat.used / (1024**3),
                'free': stat.free / (1024**3),
                'percent': (stat.used / stat.total) * 100
            }
        except:
            return {'total': 0, 'used': 0, 'free': 0, 'percent': 0}

    def get_transfer_status(self) -> Dict:
        """Get the status of hf_transfer for diagnostics."""
        return {
            'hf_transfer_available': HF_TRANSFER_AVAILABLE,
            'hf_transfer_enabled': os.environ.get('HF_HUB_ENABLE_HF_TRANSFER') == '1',
            'speed_boost': '2-5x faster' if HF_TRANSFER_AVAILABLE else 'standard speed'
        }

    def delete_model(self, model_path: str) -> bool:
        """Delete a model file or directory."""
        try:
            if os.path.isfile(model_path):
                os.remove(model_path)
            elif os.path.isdir(model_path):
                shutil.rmtree(model_path)
            return True
        except Exception as e:
            print(f"Error deleting model: {e}")
            return False