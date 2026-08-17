#!/bin/bash
# ============================================================================
# Chat Model: Qwen3-30B-A3B on RTX 3090 # Best all-round model for 24GB - MoE with only 3.3B active params
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${BASE_DIR}/logs"

# ============================================================================
# Configuration
# ============================================================================

# Model settings
MODEL="${MODEL:-Qwen/Qwen3-30B-A3B-Instruct-2507}"
PORT="${PORT:-8001}"
HOST="${HOST:-0.0.0.0}"

# GPU settings
# RTX 3090: Ampere - no FP8 hardware, use AWQ/GPTQ 4-bit
GPU_MEMORY_UTIL="${GPU_MEMORY_UTIL:-0.90}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-32768}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-16}"
QUANTIZATION="${QUANTIZATION:-awq_marlin}"

# ============================================================================
# GPU Detection
# ============================================================================
detect_gpu() {
    if ! command -v nvidia-smi &> /dev/null; then
        echo "ERROR: nvidia-smi not found"
        exit 1
    fi
    
    echo "Detected GPUs:"
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
}

# ============================================================================
# Main
# ============================================================================
main() {
    echo "=========================================="
    echo "  Chat Model: Qwen3-30B-A3B"
    echo "  Optimized for RTX 3090 (24GB)"
    echo "=========================================="
    echo ""
    
    detect_gpu
    echo ""
    echo "Starting vLLM server..."
    echo "  Model: ${MODEL}"
    echo "  Port: ${PORT}"
    echo "  Max context: ${MAX_MODEL_LEN}"
    echo "  Max sequences: ${MAX_NUM_SEQS}"
    echo ""
    
    # Create log directory
    mkdir -p "${LOG_DIR}"
    
    # Run vLLM
    # Key flags for RTX 3090 (Ampere):
    # - awq_marlin: 4-bit quantization optimized for Ampere
    # - No FP8 support: Ampere lacks FP8 tensor cores
    # - gpu-memory-utilization 0.90: Leave 10% headroom
    # - max-num-seqs 16: Balance throughput vs memory
    
    vllm serve "${MODEL}" \
        --host "${HOST}" \
        --port "${PORT}" \
        --quantization "${QUANTIZATION}" \
        --gpu-memory-utilization "${GPU_MEMORY_UTIL}" \
        --max-model-len "${MAX_MODEL_LEN}" \
        --max-num-seqs "${MAX_NUM_SEQS}" \
        --dtype auto \
        --trust-remote-code \
        --served-model-name "chat" \
        2>&1 | tee "${LOG_DIR}/chat.log"
}

main "$@"
