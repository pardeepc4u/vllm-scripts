#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${BASE_DIR}/logs"
MODEL_DIR="${BASE_DIR}/models"
VENV_DIR="${BASE_DIR}/.venv"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

setup_venv() {
    if [ -d "${VENV_DIR}" ]; then
        log_warn "Virtual environment exists at ${VENV_DIR}"
        read -p "Recreate? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "${VENV_DIR}"
        else
            return
        fi
    fi
    
    log_info "Creating virtual environment..."
    python3 -m venv "${VENV_DIR}"
    source "${VENV_DIR}/bin/activate"
    pip install --upgrade pip
    log_success "Virtual environment created at ${VENV_DIR}"
}

install_vllm() {
    source "${VENV_DIR}/bin/activate"
    
    if python3 -c "import vllm" 2>/dev/null; then
        VLLM_VERSION=$(python3 -c "import vllm; print(vllm.__version__)" 2>/dev/null || echo "unknown")
        log_warn "vLLM $VLLM_VERSION already installed"
        read -p "Reinstall? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return
        fi
    fi
    
    log_info "Installing vLLM..."
    pip install vllm --upgrade
    
    if python3 -c "import vllm; print(f'vLLM {vllm.__version__} installed')" 2>/dev/null; then
        log_success "vLLM installed successfully"
    else
        log_error "vLLM installation failed"
        exit 1
    fi
}

check_hf() {
    if ! command -v hf &> /dev/null; then
        log_error "hf CLI not found. Install it first."
        exit 1
    fi
    log_success "hf CLI found"
}

setup_dirs() {
    mkdir -p "$LOG_DIR" "$MODEL_DIR" "${BASE_DIR}/configs"
    log_success "Directories created"
}

download_model() {
    local model_id=$1
    local model_name=$(basename "$model_id")
    
    if [ -d "${MODEL_DIR}/${model_name}" ]; then
        log_warn "Model ${model_name} already exists"
        read -p "Skip download? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            return
        fi
    fi
    
    log_info "Downloading ${model_id}..."
    hf download "$model_id" --local-dir "${MODEL_DIR}/${model_name}"
    log_success "Downloaded ${model_name}"
}

download_models() {
    log_info "Model download options:"
    echo "1. Qwen3-30B-A3B (Best for chat, ~18GB at 4-bit) - RECOMMENDED"
    echo "2. Qwen3-14B (Good balance, ~13GB at 4-bit)"
    echo "3. Qwen3-8B (Fast, ~16GB FP16)"
    echo "4. CodeLlama-34B (Code focused, ~20GB at INT4)"
    echo "5. Mistral-7B (Fast completion, ~15GB FP16)"
    echo "6. Skip downloads"
    echo ""
    read -p "Select models (comma-separated or 'all'): " selection
    
    case $selection in
        1|all) download_model "Qwen/Qwen3-30B-A3B-Instruct-2507" ;;
    esac
    case $selection in
        2|all) download_model "Qwen/Qwen3-14B" ;;
    esac
    case $selection in
        3|all) download_model "Qwen/Qwen3-8B" ;;
    esac
    case $selection in
        4|all) download_model "TheBloke/CodeLlama-34B-GPTQ" ;;
    esac
    case $selection in
        5|all) download_model "mistralai/Mistral-7B-Instruct-v0.3" ;;
    esac
}

main() {
    echo ""
    log_info "=========================================="
    log_info "  vLLM Setup for Consumer GPUs"
    log_info "  Hardware: 2x RTX 3090 + 1x RTX 3080"
    log_info "=========================================="
    echo ""
    
    if ! command -v nvidia-smi &> /dev/null; then
        log_error "nvidia-smi not found. Install NVIDIA drivers first."
        exit 1
    fi
    
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
    echo ""
    
    check_hf
    setup_venv
    install_vllm
    setup_dirs
    
    echo ""
    read -p "Download recommended models? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        download_models
    fi
    
    echo ""
    log_success "Setup complete!"
    echo ""
    echo "Activate venv:  source .venv/bin/activate"
    echo "Run chat:       ./scripts/01-chat-qwen3-30b.sh"
    echo "Run code:       ./scripts/02-code-coder.sh"
    echo "Run all:        ./scripts/06-run-all.sh"
    echo ""
}

main "$@"
