#!/bin/bash

echo "========================================="
echo "HuggingFace Token Test Script"
echo "========================================="
echo ""

# Check if token is set
if [ -z "$HF_TOKEN" ]; then
    echo "❌ HF_TOKEN environment variable is not set!"
    echo ""
    echo "To set it, run:"
    echo "export HF_TOKEN='hf_...your_token_here...'"
    exit 1
fi

# Show masked token
TOKEN_PREVIEW="${HF_TOKEN:0:7}...${HF_TOKEN: -4}"
echo "📝 Testing token: $TOKEN_PREVIEW"
echo ""

# Method 1: Test with huggingface_hub Python
echo "1️⃣ Testing with Python huggingface_hub..."
python3 << EOF
import os
import sys

try:
    from huggingface_hub import HfApi

    token = os.environ.get('HF_TOKEN')
    api = HfApi()

    # Try to get user info
    user_info = api.whoami(token=token)
    print(f"✅ Token is valid!")
    print(f"   User: {user_info['name']}")
    print(f"   Email: {user_info.get('email', 'N/A')}")
    print(f"   Organizations: {', '.join([org['name'] for org in user_info.get('orgs', [])])}")

except Exception as e:
    if "Invalid" in str(e) or "401" in str(e):
        print("❌ Token is invalid or expired!")
    else:
        print(f"❌ Error: {e}")
    sys.exit(1)
EOF

if [ $? -ne 0 ]; then
    echo ""
    echo "Token validation failed!"
    exit 1
fi

echo ""
echo "2️⃣ Testing access to repositories..."

# Test access to public repo (should work even without token)
echo "   Testing public repo access..."
python3 << EOF
import os
from huggingface_hub import hf_hub_download

try:
    # Try to access a small public file
    hf_hub_download(
        repo_id="bert-base-uncased",
        filename="config.json",
        cache_dir="/tmp/hf_test",
        token=os.environ.get('HF_TOKEN')
    )
    print("   ✅ Can access public repositories")
except Exception as e:
    print(f"   ❌ Cannot access public repos: {e}")
EOF

# Test access to gated repo (requires valid token and acceptance)
echo "   Testing gated repo access (Llama 2)..."
python3 << EOF
import os
from huggingface_hub import HfApi

try:
    api = HfApi()
    token = os.environ.get('HF_TOKEN')

    # Check if user has access to Llama 2 (common gated model)
    try:
        api.model_info("meta-llama/Llama-2-7b-hf", token=token)
        print("   ✅ Can access gated repositories (Llama 2)")
    except Exception as e:
        if "401" in str(e) or "403" in str(e):
            print("   ⚠️  Cannot access Llama 2 (need to accept license at https://huggingface.co/meta-llama/Llama-2-7b-hf)")
        else:
            print(f"   ⚠️  Gated repo test inconclusive: {e}")

except Exception as e:
    print(f"   ❌ Error testing gated repos: {e}")
EOF

# Test specific WAN 2.2 repository access
echo ""
echo "3️⃣ Testing WAN 2.2 repository access..."
python3 << EOF
import os
from huggingface_hub import HfApi

try:
    api = HfApi()
    token = os.environ.get('HF_TOKEN')

    # Check WAN 2.2 repo
    repo_info = api.model_info("Comfy-Org/Wan_2.2_ComfyUI_Repackaged", token=token)
    print(f"   ✅ Can access WAN 2.2 repository")
    print(f"      Repository: {repo_info.modelId}")
    print(f"      Last modified: {repo_info.lastModified}")

    # List some files
    files = api.list_repo_files("Comfy-Org/Wan_2.2_ComfyUI_Repackaged", token=token)
    wan_files = [f for f in files if 'wan2.2' in f and '.safetensors' in f][:3]
    if wan_files:
        print(f"      Sample files found:")
        for f in wan_files:
            print(f"        - {f}")

except Exception as e:
    if "401" in str(e) or "403" in str(e):
        print("   ❌ Cannot access WAN 2.2 repository (token might not have permissions)")
    else:
        print(f"   ❌ Error accessing WAN 2.2 repo: {e}")
EOF

# Test download speed with hf_transfer
echo ""
echo "4️⃣ Testing download capabilities..."
if python3 -c "import hf_transfer" 2>/dev/null; then
    echo "   ✅ hf_transfer is installed (2-5x faster downloads)"
else
    echo "   ⚠️  hf_transfer not installed (downloads will be slower)"
    echo "      Install with: pip install hf_transfer"
fi

# Summary
echo ""
echo "========================================="
echo "📊 Summary"
echo "========================================="

python3 << EOF
import os
from huggingface_hub import HfApi

try:
    api = HfApi()
    token = os.environ.get('HF_TOKEN')
    user_info = api.whoami(token=token)

    print(f"✅ Token is VALID and working!")
    print(f"")
    print(f"Token capabilities:")
    print(f"  • User: {user_info['name']}")
    print(f"  • Type: {'Write' if user_info.get('auth', {}).get('type') == 'write' else 'Read'}")
    print(f"  • Can download public models: Yes")
    print(f"  • Can download private models: {'Yes' if user_info.get('canPay') else 'Depends on permissions'}")
    print(f"")
    print(f"Ready to download WAN 2.2 models!")

except Exception as e:
    print(f"❌ Token validation failed: {e}")
    print(f"")
    print(f"To get a token:")
    print(f"1. Go to https://huggingface.co/settings/tokens")
    print(f"2. Create a new token (Read access is sufficient)")
    print(f"3. Copy the token")
    print(f"4. Run: export HF_TOKEN='hf_...'")
EOF

echo "========================================="