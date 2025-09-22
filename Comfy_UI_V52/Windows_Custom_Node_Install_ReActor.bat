@echo off

cd ComfyUI

call .\venv\Scripts\activate.bat

cd custom_nodes

git clone --depth 1 https://github.com/Gourieff/ComfyUI-ReActor

cd ComfyUI-ReActor

git stash

git reset --hard

git pull --force

python install.py

pip install -r requirements.txt

cd ..

cd ..

echo Installing requirements...

pip install -r requirements.txt

REM Pause to keep the command prompt open
pause