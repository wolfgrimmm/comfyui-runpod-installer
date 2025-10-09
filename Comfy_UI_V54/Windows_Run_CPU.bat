@echo off

cd ComfyUI

call .\venv\Scripts\activate.bat

set CUDA_VISIBLE_DEVICES=0

python.exe -s main.py --cpu --windows-standalone-build

pause
