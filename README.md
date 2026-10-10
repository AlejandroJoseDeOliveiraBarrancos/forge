# forge

My personal place for continuous AI building and experimentation.

## Deployment: Local LLM Models with Docker

This repository includes a complete Docker-based deployment for running local LLM models via Ollama.

### Quick Start

```bash
# Copy environment templates (optional, for customization)
cp deployment/docker/models/models.env.example deployment/docker/models/models.env
cp deployment/docker/docker-compose.override.yml.example deployment/docker/docker-compose.override.yml

# Pull models before first run (recommended)
make models-pull

# Start qwen2.5-coder:7b
make qwen up

# Start deepseek-r1:8b
make dps up

# View logs
make qwen logs
make dps logs
```

### Services

| Service | Port | Description |
|---------|------|-------------|
| **qwen2.5-coder:7b** | 11434 | Code-specialized LLM (7B params) |
| **deepseek-r1:8b** | 11435 | Reasoning-focused LLM (8B params) |

### Hardware Requirements

- **GPU**: NVIDIA RTX 5060 Ti 8GB VRAM (or similar)
- **RAM**: 32GB+ system RAM
- **Storage**: ~20GB for models (q4_k_m quantization)
- **Docker**: With NVIDIA Container Toolkit installed

### Model Configuration

Models run with **q4_k_m quantization** (4-bit) to fit in 8GB VRAM:
- `OLLAMA_GPU_LAYERS=35` - Offload most layers to GPU
- `OLLAMA_MAX_LOADED_MODELS=1` - Prevent OOM with two 8B models
- `OLLAMA_NUM_PARALLEL=1` - Sequential request processing
- Context window: 4096 tokens (configurable)

### Makefile Commands (run from repository root)

```bash
make help              # Show all available commands

# Global commands
make clean             # Remove stopped containers and networks
make clean-volumes     # Remove all data volumes (DESTRUCTIVE)
make clean-all         # Clean everything including volumes

# qwen2.5-coder:7b (make qwen ...)
make qwen up           # Start qwen2.5-coder:7b
make qwen down         # Stop qwen2.5-coder:7b
make qwen logs         # Follow qwen2.5-coder:7b logs
make qwen shell        # Open shell in qwen container
make qwen ps           # Show qwen container status
make qwen pull         # Pull qwen image

# deepseek-r1:8b (make dps ...)
make dps up            # Start deepseek-r1:8b
make dps down          # Stop deepseek-r1:8b
make dps logs          # Follow deepseek-r1:8b logs
make dps shell         # Open shell in deepseek container
make dps ps            # Show deepseek container status
make dps pull          # Pull deepseek image

# Model operations
make models-pull       # Pre-pull both models (qwen2.5-coder:7b, deepseek-r1:8b)
make models-rm         # Remove pulled models from volumes

# Status & Health
make status            # Show all service status
make health            # Check health of all services + GPU status
make gpu-info          # Show detailed GPU info
```

### Testing Models

```bash
# Test qwen2.5-coder:7b
docker exec -it forge-ollama-qwen ollama run qwen2.5-coder:7b "Write a Python hello world"

# Test deepseek-r1:8b
docker exec -it forge-ollama-deepseek ollama run deepseek-r1:8b "Explain recursion in one paragraph"
```

### API Access

Both models expose the Ollama REST API:

```bash
# qwen2.5-coder:7b
curl http://localhost:11434/api/generate -d '{"model": "qwen2.5-coder:7b", "prompt": "Hello"}'

# deepseek-r1:8b
curl http://localhost:11435/api/generate -d '{"model": "deepseek-r1:8b", "prompt": "Hello"}'
```

### Customization

1. **GPU Settings**: Edit `deployment/docker/docker-compose.override.yml` to adjust `OLLAMA_GPU_LAYERS`
2. **Ports**: Change `OLLAMA_QWEN_PORT` / `OLLAMA_DEEPSEEK_PORT` in `deployment/docker/models/models.env`
3. **Model Versions**: Update `OLLAMA_QWEN_MODEL` / `OLLAMA_DEEPSEEK_MODEL` in `deployment/docker/models/models.env`
4. **Resources**: Add memory/CPU limits in `deployment/docker/docker-compose.override.yml`

### Troubleshooting

- **OOM Errors**: Reduce `OLLAMA_GPU_LAYERS`, use smaller quantization (q3_k_m)
- **Slow Inference**: Increase `OLLAMA_GPU_LAYERS`, enable `OLLAMA_FLASH_ATTENTION`
- **Model Not Found**: Run `make models-pull` or check Ollama logs
- **GPU Not Detected**: Ensure NVIDIA Container Toolkit is installed

See `deployment/docker/docs/` for detailed guides:
- [Deployment Guide](deployment/docker/docs/deployment-guide.md)
- [Model Configuration](deployment/docker/docs/model-config.md)
- [Troubleshooting](deployment/docker/docs/troubleshooting.md)