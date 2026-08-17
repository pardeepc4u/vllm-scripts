#!/bin/bash
# ============================================================================
# Agent Model: Qwen3-30B-A3B with tool calling enabled
# Optimized for agentic workflows with function calling
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${BASE_DIR}/logs"

MODEL="${MODEL:-Qwen/Qwen3-30B-A3B-Instruct-2507}"
PORT="${PORT:-8004}"
HOST="${HOST:-0.0.0.0}"

GPU_MEMORY_UTIL="${GPU_MEMORY_UTIL:-0.90}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-32768}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-16}"
QUANTIZATION="${QUANTIZATION:-awq_marlin}"

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
    echo "  Agent Model: Qwen3-30B-A3B"
    echo "  With tool calling support"
    echo "=========================================="
    echo ""
    
    detect_gpu
    echo ""
    echo "Starting vLLM server..."
    echo "  Model: ${MODEL}"
    echo "  Port: ${PORT}"
    echo "  Tool calling: enabled"
    echo ""
    
    mkdir -p "${LOG_DIR}"
    
    vllm serve "${MODEL}" \
        --host "${HOST}" \
        --port "${PORT}" \
        --quantization "${QUANTIZATION}" \
        --gpu-memory-utilization "${GPU_MEMORY_UTIL}" \
        --max-model-len "${MAX_MODEL_LEN}" \
        --max-num-seqs "${MAX_NUM_SEQS}" \
        --dtype auto \
        --trust-remote-code \
        --served-model-name "agent" \
        --enable-auto-tool-choice \
        --tool-call-parser hermes \
        2>&1 | tee "${LOG_DIR}/agent.log"
}

main "$@"
