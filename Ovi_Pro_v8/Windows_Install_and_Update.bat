@echo off

echo WARNING. For this auto installer to work you need to have installed Python 3.10.11, Git, FFmpeg, cuDNN 9.4+, CUDA 12.8, MSVC and C++ tools 
echo This tutorial shows all step by step : https://youtu.be/DrhUHnYfwC0?si=UAAVyZ8_QUPAjy7a

git clone --depth 1 https://github.com/FurkanGozukara/Ovi_Pro

cd Ovi_Pro

git reset --hard

git pull

py --version >nul 2>&1
if "%ERRORLEVEL%" == "0" (
    echo Python launcher is available. Generating Python 3.10 VENV
    py -3.10 -m venv venv
) else (
    echo Python launcher is not available, generating VENV with default Python. Make sure that it is 3.10
    python -m venv venv
)

call .\venv\Scripts\activate.bat

python -m pip install --upgrade pip

cd ..

pip install -r requirements.txt

Windows_Download_Models_or_Resume_Download.bat

echo installation completed check for errors

REM Pause to keep the command prompt open
pause