# RunPod Secrets Configuration Guide

## Overview
This guide explains how to properly set up secrets for HuggingFace and CivitAI in RunPod.

## Important: RunPod Secret Naming Rules

1. **Secret names CANNOT start with "RUNPOD"**
2. **RunPod automatically prefixes all secrets with `RUNPOD_SECRET_`**
3. **Use the template variable syntax in pod configuration**

## Setting Up Secrets

### Step 1: Create Secrets in RunPod Dashboard

Go to **Settings → Secrets** and create:

| Secret Name | Secret Value | Available As |
|------------|--------------|--------------|
| `HF_TOKEN` | `hf_your_actual_token_here` | `RUNPOD_SECRET_HF_TOKEN` |
| `CIVITAI_API_KEY` | `your_civitai_api_key` | `RUNPOD_SECRET_CIVITAI_API_KEY` |

**DO NOT** name them:
- ❌ `RUNPOD_HF_TOKEN`
- ❌ `RUNPOD_SECRET_HF_TOKEN`
- ❌ `RUNPOD_CIVITAI_API_KEY`

**DO** name them:
- ✅ `HF_TOKEN`
- ✅ `CIVITAI_API_KEY`

### Step 2: Use in Pod Template

When creating or editing a pod template, add environment variables:

```bash
# In Pod Template Environment Variables section:
HF_TOKEN={{ RUNPOD_SECRET_HF_TOKEN }}
CIVITAI_API_KEY={{ RUNPOD_SECRET_CIVITAI_API_KEY }}
```

This template syntax tells RunPod to substitute the secret value at runtime.

### Step 3: Verify in Pod

Once your pod starts, verify the secrets are loaded:

```bash
# Check HuggingFace token
echo ${HF_TOKEN:0:10}...  # Should show first 10 chars

# Check CivitAI token
echo ${CIVITAI_API_KEY:0:10}...  # Should show first 10 chars

# Test HuggingFace
python3 -c "from huggingface_hub import HfApi; print(HfApi().whoami(token='$HF_TOKEN')['name'])"

# Test CivitAI
python3 /workspace/scripts/test-civitai.py
```

## How It Works

1. **You create secret**: `HF_TOKEN` = `hf_abc123...`
2. **RunPod stores it as**: `RUNPOD_SECRET_HF_TOKEN`
3. **You use in template**: `HF_TOKEN={{ RUNPOD_SECRET_HF_TOKEN }}`
4. **Pod receives**: `HF_TOKEN=hf_abc123...`

## Alternative Methods (If Secrets Don't Work)

### Method 1: Direct Export in Pod
```bash
export HF_TOKEN='hf_your_token_here'
export CIVITAI_API_KEY='your_civitai_key_here'
```

### Method 2: .env File (Persistent)
```bash
cat > /workspace/.env << EOF
HF_TOKEN=hf_your_token_here
CIVITAI_API_KEY=your_civitai_key_here
EOF
```

### Method 3: In Startup Script
Add to `/workspace/startup.sh`:
```bash
#!/bin/bash
export HF_TOKEN='hf_your_token_here'
export CIVITAI_API_KEY='your_civitai_key_here'
```

## Token Locations

### HuggingFace Token
- Get from: https://huggingface.co/settings/tokens
- Permissions needed: Read (minimum)
- Used for: Downloading models from HuggingFace

### CivitAI API Key
- Get from: https://civitai.com/user/account
- Section: API Keys
- Used for: Downloading models from CivitAI without rate limits

## Troubleshooting

### "Token not found"
1. Check secret name doesn't start with "RUNPOD"
2. Verify pod template has the environment variable set
3. Restart pod after adding secrets

### "Invalid token"
1. Check for extra spaces or quotes
2. Verify token hasn't expired
3. Test token outside RunPod first

### Script Detection Order
Our scripts check for tokens in this order:
1. `$HF_TOKEN` (if set via template)
2. `$RUNPOD_SECRET_HF_TOKEN` (direct secret)
3. `$HUGGING_FACE_HUB_TOKEN` (alternative name)
4. `/workspace/.env` file

## Security Best Practices

1. **Never commit tokens to Git**
2. **Use RunPod secrets when possible** (encrypted at rest)
3. **Don't log token values** in scripts
4. **Rotate tokens periodically**
5. **Use read-only tokens** when possible

## Quick Test Commands

```bash
# Test all configurations
cat > /tmp/test_secrets.sh << 'EOF'
#!/bin/bash
echo "=== Secret Configuration Test ==="
echo ""

# HuggingFace
if [ -n "$HF_TOKEN" ]; then
    echo "✅ HF_TOKEN is set (${#HF_TOKEN} chars)"
elif [ -n "$RUNPOD_SECRET_HF_TOKEN" ]; then
    echo "⚠️ HF_TOKEN not set but RUNPOD_SECRET_HF_TOKEN exists"
    echo "   Add to pod template: HF_TOKEN={{ RUNPOD_SECRET_HF_TOKEN }}"
else
    echo "❌ No HuggingFace token found"
fi

# CivitAI
if [ -n "$CIVITAI_API_KEY" ]; then
    echo "✅ CIVITAI_API_KEY is set (${#CIVITAI_API_KEY} chars)"
elif [ -n "$RUNPOD_SECRET_CIVITAI_API_KEY" ]; then
    echo "⚠️ CIVITAI_API_KEY not set but RUNPOD_SECRET_CIVITAI_API_KEY exists"
    echo "   Add to pod template: CIVITAI_API_KEY={{ RUNPOD_SECRET_CIVITAI_API_KEY }}"
else
    echo "❌ No CivitAI key found"
fi

echo ""
echo "=== Test Complete ==="
EOF

bash /tmp/test_secrets.sh
```

## Summary

For RunPod secrets to work properly:
1. Name secrets WITHOUT "RUNPOD" prefix
2. Use template variables in pod configuration
3. Scripts automatically check multiple locations
4. Tokens enable faster downloads and avoid rate limits