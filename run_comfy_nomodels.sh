#!/bin/bash
set -e

# RunPod ComfyUI — ноды + симлинки (без скачивания моделей)
# Модели уже на Network Volume: /workspace/models/
# Запуск: bash /workspace/run_comfy_nomodels.sh

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

echo "=== ComfyUI RunPod Setup (no-models) ==="

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

function provisioning_start() {
    echo ""
    echo "##############################################"
    echo "#  ноды + симлинки (модели уже на volume)    #"
    echo "#  gazik X-MODE RunPod 2025-2026             #"
    echo "##############################################"
    echo ""

    find_comfyui
    provisioning_get_nodes
    provisioning_fix_onnx_cuda
    provisioning_symlink_models
    provisioning_restart_comfyui

    echo ""
    echo "Готово! Ноды установлены, модели привязаны симлинками."
    echo ""
}

function find_comfyui() {
    if [[ -d "/workspace/runpod-slim/ComfyUI" ]]; then
        COMFYUI_DIR="/workspace/runpod-slim/ComfyUI"
    elif [[ -d "/opt/ComfyUI" ]]; then
        COMFYUI_DIR="/opt/ComfyUI"
    elif [[ -d "/workspace/ComfyUI" ]]; then
        COMFYUI_DIR="/workspace/ComfyUI"
    fi
    echo "ComfyUI dir: ${COMFYUI_DIR}"
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

    SITE_PACKAGES="$(python -c 'import site; print(site.getsitepackages()[0])' 2>/dev/null || echo '/venv/main/lib/python3.12/site-packages')"
    NVIDIA_BASE="${SITE_PACKAGES}/nvidia"

    if [[ -d "$NVIDIA_BASE" ]]; then
        for libdir in "$NVIDIA_BASE"/*/lib; do
            if [[ -d "$libdir" ]]; then
                for lib in "$libdir"/*.so*; do
                    [[ -f "$lib" ]] && ln -sf "$lib" /usr/lib/ 2>/dev/null || true
                done
            fi
        done
        ldconfig 2>/dev/null || true
    fi

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

function provisioning_symlink_models() {
    echo "Создаём симлинки моделей: /workspace/models/ → ComfyUI/models/"

    local VOLUME_MODELS="/workspace/models"
    local COMFY_MODELS="${COMFYUI_DIR}/models"

    if [[ ! -d "$VOLUME_MODELS" ]]; then
        echo "  ОШИБКА: $VOLUME_MODELS не найден! Модели не скачаны на volume."
        return 1
    fi

    for dir in "$VOLUME_MODELS"/*/; do
        local name
        name="$(basename "$dir")"
        local target="${COMFY_MODELS}/${name}"

        # Если уже симлинк — пропускаем
        if [[ -L "$target" ]]; then
            echo "  ✓ $name (симлинк уже есть)"
            continue
        fi

        # Если папка существует — мержим содержимое симлинками
        if [[ -d "$target" ]]; then
            echo "  → $name (мержим файлы)"
            for file in "$dir"*; do
                [[ -f "$file" ]] && ln -sf "$file" "$target/" 2>/dev/null || true
            done
        else
            # Папки нет — делаем симлинк на всю директорию
            echo "  → $name (симлинк директории)"
            ln -sf "$dir" "$target"
        fi
    done

    echo "  Готово! Симлинки созданы."
    echo "  Проверка:"
    du -sh "$VOLUME_MODELS"
    ls -la "$COMFY_MODELS"/
}

function provisioning_restart_comfyui() {
    echo "Перезапускаем ComfyUI..."
    pkill -f "main.py.*8188" 2>/dev/null || true
    sleep 2
    cd "${COMFYUI_DIR}"
    nohup python main.py --listen 0.0.0.0 --port 8188 > /workspace/comfyui.log 2>&1 &
    echo "ComfyUI запущен на порту 8188 (лог: /workspace/comfyui.log)"
}

provisioning_start
