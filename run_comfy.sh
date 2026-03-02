#!/bin/bash
set -e
source /venv/main/bin/activate

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

echo "=== ComfyUI запускает ( x-mode) ==="

APT_PACKAGES=()           # если нужно — добавь sudo apt install ...
PIP_PACKAGES=()           # глобальные pip пакеты, если сверх requirements

NODES=(
    "https://github.com/kijai/ComfyUI-WanVideoWrapper"
    "https://github.com/chflame163/ComfyUI_LayerStyle"
    "https://github.com/yolain/ComfyUI-Easy-Use"
    "https://github.com/kijai/ComfyUI-KJNodes"
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
    "https://github.com/kijai/ComfyUI-segment-anything-2"
    "https://github.com/cubiq/ComfyUI_essentials"
    "https://github.com/fq393/ComfyUI-ZMG-Nodes"
    "https://github.com/kijai/ComfyUI-WanAnimatePreprocess"
    "https://github.com/rgthree/rgthree-comfy"
    "https://github.com/jnxmx/ComfyUI_HuggingFace_Downloader"
    "https://github.com/teskor-hub/NEW-UTILS"
)

# ЗАГРУЗКА ФАЙЛОВ НУЖНЫХ
CLIP_MODELS=(
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/klip_vision.safetensors"
)

CLIP_VISION=(
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors"
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/klip_vision.safetensors"
)

TEXT_ENCODERS=(
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/text_enc.safetensors"
)

DIFFUSION_MODELS=(
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors"
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanModel.safetensors"
)

# SD1.5 нужен для бенчмарка vast.ai serverless (без него воркер вечно Loading)
CHECKPOINT_MODELS=(
    "https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors"
)

VAE_MODELS=(
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/vae.safetensors"
)

DETECTION_MODELS=(
    "https://huggingface.co/Wan-AI/Wan2.2-Animate-14B/resolve/main/process_checkpoint/det/yolov10m.onnx"
    "https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_data.bin"
    "https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_model.onnx"
)

LORAS=(
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanFun.reworked.safetensors"
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/light.safetensors"
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanPusa.safetensors"
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/wan.reworked.safetensors"
)

### ─────────────────────────────────────────────
### DO NOT EDIT BELOW UNLESS YOU KNOW WHAT YOU ARE DOING
### ─────────────────────────────────────────────

function provisioning_start() {
    echo ""
    echo "##############################################"
    echo "# ебашим жоска и мрачно                      #"
    echo "# gazik X-MODE setup 2025-2026               #"
    echo "# бабки бабки                                #"
    echo "##############################################"
    echo ""

    provisioning_get_apt_packages
    provisioning_clone_comfyui
    provisioning_install_base_reqs
    provisioning_get_nodes
    provisioning_get_pip_packages
    pip install --no-cache-dir onnxruntime-gpu nvidia-cublas-cu12 nvidia-cudnn-cu12

    # ── FIX: onnxruntime не находит libcublas.so.12 из pip-пакетов ──
    # pip ставит .so в site-packages/nvidia/*/lib/, но LD_LIBRARY_PATH не включает этот путь
    # → onnxruntime fallback на CPU → pose detection 1.5 it/s вместо 100 it/s на 449 кадрах
    #
    # Два подхода: symlink (надёжный, переживает перезапуск) + LD_LIBRARY_PATH (на всякий случай)
    echo "Fixing CUDA libs for onnxruntime-gpu..."
    NVIDIA_LIBS="$(python -c 'import nvidia.cublas.lib as l; print(l.__path__[0])' 2>/dev/null || true)"
    CUDNN_LIBS="$(python -c 'import nvidia.cudnn.lib as l; print(l.__path__[0])' 2>/dev/null || true)"
    if [[ -n "$NVIDIA_LIBS" ]]; then
        # Симлинки в /usr/lib — работает независимо от LD_LIBRARY_PATH
        for lib in "$NVIDIA_LIBS"/libcublas*.so* "$CUDNN_LIBS"/libcudnn*.so*; do
            if [[ -f "$lib" ]]; then
                ln -sf "$lib" /usr/lib/ 2>/dev/null || true
            fi
        done
        ldconfig 2>/dev/null || true

        # + export на случай если ldconfig не обновился
        export LD_LIBRARY_PATH="${NVIDIA_LIBS}:${CUDNN_LIBS}:${LD_LIBRARY_PATH:-}"
        echo "  Symlinked CUDA libs to /usr/lib + LD_LIBRARY_PATH updated"
    fi

    # Проверка что onnxruntime видит CUDA
    python -c "
import onnxruntime as ort
providers = ort.get_available_providers()
print(f'  onnxruntime providers: {providers}')
if 'CUDAExecutionProvider' not in providers:
    print('  WARNING: CUDAExecutionProvider NOT available!')
else:
    print('  OK: CUDAExecutionProvider available')
" 2>&1 || true

    provisioning_get_files "${COMFYUI_DIR}/models/checkpoints"         "${CHECKPOINT_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/clip"               "${CLIP_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/clip_vision"        "${CLIP_VISION[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/text_encoders"      "${TEXT_ENCODERS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/vae"                "${VAE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/diffusion_models"   "${DIFFUSION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/detection"          "${DETECTION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/loras"              "${LORAS[@]}"

    echo ""
    echo "Газик настроил → всё скачано, provisioning complete"
    echo ""
}

function provisioning_clone_comfyui() {
    if [[ -d "/opt/ComfyUI" ]]; then
        COMFYUI_DIR="/opt/ComfyUI"
    elif [[ -d "/workspace/ComfyUI" ]]; then
        COMFYUI_DIR="/workspace/ComfyUI"
    fi
    echo "ComfyUI dir: ${COMFYUI_DIR}"
    cd "${COMFYUI_DIR}"
}

function provisioning_install_base_reqs() {
    if [[ -f requirements.txt ]]; then
        echo "Газик установливает base requirements..."
        pip install --no-cache-dir -r requirements.txt
    fi
}

function provisioning_get_apt_packages() {
    if [[ ${#APT_PACKAGES[@]} -gt 0 ]]; then
        echo "Газик устанавливает apt packages..."
        sudo apt update && sudo apt install -y "${APT_PACKAGES[@]}"
    fi
}

function provisioning_get_pip_packages() {
    if [[ ${#PIP_PACKAGES[@]} -gt 0 ]]; then
        echo "Газик устанавливает extra pip packages..."
        pip install --no-cache-dir "${PIP_PACKAGES[@]}"
    fi
}

function provisioning_get_nodes() {
    mkdir -p "${COMFYUI_DIR}/custom_nodes"
    cd "${COMFYUI_DIR}/custom_nodes"

    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        path="./${dir}"

        if [[ -d "$path" ]]; then
            echo "Updating node: $dir"
            (cd "$path" && git pull --ff-only 2>/dev/null || { git fetch && git reset --hard origin/main; })
        else
            echo "Cloning node: $dir"
            git clone "$repo" "$path" --recursive || echo " [!] Clone failed: $repo"
        fi

        requirements="${path}/requirements.txt"
        if [[ -f "$requirements" ]]; then
            echo "Installing deps for $dir..."
            pip install --no-cache-dir -r "$requirements" || echo " [!] pip requirements failed for $dir"
        fi
    done
}

function provisioning_get_files() {
    if [[ $# -lt 2 ]]; then return; fi
    local dir="$1"
    shift
    local files=("$@")

    mkdir -p "$dir"
    echo "Скачивание ${#files[@]} file(s) → $dir..."

    for url in "${files[@]}"; do
        echo "→ $url"
        local -a wget_args=(-nc --content-disposition --show-progress -e dotbytes=4M -P "$dir")
        if [[ -n "$HF_TOKEN" && "$url" =~ huggingface\.co ]]; then
            wget_args+=(--header="Authorization: Bearer $HF_TOKEN")
        elif [[ -n "$CIVITAI_TOKEN" && "$url" =~ civitai\.com ]]; then
            wget_args+=(--header="Authorization: Bearer $CIVITAI_TOKEN")
        fi

        wget "${wget_args[@]}" "$url" || echo " [!] Download failed: $url"
        echo ""
    done
}

# Запуск provisioning если не отключен
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
