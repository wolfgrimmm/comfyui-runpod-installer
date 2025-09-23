#!/bin/bash

# Test script for CivitAI URL downloads
# Usage: ./test-civitai-url.sh "https://civitai.com/models/..."

echo "========================================="
echo "CivitAI Direct URL Download Test"
echo "========================================="
echo ""

# Check if URL was provided
if [ -z "$1" ]; then
    echo "Usage: $0 <civitai_url>"
    echo ""
    echo "Examples:"
    echo "  $0 https://civitai.com/api/download/models/1094291"
    echo "  $0 https://civitai.com/models/12345?modelVersionId=1094291"
    echo ""
    exit 1
fi

URL="$1"
API_ENDPOINT="http://localhost:7777/api/civitai/download-url"

echo "📍 Testing URL: $URL"
echo ""

# Make the API call
echo "📡 Sending request to control panel..."
RESPONSE=$(curl -s -X POST "$API_ENDPOINT" \
    -H "Content-Type: application/json" \
    -d "{\"url\": \"$URL\"}")

# Check if curl succeeded
if [ $? -ne 0 ]; then
    echo "❌ Failed to connect to control panel"
    echo "   Make sure the control panel is running on port 7777"
    exit 1
fi

# Parse response
echo "📦 Response:"
echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"

# Check if download was successful
if echo "$RESPONSE" | grep -q '"success": true'; then
    echo ""
    echo "✅ Download successful!"

    # Extract filename if available
    FILENAME=$(echo "$RESPONSE" | grep -o '"filename": "[^"]*"' | cut -d'"' -f4)
    if [ -n "$FILENAME" ]; then
        echo "   File: $FILENAME"
    fi

    # Extract path if available
    PATH_VAL=$(echo "$RESPONSE" | grep -o '"path": "[^"]*"' | cut -d'"' -f4)
    if [ -n "$PATH_VAL" ]; then
        echo "   Location: $PATH_VAL"
    fi
else
    echo ""
    echo "❌ Download failed"
    ERROR=$(echo "$RESPONSE" | grep -o '"error": "[^"]*"' | cut -d'"' -f4)
    if [ -n "$ERROR" ]; then
        echo "   Error: $ERROR"
    fi
fi

echo ""
echo "========================================="
echo "💡 How to use in Model Manager UI:"
echo "========================================="
echo "1. Open Control Panel at http://localhost:7777"
echo "2. Go to Model Manager section"
echo "3. Look for 'Download from URL' input field"
echo "4. Paste your CivitAI URL and click Download"
echo ""
echo "Supported URL formats:"
echo "• https://civitai.com/api/download/models/VERSION_ID"
echo "• https://civitai.com/models/MODEL_ID?modelVersionId=VERSION_ID"
echo "• https://civitai.com/models/MODEL_ID"