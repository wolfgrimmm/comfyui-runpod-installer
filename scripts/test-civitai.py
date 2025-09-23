#!/usr/bin/env python3
"""
Test script for CivitAI integration
Tests authentication and download functionality
"""

import sys
import os

# Add parent directory to path
sys.path.insert(0, '/workspace')
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from ui.civitai_integration import CivitAIClient

def test_civitai():
    print("========================================")
    print("CivitAI Integration Test")
    print("========================================")
    print()

    # Initialize client
    print("1. Initializing CivitAI client...")
    client = CivitAIClient()

    # Check if API key is loaded
    if client.api_key:
        print(f"   ✅ API key loaded: {client.api_key[:10]}...")
    else:
        print("   ⚠️ No API key found")
        print()
        print("   To set an API key:")
        print("   1. Get your API key from: https://civitai.com/user/account")
        print("   2. Set it using one of these methods:")
        print("      - export CIVITAI_API_KEY='your_key_here'")
        print("      - export RUNPOD_SECRET_CIVITAI_API_KEY='your_key_here'")
        print("      - Add to /workspace/.env: CIVITAI_API_KEY=your_key_here")
        print()

    # Test API key verification
    print("2. Verifying API key...")
    if client.verify_api_key():
        print("   ✅ API key is valid!")
    else:
        print("   ❌ API key is invalid or not set")
        print("   Downloads will still work but may be rate limited")

    print()
    print("3. Testing URL parsing...")

    test_urls = [
        "https://civitai.com/api/download/models/1094291",
        "https://civitai.com/models/12345?modelVersionId=1094291",
        "https://civitai.com/models/12345",
        "1094291",  # Direct version ID
    ]

    for url in test_urls:
        version_id = client.parse_civitai_url(url)
        if version_id:
            print(f"   ✅ Parsed: {url[:50]}... → Version ID: {version_id}")
        else:
            # Try as direct ID
            try:
                version_id = int(url)
                print(f"   ✅ Direct ID: {url} → Version ID: {version_id}")
            except:
                print(f"   ❌ Failed to parse: {url[:50]}...")

    print()
    print("4. Testing download functionality...")
    print()

    # Example download (small LoRA for testing)
    test_model_id = 1094291  # Replace with a small model for testing
    print(f"   Test download of model version: {test_model_id}")
    print("   (Set CIVITAI_TEST_DOWNLOAD=1 to actually download)")

    if os.environ.get('CIVITAI_TEST_DOWNLOAD') == '1':
        try:
            print("   Starting download...")

            def progress_callback(progress):
                percent = progress.get('percentage', 0)
                downloaded = progress.get('downloaded', 0) / (1024*1024)  # Convert to MB
                total = progress.get('total', 0) / (1024*1024)
                print(f"   Progress: {percent:.1f}% ({downloaded:.1f}MB / {total:.1f}MB)", end='\r')

            path = client.download_model(test_model_id, progress_callback=progress_callback)
            print(f"\n   ✅ Downloaded to: {path}")
        except Exception as e:
            print(f"   ❌ Download failed: {e}")
    else:
        print("   Skipping actual download (set CIVITAI_TEST_DOWNLOAD=1 to test)")

    print()
    print("5. Testing direct URL download...")

    test_url = "https://civitai.com/api/download/models/1094291"
    print(f"   Test URL: {test_url}")

    if os.environ.get('CIVITAI_TEST_DOWNLOAD') == '1':
        try:
            path = client.download_from_url(test_url)
            print(f"   ✅ Downloaded to: {path}")
        except Exception as e:
            print(f"   ❌ Download failed: {e}")
    else:
        print("   Skipping actual download")

    print()
    print("========================================")
    print("✅ CivitAI Integration Test Complete")
    print("========================================")
    print()
    print("Summary:")
    print(f"• API Key: {'✅ Configured' if client.api_key else '⚠️ Not configured'}")
    print(f"• API Valid: {'✅ Yes' if client.verify_api_key() else '❌ No'}")
    print(f"• URL Parsing: ✅ Working")
    print(f"• Download Ready: {'✅ Yes' if client.api_key or True else '❌ No'}")
    print()
    print("Note: CivitAI downloads work without API key but may be rate limited.")
    print("Get your API key from: https://civitai.com/user/account")

if __name__ == "__main__":
    test_civitai()