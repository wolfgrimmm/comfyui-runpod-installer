
cd /workspace

git clone --depth 1 https://github.com/FurkanGozukara/Ovi_Pro

cd Ovi_Pro

git reset --hard

git pull

python -m venv venv

source venv/bin/activate

python -m pip install --upgrade pip

cd ..

pip install -r requirements.txt

wget https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/ffmpeg-N-121105-ga0936b9769-linux64-gpl.tar.xz

tar xvf ffmpeg-N-121105-ga0936b9769-linux64-gpl.tar.xz --no-same-owner

mv ffmpeg-N-121105-ga0936b9769-linux64-gpl/bin/ffmpeg /usr/local/bin/
mv ffmpeg-N-121105-ga0936b9769-linux64-gpl/bin/ffprobe /usr/local/bin/

chmod +x /usr/local/bin/ffmpeg
chmod +x /usr/local/bin/ffprobe

python Download_Models.py

cd Ovi_Pro
unset LD_LIBRARY_PATH
export PYTHONWARNINGS=ignore
python premium.py --share