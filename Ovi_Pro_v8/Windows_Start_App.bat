@echo off

cd Ovi_Pro

set PYTHONWARNINGS=ignore

REM SET CUDA_VISIBLE_DEVICES=1

call .\venv\Scripts\activate.bat

python premium.py

REM Pause to keep the command prompt open
pause