# CivitAI Integration for ComfyUI Model Manager

## Overview

The ComfyUI Model Manager now includes full integration with CivitAI, allowing you to search, browse, and download thousands of community models directly from the interface.

## Features

### 1. Model Search
- Search CivitAI's entire catalog of models
- Filter by model type (Checkpoint, LoRA, VAE, ControlNet, etc.)
- Sort by ratings, downloads, or newest
- NSFW content filtering

### 2. Direct Downloads
- Download models using version ID
- Automatic organization into correct ComfyUI folders
- Progress tracking for all downloads
- Support for authenticated downloads with API key

### 3. Popular Model Bundles
Pre-configured bundles of popular CivitAI models:
- **CivitAI Essentials**: Most popular community models
- **Anime Style Bundle**: Top-rated anime models
- **Photorealistic Bundle**: Ultra-realistic models
- **SDXL Collection**: Best SDXL models from the community

### 4. API Integration
Full REST API support for programmatic access:
- `/api/civitai/search` - Search models
- `/api/civitai/download` - Download specific model
- `/api/civitai/trending` - Get trending models
- `/api/civitai/set-key` - Configure API key
- `/api/civitai/verify-key` - Verify API key
- `/api/civitai/model/{id}` - Get model details

## Setup

### 1. Get CivitAI API Key (Optional)
While not required for public models, an API key enables:
- Access to restricted models
- Higher rate limits
- Authenticated downloads

To get an API key:
1. Log into [CivitAI](https://civitai.com)
2. Go to Account Settings
3. Scroll to API Keys section
4. Click "+ Add API key"
5. Copy the generated key

### 2. Configure API Key

#### Via Environment Variable
```bash
export CIVITAI_API_KEY="your-api-key-here"
```

#### Via API Endpoint
```bash
curl -X POST http://localhost:5005/api/civitai/set-key \
  -H "Content-Type: application/json" \
  -d '{"api_key": "your-api-key-here"}'
```

## Usage Examples

### Search Models
```python
import requests

# Search for SDXL models
response = requests.post('http://localhost:5005/api/civitai/search', json={
    'query': 'sdxl',
    'type': 'Checkpoint',
    'sort': 'Highest Rated',
    'nsfw': False,
    'limit': 10
})
models = response.json()
```

### Download Model
```python
# Download a specific model version
response = requests.post('http://localhost:5005/api/civitai/download', json={
    'version_id': 245598,  # Realistic Vision V6.0
    'model_type': 'Checkpoint'
})
download_id = response.json()['download_id']

# Check download progress
status = requests.get(f'http://localhost:5005/api/models/downloads')
```

### Download Bundle
```python
# Download the CivitAI Essentials bundle
response = requests.post('http://localhost:5005/api/models/bundles/download', json={
    'bundle_id': 'civitai_essentials'
})
```

## Model Type Mapping

CivitAI models are automatically organized into the correct ComfyUI directories:

| CivitAI Type | ComfyUI Directory |
|--------------|------------------|
| Checkpoint | `/workspace/models/checkpoints` |
| LORA/LoCon | `/workspace/models/loras` |
| TextualInversion | `/workspace/models/embeddings` |
| VAE | `/workspace/models/vae` |
| ControlNet | `/workspace/models/controlnet` |
| Upscaler | `/workspace/models/upscale_models` |
| MotionModule | `/workspace/models/animatediff_models` |

## Frontend UI Updates (To Be Implemented)

The following UI features are planned for the Model Manager interface:

### 1. Source Toggle
- Tab or dropdown to switch between HuggingFace and CivitAI
- Visual indicator showing current source

### 2. CivitAI Search Interface
- Search bar with advanced filters
- Model type dropdown
- Sort options (Rating, Downloads, Newest)
- NSFW content toggle
- Pagination controls

### 3. Model Cards
- Model preview images
- Creator information
- Download count and ratings
- Model version selector
- One-click download button

### 4. API Key Configuration
- Settings panel for API key input
- Key validation indicator
- Option to save key persistently

### 5. Download Management
- Progress bars for CivitAI downloads
- Queue management for multiple downloads
- Error handling and retry options

## Technical Implementation

### Backend Components

1. **civitai_integration.py**: Core CivitAI client implementation
   - Async HTTP client for API calls
   - Model type mapping
   - Download management
   - Progress tracking

2. **model_downloader.py**: Extended with CivitAI methods
   - Search functionality
   - Download orchestration
   - Bundle management
   - API key handling

3. **app.py**: New API endpoints for CivitAI
   - RESTful routes for all operations
   - Error handling
   - Authentication management

### Dependencies

Added to Dockerfile:
```dockerfile
uv pip install civitai-downloader aiofiles
```

## Troubleshooting

### API Key Issues
- Verify key is valid: `GET /api/civitai/verify-key`
- Check environment variable: `echo $CIVITAI_API_KEY`
- Ensure key has proper permissions on CivitAI

### Download Failures
- Check network connectivity
- Verify model version ID exists
- Ensure sufficient disk space
- Check folder permissions

### Rate Limiting
- CivitAI may rate limit requests
- Use API key for higher limits
- Implement retry logic with backoff

## Future Enhancements

1. **Model Metadata Caching**: Cache model information locally
2. **Batch Downloads**: Queue multiple models for download
3. **Model Updates**: Check for and download model updates
4. **Preview Images**: Download and display model preview images
5. **Auto-categorization**: Smart folder organization based on model metadata
6. **Duplicate Detection**: Prevent downloading already installed models

## Security Considerations

- API keys are stored in `/workspace/.env` for persistence
- Keys are never logged or exposed in responses
- HTTPS used for all CivitAI API calls
- Optional NSFW filtering enabled by default

## Contributing

To extend the CivitAI integration:
1. Add new model types to `TYPE_MAPPING` in `civitai_integration.py`
2. Extend search filters in `search_models()` method
3. Add new API endpoints in `app.py`
4. Update frontend UI in `model_manager.html`

## Support

For issues or questions:
- Check CivitAI API documentation: https://github.com/civitai/civitai/wiki/REST-API-Reference
- Review error logs: `/workspace/logs/`
- Open issue on GitHub repository