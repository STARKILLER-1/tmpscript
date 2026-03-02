#!/bin/bash
set -e

# RunPod ComfyUI Blackwell Edition provisioning script
# Запуск: bash /workspace/run_comfy_runpod.sh

# Активируем venv — RunPod Blackwell image использует .venv-cu128
if [[ -f /workspace/runpod-slim/ComfyUI/.venv-cu128/bin/activate ]]; then
    source /workspace/runpod-slim/ComfyUI/.venv-cu128/bin/activate
elif [[ -f /venv/main/bin/activate ]]; then
    source /venv/main/bin/activate
elif [[ -f /workspace/venv/bin/activate ]]; then
    source /workspace/venv/bin/activate
fi

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

echo "=== ComfyUI RunPod Setup (x-mode) ==="

APT_PACKAGES=()
PIP_PACKAGES=()

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
    "https://github.com/teskor-hub/comfyui-teskors-utils"
)

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

# Без SD1.5 — на RunPod не нужен бенчмарк vast.ai
CHECKPOINT_MODELS=()

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

function provisioning_start() {
    echo ""
    echo "##############################################"
    echo "# ебашим жоска и мрачно                      #"
    echo "# gazik X-MODE RunPod 2025-2026              #"
    echo "# бабки бабки                                #"
    echo "##############################################"
    echo ""

    provisioning_get_apt_packages
    provisioning_clone_comfyui
    provisioning_install_base_reqs
    provisioning_get_nodes
    provisioning_get_pip_packages
    provisioning_fix_onnx_cuda

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
    echo "Перезапусти ComfyUI: cd ${COMFYUI_DIR} && python main.py --listen 0.0.0.0 --port 8188"
    echo ""
}

function provisioning_clone_comfyui() {
    # RunPod Blackwell image: /workspace/runpod-slim/ComfyUI
    if [[ -d "/workspace/runpod-slim/ComfyUI" ]]; then
        COMFYUI_DIR="/workspace/runpod-slim/ComfyUI"
    elif [[ -d "/opt/ComfyUI" ]]; then
        COMFYUI_DIR="/opt/ComfyUI"
    elif [[ -d "/workspace/ComfyUI" ]]; then
        COMFYUI_DIR="/workspace/ComfyUI"
    fi
    echo "ComfyUI dir: ${COMFYUI_DIR}"
    cd "${COMFYUI_DIR}"
}

function provisioning_install_base_reqs() {
    if [[ -f requirements.txt ]]; then
        echo "Газик устанавливает base requirements..."
        pip install --no-cache-dir -r requirements.txt
    fi
}

function provisioning_get_apt_packages() {
    if [[ ${#APT_PACKAGES[@]} -gt 0 ]]; then
        echo "Газик устанавливает apt packages..."
        apt-get update && apt-get install -y "${APT_PACKAGES[@]}"
    fi
}

function provisioning_get_pip_packages() {
    if [[ ${#PIP_PACKAGES[@]} -gt 0 ]]; then
        echo "Газик устанавливает extra pip packages..."
        pip install --no-cache-dir "${PIP_PACKAGES[@]}"
    fi
}

function provisioning_fix_onnx_cuda() {
    echo "Fixing ONNX CUDA provider..."

    # Ставим onnxruntime-gpu ПОСЛЕ нод (чтобы ноды не перезаписали на CPU версию)
    pip install --no-cache-dir --force-reinstall \
        onnxruntime-gpu \
        nvidia-cublas-cu12 \
        nvidia-cuda-nvrtc-cu12 \
        nvidia-cuda-runtime-cu12 \
        nvidia-cudnn-cu12 \
        nvidia-cufft-cu12 \
        nvidia-curand-cu12 \
        nvidia-cusolver-cu12 \
        nvidia-cusparse-cu12 \
        nvidia-nccl-cu12 \
        nvidia-nvjitlink-cu12

    # Симлинкаем .so из pip пакетов в /usr/lib
    SITE_PACKAGES="$(python -c 'import site; print(site.getsitepackages()[0])' 2>/dev/null || echo '/venv/main/lib/python3.12/site-packages')"
    NVIDIA_BASE="${SITE_PACKAGES}/nvidia"

    if [[ -d "$NVIDIA_BASE" ]]; then
        CUDA_LIB_PATHS=""
        for libdir in "$NVIDIA_BASE"/*/lib; do
            if [[ -d "$libdir" ]]; then
                CUDA_LIB_PATHS="${CUDA_LIB_PATHS:+${CUDA_LIB_PATHS}:}${libdir}"
                for lib in "$libdir"/*.so*; do
                    [[ -f "$lib" ]] && ln -sf "$lib" /usr/lib/ 2>/dev/null || true
                done
            fi
        done
        ldconfig 2>/dev/null || true
        export LD_LIBRARY_PATH="${CUDA_LIB_PATHS}:${LD_LIBRARY_PATH:-}"
        echo "  CUDA libs symlinked: ${CUDA_LIB_PATHS}"
    fi

    [[ -d "/usr/local/cuda/lib64" ]] && export LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"

    # Проверка
    python -c "
import onnxruntime as ort
providers = ort.get_available_providers()
print(f'  onnxruntime providers: {providers}')
if 'CUDAExecutionProvider' in providers:
    print('  OK: CUDAExecutionProvider available')
else:
    print('  WARNING: CUDAExecutionProvider NOT available!')
" 2>&1 || true
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

provisioning_start
