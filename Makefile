# ============================================
# Makefile para NYC Taxi Pipeline
# Soporta Docker y Podman (con podman-compose)
# ============================================

# Detección del engine (evaluación inmediata)
CONTAINER_ENGINE := $(shell \
	if command -v docker >/dev/null 2>&1; then \
		echo docker; \
	elif command -v podman >/dev/null 2>&1; then \
		echo podman; \
	else \
		echo missing; \
	fi)

# Selección del compose (diferenciado por engine)
COMPOSE := $(shell \
	if [ "$(CONTAINER_ENGINE)" = "docker" ]; then \
		echo "docker compose"; \
	elif [ "$(CONTAINER_ENGINE)" = "podman" ]; then \
		if command -v podman-compose >/dev/null 2>&1; then \
			echo "podman-compose"; \
		else \
			echo "docker-compose"; \
		fi; \
	else \
		echo "missing"; \
	fi)

# Configuración
SERVICE ?= spark
COMPOSE_FILE ?= docker-compose.yml

# Colores para output
GREEN := \033[0;32m
RED := \033[0;31m
NC := \033[0m # No Color

.PHONY: check-engine wait-ready \
	build up down \
	shell inspect bronze silver quality \
	test logs clean \
	all-jobs help

# ============================================
# TARGETS PRINCIPALES
# ============================================

check-engine:
	@if [ "$(CONTAINER_ENGINE)" = "missing" ]; then \
		echo "$(RED)❌ Docker or Podman is required.$(NC)"; \
		exit 1; \
	fi
	@if [ "$(COMPOSE)" = "missing" ]; then \
		echo "$(RED)❌ docker-compose or podman-compose is required.$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)✅ Container engine: $(CONTAINER_ENGINE)$(NC)"
	@echo "$(GREEN)✅ Compose tool: $(COMPOSE)$(NC)"

wait-ready: check-engine up
	@echo "⏳ Waiting for Spark to be ready..."
	@until $(COMPOSE) exec -T $(SERVICE) spark-submit --version >/dev/null 2>&1; do \
		sleep 2; \
	done
	@echo "$(GREEN)✅ Spark is ready$(NC)"

build: check-engine
	$(COMPOSE) -f $(COMPOSE_FILE) build --no-cache

up: check-engine
	$(COMPOSE) -f $(COMPOSE_FILE) up -d

down: check-engine
	$(COMPOSE) -f $(COMPOSE_FILE) down

# ============================================
# TARGETS DE EJECUCIÓN (con dependencias)
# ============================================

shell: check-engine up
	@echo "$(GREEN)🔍 Entering container $(SERVICE)...$(NC)"
	$(COMPOSE) exec $(SERVICE) bash -c "export PS1='🐳 \u@\h:\w$$ ' && bash"

inspect: wait-ready
	$(COMPOSE) exec $(SERVICE) \
		spark-submit src/nyc_taxi/jobs/00_inspect_data.py

bronze: wait-ready
	$(COMPOSE) exec $(SERVICE) \
		spark-submit src/nyc_taxi/jobs/01_bronze.py

silver: wait-ready
	$(COMPOSE) exec $(SERVICE) \
		spark-submit src/nyc_taxi/jobs/02_silver.py

quality: wait-ready
	$(COMPOSE) exec $(SERVICE) \
		spark-submit src/nyc_taxi/jobs/03_quality_report.py

# Pipeline completo
pipeline: bronze silver quality
	@echo "$(GREEN)✅ Pipeline completed successfully$(NC)"

# ============================================
# TARGETS DE UTILIDAD
# ============================================

test: wait-ready
	$(COMPOSE) exec $(SERVICE) pytest -v tests --cov=src

logs: check-engine
	@echo "$(GREEN)📋 Following logs for $(SERVICE)...$(NC)"
	@trap '$(COMPOSE) logs --tail=50 $(SERVICE)' EXIT; \
	$(COMPOSE) logs -f $(SERVICE)

logs-tail: check-engine
	$(COMPOSE) logs --tail=100 $(SERVICE)

clean: check-engine
	@echo "$(RED)🧹 Cleaning up...$(NC)"
	$(COMPOSE) -f $(COMPOSE_FILE) down --remove-orphans --volumes
	$(CONTAINER_ENGINE) system prune -f --filter "label=project=nyc-taxi" 2>/dev/null || true

# ============================================
# TARGETS DE DEBUG
# ============================================

ps: check-engine
	$(COMPOSE) ps

env: check-engine
	@echo "CONTAINER_ENGINE=$(CONTAINER_ENGINE)"
	@echo "COMPOSE=$(COMPOSE)"
	@echo "SERVICE=$(SERVICE)"

# ============================================
# HELP
# ============================================

help:
	@echo "$(GREEN)NYC Taxi Pipeline - Makefile Commands$(NC)"
	@echo ""
	@echo "  $(GREEN)build$(NC)        Build containers"
	@echo "  $(GREEN)up$(NC)           Start containers in background"
	@echo "  $(GREEN)down$(NC)         Stop containers"
	@echo "  $(GREEN)shell$(NC)        Open bash inside Spark container"
	@echo "  $(GREEN)inspect$(NC)      Run data inspection job"
	@echo "  $(GREEN)bronze$(NC)       Run bronze layer (raw ingestion)"
	@echo "  $(GREEN)silver$(NC)       Run silver layer (cleansing)"
	@echo "  $(GREEN)quality$(NC)      Run quality report"
	@echo "  $(GREEN)pipeline$(NC)     Run full pipeline (bronze+silver+quality)"
	@echo "  $(GREEN)test$(NC)         Run pytest suite"
	@echo "  $(GREEN)logs$(NC)         Follow logs"
	@echo "  $(GREEN)logs-tail$(NC)    Show last 100 log lines"
	@echo "  $(GREEN)clean$(NC)        Remove containers, volumes, and prune"
	@echo "  $(GREEN)ps$(NC)           Show container status"
	@echo "  $(GREEN)env$(NC)          Show detected environment variables"
	@echo ""
	@echo "  $(GREEN)Example: make pipeline SERVICE=spark-master$(NC)"