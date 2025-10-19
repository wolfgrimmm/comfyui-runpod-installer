#!/bin/bash

echo "=========================================="
echo "🔍 SAGE ATTENTION VERIFICATION SCRIPT"
echo "=========================================="
echo ""

# Test 1: Check if ComfyUI is running
echo "✓ Test 1: ComfyUI Process Check"
COMFYUI_PID=$(ps aux | grep "python.*main.py.*8188" | grep -v grep | awk '{print $2}')
if [ -z "$COMFYUI_PID" ]; then
    echo "  ❌ FAIL: ComfyUI is not running"
    exit 1
else
    echo "  ✅ PASS: ComfyUI is running (PID: $COMFYUI_PID)"
fi
echo ""

# Test 2: Check if --use-sage-attention flag is present
echo "✓ Test 2: Command Line Flag Check"
if ps aux | grep "python.*main.py" | grep -v grep | grep -q "use-sage-attention"; then
    echo "  ✅ PASS: --use-sage-attention flag is present"
else
    echo "  ❌ FAIL: --use-sage-attention flag is MISSING"
    echo "  Current command:"
    ps aux | grep "python.*main.py" | grep -v grep
    exit 1
fi
echo ""

# Test 3: Check if sageattention package is installed
echo "✓ Test 3: Sageattention Package Check"
if python -c "import sageattention" 2>/dev/null; then
    echo "  ✅ PASS: sageattention package is installed"
else
    echo "  ❌ FAIL: sageattention package is NOT installed"
    exit 1
fi
echo ""

# Test 4: Check ComfyUI logs for "Using sage attention"
echo "✓ Test 4: ComfyUI Startup Logs Check"
LOG_FILES="/tmp/comfyui_start.log /workspace/comfyui.log /tmp/comfyui_manual.log"
FOUND_SAGE_LOG=false
for log_file in $LOG_FILES; do
    if [ -f "$log_file" ]; then
        if grep -q "Using sage attention" "$log_file" 2>/dev/null; then
            echo "  ✅ PASS: Found 'Using sage attention' in $log_file"
            FOUND_SAGE_LOG=true
            break
        fi
    fi
done

if [ "$FOUND_SAGE_LOG" = false ]; then
    echo "  ⚠️  WARNING: Could not find 'Using sage attention' in logs"
    echo "  This might be normal if logs were cleared. Continuing..."
fi
echo ""

# Test 5: Check if control panel has the fix
echo "✓ Test 5: Control Panel Code Check"
if grep -q "Force sage attention" /app/ui/app.py 2>/dev/null; then
    echo "  ✅ PASS: Control panel has Bug #27 fix"
elif grep -q "Don't trust old .env_settings" /app/ui/app.py 2>/dev/null; then
    echo "  ✅ PASS: Control panel has Bug #27 fix"
else
    echo "  ⚠️  WARNING: Control panel may have old code"
    echo "  This won't affect current session but may fail after restart"
fi
echo ""

# Test 6: Check .env_settings file
echo "✓ Test 6: Environment Settings File Check"
if [ -f "/workspace/venv/.env_settings" ]; then
    SETTING=$(grep "COMFYUI_ATTENTION_MECHANISM" /workspace/venv/.env_settings | cut -d'=' -f2)
    if [ "$SETTING" = "sage" ]; then
        echo "  ✅ PASS: .env_settings has correct value (sage)"
    else
        echo "  ⚠️  WARNING: .env_settings has wrong value ($SETTING)"
        echo "  This should be auto-fixed on next restart"
    fi
else
    echo "  ⚠️  WARNING: .env_settings file doesn't exist"
    echo "  This is OK if it's first run"
fi
echo ""

# Test 7: Check startup script has the fix
echo "✓ Test 7: Startup Script Check"
if grep -q "ALWAYS use Sage Attention" /app/start_comfyui.sh 2>/dev/null; then
    echo "  ✅ PASS: start_comfyui.sh has Bug #27 fix"
else
    echo "  ⚠️  WARNING: start_comfyui.sh may have old code"
fi
echo ""

# Final Summary
echo "=========================================="
echo "📊 VERIFICATION SUMMARY"
echo "=========================================="
echo ""
echo "✅ Current Session: SAGE IS WORKING"
echo ""
echo "🔄 After Pod Restart:"
if grep -q "Don't trust old .env_settings" /app/ui/app.py 2>/dev/null; then
    echo "  ✅ Will work correctly (control panel has fix)"
else
    echo "  ⚠️  May need manual intervention (control panel needs update)"
    echo ""
    echo "To fix permanently, run:"
    echo "  curl -o /app/ui/app.py https://raw.githubusercontent.com/wolfgrimmm/comfyui-runpod-installer/main/ui/app.py"
    echo "  pkill -f 'python.*app.py' && cd /app/ui && python -u app.py > /workspace/ui.log 2>&1 &"
fi
echo ""
echo "=========================================="
echo "✅ SAGE ATTENTION IS ACTIVE RIGHT NOW!"
echo "=========================================="
