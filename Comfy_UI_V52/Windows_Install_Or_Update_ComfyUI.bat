@echo off
setlocal EnableDelayedExpansion

echo ComfyUI Installation Script
echo ==========================
echo.

:PYTHON_VERSION
echo Please select your Python version:
echo 1. Python 3.10
echo 2. Python 3.11
echo 3. Python 3.12
echo 4. Python 3.13
echo.
set /p PYTHON_CHOICE="Enter your choice (1, 2, 3 or 4): "

if "%PYTHON_CHOICE%"=="1" (
    set PYTHON_VERSION=3.10
    set PY_VERSION_ARG=-3.10
) else if "%PYTHON_CHOICE%"=="2" (
    set PYTHON_VERSION=3.11
    set PY_VERSION_ARG=-3.11
) else if "%PYTHON_CHOICE%"=="3" (
    set PYTHON_VERSION=3.12
    set PY_VERSION_ARG=-3.12
) else if "%PYTHON_CHOICE%"=="4" (
    set PYTHON_VERSION=3.13
    set PY_VERSION_ARG=-3.13
) else (
    echo Invalid choice. Please try again.
    goto PYTHON_VERSION
)

echo.
echo Installing ComfyUI with Python %PYTHON_VERSION%...
echo Both Flash Attention and Sage Attention will be installed.
echo Make sure that you have installed Python %PYTHON_VERSION%, Git, C++ tools, FFmpeg
echo Full tutorial to install these : https://youtu.be/-NjNy7afOQ0
echo.

git clone --depth 1 https://github.com/comfyanonymous/ComfyUI

cd ComfyUI

py --version >nul 2>&1
if "%ERRORLEVEL%" == "0" (
    echo Python launcher is available. Generating Python %PYTHON_VERSION% VENV
    py %PY_VERSION_ARG% -m venv venv
) else (
    echo Python launcher is not available, generating VENV with default Python. Make sure that it is %PYTHON_VERSION%
    python -m venv venv
)

call .\venv\Scripts\activate.bat

git stash

git reset --hard

git pull --force

python -m pip install --upgrade pip

pip install torch==2.8.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu129

mkdir custom_nodes

cd custom_nodes

git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager

git clone --depth 1 https://github.com/cubiq/ComfyUI_IPAdapter_plus

git clone --depth 1 https://github.com/city96/ComfyUI-GGUF

cd ComfyUI-Manager

git stash

git reset --hard

git pull --force

pip install -r requirements.txt

cd ..

cd ComfyUI_IPAdapter_plus

git stash

git reset --hard

git pull --force

cd ..

cd ComfyUI-GGUF

git stash

git reset --hard

git pull --force

pip install -r requirements.txt

cd ..

cd ..

echo Installing requirements...

pip install -r requirements.txt

pip uninstall xformers --yes

if "%PYTHON_VERSION%"=="3.10" (
	pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/flash_attn-2.8.2-cp310-cp310-win_amd64.whl
	pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/insightface-0.7.3-cp310-cp310-win_amd64.whl
    pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/deepspeed-0.16.5-cp310-cp310-win_amd64.whl	
) else if "%PYTHON_VERSION%"=="3.11" (
    pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/flash_attn-2.8.2-cp311-cp311-win_amd64.whl
	pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/insightface-0.7.3-cp311-cp311-win_amd64.whl
    pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/deepspeed-0.16.5-cp311-cp311-win_amd64.whl
) else if "%PYTHON_VERSION%"=="3.12" (
    pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/flash_attn-2.8.2-cp312-cp312-win_amd64.whl
	pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/insightface-0.7.3-cp312-cp312-win_amd64.whl
    pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/deepspeed-0.16.5-cp312-cp312-win_amd64.whl
) else if "%PYTHON_VERSION%"=="3.13" (
    pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/flash_attn-2.8.2-cp313-cp313-win_amd64.whl
	pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/insightface-0.7.3-cp313-cp313-win_amd64.whl
)

pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/xformers-0.0.33+c159edc0.d20250906-cp39-abi3-win_amd64.whl
pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/sageattention-2.2.0-cp39-abi3-win_amd64.whl
pip install "triton-windows<3.5" huggingface_hub hf_transfer hf_xet accelerate diffusers onnxruntime-gpu piexif requests ultralytics==8.3.197 --upgrade


echo.
echo =====================================================
echo The following libraries were installed in the venv:
echo =====================================================
echo.
echo =====================================================
echo Installation completed successfully! If you had previously installed, all packages updated to latest
echo Python %PYTHON_VERSION% virtual environment created and configured.
echo We have installed and or updated Flash Attention 2.8.3, Sage Attention 2.2.0, InsightFace, DeepSpeed (Only Python 3.13 lacks this), xFormers 0.0.33, Accelerate, Diffusers, Triton 3.4, ComfyUI-Manager, ComfyUI_IPAdapter_plus, ComfyUI-GGUF, ComfyUI-Impact-Pack
echo =====================================================
echo.

REM Pause to keep the command prompt open
pause