#!/bin/bash
# ============================================================================
# Run All Models
# Starts multiple vLLM instances on different GPUs
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${BASE_DIR}/logs"

mkdir -p "${LOG_DIR}"

echo "=========================================="
echo "  Starting All Models"
echo "  Hardware: 2x RTX 3090 + 1x RTX 3080"
echo "=========================================="
echo ""

echo "Starting chat model on GPU 0 (RTX 3090)..."
PORT=8001 MODEL="Qwen/Qwen3-30B-A3B-Instruct-2507" \
    CUDA_VISIBLE_DEVICES=0 \
    bash "${SCRIPT_DIR}/01-chat-qwen3-30b.sh" &
CHAT_PID=$!
echo "Chat PID: ${CHAT_PID}"

sleep 5

echo "Starting code model on GPU 1 (RTX 3090)..."
PORT=8002 MODEL="Qwen/Qwen3-30B-A3B-Instruct-2507" \
    CUDA_VISIBLE_DEVICES=1 \
    bash "${SCRIPT_DIR}/02-code-coder.sh" &
CODE_PID=$!
echo "Code PID: ${CODE_PID}"

sleep 5

echo "Starting completion model on GPU 2 (RTX 3080)..."
PORT=8003 MODEL="mistralai/Mistral-7B-Instruct-v0.3" \
    CUDA_VISIBLE_DEVICES=2 \
    bash "${SCRIPT_DIR}/03-completion-mistral.sh" &
COMP_PID=$!
echo "Completion PID: ${COMP_PID}"

echo ""
echo "All models started!"
echo "  Chat (port 8001): PID ${CHAT_PID}"
echo "  Code (port 8002): PID ${CODE_PID}"
echo "  Completion (port 8003): PID ${COMP_PID}"
echo ""
echo "To stop all: ./scripts/99-stop-all.sh"
echo ""

wait
