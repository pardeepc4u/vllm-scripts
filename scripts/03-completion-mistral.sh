#!/bin/bash
# ============================================================================
# Completion Model: Mistral-7B on RTX 3090
# Fast text completion with low latency
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${BASE_DIR}/logs"

MODEL="${MODEL:-mistralai/Mistral-7B-Instruct-v0.3}"
PORT="${PORT:-8003}"
HOST="${HOST:-0.0.0.0}"

GPU_MEMORY_UTIL="${GPU_MEMORY_UTIL:-0.92}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-16384}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-32}"

detect_gpu() {
    if ! command -v nvidia-smi &> /dev/null; then
        echo "ERROR: nvidia-smi not found"
        exit 1
    fi
    echo "Detected GPUs:"
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
}

main() {
    echo "=========================================="
    echo "  Completion Model: Mistral-7B"
    echo "  Fast text completion"
    echo "=========================================="
    echo ""
    
    detect_gpu
    echo ""
    echo "Starting vLLM server..."
    echo "  Model: ${MODEL}"
    echo "  Port: ${PORT}"
    echo ""
    
    mkdir -p "${LOG_DIR}"
    
    # Mistral 7B runs well in FP16 on RTX 3090 (14.8GB)
    # Higher max-num-seqs for batch throughput
    vllm serve "${MODEL}" \
        --host "${HOST}" \
        --port "${PORT}" \
        --gpu-memory-utilization "${GPU_MEMORY_UTIL}" \
        --max-model-len "${MAX_MODEL_LEN}" \
        --max-num-seqs "${MAX_NUM_SEQS}" \
        --dtype auto \
        --trust-remote-code \
        --served-model-name "completion" \
        2>&1 | tee "${LOG_DIR}/completion.log"
}

main "$@"
