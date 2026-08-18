#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${BASE_DIR}/logs"
VENV_DIR="${BASE_DIR}/.venv"

if [ ! -d "${VENV_DIR}" ]; then
    echo "ERROR: Virtual environment not found. Run ./scripts/00-setup.sh first."
    exit 1
fi
source "${VENV_DIR}/bin/activate"

MODEL="${MODEL:-Qwen/Qwen3-30B-A3B-Instruct-2507}"
PORT="${PORT:-8002}"
HOST="${HOST:-0.0.0.0}"
GPU_MEMORY_UTIL="${GPU_MEMORY_UTIL:-0.90}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-32768}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-16}"
QUANTIZATION="${QUANTIZATION:-awq_marlin}"

echo "Code Model: Qwen3-30B-A3B on RTX 3090"
echo "Port: ${PORT} | Context: ${MAX_MODEL_LEN} | Quant: ${QUANTIZATION}"
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
    --served-model-name "code" \
    2>&1 | tee "${LOG_DIR}/code.log"
