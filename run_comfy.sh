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

function patch_ws_timeout() {
    local WS_TIMEOUT_NEW=1200  # 20 минут вместо 60 сек
    local PATCHED=0

    echo "[WS-PATCH] Searching for generation_worker.py..."

    # Ищем generation_worker.py в стандартных путях Docker-образа vastai/comfy
    local GW=""
    for search_dir in /workspace/vast-pyworker /workspace /opt /venv; do
        if [[ -d "$search_dir" ]]; then
            GW=$(find "$search_dir" -name "generation_worker.py" -path "*/workers/*" 2>/dev/null | head -1)
            [[ -n "$GW" ]] && break
        fi
    done

    if [[ -n "$GW" ]]; then
        echo "[WS-PATCH] Found: $GW"

        # Показываем текущие timeout-значения для отладки
        echo "[WS-PATCH] Current timeout values:"
        grep -n -i "timeout.*60\|60.*timeout\|= *60" "$GW" 2>/dev/null | head -10 || true

        # Патчим: timeout = 60.0 → 600.0, и любые другие 60.0 рядом со словом timeout
        if grep -q "60\.0" "$GW" 2>/dev/null; then
            sed -i -E 's/(timeout[^=]*=\s*)60\.0/\1'"$WS_TIMEOUT_NEW"'.0/gi' "$GW"
            sed -i -E 's/60\.0(\s*seconds)/'"$WS_TIMEOUT_NEW"'.0\1/g' "$GW"
            # Фолбэк: если есть просто 60.0 как значение по умолчанию
            sed -i -E "s/,\s*60\.0\s*\)/, ${WS_TIMEOUT_NEW}.0)/g" "$GW"
            PATCHED=1
            echo "[WS-PATCH] Patched timeout: 60.0 → ${WS_TIMEOUT_NEW}.0"
            echo "[WS-PATCH] Updated timeout values:"
            grep -n -i "timeout\|${WS_TIMEOUT_NEW}" "$GW" 2>/dev/null | head -10 || true
        else
            echo "[WS-PATCH] No 60.0 timeout found — may already be patched or different format"
            grep -n -i "timeout" "$GW" 2>/dev/null | head -10 || true
        fi
    else
        echo "[WS-PATCH] generation_worker.py not found in Docker image"
        echo "[WS-PATCH] Will try to find and patch at runtime via background task"
    fi

    # Экспортируем env var — на случай если generation_worker читает из окружения
    export WS_MESSAGE_TIMEOUT=${WS_TIMEOUT_NEW}
    export COMFY_WS_TIMEOUT=${WS_TIMEOUT_NEW}
    export GENERATION_TIMEOUT=${WS_TIMEOUT_NEW}

    # Пишем в /etc/environment чтобы start_server.sh подхватил
    echo "WS_MESSAGE_TIMEOUT=${WS_TIMEOUT_NEW}" >> /etc/environment 2>/dev/null || true
    echo "COMFY_WS_TIMEOUT=${WS_TIMEOUT_NEW}" >> /etc/environment 2>/dev/null || true
    echo "GENERATION_TIMEOUT=${WS_TIMEOUT_NEW}" >> /etc/environment 2>/dev/null || true

    echo "[WS-PATCH] Environment variables set: WS_MESSAGE_TIMEOUT=${WS_TIMEOUT_NEW}"

    # Если файл не найден — запускаем фоновый патчер на случай если он появится позже
    if [[ $PATCHED -eq 0 ]]; then
        local _timeout_val=$WS_TIMEOUT_NEW
        (
            BG_MAX_WAIT=180
            BG_INTERVAL=5
            BG_ELAPSED=0
            BG_GW=""

            while [[ $BG_ELAPSED -lt $BG_MAX_WAIT ]]; do
                sleep $BG_INTERVAL
                BG_ELAPSED=$((BG_ELAPSED + BG_INTERVAL))

                BG_GW=$(find /workspace /opt /venv /tmp -name "generation_worker.py" -path "*/workers/*" 2>/dev/null | head -1)
                if [[ -n "$BG_GW" ]]; then
                    echo "[WS-PATCH-BG] Found generation_worker at: $BG_GW"
                    if grep -q "60\.0" "$BG_GW" 2>/dev/null; then
                        sed -i -E "s/(timeout[^=]*=\s*)60\.0/\1${_timeout_val}.0/gi" "$BG_GW"
                        sed -i -E "s/60\.0(\s*seconds)/${_timeout_val}.0\1/g" "$BG_GW"
                        sed -i -E "s/,\s*60\.0\s*\)/, ${_timeout_val}.0)/g" "$BG_GW"
                        echo "[WS-PATCH-BG] Patched timeout: 60.0 → ${_timeout_val}.0"
                    else
                        echo "[WS-PATCH-BG] No 60.0 timeout found"
                    fi
                    break
                fi
            done

            if [[ -z "$BG_GW" ]]; then
                echo "[WS-PATCH-BG] WARNING: generation_worker.py not found after ${BG_MAX_WAIT}s"
            fi
        ) &
        disown
    fi
}

function provisioning_start() {
    echo ""
    echo "##############################################"
    echo "# ебашим жоска и мрачно                      #"
    echo "# gazik X-MODE setup 2025-2026               #"
    echo "# бабки бабки                                #"
    echo "##############################################"
    echo ""

    # ── FIX: WebSocket message timeout для generation_worker ──
    # WanVideo 14B загружает 1427 параметров в VRAM без WebSocket-сообщений
    # По умолчанию generation_worker ждёт 60 сек → timeout → job killed
    # Патчим до старта pyworker (start_server.sh пропускает clone если $SERVER_DIR существует)
    patch_ws_timeout

    provisioning_get_apt_packages
    provisioning_clone_comfyui
    provisioning_install_base_reqs
    provisioning_get_nodes
    provisioning_get_pip_packages
    # ── FIX: onnxruntime CUDA — установка ВСЕХ необходимых библиотек ──
    # onnxruntime-gpu тянет libcublas, libcufft, libcurand, libcusolver, libcusparse, libcudnn
    # Без них → fallback на CPU → pose detection 1.5 it/s вместо 100+ it/s
    pip install --no-cache-dir \
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

    # Собираем все пути из pip-пакетов nvidia и прокидываем в /usr/lib + LD_LIBRARY_PATH
    echo "Fixing CUDA libs for onnxruntime-gpu..."
    SITE_PACKAGES="$(python -c 'import site; print(site.getsitepackages()[0])' 2>/dev/null || echo '/venv/main/lib/python3.12/site-packages')"
    NVIDIA_BASE="${SITE_PACKAGES}/nvidia"

    if [[ -d "$NVIDIA_BASE" ]]; then
        CUDA_LIB_PATHS=""
        # Находим ВСЕ lib/ директории внутри nvidia пакетов
        for libdir in "$NVIDIA_BASE"/*/lib; do
            if [[ -d "$libdir" ]]; then
                CUDA_LIB_PATHS="${CUDA_LIB_PATHS:+${CUDA_LIB_PATHS}:}${libdir}"
                # Симлинки всех .so в /usr/lib
                for lib in "$libdir"/*.so*; do
                    if [[ -f "$lib" ]]; then
                        ln -sf "$lib" /usr/lib/ 2>/dev/null || true
                    fi
                done
            fi
        done
        ldconfig 2>/dev/null || true
        export LD_LIBRARY_PATH="${CUDA_LIB_PATHS}:${LD_LIBRARY_PATH:-}"
        echo "  CUDA libs symlinked from: ${CUDA_LIB_PATHS}"
    fi

    # Также проверяем системные CUDA пути (vast.ai часто ставит в /usr/local/cuda)
    if [[ -d "/usr/local/cuda/lib64" ]]; then
        export LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"
        echo "  Added /usr/local/cuda/lib64 to LD_LIBRARY_PATH"
    fi

    # Проверка
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
