"""
CivitAI Integration Module for ComfyUI Model Manager
Provides API access to search and download models from CivitAI
"""

import os
import json
import asyncio
import aiohttp
import aiofiles
from pathlib import Path
from typing import Dict, List, Optional, Any
from urllib.parse import urlparse, parse_qs
import time
import requests
from tqdm import tqdm

class CivitAIClient:
    """Client for interacting with CivitAI API."""

    BASE_URL = "https://civitai.com/api/v1"
    DOWNLOAD_URL = "https://civitai.com/api/download/models"

    # Map CivitAI model types to ComfyUI directories
    TYPE_MAPPING = {
        'Checkpoint': 'checkpoints',
        'CheckpointConfig': 'checkpoints',
        'LORA': 'loras',
        'LoCon': 'loras',
        'LoRA': 'loras',
        'LoHa': 'loras',
        'TextualInversion': 'embeddings',
        'VAE': 'vae',
        'ControlNet': 'controlnet',
        'Upscaler': 'upscale_models',
        'MotionModule': 'animatediff_models',
        'Wildcards': 'wildcards',
        'Workflows': 'workflows',
        'AestheticGradient': 'embeddings',
        'Hypernetwork': 'hypernetworks',
        'Poses': 'poses',
        'Clothing': 'loras',
        'Style': 'loras',
        'Character': 'loras',
        'Concept': 'loras',
        'Tool': 'custom_nodes',
        'Other': 'other',
        'Model': 'checkpoints',  # Generic fallback
    }

    def __init__(self, api_key: Optional[str] = None, models_base_path: str = "/workspace/models"):
        """Initialize CivitAI client with optional API key."""
        # Try to load API key from multiple sources
        self.api_key = api_key or self._load_api_key()
        self.models_base = models_base_path
        self.session = None
        self.headers = {}
        if self.api_key:
            self.headers['Authorization'] = f'Bearer {self.api_key}'

    def _load_api_key(self) -> Optional[str]:
        """Load API key from environment or .env file."""
        # First check RunPod secret (RunPod prefixes user secrets with RUNPOD_SECRET_)
        # User would create secret named "CIVITAI_API_KEY" and RunPod makes it available as "RUNPOD_SECRET_CIVITAI_API_KEY"
        key = os.environ.get('RUNPOD_SECRET_CIVITAI_API_KEY')
        if key:
            print("✅ Using CivitAI API key from RunPod secret")
            return key

        # Then check regular environment variable
        key = os.environ.get('CIVITAI_API_KEY')
        if key:
            print("✅ Using CivitAI API key from environment")
            return key

        # Try to load from .env file
        env_file = '/workspace/.env'
        if os.path.exists(env_file):
            try:
                with open(env_file, 'r') as f:
                    for line in f:
                        if line.startswith('CIVITAI_API_KEY='):
                            key = line.strip().split('=', 1)[1].strip('"\'')
                            # Also set it in environment for this session
                            os.environ['CIVITAI_API_KEY'] = key
                            print("✅ Using CivitAI API key from .env file")
                            return key
            except Exception as e:
                print(f"Error loading API key from .env: {e}")

        print("⚠️ No CivitAI API key found - downloads may be rate limited")
        return None

    def get_model_path(self, model_type: str, base_model: Optional[str] = None) -> str:
        """
        Get the appropriate directory path for a model type.

        Args:
            model_type: The CivitAI model type
            base_model: Optional base model (SD 1.5, SDXL, etc.) for sub-folder organization

        Returns:
            Full path to the appropriate directory
        """
        folder = self.TYPE_MAPPING.get(model_type, 'checkpoints')

        # Smart folder organization for checkpoints based on base model
        if model_type in ['Checkpoint', 'Model'] and base_model:
            base_lower = base_model.lower() if base_model else ''

            if 'flux' in base_lower:
                # FLUX models go to diffusion_models
                folder = 'diffusion_models'
            elif 'sdxl' in base_lower or 'xl' in base_lower:
                # SDXL models get their own subfolder
                folder = 'checkpoints/sdxl'
            elif 'sd 1.5' in base_lower or 'sd1.5' in base_lower:
                # SD 1.5 models get their own subfolder
                folder = 'checkpoints/sd15'
            elif 'sd 2' in base_lower or 'sd2' in base_lower:
                # SD 2.x models get their own subfolder
                folder = 'checkpoints/sd2'
            elif 'sd 3' in base_lower or 'sd3' in base_lower:
                # SD 3 models
                folder = 'checkpoints/sd3'

        # Smart organization for LoRAs
        elif model_type in ['LORA', 'LoRA', 'LoCon', 'LoHa'] and base_model:
            base_lower = base_model.lower() if base_model else ''

            if 'sdxl' in base_lower or 'xl' in base_lower:
                folder = 'loras/sdxl'
            elif 'sd 1.5' in base_lower or 'sd1.5' in base_lower:
                folder = 'loras/sd15'

        return os.path.join(self.models_base, folder)

    async def search_models(self,
                          query: Optional[str] = None,
                          types: Optional[List[str]] = None,
                          sort: str = "Highest Rated",
                          period: str = "AllTime",
                          rating: Optional[int] = None,
                          favorites: Optional[bool] = None,
                          hidden: Optional[bool] = None,
                          primary_file_only: Optional[bool] = None,
                          allow_no_credit: Optional[bool] = None,
                          allow_derivatives: Optional[bool] = None,
                          allow_different_license: Optional[bool] = None,
                          allow_commercial_use: Optional[str] = None,
                          nsfw: Optional[bool] = None,
                          username: Optional[str] = None,
                          tag: Optional[str] = None,
                          limit: int = 20,
                          page: int = 1,
                          cursor: Optional[str] = None) -> Dict:
        """
        Search for models on CivitAI.

        Args:
            query: Search query string
            types: List of model types to filter
            sort: Sort order (Highest Rated, Most Downloaded, Newest, etc.)
            period: Time period for sorting (AllTime, Year, Month, Week, Day)
            nsfw: Include NSFW content
            limit: Number of results per page
            page: Page number (only used when no query)
            cursor: Cursor for pagination (used with query)

        Returns:
            Dictionary containing search results
        """
        params = {
            'limit': limit,
        }

        # Use cursor-based pagination when searching with query
        if query:
            params['query'] = query
            # Use cursor for pagination with search queries
            if cursor:
                params['cursor'] = cursor
            # Don't use page parameter with queries
        else:
            # Only use page parameter when NOT searching (browsing)
            params['page'] = page
        if types:
            params['types'] = types if isinstance(types, str) else ','.join(types)
        if sort:
            params['sort'] = sort
        if period:
            params['period'] = period
        if nsfw is not None:
            params['nsfw'] = str(nsfw).lower()
        if username:
            params['username'] = username
        if tag:
            params['tag'] = tag
        if rating is not None:
            params['rating'] = rating
        if favorites is not None:
            params['favorites'] = favorites
        if hidden is not None:
            params['hidden'] = hidden
        if primary_file_only is not None:
            params['primaryFileOnly'] = primary_file_only
        if allow_no_credit is not None:
            params['allowNoCredit'] = allow_no_credit
        if allow_derivatives is not None:
            params['allowDerivatives'] = allow_derivatives
        if allow_different_license is not None:
            params['allowDifferentLicense'] = allow_different_license
        if allow_commercial_use:
            params['allowCommercialUse'] = allow_commercial_use

        url = f"{self.BASE_URL}/models"

        async with aiohttp.ClientSession(headers=self.headers) as session:
            async with session.get(url, params=params) as response:
                if response.status == 200:
                    data = await response.json()
                    return data
                else:
                    error_text = await response.text()
                    raise Exception(f"CivitAI API error: {response.status} - {error_text}")

    async def get_model_details(self, model_id: int) -> Dict:
        """Get detailed information about a specific model."""
        url = f"{self.BASE_URL}/models/{model_id}"

        async with aiohttp.ClientSession(headers=self.headers) as session:
            async with session.get(url) as response:
                if response.status == 200:
                    return await response.json()
                else:
                    error_text = await response.text()
                    raise Exception(f"Failed to get model details: {response.status} - {error_text}")

    async def get_model_version(self, version_id: int) -> Dict:
        """Get details about a specific model version."""
        url = f"{self.BASE_URL}/model-versions/{version_id}"

        async with aiohttp.ClientSession(headers=self.headers) as session:
            async with session.get(url) as response:
                if response.status == 200:
                    return await response.json()
                else:
                    error_text = await response.text()
                    raise Exception(f"Failed to get model version: {response.status} - {error_text}")

    def get_model_version_sync(self, version_id: int) -> Dict:
        """Synchronous version of get_model_version for use in download_model."""
        url = f"{self.BASE_URL}/model-versions/{version_id}"

        try:
            response = requests.get(url, headers=self.headers)
            if response.status_code == 200:
                return response.json()
            else:
                raise Exception(f"Failed to get model version: {response.status_code}")
        except Exception as e:
            print(f"Error fetching model version: {e}")
            return {}

    def download_model(self,
                      model_version_id: int,
                      model_type: Optional[str] = None,
                      filename: Optional[str] = None,
                      progress_callback: Optional[callable] = None) -> str:
        """
        Download a model from CivitAI.

        Args:
            model_version_id: The version ID of the model to download
            model_type: Type of model (for organizing in folders)
            filename: Custom filename to save as
            progress_callback: Callback function for progress updates

        Returns:
            Path to the downloaded file
        """
        # Auto-detect model type and base model if not provided
        base_model = None
        if not model_type:
            try:
                # Fetch model version details to get type and base model
                version_info = self.get_model_version_sync(model_version_id)
                if version_info:
                    if 'model' in version_info:
                        model_type = version_info['model'].get('type', 'Model')
                        print(f"Auto-detected model type: {model_type}")

                    # Get base model info
                    base_model = version_info.get('baseModel')
                    if base_model:
                        print(f"Auto-detected base model: {base_model}")
            except Exception as e:
                print(f"Could not auto-detect model info: {e}")
                model_type = None

        # Construct download URL
        download_url = f"{self.DOWNLOAD_URL}/{model_version_id}"

        # Determine save path based on model type and base model
        if model_type:
            save_dir = self.get_model_path(model_type, base_model)
        else:
            save_dir = os.path.join(self.models_base, 'downloads')

        Path(save_dir).mkdir(parents=True, exist_ok=True)

        # Prepare headers with authorization
        download_headers = {}
        if self.api_key:
            download_headers['Authorization'] = f'Bearer {self.api_key}'

        # Start download with proper headers
        response = requests.get(download_url, stream=True, allow_redirects=True, headers=download_headers)
        response.raise_for_status()

        # Get filename from content-disposition or URL
        if not filename:
            content_disposition = response.headers.get('content-disposition')
            if content_disposition:
                import re
                filename_match = re.findall('filename="?([^"]+)"?', content_disposition)
                if filename_match:
                    filename = filename_match[0]

            if not filename:
                # Fallback to URL path
                parsed_url = urlparse(response.url)
                filename = os.path.basename(parsed_url.path) or f"model_{model_version_id}.safetensors"

        save_path = os.path.join(save_dir, filename)

        # Download with progress
        total_size = int(response.headers.get('content-length', 0))
        block_size = 8192

        with open(save_path, 'wb') as file:
            with tqdm(total=total_size, unit='iB', unit_scale=True) as progress_bar:
                for data in response.iter_content(block_size):
                    progress_bar.update(len(data))
                    file.write(data)

                    if progress_callback:
                        progress_callback({
                            'downloaded': progress_bar.n,
                            'total': total_size,
                            'percentage': (progress_bar.n / total_size * 100) if total_size > 0 else 0
                        })

        return save_path

    async def download_model_async(self,
                                  model_version_id: int,
                                  model_type: Optional[str] = None,
                                  filename: Optional[str] = None,
                                  progress_callback: Optional[callable] = None) -> str:
        """
        Async version of model download.
        """
        # Auto-detect model type and base model if not provided
        base_model = None
        if not model_type:
            try:
                version_info = await self.get_model_version(model_version_id)
                if version_info:
                    if 'model' in version_info:
                        model_type = version_info['model'].get('type', 'Model')
                        print(f"Auto-detected model type: {model_type}")

                    base_model = version_info.get('baseModel')
                    if base_model:
                        print(f"Auto-detected base model: {base_model}")
            except Exception as e:
                print(f"Could not auto-detect model info: {e}")

        download_url = f"{self.DOWNLOAD_URL}/{model_version_id}"
        if self.api_key:
            download_url += f"?token={self.api_key}"

        if model_type:
            save_dir = self.get_model_path(model_type, base_model)
        else:
            save_dir = os.path.join(self.models_base, 'downloads')

        Path(save_dir).mkdir(parents=True, exist_ok=True)

        async with aiohttp.ClientSession() as session:
            async with session.get(download_url, allow_redirects=True) as response:
                response.raise_for_status()

                # Get filename
                if not filename:
                    content_disposition = response.headers.get('content-disposition')
                    if content_disposition:
                        import re
                        filename_match = re.findall('filename="?([^"]+)"?', content_disposition)
                        if filename_match:
                            filename = filename_match[0]

                    if not filename:
                        parsed_url = urlparse(str(response.url))
                        filename = os.path.basename(parsed_url.path) or f"model_{model_version_id}.safetensors"

                save_path = os.path.join(save_dir, filename)
                total_size = int(response.headers.get('content-length', 0))
                downloaded = 0

                async with aiofiles.open(save_path, 'wb') as file:
                    async for chunk in response.content.iter_chunked(8192):
                        await file.write(chunk)
                        downloaded += len(chunk)

                        if progress_callback:
                            await progress_callback({
                                'downloaded': downloaded,
                                'total': total_size,
                                'percentage': (downloaded / total_size * 100) if total_size > 0 else 0
                            })

                return save_path

    async def get_trending_models(self, period: str = "Week", limit: int = 20) -> Dict:
        """Get trending models from CivitAI."""
        return await self.search_models(sort="Most Downloaded", period=period, limit=limit)

    async def get_model_by_hash(self, hash_value: str) -> Optional[Dict]:
        """Find a model by its hash value."""
        url = f"{self.BASE_URL}/model-versions/by-hash/{hash_value}"

        async with aiohttp.ClientSession(headers=self.headers) as session:
            async with session.get(url) as response:
                if response.status == 200:
                    return await response.json()
                return None

    def parse_civitai_url(self, url: str) -> Optional[int]:
        """
        Parse a CivitAI URL to extract the model version ID.

        Supports formats:
        - https://civitai.com/api/download/models/1094291
        - https://civitai.com/models/1094291
        - https://civitai.com/models/12345?modelVersionId=1094291
        """
        try:
            # Direct download API URL
            if '/api/download/models/' in url:
                model_id = url.split('/api/download/models/')[1].split('?')[0]
                return int(model_id)

            # Model page URL with version ID
            if 'modelVersionId=' in url:
                parsed = urlparse(url)
                params = parse_qs(parsed.query)
                if 'modelVersionId' in params:
                    return int(params['modelVersionId'][0])

            # Simple model URL (will need to fetch latest version)
            if '/models/' in url:
                model_id = url.split('/models/')[1].split('?')[0].split('/')[0]
                # This is a model ID, not version ID - would need to fetch latest version
                # For now, return None and let user specify version
                print(f"⚠️ URL contains model ID {model_id}, not version ID. Please use a version-specific URL.")
                return None

        except Exception as e:
            print(f"Error parsing CivitAI URL: {e}")
            return None

    def download_from_url(self, url: str, filename: Optional[str] = None, progress_callback: Optional[callable] = None) -> str:
        """
        Download a model from a CivitAI URL.

        Args:
            url: CivitAI URL (can be model page or direct download URL)
            filename: Optional custom filename
            progress_callback: Optional progress callback

        Returns:
            Path to downloaded file
        """
        # Parse the URL to get model version ID
        version_id = self.parse_civitai_url(url)

        if not version_id:
            # Try to parse as direct version ID
            try:
                version_id = int(url)
            except:
                raise ValueError(f"Could not parse CivitAI URL or version ID: {url}")

        # Use the existing download_model method
        return self.download_model(version_id, filename=filename, progress_callback=progress_callback)

    def set_api_key(self, api_key: str) -> bool:
        """
        Set and save the CivitAI API key.

        Args:
            api_key: The CivitAI API key to save

        Returns:
            True if key is valid and saved, False otherwise
        """
        # Update the instance
        self.api_key = api_key
        self.headers = {'Authorization': f'Bearer {api_key}'} if api_key else {}

        # Verify it works
        if not self.verify_api_key():
            print("❌ Invalid API key")
            self.api_key = None
            self.headers = {}
            return False

        # Save to .env file
        env_file = '/workspace/.env'
        try:
            # Read existing .env content
            env_content = []
            if os.path.exists(env_file):
                with open(env_file, 'r') as f:
                    for line in f:
                        if not line.startswith('CIVITAI_API_KEY='):
                            env_content.append(line.rstrip('\n'))

            # Add the new key
            env_content.append(f'CIVITAI_API_KEY={api_key}')

            # Write back
            with open(env_file, 'w') as f:
                f.write('\n'.join(env_content) + '\n')

            # Also set in environment
            os.environ['CIVITAI_API_KEY'] = api_key

            print(f"✅ API key saved to {env_file}")
            return True

        except Exception as e:
            print(f"⚠️ Could not save API key to file: {e}")
            # Key is valid but couldn't save - still return True
            return True

    def verify_api_key(self) -> bool:
        """Verify if the API key is valid."""
        if not self.api_key:
            return False

        # Try to make an authenticated request
        try:
            response = requests.get(
                f"{self.BASE_URL}/models",
                headers={'Authorization': f'Bearer {self.api_key}'},
                params={'limit': 1}
            )
            return response.status_code == 200
        except:
            return False

    def get_popular_bundles(self) -> Dict[str, Dict]:
        """Get pre-configured bundles of popular CivitAI models."""
        return {
            "civitai_essentials": {
                "name": "CivitAI Essentials Bundle",
                "description": "Popular community models from CivitAI",
                "category": "CivitAI Collections",
                "models": [
                    {"name": "Realistic Vision V6.0", "version_id": 245598, "type": "Checkpoint", "size": "2.0 GB"},
                    {"name": "DreamShaper 8", "version_id": 128713, "type": "Checkpoint", "size": "2.0 GB"},
                    {"name": "Detail Tweaker LoRA", "version_id": 135867, "type": "LORA", "size": "144 MB"},
                    {"name": "Bad Hands Fix", "version_id": 116263, "type": "TextualInversion", "size": "24 KB"},
                    {"name": "VAE ft-mse-840000", "version_id": 155202, "type": "VAE", "size": "335 MB"},
                ],
                "total_size": "4.5 GB"
            },
            "civitai_anime": {
                "name": "Anime Style Bundle",
                "description": "Top-rated anime style models",
                "category": "CivitAI Collections",
                "models": [
                    {"name": "Anything V5", "version_id": 189063, "type": "Checkpoint", "size": "2.1 GB"},
                    {"name": "Counterfeit V3", "version_id": 157292, "type": "Checkpoint", "size": "2.0 GB"},
                    {"name": "Anime Lineart LoRA", "version_id": 160168, "type": "LORA", "size": "128 MB"},
                ],
                "total_size": "4.2 GB"
            },
            "civitai_photorealism": {
                "name": "Photorealistic Bundle",
                "description": "Ultra-realistic model collection",
                "category": "CivitAI Collections",
                "models": [
                    {"name": "Juggernaut XL", "version_id": 198962, "type": "Checkpoint", "size": "6.5 GB"},
                    {"name": "RealESRGAN 4x", "version_id": 124576, "type": "Upscaler", "size": "64 MB"},
                    {"name": "Face Detailer", "version_id": 145893, "type": "LORA", "size": "144 MB"},
                ],
                "total_size": "6.7 GB"
            },
            "civitai_sdxl": {
                "name": "SDXL Collection",
                "description": "Best SDXL models from CivitAI",
                "category": "CivitAI Collections",
                "models": [
                    {"name": "SDXL Base 1.0", "version_id": 128078, "type": "Checkpoint", "size": "6.5 GB"},
                    {"name": "SDXL Refiner", "version_id": 128079, "type": "Checkpoint", "size": "6.1 GB"},
                    {"name": "SDXL Offset LoRA", "version_id": 178925, "type": "LORA", "size": "49 MB"},
                ],
                "total_size": "12.6 GB"
            }
        }