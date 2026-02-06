.PHONY: help install install-grafana install-logging install-metrics install-telemetry install-profiling install-services \
        start start-grafana start-logging start-metrics start-telemetry start-profiling start-services \
        stop stop-grafana stop-logging stop-metrics stop-telemetry stop-profiling stop-services \
        restart restart-grafana restart-logging restart-metrics restart-telemetry restart-profiling restart-services \
        uninstall uninstall-grafana uninstall-logging uninstall-metrics uninstall-telemetry uninstall-profiling uninstall-services \
        status info info-grafana info-logging info-metrics info-telemetry info-profiling info-services \
        logs logs-grafana logs-logging logs-metrics logs-telemetry logs-profiling logs-services \
        network health doctor check-ports update update-grafana update-logging update-metrics update-telemetry update-profiling \
        clean ps validate open disk-usage version demo demo-examples demo-app demo-app-stop demo-traffic bootstrap \
        test-load test-stress test-spike test-api \
        backup backup-prometheus backup-loki backup-tempo backup-grafana \
        restore restore-prometheus restore-loki restore-tempo restore-grafana

# Colors
CYAN := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
RESET := \033[0m
BOLD := \033[1m

# Docker compose command - include root .env file for all stacks
DOCKER_COMPOSE := docker compose --env-file $(CURDIR)/.env

# Debug mode - set DEBUG=1 to enable verbose output
DEBUG ?= 0
ifeq ($(DEBUG),1)
  DOCKER_COMPOSE += --verbose
  Q :=
else
  Q := @
endif

# Default target
.DEFAULT_GOAL := help

help: ## Show this help message
	@echo ""
	@echo "$(BOLD)🔭 Observability in a Box (OIB)$(RESET)"
	@echo ""
	@echo "$(CYAN)Usage:$(RESET)"
	@echo "  make $(GREEN)<target>$(RESET)"
	@echo ""
	@echo "$(CYAN)Installation:$(RESET)"
	@grep -E '^(install|install-grafana|install-logging|install-metrics|install-telemetry|install-profiling):.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(CYAN)Management:$(RESET)"
	@grep -E '^(start|stop|restart|status|info|logs)[^-]*:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(CYAN)Health & Diagnostics:$(RESET)"
	@grep -E '^(health|doctor|check-ports|ps|validate):.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(CYAN)Load Testing:$(RESET)"
	@grep -E '^(test-load|test-stress|test-spike|test-api):.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(CYAN)Utilities:$(RESET)"
	@grep -E '^(open|disk-usage|version|demo|demo-app|demo-traffic|demo-examples|bootstrap):.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(CYAN)Maintenance:$(RESET)"
	@grep -E '^(update|update-grafana|update-logging|update-metrics|update-telemetry|update-profiling|latest|clean):.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(CYAN)Backup & Restore:$(RESET)"
	@grep -E '^(backup|restore)[^-]*:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(CYAN)Cleanup:$(RESET)"
	@grep -E '^uninstall[^-]*:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(CYAN)Stack-specific commands:$(RESET)"
	@echo "  Append $(YELLOW)-grafana$(RESET), $(YELLOW)-logging$(RESET), $(YELLOW)-metrics$(RESET), $(YELLOW)-telemetry$(RESET), $(YELLOW)-profiling$(RESET), or $(YELLOW)-services$(RESET) to commands"
	@echo "  Example: make install-logging, make stop-metrics, make logs-telemetry"
	@echo ""
	@echo "$(CYAN)Debug mode:$(RESET)"
	@echo "  Set $(YELLOW)DEBUG=1$(RESET) for verbose output: make install DEBUG=1"
	@echo ""

# ==================== Network ====================

network: ## Create shared Docker network
	@docker info >/dev/null 2>&1 || { echo "$(RED)✗ Docker is not running. Please start Docker first.$(RESET)"; exit 1; }
	@docker network inspect oib-network >/dev/null 2>&1 || { \
		docker network create oib-network && \
		echo "$(GREEN)✓ Created oib-network$(RESET)" || \
		{ echo "$(RED)✗ Failed to create oib-network$(RESET)"; exit 1; }; \
	}

# ==================== Installation ====================

install: network ## Install all observability stacks
	@if [ ! -f .env ]; then \
		echo "$(YELLOW)! No .env file found. Creating from .env.example...$(RESET)"; \
		cp .env.example .env; \
		echo "$(YELLOW)! Please edit .env and set a secure GRAFANA_ADMIN_PASSWORD$(RESET)"; \
		echo ""; \
	fi
	@if grep -q "CHANGE_ME" .env 2>/dev/null; then \
		echo "$(YELLOW)$(BOLD)⚠️  WARNING: Default password detected in .env$(RESET)"; \
		echo "$(YELLOW)   Please change GRAFANA_ADMIN_PASSWORD before production use$(RESET)"; \
		echo ""; \
	fi
	@echo "$(BOLD)[1/4]$(RESET) Installing logging stack..."
	@$(MAKE) --no-print-directory install-logging
	@echo "$(BOLD)[2/4]$(RESET) Installing metrics stack..."
	@$(MAKE) --no-print-directory install-metrics
	@echo "$(BOLD)[3/4]$(RESET) Installing telemetry stack..."
	@$(MAKE) --no-print-directory install-telemetry
	@echo "$(BOLD)[4/4]$(RESET) Installing Grafana..."
	@$(MAKE) --no-print-directory install-grafana
	@echo ""
	@echo "$(GREEN)$(BOLD)════════════════════════════════════════════════════════════════$(RESET)"
	@echo "$(GREEN)$(BOLD)              ✓ OIB installed successfully!$(RESET)"
	@echo "$(GREEN)$(BOLD)════════════════════════════════════════════════════════════════$(RESET)"
	@echo ""
	@echo "  $(BOLD)Open Grafana:$(RESET)       $(YELLOW)http://localhost:3000$(RESET)"
	@echo "  $(BOLD)Send traces to:$(RESET)     $(YELLOW)localhost:4317$(RESET) (gRPC) or $(YELLOW)localhost:4318$(RESET) (HTTP)"
	@echo ""
	@echo "$(CYAN)Next steps:$(RESET)"
	@echo "  $(GREEN)make demo$(RESET)      Generate sample data to explore"
	@echo "  $(GREEN)make open$(RESET)      Open Grafana in browser"
	@echo "  $(GREEN)make health$(RESET)    Verify all services are healthy"
	@echo "  $(GREEN)make info$(RESET)      Show all integration endpoints"
	@echo ""

install-grafana: network ## Install Grafana (unified dashboard)
	@echo "$(CYAN)📊 Installing Grafana...$(RESET)"
	@cd grafana && $(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)✓ Grafana installed$(RESET)"

install-logging: network ## Install logging stack (Loki + Alloy)
	@echo "$(CYAN)📋 Installing Logging Stack...$(RESET)"
	@cd logging && $(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)✓ Logging stack installed$(RESET)"

install-metrics: network ## Install metrics stack (Prometheus + Exporters)
	@echo "$(CYAN)📊 Installing Metrics Stack...$(RESET)"
	@cd metrics && $(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)✓ Metrics stack installed$(RESET)"

install-telemetry: network ## Install telemetry stack (Tempo + Alloy)
	@echo "$(CYAN)🔭 Installing Telemetry Stack...$(RESET)"
	@cd telemetry && $(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)✓ Telemetry stack installed$(RESET)"

install-profiling: network ## Install profiling stack (Pyroscope) - optional
	@echo "$(CYAN)🔥 Installing Profiling Stack...$(RESET)"
	@cd profiling && $(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)✓ Profiling stack installed$(RESET)"
	@echo ""
	@echo "$(YELLOW)Note: Restart Grafana to enable Pyroscope datasource: make restart-grafana$(RESET)"

install-services: network ## Install shared services (PostgreSQL + Redis) - optional
	@echo "$(CYAN)🗄️  Installing Shared Services...$(RESET)"
	@cd services && $(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)✓ Shared services installed$(RESET)"
	@echo ""
	@echo "$(CYAN)Available services:$(RESET)"
	@echo "  PostgreSQL: $(YELLOW)localhost:5432$(RESET) (user: oib, db: oib_demo)"
	@echo "  Redis:      $(YELLOW)localhost:6379$(RESET)"

# ==================== Start ====================

start: start-logging start-metrics start-telemetry start-grafana ## Start all stacks
	@echo "$(GREEN)✓ All stacks started$(RESET)"

start-grafana: ## Start Grafana
	@cd grafana && $(DOCKER_COMPOSE) start

start-logging: ## Start logging stack
	@cd logging && $(DOCKER_COMPOSE) start

start-metrics: ## Start metrics stack
	@cd metrics && $(DOCKER_COMPOSE) start

start-telemetry: ## Start telemetry stack
	@cd telemetry && $(DOCKER_COMPOSE) start

start-profiling: ## Start profiling stack
	@cd profiling && $(DOCKER_COMPOSE) start

start-services: ## Start shared services (PostgreSQL + Redis)
	@cd services && $(DOCKER_COMPOSE) start

# ==================== Stop ====================

stop: stop-grafana stop-logging stop-metrics stop-telemetry ## Stop all stacks
	@echo "$(GREEN)✓ All stacks stopped$(RESET)"

stop-grafana: ## Stop Grafana
	@cd grafana && $(DOCKER_COMPOSE) stop

stop-logging: ## Stop logging stack
	@cd logging && $(DOCKER_COMPOSE) stop

stop-metrics: ## Stop metrics stack
	@cd metrics && $(DOCKER_COMPOSE) stop

stop-telemetry: ## Stop telemetry stack
	@cd telemetry && $(DOCKER_COMPOSE) stop

stop-profiling: ## Stop profiling stack
	@cd profiling && $(DOCKER_COMPOSE) stop

stop-services: ## Stop shared services (PostgreSQL + Redis)
	@cd services && $(DOCKER_COMPOSE) stop

# ==================== Restart ====================

restart: restart-logging restart-metrics restart-telemetry restart-grafana ## Restart all stacks
	@echo "$(GREEN)✓ All stacks restarted$(RESET)"

restart-grafana: ## Restart Grafana
	@cd grafana && $(DOCKER_COMPOSE) restart

restart-logging: ## Restart logging stack
	@cd logging && $(DOCKER_COMPOSE) restart

restart-metrics: ## Restart metrics stack
	@cd metrics && $(DOCKER_COMPOSE) restart

restart-telemetry: ## Restart telemetry stack
	@cd telemetry && $(DOCKER_COMPOSE) restart

restart-profiling: ## Restart profiling stack
	@cd profiling && $(DOCKER_COMPOSE) restart

restart-services: ## Restart shared services (PostgreSQL + Redis)
	@cd services && $(DOCKER_COMPOSE) restart

# ==================== Uninstall ====================

uninstall: ## Remove all stacks and volumes (with confirmation)
	@echo "$(RED)$(BOLD)⚠️  WARNING: This will delete ALL data (logs, metrics, traces)!$(RESET)"
	@echo ""
	@read -p "Are you sure you want to uninstall? [y/N] " confirm && [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ] || (echo "Cancelled." && exit 1)
	@$(MAKE) --no-print-directory uninstall-grafana
	@$(MAKE) --no-print-directory uninstall-logging
	@$(MAKE) --no-print-directory uninstall-metrics
	@$(MAKE) --no-print-directory uninstall-telemetry
	@docker network rm oib-network 2>/dev/null || true
	@echo "$(GREEN)✓ All stacks removed$(RESET)"

uninstall-grafana: ## Remove Grafana and volumes
	@echo "$(YELLOW)Removing Grafana...$(RESET)"
	@cd grafana && $(DOCKER_COMPOSE) down -v
	@echo "$(GREEN)✓ Grafana removed$(RESET)"

uninstall-logging: ## Remove logging stack and volumes
	@echo "$(YELLOW)Removing logging stack...$(RESET)"
	@cd logging && $(DOCKER_COMPOSE) down -v
	@echo "$(GREEN)✓ Logging stack removed$(RESET)"

uninstall-metrics: ## Remove metrics stack and volumes
	@echo "$(YELLOW)Removing metrics stack...$(RESET)"
	@cd metrics && $(DOCKER_COMPOSE) down -v
	@echo "$(GREEN)✓ Metrics stack removed$(RESET)"

uninstall-telemetry: ## Remove telemetry stack and volumes
	@echo "$(YELLOW)Removing telemetry stack...$(RESET)"
	@cd telemetry && $(DOCKER_COMPOSE) down -v
	@echo "$(GREEN)✓ Telemetry stack removed$(RESET)"

uninstall-profiling: ## Remove profiling stack and volumes
	@echo "$(YELLOW)Removing profiling stack...$(RESET)"
	@cd profiling && $(DOCKER_COMPOSE) down -v
	@echo "$(GREEN)✓ Profiling stack removed$(RESET)"

uninstall-services: ## Remove shared services and volumes (PostgreSQL + Redis)
	@echo "$(YELLOW)Removing shared services...$(RESET)"
	@cd services && $(DOCKER_COMPOSE) down -v
	@echo "$(GREEN)✓ Shared services removed$(RESET)"

# ==================== Status ====================

status: ## Show status of all stacks with health indicators
	@echo ""
	@echo "$(BOLD)🔭 OIB Stack Status$(RESET)"
	@echo ""
	@printf "  %-20s %-12s %s\n" "SERVICE" "STATUS" "HEALTH"
	@echo "  ────────────────────────────────────────────────"
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -q oib-grafana; then \
		health=$$(curl -sf http://localhost:3000/api/health 2>/dev/null && echo "$(GREEN)✓ healthy$(RESET)" || echo "$(YELLOW)? starting$(RESET)"); \
		printf "  %-20s $(GREEN)%-12s$(RESET) %b\n" "Grafana" "running" "$$health"; \
	else \
		printf "  %-20s $(RED)%-12s$(RESET)\n" "Grafana" "stopped"; \
	fi
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -q oib-loki; then \
		health=$$(curl -sf http://localhost:3100/ready 2>/dev/null && echo "$(GREEN)✓ healthy$(RESET)" || echo "$(YELLOW)? starting$(RESET)"); \
		printf "  %-20s $(GREEN)%-12s$(RESET) %b\n" "Loki" "running" "$$health"; \
	else \
		printf "  %-20s $(RED)%-12s$(RESET)\n" "Loki" "stopped"; \
	fi
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -q oib-alloy-logging; then \
		health=$$(curl -sf http://localhost:12345/-/ready 2>/dev/null && echo "$(GREEN)✓ healthy$(RESET)" || echo "$(YELLOW)? starting$(RESET)"); \
		printf "  %-20s $(GREEN)%-12s$(RESET) %b\n" "Alloy (logging)" "running" "$$health"; \
	else \
		printf "  %-20s $(RED)%-12s$(RESET)\n" "Alloy (logging)" "stopped"; \
	fi
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -q oib-prometheus; then \
		health=$$(curl -sf http://localhost:9090/-/ready 2>/dev/null && echo "$(GREEN)✓ healthy$(RESET)" || echo "$(YELLOW)? starting$(RESET)"); \
		printf "  %-20s $(GREEN)%-12s$(RESET) %b\n" "Prometheus" "running" "$$health"; \
	else \
		printf "  %-20s $(RED)%-12s$(RESET)\n" "Prometheus" "stopped"; \
	fi
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -q oib-alloy-metrics; then \
		health=$$(curl -sf http://localhost:12347/-/ready 2>/dev/null && echo "$(GREEN)✓ healthy$(RESET)" || echo "$(YELLOW)? starting$(RESET)"); \
		printf "  %-20s $(GREEN)%-12s$(RESET) %b\n" "Alloy (metrics)" "running" "$$health"; \
	else \
		printf "  %-20s $(RED)%-12s$(RESET)\n" "Alloy (metrics)" "stopped"; \
	fi
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -q oib-cadvisor; then \
		printf "  %-20s $(GREEN)%-12s$(RESET) %b\n" "cAdvisor" "running" "$(GREEN)✓ healthy$(RESET)"; \
	else \
		printf "  %-20s $(RED)%-12s$(RESET)\n" "cAdvisor" "stopped"; \
	fi
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -q oib-tempo; then \
		health=$$(curl -sf http://localhost:3200/ready 2>/dev/null && echo "$(GREEN)✓ healthy$(RESET)" || echo "$(YELLOW)? starting$(RESET)"); \
		printf "  %-20s $(GREEN)%-12s$(RESET) %b\n" "Tempo" "running" "$$health"; \
	else \
		printf "  %-20s $(RED)%-12s$(RESET)\n" "Tempo" "stopped"; \
	fi
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -q oib-alloy-telemetry; then \
		health=$$(curl -sf http://localhost:12346/-/ready 2>/dev/null && echo "$(GREEN)✓ healthy$(RESET)" || echo "$(YELLOW)? starting$(RESET)"); \
		printf "  %-20s $(GREEN)%-12s$(RESET) %b\n" "Alloy (telemetry)" "running" "$$health"; \
	else \
		printf "  %-20s $(RED)%-12s$(RESET)\n" "Alloy (telemetry)" "stopped"; \
	fi
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -q oib-pyroscope; then \
		health=$$(curl -sf http://localhost:4040/ready 2>/dev/null && echo "$(GREEN)✓ healthy$(RESET)" || echo "$(YELLOW)? starting$(RESET)"); \
		printf "  %-20s $(GREEN)%-12s$(RESET) %b\n" "Pyroscope" "running" "$$health"; \
	else \
		printf "  %-20s $(RED)%-12s$(RESET)\n" "Pyroscope" "stopped"; \
	fi
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -q oib-postgres; then \
		health=$$(docker exec oib-postgres pg_isready -U oib >/dev/null 2>&1 && echo "$(GREEN)✓ healthy$(RESET)" || echo "$(YELLOW)? starting$(RESET)"); \
		printf "  %-20s $(GREEN)%-12s$(RESET) %b\n" "PostgreSQL" "running" "$$health"; \
	else \
		printf "  %-20s $(RED)%-12s$(RESET)\n" "PostgreSQL" "stopped"; \
	fi
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -q oib-redis; then \
		health=$$(docker exec oib-redis redis-cli ping >/dev/null 2>&1 && echo "$(GREEN)✓ healthy$(RESET)" || echo "$(YELLOW)? starting$(RESET)"); \
		printf "  %-20s $(GREEN)%-12s$(RESET) %b\n" "Redis" "running" "$$health"; \
	else \
		printf "  %-20s $(RED)%-12s$(RESET)\n" "Redis" "stopped"; \
	fi
	@echo ""

# ==================== Info ====================

info: ## Show integration endpoints for all stacks
	@echo ""
	@echo "$(BOLD)════════════════════════════════════════════════════════════════$(RESET)"
	@echo "$(BOLD)           🔭 Observability in a Box - Integration Guide$(RESET)"
	@echo "$(BOLD)════════════════════════════════════════════════════════════════$(RESET)"
	@$(MAKE) --no-print-directory info-grafana
	@$(MAKE) --no-print-directory info-logging
	@$(MAKE) --no-print-directory info-metrics
	@$(MAKE) --no-print-directory info-telemetry

info-grafana: ## Show Grafana info
	@echo ""
	@echo "$(BOLD)$(CYAN)📊 GRAFANA (Unified Dashboard)$(RESET)"
	@echo "$(BOLD)────────────────────────────────────────$(RESET)"
	@echo ""
	@echo "$(GREEN)Dashboard:$(RESET)"
	@echo "  URL:      $(YELLOW)http://localhost:3000$(RESET)"
	@echo "  Login:    $(CYAN)See .env file for credentials$(RESET)"
	@echo ""
	@echo "$(GREEN)Datasources:$(RESET)"
	@echo "  • Loki (logs)"
	@echo "  • Prometheus (metrics)"
	@echo "  • Tempo (traces)"
	@echo ""

info-logging: ## Show logging integration info
	@echo ""
	@echo "$(BOLD)$(CYAN)📋 LOGGING (Loki + Alloy)$(RESET)"
	@echo "$(BOLD)────────────────────────────────────────$(RESET)"
	@echo ""
	@echo "$(GREEN)Alloy UI:$(RESET)"
	@echo "  URL:      $(YELLOW)http://localhost:12345$(RESET)"
	@echo ""
	@echo "$(GREEN)Loki Push API:$(RESET)"
	@echo "  URL:      $(YELLOW)http://localhost:3100/loki/api/v1/push$(RESET)"
	@echo ""
	@echo "$(GREEN)Automatic Docker log collection:$(RESET)"
	@echo "  Alloy automatically collects logs from all Docker containers."
	@echo "  No configuration needed - just run your containers!"
	@echo ""

info-metrics: ## Show metrics integration info
	@echo ""
	@echo "$(BOLD)$(CYAN)📈 METRICS (Prometheus + Alloy + cAdvisor)$(RESET)"
	@echo "$(BOLD)────────────────────────────────────────$(RESET)"
	@echo ""
	@echo "$(GREEN)Prometheus UI:$(RESET)"
	@echo "  URL:      $(YELLOW)http://localhost:9090$(RESET)"
	@echo ""
	@echo "$(GREEN)Alloy Metrics UI:$(RESET)"
	@echo "  URL:      $(YELLOW)http://localhost:12347$(RESET)"
	@echo ""
	@echo "$(GREEN)Add scrape target:$(RESET)"
	@echo "  Edit $(CYAN)metrics/config/prometheus.yml$(RESET) and add:"
	@echo "  $(CYAN)- job_name: 'my-app'$(RESET)"
	@echo "  $(CYAN)  static_configs:$(RESET)"
	@echo "  $(CYAN)    - targets: ['host.docker.internal:8080']$(RESET)"
	@echo ""

info-telemetry: ## Show telemetry integration info
	@echo ""
	@echo "$(BOLD)$(CYAN)🔭 TELEMETRY (Tempo + Alloy)$(RESET)"
	@echo "$(BOLD)────────────────────────────────────────$(RESET)"
	@echo ""
	@echo "$(GREEN)Alloy UI:$(RESET)"
	@echo "  URL:      $(YELLOW)http://localhost:12346$(RESET)"
	@echo ""
	@echo "$(GREEN)OpenTelemetry Endpoints:$(RESET)"
	@echo "  OTLP gRPC:  $(YELLOW)localhost:4317$(RESET)"
	@echo "  OTLP HTTP:  $(YELLOW)http://localhost:4318$(RESET)"
	@echo ""
	@echo "$(GREEN)Configure your app:$(RESET)"
	@echo "  $(CYAN)OTEL_EXPORTER_OTLP_ENDPOINT=http://<oib-host>:4318$(RESET)"
	@echo ""

info-profiling: ## Show profiling integration info
	@echo ""
	@echo "$(BOLD)$(CYAN)🔥 PROFILING (Pyroscope)$(RESET)"
	@echo "$(BOLD)────────────────────────────────────────$(RESET)"
	@echo ""
	@echo "$(GREEN)Pyroscope UI:$(RESET)"
	@echo "  URL:      $(YELLOW)http://localhost:4040$(RESET)"
	@echo ""
	@echo "$(GREEN)SDK Integration:$(RESET)"
	@echo "  Server:   $(YELLOW)http://<oib-host>:4040$(RESET)"
	@echo ""
	@echo "$(GREEN)Configure your app:$(RESET)"
	@echo "  $(CYAN)PYROSCOPE_SERVER_ADDRESS=http://<oib-host>:4040$(RESET)"
	@echo ""
	@echo "$(GREEN)Supported Languages:$(RESET)"
	@echo "  • Go, Python, Java, .NET, Ruby, Node.js, Rust"
	@echo ""

info-services: ## Show shared services info (PostgreSQL + Redis)
	@echo ""
	@echo "$(BOLD)$(CYAN)🗄️  SHARED SERVICES (PostgreSQL + Redis)$(RESET)"
	@echo "$(BOLD)────────────────────────────────────────$(RESET)"
	@echo ""
	@echo "$(GREEN)PostgreSQL:$(RESET)"
	@echo "  Host:     $(YELLOW)localhost:5432$(RESET) (from host)"
	@echo "            $(YELLOW)oib-postgres:5432$(RESET) (from containers)"
	@echo "  User:     $(CYAN)oib$(RESET)"
	@echo "  Password: $(CYAN)See .env (POSTGRES_PASSWORD)$(RESET)"
	@echo "  Database: $(CYAN)oib_demo$(RESET)"
	@echo ""
	@echo "$(GREEN)Redis:$(RESET)"
	@echo "  Host:     $(YELLOW)localhost:6379$(RESET) (from host)"
	@echo "            $(YELLOW)oib-redis:6379$(RESET) (from containers)"
	@echo ""
	@echo "$(GREEN)Connection strings:$(RESET)"
	@echo "  $(CYAN)postgres://\$${POSTGRES_USER:-oib}:\$${POSTGRES_PASSWORD}@localhost:\$${POSTGRES_PORT:-5432}/\$${POSTGRES_DB:-oib_demo}$(RESET)"
	@echo "  $(CYAN)redis://localhost:\$${REDIS_PORT:-6379}$(RESET)"
	@echo ""
	@echo "  $(YELLOW)Tip: Check .env for actual credentials$(RESET)"
	@echo ""

# ==================== Logs ====================

logs: ## Tail logs from all stacks
	@echo "$(CYAN)Tailing all stack logs (Ctrl+C to stop)...$(RESET)"
	@docker compose --env-file $(CURDIR)/.env -f grafana/compose.yaml -f logging/compose.yaml -f metrics/compose.yaml -f telemetry/compose.yaml logs -f

logs-grafana: ## Tail Grafana logs
	@cd grafana && $(DOCKER_COMPOSE) logs -f

logs-logging: ## Tail logging stack logs
	@cd logging && $(DOCKER_COMPOSE) logs -f

logs-metrics: ## Tail metrics stack logs
	@cd metrics && $(DOCKER_COMPOSE) logs -f

logs-telemetry: ## Tail telemetry stack logs
	@cd telemetry && $(DOCKER_COMPOSE) logs -f

logs-profiling: ## Tail profiling stack logs
	@cd profiling && $(DOCKER_COMPOSE) logs -f

logs-services: ## Tail shared services logs (PostgreSQL + Redis)
	@cd services && $(DOCKER_COMPOSE) logs -f

# ==================== Health & Diagnostics ====================

health: ## Quick health check of all services
	@echo ""
	@echo "$(BOLD)🏥 Health Check$(RESET)"
	@echo ""
	@echo "$(CYAN)Grafana:$(RESET)"
	@curl -sf http://localhost:3000/api/health >/dev/null 2>&1 && echo "  $(GREEN)✓$(RESET) Grafana is healthy" || echo "  $(RED)✗$(RESET) Grafana is not responding"
	@echo ""
	@echo "$(CYAN)Logging:$(RESET)"
	@curl -sf http://localhost:3100/ready >/dev/null 2>&1 && echo "  $(GREEN)✓$(RESET) Loki is healthy" || echo "  $(RED)✗$(RESET) Loki is not responding"
	@curl -sf http://localhost:12345/-/ready >/dev/null 2>&1 && echo "  $(GREEN)✓$(RESET) Alloy (logging) is healthy" || echo "  $(RED)✗$(RESET) Alloy (logging) is not responding"
	@echo ""
	@echo "$(CYAN)Metrics:$(RESET)"
	@curl -sf http://localhost:9090/-/ready >/dev/null 2>&1 && echo "  $(GREEN)✓$(RESET) Prometheus is healthy" || echo "  $(RED)✗$(RESET) Prometheus is not responding"
	@curl -sf http://localhost:12347/-/ready >/dev/null 2>&1 && echo "  $(GREEN)✓$(RESET) Alloy (metrics) is healthy" || echo "  $(RED)✗$(RESET) Alloy (metrics) is not responding"
	@echo ""
	@echo "$(CYAN)Telemetry:$(RESET)"
	@curl -sf http://localhost:3200/ready >/dev/null 2>&1 && echo "  $(GREEN)✓$(RESET) Tempo is healthy" || echo "  $(RED)✗$(RESET) Tempo is not responding"
	@curl -sf http://localhost:12346/-/ready >/dev/null 2>&1 && echo "  $(GREEN)✓$(RESET) Alloy (telemetry) is healthy" || echo "  $(RED)✗$(RESET) Alloy (telemetry) is not responding"
	@echo ""
	@echo "$(CYAN)Profiling:$(RESET)"
	@curl -sf http://localhost:4040/ready >/dev/null 2>&1 && echo "  $(GREEN)✓$(RESET) Pyroscope is healthy" || echo "  $(RED)✗$(RESET) Pyroscope is not responding (run 'make install-profiling' to enable)"
	@echo ""

doctor: ## Diagnose common issues (Docker, ports, config)
	@echo ""
	@echo "$(BOLD)🩺 OIB Doctor$(RESET)"
	@echo ""
	@echo "$(CYAN)Checking Docker...$(RESET)"
	@docker info >/dev/null 2>&1 && echo "  $(GREEN)✓$(RESET) Docker is running" || echo "  $(RED)✗$(RESET) Docker is not running"
	@docker compose version >/dev/null 2>&1 && echo "  $(GREEN)✓$(RESET) Docker Compose is available" || echo "  $(RED)✗$(RESET) Docker Compose not found"
	@echo ""
	@echo "$(CYAN)Checking configuration...$(RESET)"
	@test -f .env && echo "  $(GREEN)✓$(RESET) .env file exists" || echo "  $(YELLOW)!$(RESET) .env file missing (copy from .env.example)"
	@if [ -f .env ]; then \
		grep -q "CHANGE_ME" .env && echo "  $(YELLOW)!$(RESET) Password not changed in .env (security risk)" || echo "  $(GREEN)✓$(RESET) Password has been customized"; \
	fi
	@echo ""
	@echo "$(CYAN)Checking network...$(RESET)"
	@docker network inspect oib-network >/dev/null 2>&1 && echo "  $(GREEN)✓$(RESET) oib-network exists" || echo "  $(YELLOW)!$(RESET) oib-network not created (run 'make install')"
	@echo ""
	@echo "$(CYAN)Checking ports...$(RESET)"
	@$(MAKE) --no-print-directory check-ports
	@echo ""

check-ports: ## Check if required ports are available
	@for port in 3000 3100 9090 9091 4317 4318; do \
		if lsof -i :$$port >/dev/null 2>&1; then \
			echo "  $(YELLOW)!$(RESET) Port $$port is in use"; \
		else \
			echo "  $(GREEN)✓$(RESET) Port $$port is available"; \
		fi; \
	done

ps: ## Show running OIB containers
	@echo ""
	@docker ps --filter "network=oib-network" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
	@echo ""

validate: ## Validate configuration files
	@echo ""
	@echo "$(BOLD)🔍 Validating configuration files...$(RESET)"
	@echo ""
	@ERRORS=0; \
	echo "$(CYAN)Checking YAML syntax...$(RESET)"; \
	for file in logging/config/loki-config.yml metrics/config/prometheus.yml grafana/provisioning/datasources/datasources.yml; do \
		if [ -f "$$file" ]; then \
			if docker run --rm -v "$(PWD)/$$file:/file.yml:ro" mikefarah/yq '.' /file.yml >/dev/null 2>&1; then \
				echo "  $(GREEN)✓$(RESET) $$file"; \
			else \
				echo "  $(RED)✗$(RESET) $$file has syntax errors"; \
				ERRORS=$$((ERRORS + 1)); \
			fi; \
		fi; \
	done; \
	echo ""; \
	echo "$(CYAN)Checking Docker Compose files...$(RESET)"; \
	for dir in grafana logging metrics telemetry profiling; do \
		if [ -f "$$dir/compose.yaml" ]; then \
			if cd $$dir && $(DOCKER_COMPOSE) config --quiet 2>/dev/null; then \
				echo "  $(GREEN)✓$(RESET) $$dir/compose.yaml"; \
			else \
				echo "  $(RED)✗$(RESET) $$dir/compose.yaml has errors"; \
				ERRORS=$$((ERRORS + 1)); \
			fi; \
			cd ..; \
		fi; \
	done; \
	echo ""; \
	if [ $$ERRORS -gt 0 ]; then \
		echo "$(RED)$(BOLD)✗ Validation failed with $$ERRORS error(s)$(RESET)"; \
		exit 1; \
	else \
		echo "$(GREEN)$(BOLD)✓ All configuration files are valid$(RESET)"; \
	fi
	@echo ""

# ==================== Maintenance ====================

update: ## Pull latest images and restart all stacks
	@echo "$(CYAN)Pulling latest images...$(RESET)"
	@cd grafana && $(DOCKER_COMPOSE) pull
	@cd logging && $(DOCKER_COMPOSE) pull
	@cd metrics && $(DOCKER_COMPOSE) pull
	@cd telemetry && $(DOCKER_COMPOSE) pull
	@echo ""
	@echo "$(CYAN)Restarting stacks with new images...$(RESET)"
	@$(MAKE) --no-print-directory restart
	@echo ""
	@echo "$(GREEN)✓ All stacks updated$(RESET)"

update-grafana: ## Pull latest Grafana image and restart
	@echo "$(CYAN)Pulling latest Grafana image...$(RESET)"
	@cd grafana && $(DOCKER_COMPOSE) pull
	@echo "$(CYAN)Restarting Grafana...$(RESET)"
	@cd grafana && $(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)✓ Grafana updated$(RESET)"

update-logging: ## Pull latest logging images (Loki, Alloy) and restart
	@echo "$(CYAN)Pulling latest logging images...$(RESET)"
	@cd logging && $(DOCKER_COMPOSE) pull
	@echo "$(CYAN)Restarting logging stack...$(RESET)"
	@cd logging && $(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)✓ Logging stack updated$(RESET)"

update-metrics: ## Pull latest metrics images (Prometheus, exporters) and restart
	@echo "$(CYAN)Pulling latest metrics images...$(RESET)"
	@cd metrics && $(DOCKER_COMPOSE) pull
	@echo "$(CYAN)Restarting metrics stack...$(RESET)"
	@cd metrics && $(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)✓ Metrics stack updated$(RESET)"

update-telemetry: ## Pull latest telemetry images (Tempo, Alloy) and restart
	@echo "$(CYAN)Pulling latest telemetry images...$(RESET)"
	@cd telemetry && $(DOCKER_COMPOSE) pull
	@echo "$(CYAN)Restarting telemetry stack...$(RESET)"
	@cd telemetry && $(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)✓ Telemetry stack updated$(RESET)"

update-profiling: ## Pull latest profiling images (Pyroscope) and restart
	@echo "$(CYAN)Pulling latest profiling images...$(RESET)"
	@cd profiling && $(DOCKER_COMPOSE) pull
	@echo "$(CYAN)Restarting profiling stack...$(RESET)"
	@cd profiling && $(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)✓ Profiling stack updated$(RESET)"

latest: ## Pull and run :latest versions of all images
	@echo "$(BOLD)🔄 Pulling :latest images...$(RESET)"
	@echo ""
	@echo "$(CYAN)Grafana:$(RESET)"
	@docker pull grafana/grafana:latest
	@echo "$(CYAN)Loki:$(RESET)"
	@docker pull grafana/loki:latest
	@echo "$(CYAN)Alloy:$(RESET)"
	@docker pull grafana/alloy:latest
	@echo "$(CYAN)Prometheus:$(RESET)"
	@docker pull prom/prometheus:latest
	@echo "$(CYAN)Blackbox Exporter:$(RESET)"
	@docker pull prom/blackbox-exporter:latest
	@echo "$(CYAN)cAdvisor:$(RESET)"
	@docker pull gcr.io/cadvisor/cadvisor:latest
	@echo "$(CYAN)Tempo:$(RESET)"
	@docker pull grafana/tempo:latest
	@echo "$(CYAN)Pyroscope:$(RESET)"
	@docker pull grafana/pyroscope:latest
	@echo ""
	@echo "$(CYAN)Recreating containers with :latest images...$(RESET)"
	@echo "$(CYAN)  Logging stack...$(RESET)"
	@cd logging && LOKI_VERSION=latest ALLOY_VERSION=latest $(DOCKER_COMPOSE) up -d --quiet-pull 2>&1 || true
	@echo "$(CYAN)  Metrics stack...$(RESET)"
	@cd metrics && PROMETHEUS_VERSION=latest ALLOY_VERSION=latest BLACKBOX_VERSION=latest CADVISOR_VERSION=latest $(DOCKER_COMPOSE) up -d --quiet-pull 2>&1 || true
	@echo "$(CYAN)  Telemetry stack...$(RESET)"
	@cd telemetry && TEMPO_VERSION=latest ALLOY_VERSION=latest $(DOCKER_COMPOSE) up -d --quiet-pull 2>&1 || true
	@echo "$(CYAN)  Profiling stack...$(RESET)"
	@cd profiling && PYROSCOPE_VERSION=latest $(DOCKER_COMPOSE) up -d --quiet-pull 2>&1 || true
	@echo "$(CYAN)  Grafana...$(RESET)"
	@cd grafana && GRAFANA_VERSION=latest $(DOCKER_COMPOSE) up -d --quiet-pull 2>&1 || true
	@echo ""
	@echo "$(CYAN)Waiting for services to be healthy...$(RESET)"
	@sleep 10
	@echo ""
	@$(MAKE) --no-print-directory status
	@echo ""
	@echo "$(GREEN)$(BOLD)✓ All stacks running with :latest images$(RESET)"
	@echo ""
	@echo "$(YELLOW)Note: To revert to pinned versions, run: make install$(RESET)"

clean: ## Remove unused Docker resources (images, networks, volumes)
	@echo "$(CYAN)Cleaning up unused Docker resources...$(RESET)"
	@docker system prune -f
	@echo "$(GREEN)✓ Cleanup complete$(RESET)"

# ==================== Utilities ====================

open: ## Open Grafana dashboard in browser
	@echo "$(CYAN)Opening Grafana in browser...$(RESET)"
	@if curl -sf http://localhost:3000/api/health >/dev/null 2>&1; then \
		if command -v xdg-open >/dev/null 2>&1; then \
			xdg-open http://localhost:3000 2>/dev/null; \
		elif command -v open >/dev/null 2>&1; then \
			open http://localhost:3000; \
		else \
			echo "$(YELLOW)Could not detect browser. Open manually: http://localhost:3000$(RESET)"; \
		fi; \
	else \
		echo "$(RED)Grafana is not running. Run 'make install' first.$(RESET)"; \
	fi

disk-usage: ## Show disk space used by OIB volumes
	@echo ""
	@echo "$(BOLD)💾 OIB Disk Usage$(RESET)"
	@echo ""
	@echo "$(CYAN)Docker Volumes:$(RESET)"
	@docker system df -v 2>/dev/null | grep -E "oib-|VOLUME" | head -20 || echo "  No OIB volumes found"
	@echo ""
	@echo "$(CYAN)Total Docker disk usage:$(RESET)"
	@docker system df 2>/dev/null
	@echo ""

version: ## Show versions of all OIB components
	@echo ""
	@echo "$(BOLD)📦 OIB Component Versions$(RESET)"
	@echo ""
	@printf "  %-20s %s\n" "COMPONENT" "VERSION"
	@echo "  ────────────────────────────────────────"
	@docker inspect oib-grafana --format '  Grafana              {{.Config.Image}}' 2>/dev/null || echo "  Grafana              (not running)"
	@docker inspect oib-loki --format '  Loki                 {{.Config.Image}}' 2>/dev/null || echo "  Loki                 (not running)"
	@docker inspect oib-prometheus --format '  Prometheus           {{.Config.Image}}' 2>/dev/null || echo "  Prometheus           (not running)"
	@docker inspect oib-tempo --format '  Tempo                {{.Config.Image}}' 2>/dev/null || echo "  Tempo                (not running)"
	@docker inspect oib-alloy-logging --format '  Alloy (logging)      {{.Config.Image}}' 2>/dev/null || echo "  Alloy (logging)      (not running)"
	@docker inspect oib-alloy-metrics --format '  Alloy (metrics)      {{.Config.Image}}' 2>/dev/null || echo "  Alloy (metrics)      (not running)"
	@docker inspect oib-alloy-telemetry --format '  Alloy (telemetry)    {{.Config.Image}}' 2>/dev/null || echo "  Alloy (telemetry)    (not running)"
	@docker inspect oib-cadvisor --format '  cAdvisor             {{.Config.Image}}' 2>/dev/null || echo "  cAdvisor             (not running)"
	@echo ""

demo: ## Generate sample data to demonstrate all stacks
	@echo ""
	@echo "$(BOLD)🎬 Generating demo data...$(RESET)"
	@echo ""
	@echo "$(CYAN)1. Generating logs...$(RESET)"
	@for i in 1 2 3 4 5; do \
		docker run --rm --network oib-network --log-driver json-file alpine echo "Demo log message $$i from OIB at $$(date)"; \
	done
	@echo "   $(GREEN)✓$(RESET) Created 5 log entries"
	@echo ""
	@echo "$(CYAN)2. Sending sample trace...$(RESET)"
	@curl -s -X POST http://localhost:4318/v1/traces \
		-H "Content-Type: application/json" \
		-d '{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"oib-demo"}}]},"scopeSpans":[{"spans":[{"traceId":"00000000000000000000000000000001","spanId":"0000000000000001","name":"demo-span","kind":1,"startTimeUnixNano":"1234567890000000000","endTimeUnixNano":"1234567891000000000"}]}]}]}' \
		>/dev/null 2>&1 && \
		echo "   $(GREEN)✓$(RESET) Sent trace to Tempo" || \
		echo "   $(RED)✗$(RESET) Could not send trace (is Tempo running?)"
	@echo ""
	@echo "$(GREEN)$(BOLD)Demo complete!$(RESET) Open Grafana to see the data:"
	@echo "  $(YELLOW)http://localhost:3000$(RESET)"
	@echo ""
	@echo "  • $(CYAN)Logs:$(RESET)    Explore → Loki → Run query: {}"
	@echo "  • $(CYAN)Metrics:$(RESET) Explore → Prometheus → node_cpu_seconds_total"
	@echo "  • $(CYAN)Traces:$(RESET)  Explore → Tempo → Search for 'oib-demo'"
	@echo ""

demo-examples: ## Run example apps and generate traffic for all languages
	@echo ""
	@echo "$(BOLD)🧪 Running example apps...$(RESET)"
	@echo ""
	@$(MAKE) --no-print-directory network
	@for dir in examples/python-flask examples/node-express examples/ruby-rails examples/php-laravel; do \
		echo "$(CYAN)Starting $$dir...$(RESET)"; \
		cd $$dir && $(DOCKER_COMPOSE) up -d; \
		cd - >/dev/null; \
	done
	@echo ""
	@echo "$(CYAN)Waiting for apps to be ready...$(RESET)"
	@for url in http://localhost:5000/health http://localhost:3003/health http://localhost:3004/health http://localhost:3005/health; do \
		ok=false; \
		for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do \
			if curl -sf $$url >/dev/null 2>&1; then ok=true; break; fi; \
			sleep 1; \
		done; \
		if [ "$$ok" = "true" ]; then \
			echo "  $(GREEN)✓$(RESET) $$url"; \
		else \
			echo "  $(YELLOW)!$(RESET) $$url not responding (continuing)"; \
		fi; \
	done
	@echo ""
	@echo "$(CYAN)Generating traffic...$(RESET)"
	@for i in 1 2 3 4 5 6 7 8 9 10; do \
		curl -s http://localhost:5000/ >/dev/null; \
		curl -s http://localhost:5000/api/data >/dev/null; \
		curl -s http://localhost:5000/api/error >/dev/null 2>&1 || true; \
		curl -s http://localhost:3003/ >/dev/null; \
		curl -s http://localhost:3003/api/data >/dev/null; \
		curl -s http://localhost:3003/api/error >/dev/null 2>&1 || true; \
		curl -s http://localhost:3004/ >/dev/null; \
		curl -s http://localhost:3004/api/data >/dev/null; \
		curl -s http://localhost:3004/api/error >/dev/null 2>&1 || true; \
		curl -s http://localhost:3005/ >/dev/null; \
		curl -s http://localhost:3005/api/data >/dev/null; \
		curl -s http://localhost:3005/api/error >/dev/null 2>&1 || true; \
	done
	@echo ""
	@echo "$(GREEN)$(BOLD)Example traffic generated!$(RESET) Explore in Grafana:"
	@echo "  $(YELLOW)http://localhost:3000$(RESET)"
	@echo ""

demo-app: ## Start demo app with PostgreSQL & Redis (realistic traces)
	@echo ""
	@echo "$(BOLD)🚀 Starting Demo App with PostgreSQL & Redis...$(RESET)"
	@echo ""
	@$(MAKE) --no-print-directory network
	@cd examples/demo-app && $(DOCKER_COMPOSE) up -d --build
	@echo ""
	@echo "$(CYAN)Waiting for services...$(RESET)"
	@for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do \
		if curl -sf http://localhost:5000/health >/dev/null 2>&1; then \
			echo "  $(GREEN)✓$(RESET) Demo app is ready!"; \
			break; \
		fi; \
		sleep 1; \
	done
	@echo ""
	@echo "$(GREEN)$(BOLD)Demo App Started!$(RESET)"
	@echo ""
	@echo "  $(CYAN)App URL:$(RESET)      http://localhost:5000"
	@echo "  $(CYAN)PostgreSQL:$(RESET)   localhost:5432 (oib/oib_secret)"
	@echo "  $(CYAN)Redis:$(RESET)        localhost:6379"
	@echo ""
	@echo "$(CYAN)API Endpoints:$(RESET)"
	@echo "  GET  /           - API documentation"
	@echo "  GET  /health     - Health check (DB + Redis)"
	@echo "  GET  /users      - List users (DB query)"
	@echo "  GET  /users/:id  - Get user with items (multiple queries)"
	@echo "  GET  /items      - List items (cached in Redis)"
	@echo "  GET  /items/:id  - Get item with view counter (Redis incr)"
	@echo "  POST /orders     - Create order (transaction)"
	@echo "  GET  /orders     - List orders"
	@echo "  GET  /slow       - Slow endpoint (DB + cache)"
	@echo "  GET  /error      - Simulated errors"
	@echo ""
	@echo "$(YELLOW)Run 'make demo-traffic' to generate realistic traffic$(RESET)"
	@echo ""

demo-app-stop: ## Stop demo app and clean up
	@echo "$(CYAN)Stopping Demo App...$(RESET)"
	@cd examples/demo-app && $(DOCKER_COMPOSE) down -v
	@echo "$(GREEN)✓$(RESET) Demo app stopped"

demo-traffic: ## Generate traffic to demo app for realistic traces
	@echo ""
	@echo "$(BOLD)🔥 Generating Demo Traffic...$(RESET)"
	@echo ""
	@if ! curl -sf http://localhost:5000/health >/dev/null 2>&1; then \
		echo "$(RED)✗$(RESET) Demo app not running. Start with: make demo-app"; \
		exit 1; \
	fi
	@echo "$(CYAN)Generating 50 requests with realistic patterns...$(RESET)"
	@echo ""
	@for i in $$(seq 1 50); do \
		echo -n "."; \
		USER_ID=$$(( ($$i % 3) + 1 )); \
		ITEM_ID=$$(( ($$i % 5) + 1 )); \
		ITEM_ID2=$$(( (($$i + 2) % 5) + 1 )); \
		curl -s http://localhost:5000/ >/dev/null; \
		curl -s http://localhost:5000/health >/dev/null; \
		curl -s http://localhost:5000/users >/dev/null; \
		curl -s "http://localhost:5000/users/$$USER_ID" >/dev/null; \
		curl -s http://localhost:5000/items >/dev/null; \
		curl -s "http://localhost:5000/items/$$ITEM_ID" >/dev/null; \
		curl -s -X POST -H "Content-Type: application/json" \
			-d "{\"user_id\": $$USER_ID, \"item_ids\": [$$ITEM_ID, $$ITEM_ID2]}" \
			http://localhost:5000/orders >/dev/null; \
		curl -s http://localhost:5000/orders >/dev/null; \
		curl -s http://localhost:5000/slow >/dev/null; \
		if [ $$(( $$i % 10 )) -eq 0 ]; then \
			curl -s http://localhost:5000/error >/dev/null 2>&1 || true; \
		fi; \
		sleep 0.1; \
	done
	@echo ""
	@echo ""
	@echo "$(GREEN)$(BOLD)Traffic generation complete!$(RESET)"
	@echo ""
	@echo "Open Grafana to explore traces:"
	@echo "  $(YELLOW)http://localhost:3000$(RESET)"
	@echo ""
	@echo "  $(CYAN)Traces:$(RESET)  Explore → Tempo → Service: oib-demo-app"
	@echo "  $(CYAN)Logs:$(RESET)    Explore → Loki → {container_name=\"oib-demo-app\"}"
	@echo ""
	@echo "Look for multi-span traces showing:"
	@echo "  • HTTP request → PostgreSQL queries"
	@echo "  • HTTP request → Redis cache hit/miss"
	@echo "  • Transaction spans (order creation)"
	@echo ""

bootstrap: ## Install all stacks, generate demo data, and open Grafana
	@$(MAKE) --no-print-directory install
	@$(MAKE) --no-print-directory demo
	@$(MAKE) --no-print-directory open

# ==================== Load Testing ====================

test-load: network ## Run k6 basic load test against Grafana
	@echo "$(CYAN)🔥 Running k6 basic load test...$(RESET)"
	@echo "$(YELLOW)Target: http://oib-grafana:3000$(RESET)"
	@echo ""
	@cd testing && $(DOCKER_COMPOSE) --profile test run --rm k6 run /scripts/basic-load.js
	@echo ""
	@echo "$(GREEN)✓ Load test complete. Check the Request Latency dashboard in Grafana.$(RESET)"

test-stress: network ## Run k6 stress test to find breaking point
	@echo "$(CYAN)🔥 Running k6 stress test...$(RESET)"
	@echo "$(YELLOW)⚠️  This will push your system to its limits$(RESET)"
	@echo ""
	@cd testing && $(DOCKER_COMPOSE) --profile test run --rm k6 run /scripts/stress-test.js
	@echo ""
	@echo "$(GREEN)✓ Stress test complete. Check the Request Latency dashboard in Grafana.$(RESET)"

test-spike: network ## Run k6 spike test for sudden traffic
	@echo "$(CYAN)⚡ Running k6 spike test...$(RESET)"
	@echo "$(YELLOW)Simulating sudden traffic spikes$(RESET)"
	@echo ""
	@cd testing && $(DOCKER_COMPOSE) --profile test run --rm k6 run /scripts/spike-test.js
	@echo ""
	@echo "$(GREEN)✓ Spike test complete. Check the Request Latency dashboard in Grafana.$(RESET)"

test-api: network ## Run k6 API load test
	@echo "$(CYAN)📡 Running k6 API load test...$(RESET)"
	@echo ""
	@cd testing && $(DOCKER_COMPOSE) --profile test run --rm k6 run /scripts/api-load.js
	@echo ""
	@echo "$(GREEN)✓ API test complete. Check the Request Latency dashboard in Grafana.$(RESET)"

# ==================== Backup & Restore ====================

BACKUP_DIR := ./backups
TIMESTAMP := $(shell date +%Y%m%d_%H%M%S)

backup: ## Backup all OIB data volumes
	@echo ""
	@echo "$(BOLD)💾 Backing up all OIB data...$(RESET)"
	@echo ""
	@mkdir -p $(BACKUP_DIR)
	@$(MAKE) --no-print-directory backup-prometheus
	@$(MAKE) --no-print-directory backup-loki
	@$(MAKE) --no-print-directory backup-tempo
	@$(MAKE) --no-print-directory backup-grafana
	@echo ""
	@echo "$(GREEN)$(BOLD)✓ All backups complete!$(RESET)"
	@echo ""
	@echo "Backup location: $(YELLOW)$(BACKUP_DIR)/$(RESET)"
	@ls -lh $(BACKUP_DIR)/*.tar.gz 2>/dev/null | tail -10
	@echo ""

backup-prometheus: ## Backup Prometheus data
	@mkdir -p $(BACKUP_DIR)
	@echo "$(CYAN)Backing up Prometheus...$(RESET)"
	@if docker volume inspect oib-prometheus-data >/dev/null 2>&1; then \
		docker run --rm \
			-v oib-prometheus-data:/data:ro \
			-v $(PWD)/$(BACKUP_DIR):/backup \
			alpine tar czf /backup/prometheus_$(TIMESTAMP).tar.gz -C /data . && \
		echo "  $(GREEN)✓$(RESET) Prometheus backup: $(BACKUP_DIR)/prometheus_$(TIMESTAMP).tar.gz"; \
	else \
		echo "  $(YELLOW)!$(RESET) Prometheus volume not found (skipped)"; \
	fi

backup-loki: ## Backup Loki data
	@mkdir -p $(BACKUP_DIR)
	@echo "$(CYAN)Backing up Loki...$(RESET)"
	@if docker volume inspect oib-loki-data >/dev/null 2>&1; then \
		docker run --rm \
			-v oib-loki-data:/data:ro \
			-v $(PWD)/$(BACKUP_DIR):/backup \
			alpine tar czf /backup/loki_$(TIMESTAMP).tar.gz -C /data . && \
		echo "  $(GREEN)✓$(RESET) Loki backup: $(BACKUP_DIR)/loki_$(TIMESTAMP).tar.gz"; \
	else \
		echo "  $(YELLOW)!$(RESET) Loki volume not found (skipped)"; \
	fi

backup-tempo: ## Backup Tempo data
	@mkdir -p $(BACKUP_DIR)
	@echo "$(CYAN)Backing up Tempo...$(RESET)"
	@if docker volume inspect oib-tempo-data >/dev/null 2>&1; then \
		docker run --rm \
			-v oib-tempo-data:/data:ro \
			-v $(PWD)/$(BACKUP_DIR):/backup \
			alpine tar czf /backup/tempo_$(TIMESTAMP).tar.gz -C /data . && \
		echo "  $(GREEN)✓$(RESET) Tempo backup: $(BACKUP_DIR)/tempo_$(TIMESTAMP).tar.gz"; \
	else \
		echo "  $(YELLOW)!$(RESET) Tempo volume not found (skipped)"; \
	fi

backup-grafana: ## Backup Grafana data
	@mkdir -p $(BACKUP_DIR)
	@echo "$(CYAN)Backing up Grafana...$(RESET)"
	@if docker volume inspect oib-grafana-data >/dev/null 2>&1; then \
		docker run --rm \
			-v oib-grafana-data:/data:ro \
			-v $(PWD)/$(BACKUP_DIR):/backup \
			alpine tar czf /backup/grafana_$(TIMESTAMP).tar.gz -C /data . && \
		echo "  $(GREEN)✓$(RESET) Grafana backup: $(BACKUP_DIR)/grafana_$(TIMESTAMP).tar.gz"; \
	else \
		echo "  $(YELLOW)!$(RESET) Grafana volume not found (skipped)"; \
	fi

restore: ## Restore all OIB data (interactive)
	@echo ""
	@echo "$(BOLD)📥 Restore OIB Data$(RESET)"
	@echo ""
	@echo "$(YELLOW)Available backups:$(RESET)"
	@ls -lh $(BACKUP_DIR)/*.tar.gz 2>/dev/null || echo "  No backups found in $(BACKUP_DIR)/"
	@echo ""
	@echo "$(CYAN)To restore a specific component, use:$(RESET)"
	@echo "  make restore-prometheus FILE=./backups/prometheus_YYYYMMDD_HHMMSS.tar.gz"
	@echo "  make restore-loki FILE=./backups/loki_YYYYMMDD_HHMMSS.tar.gz"
	@echo "  make restore-tempo FILE=./backups/tempo_YYYYMMDD_HHMMSS.tar.gz"
	@echo "  make restore-grafana FILE=./backups/grafana_YYYYMMDD_HHMMSS.tar.gz"
	@echo ""

restore-prometheus: ## Restore Prometheus data (FILE=path/to/backup.tar.gz)
	@if [ -z "$(FILE)" ]; then \
		echo "$(RED)Error: FILE parameter required$(RESET)"; \
		echo "Usage: make restore-prometheus FILE=./backups/prometheus_YYYYMMDD_HHMMSS.tar.gz"; \
		exit 1; \
	fi
	@if [ ! -f "$(FILE)" ]; then \
		echo "$(RED)Error: File not found: $(FILE)$(RESET)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)$(BOLD)⚠️  WARNING: This will overwrite existing Prometheus data!$(RESET)"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ] || (echo "Cancelled." && exit 1)
	@echo "$(CYAN)Stopping Prometheus...$(RESET)"
	@cd metrics && $(DOCKER_COMPOSE) stop prometheus 2>/dev/null || true
	@echo "$(CYAN)Restoring from $(FILE)...$(RESET)"
	@docker run --rm \
		-v oib-prometheus-data:/data \
		-v $(PWD)/$(FILE):/backup.tar.gz:ro \
		alpine sh -c "rm -rf /data/* && tar xzf /backup.tar.gz -C /data"
	@echo "$(CYAN)Starting Prometheus...$(RESET)"
	@cd metrics && $(DOCKER_COMPOSE) start prometheus
	@echo "$(GREEN)✓ Prometheus restored from $(FILE)$(RESET)"

restore-loki: ## Restore Loki data (FILE=path/to/backup.tar.gz)
	@if [ -z "$(FILE)" ]; then \
		echo "$(RED)Error: FILE parameter required$(RESET)"; \
		echo "Usage: make restore-loki FILE=./backups/loki_YYYYMMDD_HHMMSS.tar.gz"; \
		exit 1; \
	fi
	@if [ ! -f "$(FILE)" ]; then \
		echo "$(RED)Error: File not found: $(FILE)$(RESET)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)$(BOLD)⚠️  WARNING: This will overwrite existing Loki data!$(RESET)"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ] || (echo "Cancelled." && exit 1)
	@echo "$(CYAN)Stopping Loki...$(RESET)"
	@cd logging && $(DOCKER_COMPOSE) stop loki 2>/dev/null || true
	@echo "$(CYAN)Restoring from $(FILE)...$(RESET)"
	@docker run --rm \
		-v oib-loki-data:/data \
		-v $(PWD)/$(FILE):/backup.tar.gz:ro \
		alpine sh -c "rm -rf /data/* && tar xzf /backup.tar.gz -C /data"
	@echo "$(CYAN)Starting Loki...$(RESET)"
	@cd logging && $(DOCKER_COMPOSE) start loki
	@echo "$(GREEN)✓ Loki restored from $(FILE)$(RESET)"

restore-tempo: ## Restore Tempo data (FILE=path/to/backup.tar.gz)
	@if [ -z "$(FILE)" ]; then \
		echo "$(RED)Error: FILE parameter required$(RESET)"; \
		echo "Usage: make restore-tempo FILE=./backups/tempo_YYYYMMDD_HHMMSS.tar.gz"; \
		exit 1; \
	fi
	@if [ ! -f "$(FILE)" ]; then \
		echo "$(RED)Error: File not found: $(FILE)$(RESET)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)$(BOLD)⚠️  WARNING: This will overwrite existing Tempo data!$(RESET)"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ] || (echo "Cancelled." && exit 1)
	@echo "$(CYAN)Stopping Tempo...$(RESET)"
	@cd telemetry && $(DOCKER_COMPOSE) stop tempo 2>/dev/null || true
	@echo "$(CYAN)Restoring from $(FILE)...$(RESET)"
	@docker run --rm \
		-v oib-tempo-data:/data \
		-v $(PWD)/$(FILE):/backup.tar.gz:ro \
		alpine sh -c "rm -rf /data/* && tar xzf /backup.tar.gz -C /data"
	@echo "$(CYAN)Starting Tempo...$(RESET)"
	@cd telemetry && $(DOCKER_COMPOSE) start tempo
	@echo "$(GREEN)✓ Tempo restored from $(FILE)$(RESET)"

restore-grafana: ## Restore Grafana data (FILE=path/to/backup.tar.gz)
	@if [ -z "$(FILE)" ]; then \
		echo "$(RED)Error: FILE parameter required$(RESET)"; \
		echo "Usage: make restore-grafana FILE=./backups/grafana_YYYYMMDD_HHMMSS.tar.gz"; \
		exit 1; \
	fi
	@if [ ! -f "$(FILE)" ]; then \
		echo "$(RED)Error: File not found: $(FILE)$(RESET)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)$(BOLD)⚠️  WARNING: This will overwrite existing Grafana data!$(RESET)"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ] || (echo "Cancelled." && exit 1)
	@echo "$(CYAN)Stopping Grafana...$(RESET)"
	@cd grafana && $(DOCKER_COMPOSE) stop grafana 2>/dev/null || true
	@echo "$(CYAN)Restoring from $(FILE)...$(RESET)"
	@docker run --rm \
		-v oib-grafana-data:/data \
		-v $(PWD)/$(FILE):/backup.tar.gz:ro \
		alpine sh -c "rm -rf /data/* && tar xzf /backup.tar.gz -C /data"
	@echo "$(CYAN)Starting Grafana...$(RESET)"
	@cd grafana && $(DOCKER_COMPOSE) start grafana
	@echo "$(GREEN)✓ Grafana restored from $(FILE)$(RESET)"
