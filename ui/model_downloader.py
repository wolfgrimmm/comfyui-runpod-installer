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

# Import CivitAI integration with proper error handling
try:
    from civitai_integration import CivitAIClient
    CIVITAI_AVAILABLE = True
except ImportError:
    CIVITAI_AVAILABLE = False
    print("⚠️ CivitAI integration not available - CivitAI features disabled")
    # Create a dummy CivitAIClient class for compatibility
    class CivitAIClient:
        def __init__(self, *args, **kwargs):
            pass
        def search_civitai_models(self, *args, **kwargs):
            return {"items": [], "metadata": {"totalItems": 0}}
        def download_civitai_model(self, *args, **kwargs):
            raise NotImplementedError("CivitAI integration not available")
        def get_civitai_trending(self, *args, **kwargs):
            return {"items": [], "metadata": {"totalItems": 0}}
        def set_civitai_api_key(self, *args, **kwargs):
            return False
        def verify_api_key(self):
            return False
        def get_popular_bundles(self):
            return {}

class ModelDownloader:
    def __init__(self, models_base_path="/workspace/models"):
        """Initialize the model downloader with base paths."""
        self.models_base = models_base_path
        self.downloads = {}  # Track active downloads
        self.download_lock = threading.Lock()
        self.bundle_downloads = {}  # Track bundle downloads

        # Initialize CivitAI client (optional - don't crash if it fails)
        try:
            self.civitai_client = CivitAIClient(models_base_path=models_base_path)
        except Exception as e:
            print(f"⚠️ CivitAI client initialization failed: {e}")
            self.civitai_client = None

        # Define model bundles
        self.model_bundles = self._get_model_bundles()

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

        # Try to create directories, but don't crash if it fails
        for path in self.model_paths.values():
            try:
                Path(path).mkdir(parents=True, exist_ok=True)
            except Exception as e:
                # Don't crash the entire initialization if directory creation fails
                print(f"⚠️ Could not create directory {path}: {e}")
                # Continue - directory will be created when actually needed

    def _get_model_bundles(self):
        """Define pre-configured model bundles for easy download."""
        return {
            # SwarmUI Bundles
            "qwen_image_core": {
                "name": "Qwen Image Core Bundle",
                "description": "Core Qwen Image models for image generation with necessary components",
                "category": "Image Generation",
                "models": [
                    {"repo_id": "city96/Qwen-Image-GGUF", "filename": "qwen_image-Q8_0.gguf",
                     "model_type": "diffusion_models", "size": "11.8 GB"},
                    {"repo_id": "city96/Qwen-Image-Edit-GGUF", "filename": "qwen_image_edit-Q8_0.gguf",
                     "model_type": "diffusion_models", "size": "11.8 GB"},
                    {"repo_id": "Comfy-Org/Qwen_2.5-VL-7B_FP8_Scaled", "filename": "qwen_2.5_vl_7b_fp8_scaled.safetensors",
                     "model_type": "clip", "size": "7.2 GB"},
                    {"repo_id": "black-forest-labs/FLUX.1-dev", "filename": "vae/diffusion_pytorch_model.safetensors",
                     "save_as": "qwen_image_vae.safetensors", "model_type": "vae", "size": "335 MB"},
                    {"repo_id": "Comfy-Org/qwen-image-loras", "filename": "qwen_image_lightning_8steps_v1.1.safetensors",
                     "model_type": "loras", "size": "185 MB"},
                ],
                "total_size": "31.3 GB"
            },
            "wan22_core": {
                "name": "Wan 2.2 Core 8 Steps Bundle",
                "description": "New Wan 2.2 models in FP8 for efficient 8-step video generation",
                "category": "Wan Video Bundles",
                "models": [
                    {"repo_id": "OpenGVLab/InternVideo2", "filename": "wan2.2_i2v_high_noise_14b_fp8_scaled.safetensors",
                     "model_type": "diffusion_models", "size": "13.5 GB"},
                    {"repo_id": "OpenGVLab/InternVideo2", "filename": "wan2.2_i2v_low_noise_14b_fp8_scaled.safetensors",
                     "model_type": "diffusion_models", "size": "13.5 GB"},
                    {"repo_id": "OpenGVLab/InternVideo2", "filename": "wan2.2_t2v_high_noise_14b_fp8_scaled.safetensors",
                     "model_type": "diffusion_models", "size": "13.5 GB"},
                    {"repo_id": "OpenGVLab/InternVideo2", "filename": "wan2.2_t2v_low_noise_14b_fp8_scaled.safetensors",
                     "model_type": "diffusion_models", "size": "13.5 GB"},
                    {"repo_id": "OpenGVLab/InternVideo2", "filename": "wan2.2_vae.safetensors",
                     "model_type": "vae", "size": "335 MB"},
                    {"repo_id": "Comfy-Org/Wan_2.1_ComfyUI_repackaged", "filename": "split_files/text_encoders/umt5_xxl_fp16.safetensors",
                     "model_type": "clip", "size": "23.7 GB"},
                ],
                "total_size": "78.0 GB"
            },
            "wan21_core": {
                "name": "Wan 2.1 Core Models Bundle (GGUF Q6_K + Best LoRAs)",
                "description": "Core Wan 2.1 models for video generation including T2V, I2V and companion LoRAs",
                "category": "Wan Video Bundles",
                "models": [
                    {"repo_id": "Comfy-Org/Wan_2.1_ComfyUI_repackaged", "filename": "split_files/diffusion_models/wan2.1_t2v_1.3B_fp16.safetensors",
                     "save_as": "Wan2.1_1.3b_Text_to_Video.safetensors", "model_type": "diffusion_models", "size": "2.5 GB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Wan21_T2V_14B_720p_GGUF_Q6_K.gguf",
                     "model_type": "diffusion_models", "size": "10.7 GB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Wan21_I2V_14B_720p_GGUF_Q6_K.gguf",
                     "model_type": "diffusion_models", "size": "10.7 GB"},
                    {"repo_id": "Comfy-Org/Wan_2.1_ComfyUI_repackaged", "filename": "split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors",
                     "model_type": "clip", "size": "11.9 GB"},
                    {"repo_id": "Kijai/WanVideo_comfy", "filename": "wan-256-hw-16-vae.safetensors",
                     "save_as": "wan_2.1_vae.safetensors", "model_type": "vae", "size": "128 MB"},
                    {"repo_id": "openai/clip-vit-large-patch14", "filename": "pytorch_model.bin",
                     "save_as": "clip_vision_h.safetensors", "model_type": "clip_vision", "size": "1.7 GB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Wan21_14B_LightX2V_CFG_Step_Distill_LoRA_V2_T2V_I2V_Rank_64.safetensors",
                     "model_type": "loras", "size": "377 MB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Wan21_T2V_14B_FusionX_LoRA.safetensors",
                     "model_type": "loras", "size": "188 MB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Wan21_I2V_14B_FusionX_LoRA.safetensors",
                     "model_type": "loras", "size": "188 MB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Wan21_14B_Self_Forcing_LoRA_T2V_I2V.safetensors",
                     "model_type": "loras", "size": "188 MB"},
                ],
                "total_size": "38.7 GB"
            },
            "flux_bundle": {
                "name": "FLUX Models Bundle",
                "description": "Core set of FLUX models for ComfyUI plus common utility models",
                "category": "FLUX Bundles",
                "models": [
                    {"repo_id": "Comfy-Org/FLUX.1-dev", "filename": "flux1-dev.safetensors",
                     "save_as": "FLUX_Dev.safetensors", "model_type": "checkpoints", "size": "23.8 GB"},
                    {"repo_id": "black-forest-labs/FLUX.1-Fill-dev", "filename": "flux1-fill-dev.safetensors",
                     "save_as": "FLUX_DEV_Fill.safetensors", "model_type": "checkpoints", "size": "23.8 GB"},
                    {"repo_id": "black-forest-labs/FLUX.1-Redux-dev", "filename": "flux1-redux-dev.safetensors",
                     "save_as": "FLUX_DEV_Redux.safetensors", "model_type": "checkpoints", "size": "23.8 GB"},
                    {"repo_id": "MonsterMMORPG/Best_FLUX_Models", "filename": "flux1-kontext-dev.safetensors",
                     "save_as": "FLUX_Kontext_Dev.safetensors", "model_type": "checkpoints", "size": "23.8 GB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "flux1-krea-dev.safetensors",
                     "save_as": "FLUX_Krea_Dev.safetensors", "model_type": "checkpoints", "size": "23.8 GB"},
                    {"repo_id": "Comfy-Org/flux_text_encoders", "filename": "t5xxl_fp16.safetensors",
                     "save_as": "t5xxl_enconly.safetensors", "model_type": "clip", "size": "9.5 GB"},
                    {"repo_id": "black-forest-labs/FLUX.1-dev", "filename": "ae.safetensors",
                     "save_as": "FLUX_VAE.safetensors", "model_type": "vae", "size": "335 MB"},
                    {"repo_id": "comfyanonymous/flux_text_encoders", "filename": "clip_l.safetensors",
                     "model_type": "clip", "size": "246 MB"},
                ],
                "total_size": "128.9 GB"
            },
            "flux_gguf_bundle": {
                "name": "FLUX GGUF Optimized Bundle",
                "description": "Quantized FLUX models for low VRAM including Kontext and Krea",
                "category": "FLUX Bundles",
                "models": [
                    {"repo_id": "city96/FLUX.1-dev-gguf", "filename": "flux1-dev-Q8_0.gguf",
                     "save_as": "FLUX_Dev_GGUF_Q8_0.gguf", "model_type": "diffusion_models", "size": "12.2 GB"},
                    {"repo_id": "city96/FLUX.1-dev-gguf", "filename": "flux1-dev-Q6_K.gguf",
                     "save_as": "FLUX_Dev_GGUF_Q6_K.gguf", "model_type": "diffusion_models", "size": "9.2 GB"},
                    {"repo_id": "city96/FLUX.1-dev-gguf", "filename": "flux1-dev-Q5_K_S.gguf",
                     "save_as": "FLUX_Dev_GGUF_Q5_K_S.gguf", "model_type": "diffusion_models", "size": "7.7 GB"},
                    {"repo_id": "city96/FLUX.1-dev-gguf", "filename": "flux1-dev-Q4_K_S.gguf",
                     "save_as": "FLUX_Dev_GGUF_Q4_K_S.gguf", "model_type": "diffusion_models", "size": "6.3 GB"},
                    {"repo_id": "bullerwins/FLUX.1-Kontext-dev-GGUF", "filename": "flux1-kontext-dev-Q8_0.gguf",
                     "save_as": "FLUX_Kontext_Dev_GGUF_Q8_0.gguf", "model_type": "diffusion_models", "size": "12.2 GB"},
                    {"repo_id": "bullerwins/FLUX.1-Kontext-dev-GGUF", "filename": "flux1-kontext-dev-Q6_K.gguf",
                     "save_as": "FLUX_Kontext_Dev_GGUF_Q6_K.gguf", "model_type": "diffusion_models", "size": "9.2 GB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "flux1_krea_dev_BF16_Q8_0.gguf",
                     "save_as": "FLUX_Krea_Dev_GGUF_Q8_0.gguf", "model_type": "diffusion_models", "size": "12.2 GB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "flux1_krea_dev_BF16_Q6_K.gguf",
                     "save_as": "FLUX_Krea_Dev_GGUF_Q6_K.gguf", "model_type": "diffusion_models", "size": "9.2 GB"},
                ],
                "total_size": "78.5 GB"
            },
            "hidream_i1_dev": {
                "name": "HiDream-I1 Dev Bundle (Recommended)",
                "description": "Recommended HiDream-I1 Dev model (Q8 GGUF) with necessary supporting files",
                "category": "Image Generation",
                "models": [
                    {"repo_id": "MonsterMMORPG/HiDream-I1-Dev", "filename": "HiDream-I1-Dev-Q8_0.gguf",
                     "model_type": "diffusion_models", "size": "10.6 GB"},
                    {"repo_id": "MonsterMMORPG/HiDream-I1-Dev", "filename": "HiDream-I1_VAE.safetensors",
                     "model_type": "vae", "size": "335 MB"},
                    {"repo_id": "MonsterMMORPG/HiDream-I1-Dev", "filename": "clip_l.safetensors",
                     "model_type": "clip", "size": "246 MB"},
                    {"repo_id": "MonsterMMORPG/HiDream-I1-Dev", "filename": "t5xxl_fp16.safetensors",
                     "model_type": "clip", "size": "9.5 GB"},
                ],
                "total_size": "20.7 GB"
            },
            "sd35_bundle": {
                "name": "Stable Diffusion 3.5 Large Bundle",
                "description": "SD3.5 Large Official models in multiple formats (FP16, FP8, GGUF)",
                "category": "Image Generation",
                "models": [
                    {"repo_id": "OwlMaster/SD3New", "filename": "sd3.5_large.safetensors",
                     "save_as": "SD3.5_Official_Large.safetensors", "model_type": "checkpoints", "size": "16.0 GB"},
                    {"repo_id": "OwlMaster/SD3New", "filename": "sd3.5_large_fp8_scaled.safetensors",
                     "save_as": "SD3.5_Official_Large_FP8_Scaled.safetensors", "model_type": "checkpoints", "size": "8.0 GB"},
                    {"repo_id": "city96/stable-diffusion-3.5-large-gguf", "filename": "sd3.5_large-Q8_0.gguf",
                     "save_as": "SD3.5_Official_Large_GGUF_Q8.gguf", "model_type": "diffusion_models", "size": "8.5 GB"},
                    {"repo_id": "city96/stable-diffusion-3.5-large-gguf", "filename": "sd3.5_large-Q6_K.gguf",
                     "save_as": "SD3.5_Official_Large_GGUF_Q6_K.gguf", "model_type": "diffusion_models", "size": "6.6 GB"},
                    {"repo_id": "city96/stable-diffusion-3.5-large-gguf", "filename": "sd3.5_large-Q5_1.gguf",
                     "save_as": "SD3.5_Official_Large_GGUF_Q5_1.gguf", "model_type": "diffusion_models", "size": "5.8 GB"},
                    {"repo_id": "city96/stable-diffusion-3.5-large-gguf", "filename": "sd3.5_large-Q4_1.gguf",
                     "save_as": "SD3.5_Official_Large_GGUF_Q4_1.gguf", "model_type": "diffusion_models", "size": "4.7 GB"},
                ],
                "total_size": "49.6 GB"
            },
            "ltx_video_bundle": {
                "name": "LTX Video 13B Dev Bundle",
                "description": "LTX 13B Dev models for video generation with VAE",
                "category": "Video Generation",
                "models": [
                    {"repo_id": "Lightricks/LTX-Video", "filename": "ltx-video-13b-v0.9.safetensors",
                     "save_as": "LTX_Video_13B_Dev.safetensors", "model_type": "diffusion_models", "size": "25.5 GB"},
                    {"repo_id": "wsbagnsv1/ltxv-13b-0.9.7-dev-GGUF", "filename": "ltxv-13b-0.9.7-vae-BF16.safetensors",
                     "save_as": "LTX_VAE_13B_Dev_BF16.safetensors", "model_type": "vae", "size": "335 MB"},
                    {"repo_id": "Comfy-Org/Wan_2.1_ComfyUI_repackaged", "filename": "split_files/text_encoders/t5xxl_fp16.safetensors",
                     "model_type": "clip", "size": "9.5 GB"},
                ],
                "total_size": "35.3 GB"
            },
            "wan21_extended": {
                "name": "Wan 2.1 Extended Bundle (All LoRAs)",
                "description": "Complete collection of Wan 2.1 LoRAs including CausVid, Phantom, and all FusionX variants",
                "category": "Wan Video Bundles",
                "models": [
                    {"repo_id": "Kijai/WanVideo_comfy", "filename": "Wan21_CausVid_14B_T2V_lora_rank32_v2.safetensors",
                     "save_as": "Wan21_CausVid_14B_T2V_lora_rank32_v2.safetensors", "model_type": "loras", "size": "188 MB"},
                    {"repo_id": "Kijai/WanVideo_comfy", "filename": "Wan21_CausVid_14B_T2V_lora_rank32.safetensors",
                     "save_as": "Wan21_CausVid_14B_T2V_lora_rank32.safetensors", "model_type": "loras", "size": "188 MB"},
                    {"repo_id": "Kijai/WanVideo_comfy", "filename": "Wan21_CausVid_bidirect2_T2V_1_3B_lora_rank32.safetensors",
                     "save_as": "Wan21_CausVid_1.3B_T2V_lora_rank32.safetensors", "model_type": "loras", "size": "94 MB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Phantom_Wan_14B_FusionX_LoRA.safetensors",
                     "save_as": "Phantom_Wan_14B_FusionX_LoRA.safetensors", "model_type": "loras", "size": "188 MB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Wan21_I2V_14B_FusionX_LoRA.safetensors",
                     "model_type": "loras", "size": "188 MB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Wan21_T2V_14B_FusionX_LoRA.safetensors",
                     "model_type": "loras", "size": "188 MB"},
                ],
                "total_size": "1.0 GB"
            },
            "wan21_fusionx_gguf": {
                "name": "Wan 2.1 FusionX GGUF Collection",
                "description": "All GGUF quantizations of Wan 2.1 FusionX models for I2V and T2V",
                "category": "Wan Video Bundles",
                "models": [
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Wan21_FusionX_I2V_14B_GGUF_Q8.gguf",
                     "model_type": "diffusion_models", "size": "14.3 GB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Wan21_FusionX_I2V_14B_GGUF_Q6_K.gguf",
                     "model_type": "diffusion_models", "size": "10.7 GB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Wan21_FusionX_I2V_14B_GGUF_Q5_K_M.gguf",
                     "model_type": "diffusion_models", "size": "9.3 GB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Wan21_FusionX_I2V_14B_GGUF_Q4_K_M.gguf",
                     "model_type": "diffusion_models", "size": "7.9 GB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Wan21_FusionX_T2V_14B_GGUF_Q8_0.gguf",
                     "model_type": "diffusion_models", "size": "14.3 GB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Wan21_FusionX_T2V_14B_GGUF_Q6_K.gguf",
                     "model_type": "diffusion_models", "size": "10.7 GB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Wan21_FusionX_T2V_14B_GGUF_Q5_K_M.gguf",
                     "model_type": "diffusion_models", "size": "9.3 GB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Wan21_FusionX_T2V_14B_GGUF_Q4_K_M.gguf",
                     "model_type": "diffusion_models", "size": "7.9 GB"},
                ],
                "total_size": "84.4 GB"
            },
            "qwen_extended": {
                "name": "Qwen Image Extended Bundle (All Quantizations)",
                "description": "Complete Qwen Image model collection with all GGUF and safetensor variants",
                "category": "Image Generation",
                "models": [
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "qwen-image-Q8_0.gguf",
                     "save_as": "Qwen_Image_Q8_0.gguf", "model_type": "diffusion_models", "size": "11.8 GB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "qwen-image-Q6_K.gguf",
                     "save_as": "Qwen_Image_Q6_K.gguf", "model_type": "diffusion_models", "size": "8.9 GB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "qwen-image-Q5_1.gguf",
                     "save_as": "Qwen_Image_Q5_1.gguf", "model_type": "diffusion_models", "size": "8.1 GB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "qwen-image-Q4_1.gguf",
                     "save_as": "Qwen_Image_Q4_1.gguf", "model_type": "diffusion_models", "size": "6.7 GB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "qwen_image_fp8_e4m3fn.safetensors",
                     "save_as": "Qwen_Image_FP8_e4m3f.safetensors", "model_type": "diffusion_models", "size": "10.8 GB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "qwen_image_bf16.safetensors",
                     "save_as": "Qwen_Image_BF16.safetensors", "model_type": "diffusion_models", "size": "21.5 GB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Qwen-Image-Lightning-8steps-V1.1.safetensors",
                     "save_as": "Qwen-Image-Lightning-8steps-V1.1.safetensors", "model_type": "loras", "size": "185 MB"},
                ],
                "total_size": "68.0 GB"
            },
            # ComfyUI Bundles
            "clothing_migration": {
                "name": "Clothing Migration Workflow Bundle",
                "description": "All necessary models for Clothing Migration workflow in ComfyUI",
                "category": "Workflow Bundles",
                "models": [
                    {"repo_id": "John6666/joy-caption-alpha-two-flux-nf4-gguf", "filename": "model.safetensors",
                     "model_type": "text_encoders", "size": "8.5 GB"},
                    {"repo_id": "TTPlanet/Migration-LoRA-Cloth", "filename": "migration_lora_cloth.safetensors",
                     "model_type": "loras", "size": "185 MB"},
                    {"repo_id": "TTPlanet/Figures-TTP-Migration-LoRA", "filename": "figures_migration.safetensors",
                     "model_type": "loras", "size": "185 MB"},
                    {"repo_id": "google/siglip-so400m-patch14-384", "filename": "model.safetensors",
                     "model_type": "clip_vision", "size": "877 MB"},
                    {"repo_id": "meta-llama/Meta-Llama-3.1-8B-Instruct", "filename": "model.safetensors",
                     "model_type": "text_encoders", "size": "16.1 GB"},
                    {"repo_id": "black-forest-labs/FLUX.1-dev", "filename": "ae.safetensors",
                     "model_type": "vae", "size": "335 MB"},
                    {"repo_id": "alimama-creative/FLUX-dev-Controlnet-Inpainting-Beta", "filename": "diffusion_pytorch_model.safetensors",
                     "model_type": "controlnet", "size": "3.58 GB"},
                    {"repo_id": "comfyanonymous/flux_text_encoders", "filename": "t5xxl_fp16.safetensors",
                     "model_type": "clip", "size": "9.5 GB"},
                    {"repo_id": "comfyanonymous/flux_text_encoders", "filename": "clip_l.safetensors",
                     "model_type": "clip", "size": "246 MB"},
                ],
                "total_size": "39.3 GB"
            },
            "comfyui_multitalk": {
                "name": "ComfyUI MultiTalk Bundle",
                "description": "All models for ComfyUI MultiTalk workflow including Wan 2.1 MultiTalk",
                "category": "Workflow Bundles",
                "models": [
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Wan21_14B_LightX2V_CFG_Step_Distill_LoRA_V2_T2V_I2V_Rank_64.safetensors",
                     "model_type": "loras", "size": "377 MB"},
                    {"repo_id": "Kijai/WanVideo_comfy", "filename": "wan2.1_uni3c_controlnet.safetensors",
                     "model_type": "controlnet", "size": "1.3 GB"},
                    {"repo_id": "OpenGVLab/InternVideo2", "filename": "WanVideo_2.1_MultiTalk_14B_FP32.safetensors",
                     "model_type": "diffusion_models", "size": "56 GB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Wan21_I2V_14B_480p_GGUF_Q8.gguf",
                     "model_type": "diffusion_models", "size": "14.3 GB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Wan21_I2V_14B_720p_GGUF_Q8.gguf",
                     "model_type": "diffusion_models", "size": "14.3 GB"},
                    {"repo_id": "openai/clip-vit-large-patch14", "filename": "pytorch_model.bin",
                     "save_as": "clip_vision_h.safetensors", "model_type": "clip_vision", "size": "1.7 GB"},
                    {"repo_id": "Comfy-Org/Wan_2.1_ComfyUI_repackaged", "filename": "split_files/text_encoders/umt5_xxl_fp16.safetensors",
                     "model_type": "clip", "size": "23.7 GB"},
                    {"repo_id": "Kijai/WanVideo_comfy", "filename": "wan-256-hw-16-vae.safetensors",
                     "save_as": "wan_2.1_vae.safetensors", "model_type": "vae", "size": "128 MB"},
                ],
                "total_size": "111.7 GB"
            },
            "sdxl_essential": {
                "name": "SDXL Essential Bundle",
                "description": "SDXL base, refiner, and VAE",
                "category": "Image Generation",
                "models": [
                    {"repo_id": "stabilityai/stable-diffusion-xl-base-1.0",
                     "filename": "sd_xl_base_1.0.safetensors", "model_type": "checkpoints", "size": "6.9 GB"},
                    {"repo_id": "stabilityai/stable-diffusion-xl-refiner-1.0",
                     "filename": "sd_xl_refiner_1.0.safetensors", "model_type": "checkpoints", "size": "6.1 GB"},
                    {"repo_id": "madebyollin/sdxl-vae-fp16-fix", "filename": "sdxl_vae.safetensors",
                     "model_type": "vae", "size": "335 MB"},
                ],
                "total_size": "13.3 GB"
            },
            "controlnet_pack": {
                "name": "ControlNet Collection",
                "description": "Essential ControlNet models for SDXL",
                "category": "Other Models",
                "models": [
                    {"repo_id": "diffusers/controlnet-canny-sdxl-1.0",
                     "filename": "diffusion_pytorch_model.fp16.safetensors",
                     "model_type": "controlnet", "size": "2.5 GB"},
                    {"repo_id": "diffusers/controlnet-depth-sdxl-1.0",
                     "filename": "diffusion_pytorch_model.fp16.safetensors",
                     "model_type": "controlnet", "size": "2.5 GB"},
                    {"repo_id": "SargeZT/controlnet-sd-xl-1.0-openpose-fp16",
                     "filename": "OpenPoseXL2.safetensors",
                     "model_type": "controlnet", "size": "2.5 GB"},
                ],
                "total_size": "7.5 GB"
            },
            "upscaler_pack": {
                "name": "Upscaler Collection",
                "description": "Popular upscaling models (4x)",
                "category": "Other Models",
                "models": [
                    {"repo_id": "uwg/upscaler", "filename": "ESRGAN/ESRGAN_4x.pth",
                     "model_type": "upscale_models", "size": "67 MB"},
                    {"repo_id": "uwg/upscaler", "filename": "ESRGAN/RealESRGAN_x4plus.pth",
                     "model_type": "upscale_models", "size": "67 MB"},
                    {"repo_id": "uwg/upscaler", "filename": "ESRGAN/RealESRGAN_x4plus_anime_6B.pth",
                     "model_type": "upscale_models", "size": "18 MB"},
                    {"repo_id": "uwg/upscaler", "filename": "ESRGAN/4x_foolhardy_Remacri.pth",
                     "model_type": "upscale_models", "size": "67 MB"},
                ],
                "total_size": "219 MB"
            },
            "insightface_bundle": {
                "name": "InsightFace Bundle",
                "description": "Face analysis and swap models",
                "category": "Other Models",
                "models": [
                    {"repo_id": "public-data/insightface", "filename": "models/buffalo_l.zip",
                     "model_type": "insightface", "size": "326 MB"},
                    {"repo_id": "public-data/insightface", "filename": "models/antelopev2.zip",
                     "model_type": "insightface", "size": "360 MB"},
                ],
                "total_size": "686 MB"
            },

            # Additional SwarmUI Bundles
            "wan22_fp16_bundle": {
                "name": "Wan 2.2 FP16 Complete Bundle",
                "description": "Wan 2.2 models in FP16 format for highest quality video generation",
                "category": "Wan Video Bundles",
                "models": [
                    {"repo_id": "OpenGVLab/InternVideo2", "filename": "wan2.2_i2v_high_noise_14b_fp16.safetensors",
                     "model_type": "diffusion_models", "size": "27 GB"},
                    {"repo_id": "OpenGVLab/InternVideo2", "filename": "wan2.2_i2v_low_noise_14b_fp16.safetensors",
                     "model_type": "diffusion_models", "size": "27 GB"},
                    {"repo_id": "OpenGVLab/InternVideo2", "filename": "wan2.2_t2v_high_noise_14b_fp16.safetensors",
                     "model_type": "diffusion_models", "size": "27 GB"},
                    {"repo_id": "OpenGVLab/InternVideo2", "filename": "wan2.2_t2v_low_noise_14b_fp16.safetensors",
                     "model_type": "diffusion_models", "size": "27 GB"},
                    {"repo_id": "OpenGVLab/InternVideo2", "filename": "wan2.2_vae_fp16.safetensors",
                     "model_type": "vae", "size": "670 MB"},
                ],
                "total_size": "108.7 GB"
            },
            "wan21_phantom_bundle": {
                "name": "Wan 2.1 Phantom Complete Bundle",
                "description": "Wan 2.1 Phantom models with all LoRAs for enhanced video generation",
                "category": "Wan Video Bundles",
                "models": [
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Wan21_Phantom_14B_GGUF_Q8.gguf",
                     "model_type": "diffusion_models", "size": "14.3 GB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Wan21_Phantom_14B_GGUF_Q6_K.gguf",
                     "model_type": "diffusion_models", "size": "10.7 GB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Phantom_Wan_14B_FusionX_LoRA.safetensors",
                     "model_type": "loras", "size": "188 MB"},
                    {"repo_id": "MonsterMMORPG/Wan_GGUF", "filename": "Phantom_Wan_14B_T2V_LoRA.safetensors",
                     "model_type": "loras", "size": "188 MB"},
                ],
                "total_size": "25.4 GB"
            },
            "flux_tools_bundle": {
                "name": "FLUX Tools Complete Bundle",
                "description": "FLUX Tools including Canny, Depth, Redux, and Fill models",
                "category": "FLUX Bundles",
                "models": [
                    {"repo_id": "black-forest-labs/FLUX.1-Canny-dev", "filename": "flux1-canny-dev.safetensors",
                     "model_type": "controlnet", "size": "3.58 GB"},
                    {"repo_id": "black-forest-labs/FLUX.1-Depth-dev", "filename": "flux1-depth-dev.safetensors",
                     "model_type": "controlnet", "size": "3.58 GB"},
                    {"repo_id": "black-forest-labs/FLUX.1-Redux-dev", "filename": "flux1-redux-dev.safetensors",
                     "model_type": "checkpoints", "size": "23.8 GB"},
                    {"repo_id": "black-forest-labs/FLUX.1-Fill-dev", "filename": "flux1-fill-dev.safetensors",
                     "model_type": "checkpoints", "size": "23.8 GB"},
                    {"repo_id": "jasperai/FLUX.1-dev-Controlnet-Upscaler", "filename": "diffusion_pytorch_model.safetensors",
                     "model_type": "controlnet", "size": "3.58 GB"},
                ],
                "total_size": "58.3 GB"
            },
            "flux_schnell_bundle": {
                "name": "FLUX Schnell Fast Generation Bundle",
                "description": "FLUX Schnell models for 4-step fast generation in multiple formats",
                "category": "FLUX Bundles",
                "models": [
                    {"repo_id": "black-forest-labs/FLUX.1-schnell", "filename": "flux1-schnell.safetensors",
                     "model_type": "checkpoints", "size": "23.8 GB"},
                    {"repo_id": "city96/FLUX.1-schnell-gguf", "filename": "flux1-schnell-Q8_0.gguf",
                     "model_type": "diffusion_models", "size": "12.2 GB"},
                    {"repo_id": "city96/FLUX.1-schnell-gguf", "filename": "flux1-schnell-Q6_K.gguf",
                     "model_type": "diffusion_models", "size": "9.2 GB"},
                    {"repo_id": "city96/FLUX.1-schnell-gguf", "filename": "flux1-schnell-Q4_K_S.gguf",
                     "model_type": "diffusion_models", "size": "6.3 GB"},
                ],
                "total_size": "51.5 GB"
            },
            "flux_loras_bundle": {
                "name": "FLUX LoRAs Collection",
                "description": "Popular FLUX LoRAs including Realism, Anime, and Style enhancers",
                "category": "FLUX Bundles",
                "models": [
                    {"repo_id": "XLabs-AI/flux-RealismLora", "filename": "lora.safetensors",
                     "save_as": "flux_realism_lora.safetensors", "model_type": "loras", "size": "185 MB"},
                    {"repo_id": "alvdansen/flux_film_foto", "filename": "flux_film_foto.safetensors",
                     "model_type": "loras", "size": "185 MB"},
                    {"repo_id": "glif/flux-koda", "filename": "flux-koda.safetensors",
                     "model_type": "loras", "size": "185 MB"},
                    {"repo_id": "TheLastBen/flux_slider", "filename": "flux_slider.safetensors",
                     "model_type": "loras", "size": "185 MB"},
                    {"repo_id": "Shakker-Labs/FLUX.1-dev-LoRA-add-details", "filename": "add-details-flux-lora.safetensors",
                     "save_as": "flux_add_details_lora.safetensors", "model_type": "loras", "size": "185 MB"},
                ],
                "total_size": "925 MB"
            },
            "mochi_bundle": {
                "name": "Mochi Text to Video Bundle",
                "description": "Mochi 1 Preview models for text to video generation",
                "category": "Video Generation",
                "models": [
                    {"repo_id": "genmo/mochi-1-preview", "filename": "mochi-1-preview-dit.safetensors",
                     "model_type": "diffusion_models", "size": "10.5 GB"},
                    {"repo_id": "genmo/mochi-1-preview", "filename": "mochi-1-preview-vae.safetensors",
                     "model_type": "vae", "size": "316 MB"},
                    {"repo_id": "genmo/mochi-1-preview", "filename": "t5-v1_1-xxl.safetensors",
                     "model_type": "clip", "size": "11.9 GB"},
                ],
                "total_size": "22.7 GB"
            },
            "hunyuan_video_bundle": {
                "name": "Hunyuan Video Generation Bundle",
                "description": "Hunyuan Video models for high-quality video generation",
                "category": "Video Generation",
                "models": [
                    {"repo_id": "tencent/HunyuanVideo", "filename": "hunyuan_video_dit.safetensors",
                     "model_type": "diffusion_models", "size": "13.4 GB"},
                    {"repo_id": "tencent/HunyuanVideo", "filename": "hunyuan_video_vae.safetensors",
                     "model_type": "vae", "size": "504 MB"},
                    {"repo_id": "tencent/HunyuanVideo", "filename": "hunyuan_video_text_encoder.safetensors",
                     "model_type": "clip", "size": "1.3 GB"},
                ],
                "total_size": "15.2 GB"
            },
            "sd35_medium_bundle": {
                "name": "Stable Diffusion 3.5 Medium Bundle",
                "description": "SD3.5 Medium models in multiple formats for balanced performance",
                "category": "Image Generation",
                "models": [
                    {"repo_id": "stabilityai/stable-diffusion-3.5-medium", "filename": "sd3.5_medium.safetensors",
                     "model_type": "checkpoints", "size": "5.7 GB"},
                    {"repo_id": "city96/stable-diffusion-3.5-medium-gguf", "filename": "sd3.5_medium-Q8_0.gguf",
                     "model_type": "diffusion_models", "size": "2.9 GB"},
                    {"repo_id": "city96/stable-diffusion-3.5-medium-gguf", "filename": "sd3.5_medium-Q6_K.gguf",
                     "model_type": "diffusion_models", "size": "2.2 GB"},
                ],
                "total_size": "10.8 GB"
            },
            "sdxl_turbo_bundle": {
                "name": "SDXL Turbo Fast Generation Bundle",
                "description": "SDXL Turbo models for 1-step image generation",
                "category": "Image Generation",
                "models": [
                    {"repo_id": "stabilityai/sdxl-turbo", "filename": "sd_xl_turbo_1.0.safetensors",
                     "model_type": "checkpoints", "size": "6.9 GB"},
                    {"repo_id": "stabilityai/sdxl-turbo", "filename": "sd_xl_turbo_1.0_fp16.safetensors",
                     "model_type": "checkpoints", "size": "3.5 GB"},
                    {"repo_id": "madebyollin/sdxl-vae-fp16-fix", "filename": "sdxl_vae.safetensors",
                     "model_type": "vae", "size": "335 MB"},
                ],
                "total_size": "10.7 GB"
            },
            "stable_cascade_bundle": {
                "name": "Stable Cascade Bundle",
                "description": "Stable Cascade models for high-resolution image generation",
                "category": "Image Generation",
                "models": [
                    {"repo_id": "stabilityai/stable-cascade", "filename": "cascade_stage_b.safetensors",
                     "model_type": "checkpoints", "size": "6.5 GB"},
                    {"repo_id": "stabilityai/stable-cascade", "filename": "cascade_stage_c.safetensors",
                     "model_type": "checkpoints", "size": "3.9 GB"},
                    {"repo_id": "stabilityai/stable-cascade", "filename": "cascade_vae.safetensors",
                     "model_type": "vae", "size": "19 MB"},
                ],
                "total_size": "10.4 GB"
            },
            "rife_interpolation_bundle": {
                "name": "RIFE Frame Interpolation Bundle",
                "description": "RIFE models for smooth frame interpolation and video enhancement",
                "category": "Utility Models",
                "models": [
                    {"repo_id": "AlexWortega/RIFE", "filename": "rife47.pth",
                     "model_type": "custom_nodes", "size": "49 MB"},
                    {"repo_id": "AlexWortega/RIFE", "filename": "rife46.pth",
                     "model_type": "custom_nodes", "size": "49 MB"},
                    {"repo_id": "AlexWortega/RIFE", "filename": "rife48.pth",
                     "model_type": "custom_nodes", "size": "49 MB"},
                ],
                "total_size": "147 MB"
            },
            "ip_adapter_complete_bundle": {
                "name": "IP Adapter Complete Collection",
                "description": "All IP Adapter models including FaceID, Plus, and SDXL versions",
                "category": "Utility Models",
                "models": [
                    {"repo_id": "h94/IP-Adapter", "filename": "models/ip-adapter_sd15.safetensors",
                     "model_type": "ipadapter", "size": "44 MB"},
                    {"repo_id": "h94/IP-Adapter", "filename": "models/ip-adapter_sd15_plus.safetensors",
                     "model_type": "ipadapter", "size": "98 MB"},
                    {"repo_id": "h94/IP-Adapter", "filename": "sdxl_models/ip-adapter_sdxl.safetensors",
                     "model_type": "ipadapter", "size": "702 MB"},
                    {"repo_id": "h94/IP-Adapter", "filename": "sdxl_models/ip-adapter_sdxl_plus.safetensors",
                     "model_type": "ipadapter", "size": "1.7 GB"},
                    {"repo_id": "h94/IP-Adapter-FaceID", "filename": "ip-adapter-faceid_sd15.bin",
                     "model_type": "ipadapter", "size": "157 MB"},
                    {"repo_id": "h94/IP-Adapter-FaceID", "filename": "ip-adapter-faceid-plusv2_sd15.bin",
                     "model_type": "ipadapter", "size": "323 MB"},
                    {"repo_id": "h94/IP-Adapter-FaceID", "filename": "ip-adapter-faceid_sdxl.bin",
                     "model_type": "ipadapter", "size": "1.2 GB"},
                ],
                "total_size": "4.2 GB"
            },
            "animatediff_complete_bundle": {
                "name": "AnimateDiff Complete Bundle",
                "description": "All AnimateDiff motion modules and LoRAs for animation",
                "category": "Video Generation",
                "models": [
                    {"repo_id": "guoyww/animatediff", "filename": "v3_sd15_mm.ckpt",
                     "model_type": "animatediff_models", "size": "1.7 GB"},
                    {"repo_id": "guoyww/animatediff", "filename": "v2_sd15_mm.ckpt",
                     "model_type": "animatediff_models", "size": "1.7 GB"},
                    {"repo_id": "guoyww/animatediff", "filename": "mm_sdxl_v10_beta.ckpt",
                     "model_type": "animatediff_models", "size": "1.1 GB"},
                    {"repo_id": "guoyww/animatediff", "filename": "v3_sd15_adapter.ckpt",
                     "model_type": "animatediff_models", "size": "102 MB"},
                    {"repo_id": "guoyww/animatediff", "filename": "v3_sd15_sparsectrl.ckpt",
                     "model_type": "animatediff_models", "size": "1.9 GB"},
                ],
                "total_size": "6.5 GB"
            },
            "omnigen2_bundle": {
                "name": "OmniGen 2 Bundle",
                "description": "OmniGen v2 models for versatile image generation",
                "category": "Image Generation",
                "models": [
                    {"repo_id": "Shitao/OmniGen-v2", "filename": "omnigen_v2.safetensors",
                     "model_type": "checkpoints", "size": "15.8 GB"},
                    {"repo_id": "Shitao/OmniGen-v2", "filename": "omnigen_v2_vae.safetensors",
                     "model_type": "vae", "size": "335 MB"},
                ],
                "total_size": "16.1 GB"
            },
            "face_models_bundle": {
                "name": "Face Enhancement Models Bundle",
                "description": "Complete collection of face restoration and enhancement models",
                "category": "Utility Models",
                "models": [
                    {"repo_id": "facexlib/CodeFormer", "filename": "codeformer.pth",
                     "model_type": "facerestore_models", "size": "376 MB"},
                    {"repo_id": "TencentARC/GFPGAN", "filename": "GFPGANv1.4.pth",
                     "model_type": "facerestore_models", "size": "348 MB"},
                    {"repo_id": "TencentARC/GFPGAN", "filename": "GFPGANv1.3.pth",
                     "model_type": "facerestore_models", "size": "348 MB"},
                    {"repo_id": "sczhou/RestoreFormer", "filename": "RestoreFormer.pth",
                     "model_type": "facerestore_models", "size": "290 MB"},
                ],
                "total_size": "1.36 GB"
            },
            "cosmos_bundle": {
                "name": "Cosmos Video Generation Bundle",
                "description": "Cosmos-1.0 models for text and image to video generation",
                "category": "Video Generation",
                "models": [
                    {"repo_id": "nvidia/Cosmos-1.0-Diffusion", "filename": "cosmos_1_0_diffusion_7b_fp16.safetensors",
                     "model_type": "diffusion_models", "size": "14 GB"},
                    {"repo_id": "nvidia/Cosmos-1.0-Diffusion", "filename": "cosmos_1_0_vae.safetensors",
                     "model_type": "vae", "size": "335 MB"},
                    {"repo_id": "nvidia/Cosmos-1.0-Diffusion", "filename": "cosmos_1_0_text_encoder.safetensors",
                     "model_type": "clip", "size": "1.2 GB"},
                ],
                "total_size": "15.5 GB"
            },
            "ltx_extended_bundle": {
                "name": "LTX Video Extended Bundle",
                "description": "Complete LTX Video collection with all quantizations",
                "category": "Video Generation",
                "models": [
                    {"repo_id": "Lightricks/LTX-Video", "filename": "ltx-video-13b-v0.9.safetensors",
                     "model_type": "diffusion_models", "size": "25.5 GB"},
                    {"repo_id": "wsbagnsv1/ltxv-13b-0.9.7-dev-GGUF", "filename": "ltxv-13b-0.9.7-vae-BF16.safetensors",
                     "model_type": "vae", "size": "335 MB"},
                    {"repo_id": "wsbagnsv1/ltxv-13b-0.9.7-dev-GGUF", "filename": "ltxv-13b-0.9.7-dev-Q8_0.gguf",
                     "model_type": "diffusion_models", "size": "13.5 GB"},
                    {"repo_id": "wsbagnsv1/ltxv-13b-0.9.7-dev-GGUF", "filename": "ltxv-13b-0.9.7-dev-Q6_K.gguf",
                     "model_type": "diffusion_models", "size": "10.4 GB"},
                    {"repo_id": "wsbagnsv1/ltxv-13b-0.9.7-dev-GGUF", "filename": "ltxv-13b-0.9.7-dev-Q4_K_M.gguf",
                     "model_type": "diffusion_models", "size": "7.6 GB"},
                ],
                "total_size": "57.3 GB"
            },
            "teacache_bundle": {
                "name": "TeaCache Optimization Bundle",
                "description": "TeaCache models for optimized caching and faster inference",
                "category": "Utility Models",
                "models": [
                    {"repo_id": "techmonsterwang/TeaCache", "filename": "teacache_flux_v1.safetensors",
                     "model_type": "custom_nodes", "size": "125 MB"},
                    {"repo_id": "techmonsterwang/TeaCache", "filename": "teacache_sdxl_v1.safetensors",
                     "model_type": "custom_nodes", "size": "85 MB"},
                ],
                "total_size": "210 MB"
            },

            # Text Encoder Model Bundles
            "clip_models_essential": {
                "name": "Essential CLIP Models (L and G variants)",
                "description": "CLIP models used by SDXL, SD2.x, and many other models - SwarmUI defaults",
                "category": "Text Encoders",
                "models": [
                    {"repo_id": "comfyanonymous/flux_text_encoders", "filename": "clip_l.safetensors",
                     "save_as": "clip_l.safetensors", "model_type": "clip", "size": "246 MB"},
                    {"repo_id": "stabilityai/stable-diffusion-2-1", "filename": "text_encoder/model.safetensors",
                     "save_as": "CLIP_SAE_ViT_L_14.safetensors", "model_type": "clip", "size": "492 MB"},
                    {"repo_id": "openai/clip-vit-large-patch14", "filename": "pytorch_model.bin",
                     "save_as": "clip_g.safetensors", "model_type": "clip", "size": "1.71 GB"},
                ],
                "total_size": "2.45 GB"
            },
            "t5_text_encoders": {
                "name": "T5-XXL Text Encoders for FLUX",
                "description": "T5 XXL text encoders required for FLUX models in different precisions",
                "category": "Text Encoders",
                "models": [
                    {"repo_id": "comfyanonymous/flux_text_encoders", "filename": "t5xxl_fp16.safetensors",
                     "save_as": "t5xxl_fp16.safetensors", "model_type": "clip", "size": "9.5 GB"},
                    {"repo_id": "comfyanonymous/flux_text_encoders", "filename": "t5xxl_fp8_e4m3fn.safetensors",
                     "save_as": "t5xxl_fp8_e4m3fn.safetensors", "model_type": "clip", "size": "4.89 GB"},
                    {"repo_id": "city96/t5-v1_1-xxl-encoder-gguf", "filename": "t5-v1_1-xxl-Q8_0.gguf",
                     "save_as": "t5xxl_Q8_0.gguf", "model_type": "clip", "size": "4.92 GB"},
                ],
                "total_size": "19.31 GB"
            },
            "hidream_clip_bundle": {
                "name": "HiDream Long CLIP Models",
                "description": "Extended context CLIP models optimized for HiDream-I1",
                "category": "Text Encoders",
                "models": [
                    {"repo_id": "MonsterMMORPG/HiDream-I1-Dev", "filename": "long_clip_l.safetensors",
                     "save_as": "long_clip_l_hidream.safetensors", "model_type": "clip", "size": "210 MB"},
                    {"repo_id": "MonsterMMORPG/HiDream-I1-Dev", "filename": "long_clip_g.safetensors",
                     "save_as": "long_clip_g_hidream.safetensors", "model_type": "clip", "size": "694 MB"},
                ],
                "total_size": "904 MB"
            },
            "sd3_text_encoders": {
                "name": "SD3/SD3.5 Text Encoders",
                "description": "CLIP and T5 encoders for Stable Diffusion 3 and 3.5 models",
                "category": "Text Encoders",
                "models": [
                    {"repo_id": "Comfy-Org/stable-diffusion-3.5-fp8", "filename": "text_encoders/clip_g.safetensors",
                     "save_as": "clip_g_sd3.safetensors", "model_type": "clip", "size": "1.39 GB"},
                    {"repo_id": "Comfy-Org/stable-diffusion-3.5-fp8", "filename": "text_encoders/clip_l.safetensors",
                     "save_as": "clip_l_sd3.safetensors", "model_type": "clip", "size": "246 MB"},
                    {"repo_id": "Comfy-Org/stable-diffusion-3.5-fp8", "filename": "text_encoders/t5xxl_fp8_e4m3fn.safetensors",
                     "save_as": "t5xxl_fp8_sd3.safetensors", "model_type": "clip", "size": "4.89 GB"},
                ],
                "total_size": "6.53 GB"
            },
            "qwen_text_encoders": {
                "name": "Qwen Image Text Encoders",
                "description": "Qwen 2.5 VL text encoders for Qwen Image generation models",
                "category": "Text Encoders",
                "models": [
                    {"repo_id": "Comfy-Org/Qwen_2.5-VL-7B_FP8_Scaled", "filename": "qwen_2.5_vl_7b_fp8_scaled.safetensors",
                     "model_type": "clip", "size": "7.2 GB"},
                    {"repo_id": "Comfy-Org/qwen-image-loras", "filename": "qwen_image_lightning_8steps_v1.1.safetensors",
                     "model_type": "loras", "size": "185 MB"},
                ],
                "total_size": "7.39 GB"
            },
            "wan_text_encoders": {
                "name": "Wan Video Text Encoders",
                "description": "UMT5 XXL text encoders for Wan 2.1 and 2.2 video generation",
                "category": "Text Encoders",
                "models": [
                    {"repo_id": "Comfy-Org/Wan_2.1_ComfyUI_repackaged", "filename": "split_files/text_encoders/umt5_xxl_fp16.safetensors",
                     "save_as": "umt5_xxl_fp16_wan.safetensors", "model_type": "clip", "size": "23.7 GB"},
                    {"repo_id": "Comfy-Org/Wan_2.1_ComfyUI_repackaged", "filename": "split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors",
                     "save_as": "umt5_xxl_fp8_wan.safetensors", "model_type": "clip", "size": "11.9 GB"},
                ],
                "total_size": "35.6 GB"
            },
            "all_clip_models": {
                "name": "Complete CLIP Collection",
                "description": "All essential CLIP models for maximum compatibility",
                "category": "Text Encoders",
                "models": [
                    {"repo_id": "comfyanonymous/flux_text_encoders", "filename": "clip_l.safetensors",
                     "save_as": "clip_l.safetensors", "model_type": "clip", "size": "246 MB"},
                    {"repo_id": "openai/clip-vit-large-patch14", "filename": "pytorch_model.bin",
                     "save_as": "clip_g.safetensors", "model_type": "clip", "size": "1.71 GB"},
                    {"repo_id": "stabilityai/stable-diffusion-2-1", "filename": "text_encoder/model.safetensors",
                     "save_as": "CLIP_ViT_L_14.safetensors", "model_type": "clip", "size": "492 MB"},
                    {"repo_id": "openai/clip-vit-base-patch32", "filename": "pytorch_model.bin",
                     "save_as": "clip_b.safetensors", "model_type": "clip", "size": "151 MB"},
                    {"repo_id": "openai/clip-vit-base-patch16", "filename": "pytorch_model.bin",
                     "save_as": "clip_b16.safetensors", "model_type": "clip", "size": "151 MB"},
                ],
                "total_size": "2.75 GB"
            },

            # CivitAI Popular Models Bundles
            "civitai_essentials": {
                "name": "CivitAI Essentials Bundle",
                "description": "Most popular community models from CivitAI",
                "category": "CivitAI Collections",
                "source": "civitai",
                "models": [
                    {"name": "Realistic Vision V6.0", "version_id": 245598, "type": "Checkpoint", "size": "2.0 GB"},
                    {"name": "DreamShaper 8", "version_id": 128713, "type": "Checkpoint", "size": "2.0 GB"},
                    {"name": "Detail Tweaker LoRA", "version_id": 135867, "type": "LORA", "size": "144 MB"},
                    {"name": "VAE ft-mse-840000", "version_id": 155202, "type": "VAE", "size": "335 MB"},
                ],
                "total_size": "4.5 GB"
            },
            "civitai_anime": {
                "name": "Anime Style Bundle",
                "description": "Top-rated anime style models from CivitAI",
                "category": "CivitAI Collections",
                "source": "civitai",
                "models": [
                    {"name": "Anything V5", "version_id": 189063, "type": "Checkpoint", "size": "2.1 GB"},
                    {"name": "Counterfeit V3", "version_id": 157292, "type": "Checkpoint", "size": "2.0 GB"},
                    {"name": "Anime Lineart LoRA", "version_id": 160168, "type": "LORA", "size": "128 MB"},
                ],
                "total_size": "4.2 GB"
            },
            "civitai_photorealism": {
                "name": "Photorealistic Bundle",
                "description": "Ultra-realistic model collection from CivitAI",
                "category": "CivitAI Collections",
                "source": "civitai",
                "models": [
                    {"name": "Juggernaut XL", "version_id": 198962, "type": "Checkpoint", "size": "6.5 GB"},
                    {"name": "RealESRGAN 4x", "version_id": 124576, "type": "Upscaler", "size": "64 MB"},
                    {"name": "Face Detailer", "version_id": 145893, "type": "LORA", "size": "144 MB"},
                ],
                "total_size": "6.7 GB"
            },
            "civitai_sdxl": {
                "name": "SDXL Collection",
                "description": "Best SDXL models from CivitAI community",
                "category": "CivitAI Collections",
                "source": "civitai",
                "models": [
                    {"name": "Juggernaut XL V9", "version_id": 288982, "type": "Checkpoint", "size": "6.5 GB"},
                    {"name": "SDXL Offset LoRA", "version_id": 178925, "type": "LORA", "size": "49 MB"},
                    {"name": "SDXL Turbo", "version_id": 221544, "type": "Checkpoint", "size": "6.5 GB"},
                ],
                "total_size": "13.0 GB"
            }
        }

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
                      model_type: Optional[str] = None, is_snapshot: bool = False,
                      save_as: Optional[str] = None) -> str:
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
            args=(download_id, repo_id, filename, dest_path, is_snapshot, save_as)
        )
        thread.daemon = True
        thread.start()

        return download_id

    def _download_worker(self, download_id: str, repo_id: str,
                        filename: Optional[str], dest_path: str, is_snapshot: bool,
                        save_as: Optional[str] = None):
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

                # If save_as is specified, rename the file
                if save_as and local_path:
                    final_path = os.path.join(dest_path, save_as)
                    if os.path.exists(local_path):
                        shutil.move(local_path, final_path)
                        local_path = final_path

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
            # Convert bytes to GB with proper calculation
            gb_divisor = 1024 * 1024 * 1024  # 1024^3

            total_gb = stat.total / gb_divisor
            used_gb = stat.used / gb_divisor
            free_gb = stat.free / gb_divisor

            # Sanity check: if values are unreasonably large (> 10000 GB),
            # they might be in MB or KB already
            if total_gb > 10000:
                # Values are likely in MB, divide by 1024 again
                total_gb = total_gb / 1024
                used_gb = used_gb / 1024
                free_gb = free_gb / 1024

            return {
                'total': round(total_gb, 1),  # GB with 1 decimal
                'used': round(used_gb, 1),
                'free': round(free_gb, 1),
                'percent': round((stat.used / stat.total) * 100, 1) if stat.total > 0 else 0
            }
        except Exception as e:
            print(f"Error getting disk usage: {e}")
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

    def get_bundles(self) -> Dict:
        """Get all available model bundles."""
        return self.model_bundles

    def download_bundle(self, bundle_id: str) -> str:
        """
        Download all models in a bundle.

        Args:
            bundle_id: ID of the bundle to download

        Returns:
            Bundle download ID for tracking progress
        """
        if bundle_id not in self.model_bundles:
            raise ValueError(f"Bundle {bundle_id} not found")

        bundle = self.model_bundles[bundle_id]
        bundle_download_id = f"bundle_{bundle_id}_{int(time.time())}"

        # Initialize bundle tracking
        with self.download_lock:
            self.bundle_downloads[bundle_download_id] = {
                'bundle_id': bundle_id,
                'bundle_name': bundle['name'],
                'status': 'starting',
                'total_models': len(bundle['models']),
                'completed_models': 0,
                'current_model': None,
                'download_ids': [],
                'started_at': time.time()
            }

        # Start bundle download in background thread
        thread = threading.Thread(
            target=self._download_bundle_worker,
            args=(bundle_download_id, bundle)
        )
        thread.daemon = True
        thread.start()

        return bundle_download_id

    def _download_bundle_worker(self, bundle_download_id: str, bundle: Dict):
        """Worker thread for downloading bundle models."""
        try:
            with self.download_lock:
                self.bundle_downloads[bundle_download_id]['status'] = 'downloading'

            download_ids = []

            # Download each model in the bundle
            for i, model in enumerate(bundle['models']):
                # Update current model being downloaded
                with self.download_lock:
                    self.bundle_downloads[bundle_download_id]['current_model'] = model.get('filename', model['repo_id'])

                # Start individual model download
                try:
                    download_id = self.download_model(
                        repo_id=model['repo_id'],
                        filename=model.get('filename'),
                        model_type=model['model_type'],
                        is_snapshot=False,
                        save_as=model.get('save_as')
                    )
                    download_ids.append(download_id)

                    # Wait for this download to complete before starting next
                    max_wait = 3600  # 1 hour max per model
                    wait_time = 0
                    while wait_time < max_wait:
                        time.sleep(2)
                        wait_time += 2

                        with self.download_lock:
                            if download_id in self.downloads:
                                status = self.downloads[download_id]['status']
                                if status == 'completed':
                                    break
                                elif status == 'error':
                                    raise Exception(f"Failed to download {model.get('filename', model['repo_id'])}")

                    # Update progress
                    with self.download_lock:
                        self.bundle_downloads[bundle_download_id]['completed_models'] = i + 1
                        self.bundle_downloads[bundle_download_id]['download_ids'] = download_ids

                except Exception as e:
                    print(f"Error downloading model {model.get('filename', model['repo_id'])} in bundle: {e}")
                    # Log error but continue with next model
                    with self.download_lock:
                        if 'failed_models' not in self.bundle_downloads[bundle_download_id]:
                            self.bundle_downloads[bundle_download_id]['failed_models'] = []
                        self.bundle_downloads[bundle_download_id]['failed_models'].append({
                            'model': model.get('filename', model['repo_id']),
                            'error': str(e)
                        })
                    continue

            # Mark bundle as completed
            with self.download_lock:
                self.bundle_downloads[bundle_download_id]['status'] = 'completed'
                self.bundle_downloads[bundle_download_id]['current_model'] = None

        except Exception as e:
            with self.download_lock:
                self.bundle_downloads[bundle_download_id]['status'] = 'error'
                self.bundle_downloads[bundle_download_id]['error'] = str(e)

    def get_bundle_status(self, bundle_download_id: str) -> Optional[Dict]:
        """Get status of a specific bundle download."""
        with self.download_lock:
            return self.bundle_downloads.get(bundle_download_id, None)

    def get_all_bundle_downloads(self) -> Dict:
        """Get status of all bundle downloads."""
        with self.download_lock:
            return self.bundle_downloads.copy()

    def search_bundles(self, query: str) -> Dict:
        """Search bundles by name, description, models, or category with partial matching."""
        query_lower = query.lower().strip()
        if not query_lower:
            return self.model_bundles

        matching_bundles = {}
        query_words = query_lower.split()  # Split query into words for better partial matching

        for bundle_id, bundle in self.model_bundles.items():
            # Check if any query word matches any part of the bundle info
            bundle_text = ' '.join([
                bundle.get('name', '').lower(),
                bundle.get('description', '').lower(),
                bundle.get('category', '').lower(),
            ])

            # Add model names to searchable text
            for model in bundle.get('models', []):
                model_name = model.get('save_as') or model.get('filename', '')
                bundle_text += ' ' + model_name.lower()
                # Also add repo_id to searchable text
                bundle_text += ' ' + model.get('repo_id', '').lower()

            # Check if all query words are found in bundle text (partial matching)
            if all(word in bundle_text for word in query_words):
                matching_bundles[bundle_id] = bundle

        return matching_bundles

    def get_bundles_by_category(self, category: str = None) -> Dict:
        """Filter bundles by category."""
        if not category or category.lower() == 'all':
            return self.model_bundles

        filtered_bundles = {}
        for bundle_id, bundle in self.model_bundles.items():
            if bundle.get('category', '').lower() == category.lower():
                filtered_bundles[bundle_id] = bundle

        return filtered_bundles

    def get_bundle_categories(self) -> List[str]:
        """Get list of all unique bundle categories."""
        categories = set()
        for bundle in self.model_bundles.values():
            category = bundle.get('category', 'Other')
            categories.add(category)

        # Return sorted list with preferred order
        category_order = [
            'Text Encoders',
            'FLUX Bundles',
            'Wan Video Bundles',
            'Image Generation',
            'Video Generation',
            'Workflow Bundles',
            'Utility Models',
            'Other Models'
        ]

        sorted_categories = []
        for cat in category_order:
            if cat in categories:
                sorted_categories.append(cat)
                categories.remove(cat)

        # Add any remaining categories
        sorted_categories.extend(sorted(categories))

        return sorted_categories

    # CivitAI Integration Methods
    def search_civitai_models(self, query: str = None, model_type: str = None,
                             sort: str = "Highest Rated", nsfw: bool = False,
                             limit: int = 20, page: int = 1) -> Dict:
        """
        Search models on CivitAI.

        Args:
            query: Search query
            model_type: Type of model to filter
            sort: Sort order
            nsfw: Include NSFW content
            limit: Results per page
            page: Page number

        Returns:
            Search results from CivitAI
        """
        import asyncio

        async def search():
            types = [model_type] if model_type else None
            return await self.civitai_client.search_models(
                query=query, types=types, sort=sort,
                nsfw=nsfw, limit=limit, page=page
            )

        try:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            results = loop.run_until_complete(search())
            loop.close()
            return results
        except Exception as e:
            return {'error': str(e), 'items': []}

    def download_civitai_model(self, version_id: int, model_type: str = None) -> str:
        """
        Download a model from CivitAI.

        Args:
            version_id: CivitAI model version ID
            model_type: Type of model for folder organization

        Returns:
            Download ID for tracking
        """
        download_id = f"civitai_{version_id}_{int(time.time())}"

        def download_thread():
            try:
                with self.download_lock:
                    self.downloads[download_id] = {
                        'status': 'downloading',
                        'progress': 0,
                        'error': None,
                        'source': 'civitai',
                        'version_id': version_id,
                        'started_at': time.time()
                    }

                # Progress callback
                def progress_update(info):
                    with self.download_lock:
                        if download_id in self.downloads:
                            self.downloads[download_id]['progress'] = info['percentage']
                            self.downloads[download_id]['downloaded'] = info.get('downloaded', 0)
                            self.downloads[download_id]['total'] = info.get('total', 0)

                # Download the model
                dest_path = self.civitai_client.download_model(
                    model_version_id=version_id,
                    model_type=model_type,
                    progress_callback=progress_update
                )

                # Update status
                with self.download_lock:
                    self.downloads[download_id]['status'] = 'completed'
                    self.downloads[download_id]['dest_path'] = dest_path
                    self.downloads[download_id]['progress'] = 100

            except Exception as e:
                with self.download_lock:
                    self.downloads[download_id]['status'] = 'error'
                    self.downloads[download_id]['error'] = str(e)

        # Start download in background thread
        thread = threading.Thread(target=download_thread)
        thread.start()

        return download_id

    def download_civitai_bundle(self, bundle_id: str) -> str:
        """
        Download all models in a CivitAI bundle.

        Args:
            bundle_id: ID of the CivitAI bundle

        Returns:
            Bundle download ID for tracking
        """
        if bundle_id not in self.model_bundles:
            raise ValueError(f"Bundle '{bundle_id}' not found")

        bundle = self.model_bundles[bundle_id]

        # Check if it's a CivitAI bundle
        if bundle.get('source') != 'civitai':
            # Use regular bundle download for non-CivitAI bundles
            return self.download_bundle(bundle_id)

        bundle_download_id = f"bundle_{bundle_id}_{int(time.time())}"

        def download_bundle_thread():
            try:
                with self.download_lock:
                    self.bundle_downloads[bundle_download_id] = {
                        'bundle_id': bundle_id,
                        'status': 'downloading',
                        'total_models': len(bundle['models']),
                        'completed_models': 0,
                        'failed_models': 0,
                        'current_model': None,
                        'models_status': {},
                        'started_at': time.time(),
                        'source': 'civitai'
                    }

                for idx, model in enumerate(bundle['models']):
                    model_name = model.get('name', f'Model {idx+1}')

                    with self.download_lock:
                        self.bundle_downloads[bundle_download_id]['current_model'] = model_name
                        self.bundle_downloads[bundle_download_id]['models_status'][model_name] = 'downloading'

                    try:
                        # Download CivitAI model
                        version_id = model.get('version_id')
                        model_type = model.get('type')

                        if version_id:
                            download_id = self.download_civitai_model(version_id, model_type)

                            # Wait for download to complete
                            while True:
                                time.sleep(1)
                                with self.download_lock:
                                    if download_id in self.downloads:
                                        status = self.downloads[download_id]['status']
                                        if status == 'completed':
                                            self.bundle_downloads[bundle_download_id]['completed_models'] += 1
                                            self.bundle_downloads[bundle_download_id]['models_status'][model_name] = 'completed'
                                            break
                                        elif status == 'error':
                                            self.bundle_downloads[bundle_download_id]['failed_models'] += 1
                                            self.bundle_downloads[bundle_download_id]['models_status'][model_name] = 'error'
                                            break

                    except Exception as e:
                        with self.download_lock:
                            self.bundle_downloads[bundle_download_id]['failed_models'] += 1
                            self.bundle_downloads[bundle_download_id]['models_status'][model_name] = f'error: {str(e)}'

                # Mark bundle as completed
                with self.download_lock:
                    self.bundle_downloads[bundle_download_id]['status'] = 'completed'
                    self.bundle_downloads[bundle_download_id]['current_model'] = None

            except Exception as e:
                with self.download_lock:
                    self.bundle_downloads[bundle_download_id]['status'] = 'error'
                    self.bundle_downloads[bundle_download_id]['error'] = str(e)

        # Start bundle download in background thread
        thread = threading.Thread(target=download_bundle_thread)
        thread.start()

        return bundle_download_id

    def set_civitai_api_key(self, api_key: str) -> bool:
        """
        Set CivitAI API key.

        Args:
            api_key: CivitAI API key

        Returns:
            True if key is valid
        """
        self.civitai_client.api_key = api_key
        os.environ['CIVITAI_API_KEY'] = api_key

        # Verify the key
        return self.civitai_client.verify_api_key()

    def get_civitai_trending(self, period: str = "Week", limit: int = 20) -> Dict:
        """Get trending models from CivitAI."""
        import asyncio

        async def get_trending():
            return await self.civitai_client.get_trending_models(period=period, limit=limit)

        try:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            results = loop.run_until_complete(get_trending())
            loop.close()
            return results
        except Exception as e:
            return {'error': str(e), 'items': []}