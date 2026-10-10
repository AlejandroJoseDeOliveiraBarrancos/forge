# Forge Deployment Makefile
# Operational commands for Docker-based LLM deployment

COMPOSE_DIR := deployment/docker
COMPOSE_FILE := $(COMPOSE_DIR)/docker-compose.yml
COMPOSE_OVERRIDE := $(COMPOSE_DIR)/docker-compose.override.yml
MODEL_QWEN := $(COMPOSE_DIR)/models/qwen2.5-coder-7b.yml
MODEL_DPS := $(COMPOSE_DIR)/models/deepseek-r1-8b.yml

# Detect override file
ifeq (,$(wildcard $(COMPOSE_OVERRIDE)))
  COMPOSE_BASE := docker compose -f $(COMPOSE_FILE)
else
  COMPOSE_BASE := docker compose -f $(COMPOSE_FILE) -f $(COMPOSE_OVERRIDE)
endif

COMPOSE_QWEN := $(COMPOSE_BASE) -f $(MODEL_QWEN)
COMPOSE_DPS := $(COMPOSE_BASE) -f $(MODEL_DPS)
COMPOSE_ALL := $(COMPOSE_BASE) -f $(MODEL_QWEN) -f $(MODEL_DPS)

# Include environment files if they exist
ifneq (,$(wildcard $(COMPOSE_DIR)/models/models.env))
  ENV_FILE := --env-file $(COMPOSE_DIR)/models/models.env
else
  ENV_FILE :=
endif

# Include environment files if they exist
ifneq (,$(wildcard $(COMPOSE_DIR)/models/models.env))
  COMPOSE_CMD += --env-file $(COMPOSE_DIR)/models/models.env
endif

.PHONY: help clean clean-volumes clean-all \
        qwen-up qwen-down qwen-logs qwen-shell qwen-ps qwen-pull \
        dps-up dps-down dps-logs dps-shell dps-ps dps-pull \
        models-pull models-rm \
        status health gpu-info

# Default target
help:
	@echo "Forge Deployment - Docker Compose Operations"
	@echo ""
	@echo "Global Commands:"
	@echo "  make clean           Remove stopped containers and networks"
	@echo "  make clean-volumes   Remove all data volumes (DESTRUCTIVE)"
	@echo "  make clean-all       Clean everything including volumes"
	@echo ""
	@echo "qwen2.5-coder:7b (make qwen ...):"
	@echo "  make qwen up         Start qwen2.5-coder:7b"
	@echo "  make qwen down       Stop qwen2.5-coder:7b"
	@echo "  make qwen logs       Follow qwen2.5-coder:7b logs"
	@echo "  make qwen shell      Open shell in qwen container"
	@echo "  make qwen ps         Show qwen container status"
	@echo "  make qwen pull       Pull qwen image"
	@echo ""
	@echo "deepseek-r1:8b (make dps ...):"
	@echo "  make dps up          Start deepseek-r1:8b"
	@echo "  make dps down        Stop deepseek-r1:8b"
	@echo "  make dps logs        Follow deepseek-r1:8b logs"
	@echo "  make dps shell       Open shell in deepseek container"
	@echo "  make dps ps          Show deepseek container status"
	@echo "  make dps pull        Pull deepseek image"
	@echo ""
	@echo "Model Operations:"
	@echo "  make models-pull     Pre-pull both models (qwen2.5-coder:7b, deepseek-r1:8b)"
	@echo "  make models-rm       Remove pulled models from volumes"
	@echo ""
	@echo "Status & Health:"
	@echo "  make status          Show all service status"
	@echo "  make health          Check health of all services + GPU status"
	@echo "  make gpu-info        Show detailed GPU info"
	@echo ""
	@echo "Override: Copy deployment/docker/docker-compose.override.yml.example to deployment/docker/docker-compose.override.yml"

# Global clean commands
clean:
	$(COMPOSE_ALL) $(ENV_FILE) --profile models down --remove-orphans
	docker system prune -f

clean volumes:
	@echo "WARNING: This will delete ALL model data!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		$(COMPOSE_ALL) $(ENV_FILE) --profile models down -v; \
		docker volume rm forge-ollama-qwen forge-ollama-deepseek 2>/dev/null || true; \
	fi

clean all: clean-volumes
	docker system prune -af --volumes

# qwen2.5-coder:7b commands (make qwen ...)
qwen up:
	$(COMPOSE_QWEN) $(ENV_FILE) --profile qwen up -d

qwen down:
	$(COMPOSE_QWEN) $(ENV_FILE) --profile qwen down

qwen logs:
	$(COMPOSE_QWEN) $(ENV_FILE) --profile qwen logs -f

qwen shell:
	$(COMPOSE_QWEN) $(ENV_FILE) --profile qwen exec ollama-qwen /bin/bash

qwen ps:
	$(COMPOSE_QWEN) $(ENV_FILE) --profile qwen ps

qwen pull:
	$(COMPOSE_QWEN) $(ENV_FILE) --profile qwen pull

# deepseek-r1:8b commands (make dps ...)
dps up:
	$(COMPOSE_DPS) $(ENV_FILE) --profile deepseek up -d

dps down:
	$(COMPOSE_DPS) $(ENV_FILE) --profile deepseek down

dps logs:
	$(COMPOSE_DPS) $(ENV_FILE) --profile deepseek logs -f

dps shell:
	$(COMPOSE_DPS) $(ENV_FILE) --profile deepseek exec ollama-deepseek /bin/bash

dps ps:
	$(COMPOSE_DPS) $(ENV_FILE) --profile deepseek ps

dps pull:
	$(COMPOSE_DPS) $(ENV_FILE) --profile deepseek pull

# Model operations
models pull:
	@echo "Pulling qwen2.5-coder:7b..."
	$(COMPOSE_QWEN) $(ENV_FILE) --profile qwen run --rm ollama-qwen ollama pull qwen2.5-coder:7b
	@echo "Pulling deepseek-r1:8b..."
	$(COMPOSE_DPS) $(ENV_FILE) --profile deepseek run --rm ollama-deepseek ollama pull deepseek-r1:8b

models rm:
	@echo "Removing models from volumes..."
	docker run --rm -v forge-ollama-qwen:/root/.ollama alpine rm -rf /root/.ollama/models/*
	docker run --rm -v forge-ollama-deepseek:/root/.ollama alpine rm -rf /root/.ollama/models/*

# Status & Health
status:
	$(COMPOSE_ALL) $(ENV_FILE) --profile models ps -a

health:
	@echo "=== Service Health Status ==="
	@$(COMPOSE_ALL) $(ENV_FILE) --profile models ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
	@echo ""
	@echo "=== GPU Status ==="
	@nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv 2>/dev/null || echo "nvidia-smi not available"

gpu info:
	@nvidia-smi
	@echo ""
	@echo "=== Docker GPU Support ==="
	@docker run --rm --gpus all nvidia/cuda:12.4-base nvidia-smi