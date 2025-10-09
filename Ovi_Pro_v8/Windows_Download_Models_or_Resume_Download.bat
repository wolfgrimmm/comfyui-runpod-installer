@echo off

cd Ovi_Pro

call .\venv\Scripts\activate.bat

cd ..

python Download_Models.py

REM Pause to keep the command prompt open
pause