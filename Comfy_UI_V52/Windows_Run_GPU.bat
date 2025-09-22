@echo off

cd ComfyUI

call .\venv\Scripts\activate.bat

REM set CUDA_VISIBLE_DEVICES=0

python.exe -s main.py --windows-standalone-build --use-sage-attention

pause
