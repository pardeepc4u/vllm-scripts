# vLLM Systemd Services

Systemd service files for running multiple vLLM inference servers on consumer GPUs.

## Hardware Configuration

- **GPU 0**: NVIDIA RTX 3090 (24GB VRAM)
- **GPU 1**: NVIDIA RTX 3090 (24GB VRAM)
- **GPU 2**: NVIDIA RTX 3080 (10GB VRAM)

## Available Services

| Service | Model | GPU | Port | Use Case |
|---------|-------|-----|------|----------|
| `vllm-chat-agent` | Qwen 3.5 27B Dense | GPU 0 (3090) | 8001 | Chat + Agent/Tool use |
| `vllm@code` | Qwen 3.5 27B Dense | GPU 1 (3090) | 8002 | Code generation |
| `vllm@completion` | Mistral-7B | GPU 2 (3080) | 8003 | Text completion |

## Quick Start

### 1. Initial Setup (as root)

```bash
sudo ./scripts/setup-services.sh
```

This will:
- Create `vllm` user with GPU access
- Install systemd service template
- Copy environment files to `/opt/vllm/configs/`

### 2. Install and Start Services

```bash
# Install all services
sudo ./scripts/manage-services.sh install all

# Start specific service
sudo ./scripts/manage-services.sh start chat

# Start all services
sudo ./scripts/manage-services.sh start all

# Check status
sudo ./scripts/manage-services.sh status
```

### 3. Enable Auto-start on Boot

```bash
sudo ./scripts/manage-services.sh enable all
```

## Service Management

```bash
# Start/stop/restart
sudo systemctl start vllm@chat
sudo systemctl stop vllm@code
sudo systemctl restart vllm@multi-gpu

# Enable/disable on boot
sudo systemctl enable vllm@chat
sudo systemctl disable vllm@completion

# View status
sudo systemctl status vllm@chat

# View logs
sudo journalctl -u vllm@chat -f
```

## Configuration Files

Environment files are located in `/opt/vllm/configs/`:

- `vllm.env` - Base configuration
- `vllm-chat.env` - Chat model settings
- `vllm-code.env` - Code model settings
- `vllm-completion.env` - Completion model settings
- `vllm-agent.env` - Agent model settings
- `vllm-multi-gpu.env` - Multi-GPU settings

## Customization

### Change Model

Edit the environment file:

```bash
sudo nano /opt/vllm/configs/vllm-chat.env
```

Modify `MODEL_NAME` and other settings, then restart:

```bash
sudo systemctl restart vllm@chat
```

### Add New Model

1. Create environment file:
   ```bash
   sudo cp /opt/vllm/configs/vllm-chat.env /opt/vllm/configs/vllm-myenv.env
   sudo nano /opt/vllm/configs/vllm-myenv.env
   ```

2. Start the service:
   ```bash
   sudo systemctl start vllm@myenv
   ```

## Resource Allocation

### GPU Memory

- **RTX 3090 (24GB)**: Use `GPU_MEMORY_UTILIZATION=0.90`
- **RTX 3080 (10GB)**: Use `GPU_MEMORY_UTILIZATION=0.92`

### CPU Affinity

- **GPU 0/1 services**: `CPUAffinity=0-7`
- **GPU 2 services**: `CPUAffinity=8-15`

## Troubleshooting

### Service Won't Start

```bash
# Check logs
sudo journalctl -u vllm@chat -n 100

# Check GPU access
sudo -u vllm nvidia-smi

# Check environment
sudo -u vllm cat /opt/vllm/configs/vllm-chat.env
```

### OOM Error

Reduce `MAX_NUM_SEQS` or `MAX_MODEL_LEN` in the environment file.

### Port Already in Use

Change `PORT` in the environment file or stop the conflicting service.

## API Access

Once running, access the OpenAI-compatible API:

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8001/v1",
    api_key="not-needed"
)

# Chat (general conversation)
response = client.chat.completions.create(
    model="chat",
    messages=[{"role": "user", "content": "Hello!"}]
)

# Agent (with tool calling)
response = client.chat.completions.create(
    model="agent",
    messages=[{"role": "user", "content": "What's the weather?"}],
    tools=[{
        "type": "function",
        "function": {
            "name": "get_weather",
            "parameters": {"type": "object", "properties": {"location": {"type": "string"}}}
        }
    }]
)
```

## Architecture

```
/opt/vllm/
├── .venv/                  # Python virtual environment
├── configs/                # Environment files
│   ├── vllm.env           # Base config
│   ├── vllm-chat.env      # Chat model
│   ├── vllm-code.env      # Code model
│   ├── vllm-completion.env
│   ├── vllm-agent.env
│   └── vllm-multi-gpu.env
├── logs/                   # Service logs
└── models/                 # Model files
```

## Security Notes

- Services run as `vllm` user (not root)
- GPU access via `video` group
- Filesystem restricted to `/opt/vllm`
- No new privileges allowed
