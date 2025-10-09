echo "starting to install"

cd ..

cd ..

cd ComfyUI

source ./venv/bin/activate

cd custom_nodes

git clone --recursive https://github.com/orssorbit/ComfyUI-wanBlockswap

cd ComfyUI-wanBlockswap

git pull

cd ..

git clone --recursive https://github.com/christian-byrne/audio-separation-nodes-comfyui

cd audio-separation-nodes-comfyui

git pull

pip install -r requirements.txt

cd ..

git clone --recursive https://github.com/kijai/ComfyUI-KJNodes

cd ComfyUI-KJNodes

git pull

pip install -r requirements.txt

cd ..

git clone --recursive https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite

cd ComfyUI-VideoHelperSuite

git pull

pip install -r requirements.txt

cd ..

git clone --recursive https://github.com/kijai/ComfyUI-WanVideoWrapper

cd ComfyUI-WanVideoWrapper

git pull

git checkout 6d51934ae816e9c87fb9b6183fb644d7fd564943

pip install -r requirements.txt

pip install peft>=0.15.0 --upgrade

pip install soxr==0.5.0.post1

echo "all installed"