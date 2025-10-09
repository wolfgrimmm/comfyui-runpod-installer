@echo off

cd ComfyUI

call .\venv\Scripts\activate.bat

cd custom_nodes

git clone --depth 1 https://github.com/Gourieff/ComfyUI-ReActor

git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Impact-Pack

cd ComfyUI-ReActor

git stash

git reset --hard

git pull --force

python install.py

pip install -r requirements.txt

cd ..

cd ComfyUI-Impact-Pack

git stash

git reset --hard

git pull --force

pip install -r requirements.txt

cd ..

cd ..

echo Installing requirements...

pip install -r requirements.txt

pip install onnxruntime-gpu==1.22.0

REM Pause to keep the command prompt open
pause