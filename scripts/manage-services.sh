#!/bin/bash
# ============================================================================
# vLLM Service Manager
# Install, enable, start, stop, and manage vLLM systemd services
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="${BASE_DIR}/configs"
SERVICE_TEMPLATE="${CONFIG_DIR}/vllm@.service"
SYSTEMD_DIR="/etc/systemd/system"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Available model configurations
declare -A MODEL_CONFIGS=(
    ["chat"]="Chat Model: Qwen3-30B-A3B on GPU 0 (RTX 3090) - Port 8001"
    ["code"]="Code Model: Qwen3-30B-A3B on GPU 1 (RTX 3090) - Port 8002"
    ["completion"]="Completion Model: Mistral-7B on GPU 2 (RTX 3080) - Port 8003"
    ["agent"]="Agent Model: Qwen3-30B-A3B on GPU 0 (RTX 3090) - Port 8004"
    ["multi-gpu"]="Multi-GPU Chat: Qwen3-30B-A3B across 2x RTX 3090 - Port 8010"
)

usage() {
    echo ""
    echo -e "${CYAN}vLLM Service Manager${NC}"
    echo ""
    echo "Usage: $0 <command> [config]"
    echo ""
    echo "Commands:"
    echo "  install [config]    Install service(s) to systemd"
    echo "  uninstall [config]  Remove service(s) from systemd"
    echo "  enable [config]     Enable service(s) to start on boot"
    echo "  disable [config]    Disable service(s) from starting on boot"
    echo "  start [config]      Start service(s)"
    echo "  stop [config]       Stop service(s)"
    echo "  restart [config]    Restart service(s)"
    echo "  status [config]     Show status of service(s)"
    echo "  logs [config]       Follow logs of a service"
    echo "  list                List all available configurations"
    echo "  all                 Perform action on all services"
    echo ""
    echo "Configurations: chat, code, completion, agent, multi-gpu"
    echo ""
    echo "Examples:"
    echo "  $0 install chat        # Install chat service"
    echo "  $0 install all         # Install all services"
    echo "  $0 start chat          # Start chat service"
    echo "  $0 stop all            # Stop all services"
    echo "  $0 status              # Show status of all services"
    echo "  $0 logs chat           # Follow chat service logs"
    echo ""
}

list_configs() {
    echo ""
    echo -e "${CYAN}Available Configurations:${NC}"
    echo ""
    for config in "${!MODEL_CONFIGS[@]}"; do
        echo -e "  ${GREEN}${config}${NC} - ${MODEL_CONFIGS[$config]}"
    done
    echo ""
}

get_all_configs() {
    echo "${!MODEL_CONFIGS[@]}" | tr ' ' '\n' | sort
}

validate_config() {
    local config=$1
    if [[ -z "${MODEL_CONFIGS[$config]+x}" ]]; then
        log_error "Unknown configuration: $config"
        echo "Available configurations: $(get_all_configs | tr '\n' ', ')"
        exit 1
    fi
}

install_service() {
    local config=$1
    validate_config "$config"
    
    if [ ! -f "${SERVICE_TEMPLATE}" ]; then
        log_error "Service template not found: ${SERVICE_TEMPLATE}"
        exit 1
    fi
    
    if [ ! -f "${CONFIG_DIR}/vllm-${config}.env" ]; then
        log_error "Environment file not found: ${CONFIG_DIR}/vllm-${config}.env"
        exit 1
    fi
    
    log_info "Installing vllm@${config}.service..."
    cp "${SERVICE_TEMPLATE}" "${SYSTEMD_DIR}/vllm@${config}.service"
    chmod 644 "${SYSTEMD_DIR}/vllm@${config}.service"
    systemctl daemon-reload
    log_success "Installed vllm@${config}.service"
}

uninstall_service() {
    local config=$1
    validate_config "$config"
    
    log_info "Uninstalling vllm@${config}.service..."
    systemctl stop "vllm@${config}.service" 2>/dev/null || true
    systemctl disable "vllm@${config}.service" 2>/dev/null || true
    rm -f "${SYSTEMD_DIR}/vllm@${config}.service"
    systemctl daemon-reload
    log_success "Uninstalled vllm@${config}.service"
}

enable_service() {
    local config=$1
    validate_config "$config"
    
    log_info "Enabling vllm@${config}.service..."
    systemctl enable "vllm@${config}.service"
    log_success "Enabled vllm@${config}.service"
}

disable_service() {
    local config=$1
    validate_config "$config"
    
    log_info "Disabling vllm@${config}.service..."
    systemctl disable "vllm@${config}.service"
    log_success "Disabled vllm@${config}.service"
}

start_service() {
    local config=$1
    validate_config "$config"
    
    log_info "Starting vllm@${config}.service..."
    systemctl start "vllm@${config}.service"
    sleep 2
    
    if systemctl is-active --quiet "vllm@${config}.service"; then
        log_success "Started vllm@${config}.service"
    else
        log_error "Failed to start vllm@${config}.service"
        systemctl status "vllm@${config}.service" --no-pager
        return 1
    fi
}

stop_service() {
    local config=$1
    validate_config "$config"
    
    log_info "Stopping vllm@${config}.service..."
    systemctl stop "vllm@${config}.service"
    log_success "Stopped vllm@${config}.service"
}

restart_service() {
    local config=$1
    validate_config "$config"
    
    log_info "Restarting vllm@${config}.service..."
    systemctl restart "vllm@${config}.service"
    sleep 2
    
    if systemctl is-active --quiet "vllm@${config}.service"; then
        log_success "Restarted vllm@${config}.service"
    else
        log_error "Failed to restart vllm@${config}.service"
        systemctl status "vllm@${config}.service" --no-pager
        return 1
    fi
}

status_service() {
    local config=$1
    validate_config "$config"
    
    echo ""
    echo -e "${CYAN}vllm@${config}.service${NC}"
    systemctl status "vllm@${config}.service" --no-pager || true
    echo ""
}

logs_service() {
    local config=$1
    validate_config "$config"
    
    journalctl -u "vllm@${config}.service" -f --no-pager
}

# Main command handling
COMMAND="${1:-}"
CONFIG="${2:-}"

if [ -z "$COMMAND" ]; then
    usage
    exit 0
fi

case "$COMMAND" in
    install)
        if [ "$CONFIG" = "all" ]; then
            for config in $(get_all_configs); do
                install_service "$config"
            done
        elif [ -n "$CONFIG" ]; then
            install_service "$CONFIG"
        else
            log_error "Please specify a configuration or 'all'"
            exit 1
        fi
        ;;
    
    uninstall)
        if [ "$CONFIG" = "all" ]; then
            for config in $(get_all_configs); do
                uninstall_service "$config"
            done
        elif [ -n "$CONFIG" ]; then
            uninstall_service "$CONFIG"
        else
            log_error "Please specify a configuration or 'all'"
            exit 1
        fi
        ;;
    
    enable)
        if [ "$CONFIG" = "all" ]; then
            for config in $(get_all_configs); do
                enable_service "$config"
            done
        elif [ -n "$CONFIG" ]; then
            enable_service "$CONFIG"
        else
            log_error "Please specify a configuration or 'all'"
            exit 1
        fi
        ;;
    
    disable)
        if [ "$CONFIG" = "all" ]; then
            for config in $(get_all_configs); do
                disable_service "$config"
            done
        elif [ -n "$CONFIG" ]; then
            disable_service "$CONFIG"
        else
            log_error "Please specify a configuration or 'all'"
            exit 1
        fi
        ;;
    
    start)
        if [ "$CONFIG" = "all" ]; then
            for config in $(get_all_configs); do
                start_service "$config"
            done
        elif [ -n "$CONFIG" ]; then
            start_service "$CONFIG"
        else
            log_error "Please specify a configuration or 'all'"
            exit 1
        fi
        ;;
    
    stop)
        if [ "$CONFIG" = "all" ]; then
            for config in $(get_all_configs); do
                stop_service "$config"
            done
        elif [ -n "$CONFIG" ]; then
            stop_service "$CONFIG"
        else
            log_error "Please specify a configuration or 'all'"
            exit 1
        fi
        ;;
    
    restart)
        if [ "$CONFIG" = "all" ]; then
            for config in $(get_all_configs); do
                restart_service "$config"
            done
        elif [ -n "$CONFIG" ]; then
            restart_service "$CONFIG"
        else
            log_error "Please specify a configuration or 'all'"
            exit 1
        fi
        ;;
    
    status)
        if [ -n "$CONFIG" ] && [ "$CONFIG" != "all" ]; then
            status_service "$CONFIG"
        else
            echo ""
            echo -e "${CYAN}All vLLM Services:${NC}"
            echo ""
            for config in $(get_all_configs); do
                if systemctl is-active --quiet "vllm@${config}.service" 2>/dev/null; then
                    echo -e "  ${GREEN}●${NC} vllm@${config}.service - active"
                elif systemctl list-unit-files | grep -q "vllm@${config}.service" 2>/dev/null; then
                    echo -e "  ${YELLOW}○${NC} vllm@${config}.service - inactive"
                else
                    echo -e "  ${RED}○${NC} vllm@${config}.service - not installed"
                fi
            done
            echo ""
        fi
        ;;
    
    logs)
        if [ -z "$CONFIG" ]; then
            log_error "Please specify a configuration"
            exit 1
        fi
        logs_service "$CONFIG"
        ;;
    
    list)
        list_configs
        ;;
    
    *)
        log_error "Unknown command: $COMMAND"
        usage
        exit 1
        ;;
esac
