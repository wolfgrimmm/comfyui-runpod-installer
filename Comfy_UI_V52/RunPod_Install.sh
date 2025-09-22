cd /workspace

git clone --depth 1 https://github.com/comfyanonymous/ComfyUI

cd /workspace/ComfyUI

git reset --hard

git stash

git pull --force

python -m venv venv

source venv/bin/activate

python -m pip install --upgrade pip

pip install torch==2.8.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu129

cd custom_nodes

git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager

git clone --depth 1 https://github.com/cubiq/ComfyUI_IPAdapter_plus

git clone --depth 1 https://github.com/Gourieff/ComfyUI-ReActor

git clone --depth 1 https://github.com/city96/ComfyUI-GGUF

git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Impact-Pack

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

cd ComfyUI-ReActor

git stash

git reset --hard

git pull --force

python install.py

pip install -r requirements.txt

cd ..

cd ComfyUI-GGUF

git stash

git reset --hard

git pull --force

pip install -r requirements.txt

cd ..

cd ComfyUI-Impact-Pack

git stash

git reset --hard

git pull --force

python install.py

pip install -r requirements.txt

cd ..

cd ..

echo Installing requirements...

pip install -r requirements.txt

pip uninstall xformers --yes

pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/flash_attn-2.8.2-cp310-cp310-linux_x86_64.whl

pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/xformers-0.0.33+c159edc0.d20250906-cp39-abi3-linux_x86_64.whl

pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/sageattention-2.2.0-cp310-cp310-linux_x86_64.whl

pip install https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/insightface-0.7.3-cp310-cp310-linux_x86_64.whl

pip install huggingface_hub hf_transfer hf_xet accelerate diffusers onnxruntime-gpu piexif requests deepspeed ultralytics==8.3.197 --upgrade

apt update

apt install psmisc

