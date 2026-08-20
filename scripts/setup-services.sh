#!/bin/bash
# ============================================================================
# vLLM Service Setup
# Creates vllm user, installs services, and configures the system
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="${BASE_DIR}/configs"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

create_vllm_user() {
    log_info "Creating vllm user..."
    
    if id "vllm" &>/dev/null; then
        log_warn "User 'vllm' already exists"
    else
        useradd -r -s /bin/false -d /opt/vllm -m vllm
        log_success "Created user 'vllm'"
    fi
    
    # Add to video group for GPU access
    usermod -aG video vllm
    log_success "Added vllm to video group"
}

setup_directories() {
    log_info "Setting up directories..."
    
    mkdir -p /opt/vllm/{configs,logs,models,.venv}
    chown -R vllm:vllm /opt/vllm
    chmod -R 755 /opt/vllm
    
    log_success "Directory structure created"
}

install_systemd_services() {
    log_info "Installing systemd services..."
    
    # Install template service
    if [ -f "${CONFIG_DIR}/vllm@.service" ]; then
        cp "${CONFIG_DIR}/vllm@.service" /etc/systemd/system/
        chmod 644 /etc/systemd/system/vllm@.service
        log_success "Installed template service: vllm@.service"
    else
        log_error "Template service not found: ${CONFIG_DIR}/vllm@.service"
        exit 1
    fi
    
    systemctl daemon-reload
    log_success "Systemd daemon reloaded"
}

install_environment_files() {
    log_info "Installing environment files..."
    
    # Copy base environment
    if [ -f "${CONFIG_DIR}/vllm.env" ]; then
        cp "${CONFIG_DIR}/vllm.env" /opt/vllm/configs/
        log_success "Installed base environment: vllm.env"
    fi
    
    # Copy model-specific environments
    for env_file in "${CONFIG_DIR}"/vllm-*.env; do
        if [ -f "$env_file" ]; then
            filename=$(basename "$env_file")
            cp "$env_file" /opt/vllm/configs/
            log_success "Installed environment: $filename"
        fi
    done
    
    chown -R vllm:vllm /opt/vllm/configs
}

verify_installation() {
    log_info "Verifying installation..."
    
    echo ""
    echo "Directory structure:"
    tree /opt/vllm -L 2 2>/dev/null || find /opt/vllm -type f | head -20
    
    echo ""
    echo "Systemd services:"
    systemctl list-unit-files | grep vllm || echo "No vLLM services found"
    
    echo ""
    echo "vLLM user:"
    id vllm
    
    echo ""
    log_success "Installation complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Install vLLM in the virtual environment:"
    echo "     sudo -u vllm bash -c 'source /opt/vllm/.venv/bin/activate && pip install vllm'"
    echo ""
    echo "  2. Download models:"
    echo "     sudo -u vllm bash -c 'source /opt/vllm/.venv/bin/activate && hf download Qwen/Qwen3-30B-A3B-Instruct-2507 --local-dir /opt/vllm/models/Qwen3-30B-A3B-Instruct-2507'"
    echo ""
    echo "  3. Manage services:"
    echo "     sudo ./scripts/manage-services.sh install all"
    echo "     sudo ./scripts/manage-services.sh start all"
    echo "     sudo ./scripts/manage-services.sh status"
    echo ""
}

main() {
    echo ""
    log_info "=========================================="
    log_info "  vLLM Service Setup"
    log_info "  Hardware: 2x RTX 3090 + 1x RTX 3080"
    log_info "=========================================="
    echo ""
    
    check_root
    create_vllm_user
    setup_directories
    install_systemd_services
    install_environment_files
    verify_installation
}

main "$@"
