echo starting to insta

cd ..

cd ..

cd ComfyUI

call .\venv\Scripts\activate.bat

cd custom_nodes

git clone https://github.com/agilly1989/ComfyUI_agilly1989_motorway

git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts

git clone https://github.com/yolain/ComfyUI-Easy-Use

cd ComfyUI-Easy-Use

pip install -r requirements.txt

cd ..

git clone https://github.com/Acly/comfyui-inpaint-nodes

git clone https://github.com/TTPlanetPig/Comfyui_JC2

cd Comfyui_JC2

pip install -r requirements.txt

cd ..

git clone https://github.com/chflame163/ComfyUI_LayerStyle

cd ComfyUI_LayerStyle

pip install -r requirements.txt

cd ..

git clone https://github.com/rgthree/rgthree-comfy

cd rgthree-comfy

pip install -r requirements.txt

cd ..

git clone https://github.com/cubiq/ComfyUI_essentials

cd ComfyUI_essentials

pip install -r requirements.txt

cd ..

git clone https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes

git clone https://github.com/TTPlanetPig/Comfyui_Object_Migration

git clone https://github.com/chflame163/ComfyUI_LayerStyle

cd ComfyUI_LayerStyle

pip install -r requirements.txt

cd ..

git clone https://github.com/chflame163/ComfyUI_LayerStyle_Advance

cd ComfyUI_LayerStyle_Advance

pip install -r requirements.txt

cd ..


git clone https://github.com/MinusZoneAI/ComfyUI-FluxExt-MZ


git clone https://github.com/shadowcz007/comfyui-mixlab-nodes

cd comfyui-mixlab-nodes

pip install -r requirements.txt

cd ..

echo all installed

pause