#!/bin/bash
# ============================================================================
# Stop All vLLM Servers
# ============================================================================
set -euo pipefail

echo "Stopping all vLLM servers..."

pkill -f "vllm serve" || true
pkill -f "vllm.entrypoints" || true

echo "All vLLM servers stopped."
