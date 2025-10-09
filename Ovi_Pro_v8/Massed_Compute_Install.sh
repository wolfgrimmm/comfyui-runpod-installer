

git clone --depth 1 https://github.com/FurkanGozukara/Ovi_Pro

cd Ovi_Pro

git reset --hard

git pull

python3 -m venv venv

source venv/bin/activate

python3 -m pip install --upgrade pip

cd ..

pip install -r requirements.txt

wget https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/ffmpeg-N-121105-ga0936b9769-linux64-gpl.tar.xz

tar xvf ffmpeg-N-121105-ga0936b9769-linux64-gpl.tar.xz --no-same-owner

sudo mv ffmpeg-N-121105-ga0936b9769-linux64-gpl/bin/ffmpeg /usr/local/bin/
sudo mv ffmpeg-N-121105-ga0936b9769-linux64-gpl/bin/ffprobe /usr/local/bin/

sudo chmod +x /usr/local/bin/ffmpeg
sudo chmod +x /usr/local/bin/ffprobe

echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.bashrc
echo "PATH updated in ~/.bashrc"
echo "Please open a new terminal or run 'source ~/.bashrc' to use the new FFmpeg version"

python Download_Models.py

cd Ovi_Pro

unset LD_LIBRARY_PATH
export PYTHONWARNINGS=ignore
python3 premium.py --share