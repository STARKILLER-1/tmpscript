#!/bin/bash
set -e

# RunPod ComfyUI Blackwell Edition provisioning script
# Модели → /workspace/models/ (общие для pod и serverless)
# Симлинки → ComfyUI/models/
# Запуск: bash /workspace/run_comfy.sh

# Активируем venv
if [[ -f /workspace/runpod-slim/ComfyUI/.venv-cu128/bin/activate ]]; then
    source /workspace/runpod-slim/ComfyUI/.venv-cu128/bin/activate
elif [[ -f /venv/main/bin/activate ]]; then
    source /venv/main/bin/activate
elif [[ -f /workspace/venv/bin/activate ]]; then
    source /workspace/venv/bin/activate
fi

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"
MODELS_DIR="${WORKSPACE}/models"

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
    provisioning_find_comfyui
    provisioning_install_base_reqs
    provisioning_get_nodes
    provisioning_get_pip_packages
    provisioning_fix_onnx_cuda

    # Модели качаются в /workspace/models/ (общая папка для pod + serverless)
    provisioning_get_files "${MODELS_DIR}/checkpoints"         "${CHECKPOINT_MODELS[@]}"
    provisioning_get_files "${MODELS_DIR}/clip"               "${CLIP_MODELS[@]}"
    provisioning_get_files "${MODELS_DIR}/clip_vision"        "${CLIP_VISION[@]}"
    provisioning_get_files "${MODELS_DIR}/text_encoders"      "${TEXT_ENCODERS[@]}"
    provisioning_get_files "${MODELS_DIR}/vae"                "${VAE_MODELS[@]}"
    provisioning_get_files "${MODELS_DIR}/diffusion_models"   "${DIFFUSION_MODELS[@]}"
    provisioning_get_files "${MODELS_DIR}/detection"          "${DETECTION_MODELS[@]}"
    provisioning_get_files "${MODELS_DIR}/loras"              "${LORAS[@]}"

    provisioning_symlink_models
    provisioning_restart_comfyui

    echo ""
    echo "Газик настроил → всё скачано, provisioning complete"
    echo "Модели: ${MODELS_DIR}/ ($(du -sh ${MODELS_DIR} 2>/dev/null | cut -f1))"
    echo "ComfyUI: ${COMFYUI_DIR}"
    echo ""
}

function provisioning_find_comfyui() {
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

    SITE_PACKAGES="$(python3 -c 'import site; print(site.getsitepackages()[0])' 2>/dev/null || echo '/venv/main/lib/python3.12/site-packages')"
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

    python3 -c "
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

        if [[ -f "${path}/requirements.txt" ]]; then
            echo "Installing deps for $dir..."
            pip install --no-cache-dir -r "${path}/requirements.txt" || echo " [!] pip failed for $dir"
        fi
    done
}

function provisioning_symlink_models() {
    echo "Создаём симлинки: ${MODELS_DIR}/ → ${COMFYUI_DIR}/models/"

    local COMFY_MODELS="${COMFYUI_DIR}/models"

    for dir in "${MODELS_DIR}"/*/; do
        local name
        name="$(basename "$dir")"
        local target="${COMFY_MODELS}/${name}"

        if [[ -L "$target" ]]; then
            echo "  ✓ $name (симлинк уже есть)"
            continue
        fi

        if [[ -d "$target" ]]; then
            echo "  → $name (мержим файлы)"
            for file in "$dir"*; do
                [[ -f "$file" ]] && ln -sf "$file" "$target/" 2>/dev/null || true
            done
        else
            echo "  → $name (симлинк директории)"
            ln -sf "$dir" "$target"
        fi
    done

    echo "  Симлинки готовы."
}

function provisioning_restart_comfyui() {
    echo "Перезапускаем ComfyUI..."
    pkill -f "main.py.*8188" 2>/dev/null || true
    sleep 2
    cd "${COMFYUI_DIR}"
    nohup python3 main.py --listen 0.0.0.0 --port 8188 > /workspace/comfyui.log 2>&1 &
    echo "ComfyUI запущен на порту 8188 (лог: /workspace/comfyui.log)"
}

function provisioning_get_files() {
    if [[ $# -lt 2 ]]; then return; fi
    local dir="$1"
    shift
    local files=("$@")

    mkdir -p "$dir"
    echo "Скачивание ${#files[@]} file(s) → $dir..."

    for url in "${files[@]}"; do
        local filename
        filename="$(basename "$url")"
        if [[ -f "${dir}/${filename}" ]]; then
            echo "  ✓ $filename (уже есть)"
            continue
        fi
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
