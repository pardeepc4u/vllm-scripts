#!/bin/bash
# ============================================================================
# vLLM Setup Script
# Hardware: 2x RTX 3090 (24GB) + 1x RTX 3080 (10GB) = 58GB VRAM total
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${BASE_DIR}/logs"
MODEL_DIR="${BASE_DIR}/models"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================================
# IMPORTANT: Big models CANNOT run on consumer GPUs
# ============================================================================
echo -e "${RED}"
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║                    ⚠️  IMPORTANT NOTICE                               ║"
echo "║                                                                       ║"
echo "║  Your hardware: 2x RTX 3090 + 1x RTX 3080 = 58GB VRAM                 ║"
echo "║                                                                       ║"
echo "║  This script will set up ALTERNATIVE models that work on your GPUs:   ║"
echo "║  - Qwen3-30B-A3B (Best for chat)                                      ║"
echo "║  - Qwen3-Coder (Best for code)                                        ║"
echo "║  - CodeLlama-34B (Alternative code)                                   ║"
echo "║  - Mistral-7B (Fast completion)                                       ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================================================
# Check System Requirements
# ============================================================================
check_system() {
    log_info "Checking system requirements..."
    
    # Check for NVIDIA GPUs
    if ! command -v nvidia-smi &> /dev/null; then
        log_error "nvidia-smi not found. Install NVIDIA drivers first."
        exit 1
    fi
    
    # Display GPU info
    log_info "Detected GPUs:"
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
    
    # Check CUDA version
    CUDA_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
    log_info "NVIDIA Driver: $CUDA_VERSION"
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 not found."
        exit 1
    fi
    
    PYTHON_VERSION=$(python3 --version)
    log_info "Python: $PYTHON_VERSION"
    
    # Check pip
    if ! command -v pip3 &> /dev/null; then
        log_error "pip3 not found."
        exit 1
    fi
    
    log_success "System check passed"
}

# ============================================================================
# Install vLLM
# ============================================================================
install_vllm() {
    log_info "Installing vLLM..."
    
    # Check if vllm is already installed
    if python3 -c "import vllm" 2>/dev/null; then
        VLLM_VERSION=$(python3 -c "import vllm; print(vllm.__version__)" 2>/dev/null || echo "unknown")
        log_warn "vLLM $VLLM_VERSION already installed"
        read -p "Reinstall? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return
        fi
    fi
    
    # Install vLLM
    pip3 install vllm --upgrade
    
    # Verify installation
    if python3 -c "import vllm; print(f'vLLM {vllm.__version__} installed')" 2>/dev/null; then
        log_success "vLLM installed successfully"
    else
        log_error "vLLM installation failed"
        exit 1
    fi
}

install_deps() {
    log_info "Checking dependencies..."
    
    if ! command -v hf &> /dev/null; then
        log_error "hf CLI not found. Install it first."
        exit 1
    fi
    
    log_success "hf CLI found"
}

# ============================================================================
# Create Model Directory
# ============================================================================
setup_dirs() {
    log_info "Setting up directories..."
    
    mkdir -p "$LOG_DIR"
    mkdir -p "$MODEL_DIR"
    mkdir -p "${BASE_DIR}/configs"
    
    log_success "Directories created"
}

# ============================================================================
# Download Helper
# ============================================================================
download_model() {
    local model_id=$1
    local model_name=$(basename "$model_id")
    
    if [ -d "${MODEL_DIR}/${model_name}" ]; then
        log_warn "Model ${model_name} already exists at ${MODEL_DIR}/${model_name}"
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

# ============================================================================
# Pre-download Recommended Models
# ============================================================================
download_models() {
    log_info "Model download options:"
    echo "1. Qwen3-30B-A3B (Best for chat, ~18GB at 4-bit) - RECOMMENDED"
    echo "2. Qwen3-14B (Good balance, ~13GB at 4-bit)"
    echo "3. Qwen3-8B (Fast, ~16GB FP16)"
    echo "4. CodeLlama-34B (Code focused, ~20GB at INT4)"
    echo "5. Mistral-7B (Fast completion, ~15GB FP16)"
    echo "6. Skip downloads"
    echo ""
    read -p "Select models to download (comma-separated numbers, or 'all'): " selection
    
    case $selection in
        1|all)
            download_model "Qwen/Qwen3-30B-A3B-Instruct-2507"
            ;;
    esac
    
    case $selection in
        2|all)
            download_model "Qwen/Qwen3-14B"
            ;;
    esac
    
    case $selection in
        3|all)
            download_model "Qwen/Qwen3-8B"
            ;;
    esac
    
    case $selection in
        4|all)
            download_model "TheBloke/CodeLlama-34B-GPTQ"
            ;;
    esac
    
    case $selection in
        5|all)
            download_model "mistralai/Mistral-7B-Instruct-v0.3"
            ;;
    esac
}

# ============================================================================
# Main
# ============================================================================
main() {
    echo ""
    log_info "=========================================="
    log_info "  vLLM Setup for Consumer GPUs"
    log_info "  Hardware: 2x RTX 3090 + 1x RTX 3080"
    log_info "=========================================="
    echo ""
    
    check_system
    install_deps
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
    echo "Next steps:"
    echo "  1. Run chat model:     ./scripts/01-chat-qwen3-30b.sh"
    echo "  2. Run code model:     ./scripts/02-code-coder.sh"
    echo "  3. Run completion:     ./scripts/03-completion-mistral.sh"
    echo "  4. Run all models:     ./scripts/04-run-all.sh"
    echo ""
}

main "$@"
