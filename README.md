# vLLM Scripts for Consumer GPUs

## Hardware Configuration
- **GPU 0**: NVIDIA RTX 3090 (24GB VRAM)
- **GPU 1**: NVIDIA RTX 3090 (24GB VRAM)
- **GPU 2**: NVIDIA RTX 3080 (10GB VRAM)
- **Total**: 58GB VRAM

## Requirements
- `hf` CLI (Hugging Face CLI) - for model downloads
- `vllm` - installed via setup script

---

## Available Models

| Script | Model | Use Case | GPU | Port |
|--------|-------|----------|-----|------|
| `01-chat-qwen3-30b.sh` | Qwen3-30B-A3B | Chat/General | RTX 3090 | 8001 |
| `02-code-coder.sh` | Qwen3-30B-A3B | Code generation | RTX 3090 | 8002 |
| `03-completion-mistral.sh` | Mistral-7B | Text completion | RTX 3080 | 8003 |
| `04-multi-gpu-chat.sh` | Qwen3-30B-A3B | Multi-GPU chat | 2x RTX 3090 | 8010 |
| `05-agent-qwen3.sh` | Qwen3-30B-A3B | Agent/Tool use | RTX 3090 | 8004 |
| `06-run-all.sh` | All above | Run everything | All GPUs | varies |

---

## Manual Model Download

To download models manually using `hf`:

```bash
# Download Qwen3-30B-A3B (recommended for chat/code)
hf download Qwen/Qwen3-30B-A3B-Instruct-2507 --local-dir ./models/Qwen3-30B-A3B-Instruct-2507

# Download Mistral-7B (fast completion)
hf download mistralai/Mistral-7B-Instruct-v0.3 --local-dir ./models/Mistral-7B-Instruct-v0.3
```

---

## Quick Start

```bash
# 1. Setup (install vLLM and dependencies)
./scripts/00-setup.sh

# 2. Run individual models
./scripts/01-chat-qwen3-30b.sh      # Chat on GPU 0
./scripts/02-code-coder.sh          # Code on GPU 1
./scripts/03-completion-mistral.sh  # Completion on GPU 2

# 3. Or run all at once
./scripts/06-run-all.sh

# 4. Stop all servers
./scripts/99-stop-all.sh
```

---

## GPU Optimization Notes

### RTX 3090 (Ampere)
- **No FP8 hardware support** - use AWQ/GPTQ 4-bit quantization
- `--quantization awq_marlin` for optimal performance
- `--gpu-memory-utilization 0.90` leaves headroom for KV cache

### RTX 3080 (Ampere)
- 10GB VRAM - suitable for 7B models
- Use FP16 for best quality
- Reduce `--max-num-seqs` if OOM

### Multi-GPU (Tensor Parallel)
- Use `--tensor-parallel-size 2` across 2x RTX 3090
- Enables larger context windows (65K+)
- Requires NVLink for best performance

---

## Environment Variables

Override defaults by setting environment variables:

```bash
# Custom model
MODEL=Qwen/Qwen3-14B ./scripts/01-chat-qwen3-30b.sh

# Custom port
PORT=9000 ./scripts/01-chat-qwen3-30b.sh

# Custom memory utilization
GPU_MEMORY_UTIL=0.85 ./scripts/01-chat-qwen3-30b.sh
```

---

## API Usage

Once running, use the OpenAI-compatible API:

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8001/v1",
    api_key="not-needed"
)

response = client.chat.completions.create(
    model="chat",
    messages=[{"role": "user", "content": "Hello!"}]
)
print(response.choices[0].message.content)
```

---

## Logs

Logs are stored in `./logs/`:
- `chat.log` - Chat model logs
- `code.log` - Code model logs
- `completion.log` - Completion model logs

---

## Troubleshooting

**OOM Error**: Reduce `--max-num-seqs` or `--max-model-len`

**Slow inference**: Check GPU utilization with `nvidia-smi`

**Port in use**: Change `PORT` environment variable
