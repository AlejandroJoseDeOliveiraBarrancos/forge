# Troubleshooting Guide

Common issues and solutions for the Forge Docker LLM deployment.

## Quick Diagnostics

```bash
# Check all service status
make status

# Check health + GPU
make health

# View recent logs
make logs

# Check Docker resources
docker system df
docker stats --no-stream
```

## GPU Issues

### "CUDA out of memory" / OOM Errors

**Symptoms:**
- Container crashes on model load
- "CUDA out of memory" in logs
- `nvidia-smi` shows VRAM near 100%

**Solutions:**

1. **Reduce GPU layers:**
```bash
# In models.env or docker-compose.override.yml
OLLAMA_GPU_LAYERS=30   # Try 30, then 25, then 20
```

2. **Reduce context window:**
```bash
OLLAMA_CONTEXT_SIZE=2048   # Half default
```

3. **Use smaller quantization:**
```bash
OLLAMA_QWEN_QUANTIZATION=q3_k_m
OLLAMA_DEEPSEEK_QUANTIZATION=q3_k_m
# Then re-pull: make models-rm && make models-pull
```

4. **Disable flash attention:**
```bash
OLLAMA_FLASH_ATTENTION=false
```

5. **Ensure only one model loaded:**
```bash
OLLAMA_MAX_LOADED_MODELS=1
OLLAMA_NUM_PARALLEL=1
```

### "No GPU devices found" / GPU Not Detected

**Symptoms:**
- "no GPU devices available" in logs
- Model runs on CPU (very slow)
- `nvidia-smi` works on host but not in container

**Solutions:**

1. **Verify NVIDIA Container Toolkit:**
```bash
docker run --rm --gpus all nvidia/cuda:12.4-base nvidia-smi
# Should show GPU info
```

2. **Restart Docker after toolkit install:**
```bash
sudo systemctl restart docker
```

3. **Check compose GPU config:**
```yaml
# In docker-compose.yml or override
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: 1
          capabilities: [gpu]
```

4. **Check NVIDIA driver version:**
```bash
nvidia-smi
# Driver should be 550+ for CUDA 12.4
```

### Slow Inference Despite GPU

**Symptoms:**
- GPU shows low utilization in `nvidia-smi`
- Tokens/sec much lower than expected

**Solutions:**

1. **Increase GPU layers:**
```bash
OLLAMA_GPU_LAYERS=38   # Try higher if stable
```

2. **Enable flash attention:**
```bash
OLLAMA_FLASH_ATTENTION=true
```

3. **Check CPU bottleneck:**
```bash
# Monitor during inference
htop
# If CPU at 100%, model partially on CPU
```

4. **Verify model actually on GPU:**
```bash
docker exec forge-ollama-qwen ollama ps
# Should show "GPU" in the "Processor" column
```

## Model Issues

### "Model not found" / Pull Failures

**Symptoms:**
- "model 'qwen2.5-coder:7b' not found" error
- Pull hangs or fails

**Solutions:**

1. **Pre-pull models:**
```bash
make models-pull
```

2. **Manual pull with debug:**
```bash
docker exec -it forge-ollama-qwen ollama pull qwen2.5-coder:7b
```

3. **Check disk space:**
```bash
df -h /var/lib/docker
# Need 10GB+ free
```

4. **Check network/proxy:**
```bash
# If behind proxy, set in docker-compose.override.yml
environment:
  - HTTP_PROXY=http://proxy:port
  - HTTPS_PROXY=http://proxy:port
```

### Model Quality Issues

**Symptoms:**
- Gibberish output
- Repetitive loops
- Wrong language

**Solutions:**

1. **Adjust temperature:**
```bash
# For code: lower (0.1-0.3)
# For chat: medium (0.7)
# For creative: higher (0.9-1.0)
OLLAMA_TEMPERATURE=0.7
```

2. **Check quantization:**
```bash
# q3_k_m may degrade quality significantly
# Use q4_k_m or q5_k_m for better quality
```

3. **Increase context for long conversations:**
```bash
OLLAMA_CONTEXT_SIZE=8192
```

4. **Verify correct model loaded:**
```bash
docker exec forge-ollama-qwen ollama list
# Should show qwen2.5-coder:7b with correct size
```

### Model Loading Hangs

**Symptoms:**
- Container starts but model never loads
- Health check fails

**Solutions:**

1. **Check logs:**
```bash
make qwen-logs
# Look for "loading model" messages
```

2. **Increase health check timeout:**
```yaml
# In model compose file
healthcheck:
  start_period: 120s   # Increase from 60s
```

3. **Check volume permissions:**
```bash
docker run --rm -v forge-ollama-qwen:/data alpine ls -la /data
```

## Container Issues

### Container Exits Immediately

**Symptoms:**
- `make ps` shows "Exited" status
- Restart loop in logs

**Solutions:**

1. **Check logs:**
```bash
make qwen-logs
# Look for error at startup
```

2. **Common causes:**
- GPU not available (see GPU section)
- Volume mount issues
- Port already in use
- Invalid environment variable

3. **Run interactively for debug:**
```bash
docker run --rm --gpus all -it \
  -v forge-ollama-qwen:/root/.ollama \
  ollama/ollama:latest /bin/bash
# Then run: ollama serve
```

### Port Conflicts

**Symptoms:**
- "port already allocated" error
- Service won't start

**Solutions:**

1. **Change ports in models.env:**
```bash
OLLAMA_QWEN_PORT=11434
OLLAMA_DEEPSEEK_PORT=11435
```

2. **Check what's using port:**
```bash
sudo lsof -i :11434
sudo lsof -i :11435
```

3. **Use different host ports in override:**
```yaml
services:
  ollama-qwen:
    ports:
      - "11434:11434"
  ollama-deepseek:
    ports:
      - "11436:11434"  # Host 11436 -> Container 11434
```

### Permission Denied on Volumes

**Symptoms:**
- "permission denied" in logs
- Can't write to model cache

**Solutions:**

1. **Fix volume ownership:**
```bash
sudo chown -R 1000:1000 /var/lib/docker/volumes/forge-ollama-qwen/_data
sudo chown -R 1000:1000 /var/lib/docker/volumes/forge-ollama-deepseek/_data
```

2. **Run as root (less secure):**
```yaml
# In compose file
user: "root"
```

## Network Issues

### External Access Issues

**Symptoms:**
- Can't reach API from host/other machines
- Connection timeout

**Solutions:**

1. **Check port binding:**
```bash
docker port forge-ollama-qwen
# Should show 11434/tcp -> 0.0.0.0:11434
```

2. **Check firewall:**
```bash
sudo ufw status
# Allow ports if needed:
sudo ufw allow 11434
sudo ufw allow 11435
```

3. **Bind to specific interface:**
```yaml
# In docker-compose.override.yml
ports:
  - "127.0.0.1:11434:11434"  # Only localhost
  # OR
  - "0.0.0.0:11434:11434"    # All interfaces
```

## Performance Issues

### High Memory Usage

**Symptoms:**
- System RAM near 100%
- Swap usage high
- OOM killer activating

**Solutions:**

1. **Limit container memory:**
```yaml
# In docker-compose.override.yml
deploy:
  resources:
    limits:
      memory: 8G
```

2. **Reduce model count:**
```bash
# Only run one model at a time
make qwen-up
# use model
make qwen-down
make deepseek-up
```

3. **Add swap (if needed):**
```bash
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### High CPU Usage

**Symptoms:**
- CPU at 100% during inference
- System laggy

**Solutions:**

1. **Ensure GPU is being used** (see GPU section)

2. **Limit CPU cores:**
```yaml
deploy:
  resources:
    limits:
      cpus: '4'   # Limit to 4 cores
```

## Cleanup and Reset

### Complete Reset

```bash
# Stop everything
make down

# Remove all data (DESTRUCTIVE)
make clean-all

# Or manually:
docker compose down -v
docker volume rm forge-ollama-qwen forge-ollama-deepseek
docker network rm forge-network
docker system prune -af --volumes
```

### Reset Single Model

```bash
# Remove model data
docker run --rm -v forge-ollama-qwen:/data alpine rm -rf /data/*

# Re-pull
make models-pull
```

## Getting Help

### Collect Debug Info

```bash
# System info
nvidia-smi
docker version
docker compose version

# Container status
make status
make health

# Logs (last 100 lines)
make qwen-logs | tail -100
make deepseek-logs | tail -100

# Resource usage
docker stats --no-stream
```

### Useful Commands

```bash
# Enter container shell
make qwen-shell
make deepseek-shell

# Run Ollama CLI directly
docker exec -it forge-ollama-qwen ollama list
docker exec -it forge-ollama-qwen ollama ps

# Test API directly
curl http://localhost:11434/api/tags
curl http://localhost:11434/api/generate -d '{"model":"qwen2.5-coder:7b","prompt":"test"}'
```

## Known Limitations

| Limitation | Workaround |
|------------|------------|
| Two 8B models = tight on 8GB VRAM | Run one at a time, or use q3_k_m |
| No native multi-GPU support | Use single GPU, or tensor parallelism (not in Ollama) |
| Context limited by VRAM | Use smaller context, RAG for long docs |
| No built-in load balancing | Use external proxy (nginx, traefik) |
| Model updates require restart | Use `make restart` after pull |

## Version Compatibility

| Component | Tested Version |
|-----------|----------------|
| Docker Engine | 24.0+ |
| Docker Compose | 2.20+ |
| NVIDIA Driver | 550+ |
| CUDA | 12.4 |
| Ollama | 0.1.40+ |
| qwen2.5-coder | 7b (q4_k_m) |
| deepseek-r1 | 8b (q4_k_m) |

Report issues with: `make health` output, relevant logs, and hardware specs.