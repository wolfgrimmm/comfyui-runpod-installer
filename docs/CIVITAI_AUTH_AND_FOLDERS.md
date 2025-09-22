# CivitAI Authentication and Folder Organization

## How CivitAI Downloads Work

### Automatic Folder Detection

When downloading a model from CivitAI, the system now **automatically determines the correct folder** through the following process:

1. **Fetches Model Metadata**: Before downloading, the system calls the CivitAI API to get model version details
2. **Extracts Model Type**: From the API response, it identifies the model type (Checkpoint, LoRA, VAE, etc.)
3. **Identifies Base Model**: Also extracts the base model information (SD 1.5, SDXL, FLUX, etc.)
4. **Smart Folder Selection**: Based on both type and base model, selects the optimal folder

### Folder Mapping

#### Basic Type Mapping
```python
'Checkpoint' → /workspace/models/checkpoints
'LORA/LoCon/LoHA' → /workspace/models/loras
'VAE' → /workspace/models/vae
'ControlNet' → /workspace/models/controlnet
'TextualInversion' → /workspace/models/embeddings
'Upscaler' → /workspace/models/upscale_models
```

#### Smart Organization by Base Model

**Checkpoints:**
- FLUX models → `/workspace/models/diffusion_models/`
- SDXL models → `/workspace/models/checkpoints/sdxl/`
- SD 1.5 models → `/workspace/models/checkpoints/sd15/`
- SD 2.x models → `/workspace/models/checkpoints/sd2/`
- SD 3 models → `/workspace/models/checkpoints/sd3/`

**LoRAs:**
- SDXL LoRAs → `/workspace/models/loras/sdxl/`
- SD 1.5 LoRAs → `/workspace/models/loras/sd15/`

### Example Download Flow

When you download model version ID `245598` (Realistic Vision V6.0):

1. System fetches metadata from CivitAI API
2. Discovers: `type: "Checkpoint"`, `baseModel: "SD 1.5"`
3. Calculates folder: `/workspace/models/checkpoints/sd15/`
4. Downloads file to: `/workspace/models/checkpoints/sd15/Realistic_Vision_V6.0.safetensors`

## Authentication System

### How Authentication Works

1. **API Key Sources** (checked in order):
   - Passed directly to function
   - Environment variable: `CIVITAI_API_KEY`
   - Persistent file: `/workspace/.env`

2. **Automatic Loading**:
   - On initialization, the CivitAI client automatically loads the API key
   - If found in `/workspace/.env`, it's loaded and set as environment variable
   - Key persists across container restarts

3. **Authentication Methods**:
   - **For API calls**: Bearer token in headers
   - **For downloads**: Token as URL parameter

### Setting Up Authentication

#### Method 1: Via API Endpoint (Recommended)
```bash
curl -X POST http://localhost:5005/api/civitai/set-key \
  -H "Content-Type: application/json" \
  -d '{"api_key": "your-civitai-api-key"}'
```

This will:
- Save the key to `/workspace/.env` for persistence
- Validate the key with CivitAI
- Return success/failure status

#### Method 2: Environment Variable
```bash
export CIVITAI_API_KEY="your-api-key"
```

#### Method 3: .env File
Create or edit `/workspace/.env`:
```
CIVITAI_API_KEY=your-api-key
```

### Getting a CivitAI API Key

1. Log into [CivitAI](https://civitai.com)
2. Go to Account Settings
3. Scroll to "API Keys" section
4. Click "+ Add API key"
5. Name your key (e.g., "ComfyUI")
6. Copy the generated key

### Key Benefits

With API key configured:
- ✅ Access to restricted/private models
- ✅ Higher rate limits (more downloads)
- ✅ Authenticated downloads (some creators require auth)
- ✅ Access to your favorites and collections

Without API key:
- ⚠️ Only public models accessible
- ⚠️ Lower rate limits
- ⚠️ Some models may be inaccessible

## API Usage Examples

### Download with Auto-Detection
```python
# Only need version ID - everything else is automatic!
response = requests.post('http://localhost:5005/api/civitai/download', json={
    'version_id': 245598  # System will auto-detect it's SD 1.5 Checkpoint
})
```

### Check Authentication Status
```python
response = requests.get('http://localhost:5005/api/civitai/verify-key')
# Returns: {"has_key": true, "is_valid": true}
```

### Search with Authentication
```python
# Authenticated searches can access more content
response = requests.post('http://localhost:5005/api/civitai/search', json={
    'query': 'anime',
    'nsfw': False  # Can be true if authenticated
})
```

## Troubleshooting

### Models Download to Wrong Folder
- Check if model metadata is being fetched correctly
- Verify base model detection in logs
- Ensure folders have write permissions

### Authentication Not Working
- Check if key exists: `cat /workspace/.env | grep CIVITAI`
- Verify key: `curl http://localhost:5005/api/civitai/verify-key`
- Ensure key has correct permissions on CivitAI

### Rate Limiting
- Add API key for higher limits
- Implement retry logic with exponential backoff
- Check CivitAI status page for outages

## Implementation Details

### Key Components

1. **civitai_integration.py**:
   - `_load_api_key()`: Loads key from env or file
   - `get_model_version_sync()`: Fetches model metadata
   - `get_model_path()`: Smart folder selection logic
   - `download_model()`: Auto-detects type and downloads

2. **Authentication Flow**:
   ```python
   # On init
   api_key = passed_key or env_var or load_from_file()

   # For API calls
   headers['Authorization'] = f'Bearer {api_key}'

   # For downloads
   url += f'?token={api_key}'
   ```

3. **Folder Detection Flow**:
   ```python
   # Fetch metadata
   info = get_model_version(version_id)
   model_type = info['model']['type']  # e.g., "Checkpoint"
   base_model = info['baseModel']      # e.g., "SD 1.5"

   # Determine folder
   folder = get_model_path(model_type, base_model)
   # Returns: /workspace/models/checkpoints/sd15/
   ```

The system is now fully automatic - just provide a model version ID and everything else is handled!