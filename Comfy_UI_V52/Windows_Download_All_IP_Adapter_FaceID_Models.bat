@echo off

cd ComfyUI

call .\venv\Scripts\activate.bat

cd ..

set HF_HUB_ENABLE_HF_TRANSFER=1
python Download_IP_Adapters_Fast.py

REM Pause to keep the command prompt open
pause