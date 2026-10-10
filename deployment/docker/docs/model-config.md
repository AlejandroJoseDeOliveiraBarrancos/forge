# Model Configuration Guide

Detailed configuration options for qwen2.5-coder:7b and deepseek-r1:8b models running on Ollama.

## Model Specifications

### qwen2.5-coder:7b

| Property | Value |
|----------|-------|
| **Parameters** | 7.61B |
| **Architecture** | Qwen2.5 (Transformer) |
| **Context Window** | 32,768 tokens (default 4096) |
| **Specialization** | Code generation, completion, reasoning |
| **Languages** | 40+ programming languages |
| **License** | Apache 2.0 |

### deepseek-r1:8b

| Property | Value |
|----------|-------|
| **Parameters** | 7.62B (8B nominal) |
| **Architecture** | DeepSeek (Transformer with MoE) |
| **Context Window** | 32,768 tokens (default 4096) |
| **Specialization** | Reasoning, math, code, logic |
| **Training** | RL from DeepSeek-R1-Zero |
| **License** | MIT |

## Quantization Options

Quantization reduces model size and VRAM usage at the cost of some quality.

| Quantization | Size (7B) | VRAM (8GB GPU) | Quality | Speed |
|--------------|-----------|----------------|---------|-------|
| **q4_k_m** (default) | ~4.4 GB | ~5.5 GB | ★★★★☆ | Fast |
| q3_k_m | ~3.3 GB | ~4.5 GB | ★★★☆☆ | Faster |
| q5_k_m | ~5.1 GB | ~6.5 GB | ★★★★★ | Slower |
| q8_0 | ~7.2 GB | ~8.5 GB* | ★★★★★ | Slowest |
| fp16 | ~14.4 GB | OOM | ★★★★★ | Slowest |

*q8_0 may OOM on 8GB with context > 2048

### Recommended: q4_k_m

Best balance for RTX 5060 Ti 8GB:
- Fits model + KV cache + overhead
- Minimal quality loss vs fp16
- Fast inference with flash attention

## Environment Variables

### Model-Specific (models/models.env)

```bash
# Model selection
OLLAMA_QWEN_MODEL=qwen2.5-coder:7b
OLLAMA_DEEPSEEK_MODEL=deepseek-r1:8b

# Quantization (must match pulled model)
OLLAMA_QWEN_QUANTIZATION=q4_k_m
OLLAMA_DEEPSEEK_QUANTIZATION=q4_k_m

# GPU offload (layers on GPU vs CPU)
# 0 = CPU only, 35-40 = most layers on GPU for 7B/8B
OLLAMA_QWEN_GPU_LAYERS=35
OLLAMA_DEEPSEEK_GPU_LAYERS=35

# Parallel requests (1 = sequential, prevents OOM)
OLLAMA_QWEN_NUM_PARALLEL=1
OLLAMA_DEEPSEEK_NUM_PARALLEL=1

# Flash attention (faster, less memory)
OLLAMA_QWEN_FLASH_ATTENTION=true
OLLAMA_DEEPSEEK_FLASH_ATTENTION=true

# KV cache quantization
OLLAMA_QWEN_KV_CACHE_TYPE=q4_0
OLLAMA_DEEPSEEK_KV_CACHE_TYPE=q4_0

# Ports
OLLAMA_QWEN_PORT=11434
OLLAMA_DEEPSEEK_PORT=11435
```

### Generation Parameters

Can be set per-request or as defaults:

```bash
# Temperature (0.0 = deterministic, 1.0 = creative)
OLLAMA_TEMPERATURE=0.7

# Top-p nucleus sampling
OLLAMA_TOP_P=0.9

# Top-k sampling
OLLAMA_TOP_K=40

# Repeat penalty
OLLAMA_REPEAT_PENALTY=1.1

# Context window (max tokens)
OLLAMA_CONTEXT_SIZE=4096

# Keep model loaded after request (5m = 5 minutes)
OLLAMA_KEEP_ALIVE=5m
```

## GPU Layer Offloading

### Understanding GPU_LAYERS

| Layers | VRAM Usage | Inference Speed | Notes |
|--------|------------|-----------------|-------|
| 0 (CPU) | ~500 MB | Very Slow | All on CPU |
| 10 | ~1.5 GB | Slow | Embedding + few layers |
| 20 | ~2.5 GB | Moderate | Half on GPU |
| **35 (default)** | **~5.5 GB** | **Fast** | **Recommended for 8GB** |
| 40 | ~6.5 GB | Fastest | May OOM with context |
| 99 (all) | ~7.5 GB | Fastest | Likely OOM on 8GB |

### Tuning for Your GPU

**RTX 5060 Ti 8GB (this setup):**
```bash
OLLAMA_GPU_LAYERS=35        # Safe default
OLLAMA_GPU_LAYERS=38        # If stable, try higher
OLLAMA_CONTEXT_SIZE=4096    # Reduce if OOM
```

**RTX 3060 12GB:**
```bash
OLLAMA_GPU_LAYERS=40
OLLAMA_CONTEXT_SIZE=8192
```

**RTX 4090 24GB:**
```bash
OLLAMA_GPU_LAYERS=99        # Full offload
OLLAMA_CONTEXT_SIZE=32768   # Full context
```

## Context Window Configuration

Default is 4096 tokens. Increase for longer conversations:

```bash
# In models.env or docker-compose.override.yml
OLLAMA_CONTEXT_SIZE=8192    # 8K context (needs ~1GB more VRAM)
OLLAMA_CONTEXT_SIZE=16384   # 16K context (needs ~2GB more VRAM)
OLLAMA_CONTEXT_SIZE=32768   # Full 32K (needs 16GB+ VRAM)
```

**VRAM estimation for context:**
- Base model (q4_k_m): ~4.4 GB
- KV cache per 1K tokens: ~0.5 GB (q4_0)
- 4096 context: ~4.4 + 2 = 6.4 GB
- 8192 context: ~4.4 + 4 = 8.4 GB (OOM on 8GB!)

## Flash Attention

Enabled by default (`OLLAMA_FLASH_ATTENTION=true`):
- 2-3x faster attention computation
- Reduced memory usage
- Requires Ampere+ GPU (RTX 30 series or newer)
- Disable if stability issues: `OLLAMA_FLASH_ATTENTION=false`

## KV Cache Quantization

```bash
OLLAMA_KV_CACHE_TYPE=q4_0    # 4-bit KV cache (default, recommended)
OLLAMA_KV_CACHE_TYPE=q8_0    # 8-bit KV cache (higher quality, more VRAM)
OLLAMA_KV_CACHE_TYPE=f16     # fp16 KV cache (highest quality, most VRAM)
```

## Model-Specific Tuning

### qwen2.5-coder:7b

Optimized for code tasks:
```bash
# Good defaults for coding
OLLAMA_TEMPERATURE=0.2      # Lower for code (more deterministic)
OLLAMA_TOP_P=0.95
OLLAMA_TOP_K=50
OLLAMA_REPEAT_PENALTY=1.05
```

### deepseek-r1:8b

Optimized for reasoning:
```bash
# Good defaults for reasoning
OLLAMA_TEMPERATURE=0.6      # Higher for reasoning chains
OLLAMA_TOP_P=0.9
OLLAMA_TOP_K=40
OLLAMA_REPEAT_PENALTY=1.1
```

## Performance Benchmarks

### Expected Tokens/Second (RTX 5060 Ti 8GB, q4_k_m)

| Model | Context | GPU Layers | Tokens/s (prefill) | Tokens/s (decode) |
|-------|---------|------------|-------------------|-------------------|
| qwen2.5-coder:7b | 4096 | 35 | ~120 | ~35 |
| deepseek-r1:8b | 4096 | 35 | ~100 | ~30 |

### Optimization Checklist

- [ ] GPU layers set to 35 (adjust up if stable)
- [ ] Flash attention enabled
- [ ] KV cache at q4_0
- [ ] NUM_PARALLEL=1
- [ ] Context size at 4096
- [ ] Temperature tuned for use case
- [ ] Models pulled with correct quantization

## Adding New Models

1. Add new compose file in `models/`:
```yaml
# models/new-model.yml
services:
  ollama-newmodel:
    image: ollama/ollama:latest
    # ... similar structure
```

2. Add to main compose or use profile

3. Add env vars to `models.env.example`

4. Update Makefile with new targets

## Troubleshooting Model Issues

| Issue | Solution |
|-------|----------|
| Slow generation | Increase GPU_LAYERS, enable flash attention |
| OOM on load | Reduce GPU_LAYERS, reduce context, use q3_k_m |
| OOM during generation | Reduce context, reduce NUM_PARALLEL |
| Poor quality | Increase quantization (q5_k_m), check temperature |
| Model not found | Run `make models-pull` or `ollama pull` manually |
| CUDA errors | Update NVIDIA driver, check container toolkit |