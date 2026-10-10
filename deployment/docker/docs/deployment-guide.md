# Deployment Guide

Complete guide for deploying and operating local LLM models with the Forge Docker deployment.

## Prerequisites

### System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| GPU | NVIDIA 8GB VRAM | NVIDIA 12GB+ VRAM |
| RAM | 16GB | 32GB+ |
| Storage | 20GB free | 50GB+ free |
| OS | Linux (Ubuntu 22.04+) | Linux (Ubuntu 24.04) |

### Software Requirements

1. **Docker Engine** 24.0+
2. **Docker Compose** v2.20+ (plugin)
3. **NVIDIA Container Toolkit** (for GPU support)

```bash
# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker

# Install NVIDIA Container Toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt update && sudo apt install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Verify GPU access
docker run --rm --gpus all nvidia/cuda:12.4-base nvidia-smi
```

## Quick Deployment

All Makefile commands are run from the **repository root** (`/home/usuario/personal/forge`).

### 1. Configure Environment (Optional)

```bash
# Copy templates
cp deployment/docker/models/models.env.example deployment/docker/models/models.env
cp deployment/docker/docker-compose.override.yml.example deployment/docker/docker-compose.override.yml

# Edit as needed
vim deployment/docker/models/models.env
vim deployment/docker/docker-compose.override.yml
```

### 2. Pull Models (Recommended Before First Start)

```bash
make models-pull
```

This downloads ~10GB of model weights. Takes 5-15 minutes depending on connection.

### 3. Start Services

```bash
# Start qwen2.5-coder:7b
make qwen up

# Start deepseek-r1:8b
make dps up
```

### 4. Verify Deployment

```bash
# Check container status
make qwen ps
make dps ps

# Check health
make health

# Test models
docker exec -it forge-ollama-qwen ollama run qwen2.5-coder:7b "Hello"
docker exec -it forge-ollama-deepseek ollama run deepseek-r1:8b "Hello"
```

## Service Management

### Viewing Logs

```bash
# qwen2.5-coder:7b
make qwen logs

# deepseek-r1:8b
make dps logs
```

### Accessing Shells

```bash
# qwen2.5-coder:7b
make qwen shell

# deepseek-r1:8b
make dps shell
```

### Stopping Services

```bash
# Stop qwen2.5-coder:7b
make qwen down

# Stop deepseek-r1:8b
make dps down
```

## Configuration

### Model Selection

Edit `deployment/docker/models/models.env`:

```bash
# Change model variants
OLLAMA_QWEN_MODEL=qwen2.5-coder:7b      # or qwen2.5-coder:14b, qwen2.5-coder:32b
OLLAMA_DEEPSEEK_MODEL=deepseek-r1:8b    # or deepseek-r1:14b, deepseek-r1:32b

# Change quantization (affects VRAM usage and quality)
OLLAMA_QWEN_QUANTIZATION=q4_k_m         # q3_k_m, q4_k_m, q5_k_m, q8_0
OLLAMA_DEEPSEEK_QUANTIZATION=q4_k_m
```

### GPU Tuning

Edit `deployment/docker/docker-compose.override.yml`:

```yaml
services:
  ollama-qwen:
    environment:
      - OLLAMA_GPU_LAYERS=35      # Increase for more GPU offload (max ~40 for 7B)
      - OLLAMA_NUM_PARALLEL=1     # Keep at 1 for 8GB VRAM
  
  ollama-deepseek:
    environment:
      - OLLAMA_GPU_LAYERS=35
      - OLLAMA_NUM_PARALLEL=1
```

### Port Mapping

Edit `deployment/docker/models/models.env`:

```bash
OLLAMA_QWEN_PORT=11434      # Default
OLLAMA_DEEPSEEK_PORT=11435  # Default (different from qwen)
```

## Data Persistence

Models and data are stored in Docker named volumes:

| Volume | Purpose |
|--------|---------|
| `forge-ollama-qwen` | qwen2.5-coder model weights & cache |
| `forge-ollama-deepseek` | deepseek-r1 model weights & cache |

### Backup Volumes

```bash
# Backup model volumes
docker run --rm -v forge-ollama-qwen:/data -v $(pwd):/backup alpine tar czf /backup/ollama-qwen-backup.tar.gz -C /data .
docker run --rm -v forge-ollama-deepseek:/data -v $(pwd):/backup alpine tar czf /backup/ollama-deepseek-backup.tar.gz -C /data .

# Restore
docker run --rm -v forge-ollama-qwen:/data -v $(pwd):/backup alpine tar xzf /backup/ollama-qwen-backup.tar.gz -C /data
```

## Updating

### Update Images

```bash
make qwen pull
make dps pull
# Then restart
make qwen down && make qwen up
make dps down && make dps up
```

### Update Models

```bash
# Remove old models
make models-rm

# Pull new versions
make models-pull

# Restart
make qwen down && make qwen up
make dps down && make dps up
```

## Profiles

Use Docker Compose profiles to control which services start:

```bash
# qwen2.5-coder:7b only
docker compose -f deployment/docker/docker-compose.yml -f deployment/docker/models/qwen2.5-coder-7b.yml --profile qwen up -d

# deepseek-r1:8b only
docker compose -f deployment/docker/docker-compose.yml -f deployment/docker/models/deepseek-r1-8b.yml --profile deepseek up -d
```

## Production Considerations

### Security

- Restrict port exposure in `deployment/docker/docker-compose.override.yml`
- Use Docker secrets for sensitive values if needed

### Resource Limits

Add to `deployment/docker/docker-compose.override.yml`:

```yaml
services:
  ollama-qwen:
    deploy:
      resources:
        limits:
          memory: 8G
        reservations:
          memory: 6G
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
```

### Monitoring

```bash
# Resource usage
docker stats

# GPU usage
watch -n 1 nvidia-smi

# Container health
make health
```

## Uninstall

```bash
# Stop and remove everything including volumes
make clean-all

# Or manually
docker compose -f deployment/docker/docker-compose.yml -f deployment/docker/models/qwen2.5-coder-7b.yml -f deployment/docker/models/deepseek-r1-8b.yml down -v
docker volume rm forge-ollama-qwen forge-ollama-deepseek
docker network rm forge-network
```