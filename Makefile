.PHONY: help install install-logging install-metrics install-telemetry \
        start start-logging start-metrics start-telemetry \
        stop stop-logging stop-metrics stop-telemetry \
        restart restart-logging restart-metrics restart-telemetry \
        uninstall uninstall-logging uninstall-metrics uninstall-telemetry \
        status info info-logging info-metrics info-telemetry \
        logs logs-logging logs-metrics logs-telemetry \
        network

# Colors
CYAN := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
RESET := \033[0m
BOLD := \033[1m

# Docker compose command
DOCKER_COMPOSE := docker compose

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
	@grep -E '^(install|install-logging|install-metrics|install-telemetry):.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(CYAN)Management:$(RESET)"
	@grep -E '^(start|stop|restart|status|info|logs)[^-]*:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(CYAN)Cleanup:$(RESET)"
	@grep -E '^uninstall[^-]*:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(CYAN)Stack-specific commands:$(RESET)"
	@echo "  Append $(YELLOW)-logging$(RESET), $(YELLOW)-metrics$(RESET), or $(YELLOW)-telemetry$(RESET) to most commands"
	@echo "  Example: make install-logging, make stop-metrics, make logs-telemetry"
	@echo ""

# ==================== Network ====================

network: ## Create shared Docker network
	@docker network inspect oib-network >/dev/null 2>&1 || \
		(docker network create oib-network && echo "$(GREEN)✓ Created oib-network$(RESET)")

# ==================== Installation ====================

install: network install-logging install-metrics install-telemetry ## Install all observability stacks
	@echo ""
	@echo "$(GREEN)$(BOLD)✓ All stacks installed successfully!$(RESET)"
	@echo ""
	@$(MAKE) --no-print-directory info

install-logging: network ## Install logging stack (Loki + Promtail + Grafana)
	@echo "$(CYAN)📋 Installing Logging Stack...$(RESET)"
	@cd logging && $(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)✓ Logging stack installed$(RESET)"
	@echo ""
	@$(MAKE) --no-print-directory info-logging

install-metrics: network ## Install metrics stack (Prometheus + Grafana)
	@echo "$(CYAN)📊 Installing Metrics Stack...$(RESET)"
	@cd metrics && $(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)✓ Metrics stack installed$(RESET)"
	@echo ""
	@$(MAKE) --no-print-directory info-metrics

install-telemetry: network ## Install telemetry stack (Tempo + OTEL Collector + Grafana)
	@echo "$(CYAN)🔭 Installing Telemetry Stack...$(RESET)"
	@cd telemetry && $(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)✓ Telemetry stack installed$(RESET)"
	@echo ""
	@$(MAKE) --no-print-directory info-telemetry

# ==================== Start ====================

start: start-logging start-metrics start-telemetry ## Start all stacks
	@echo "$(GREEN)✓ All stacks started$(RESET)"

start-logging: ## Start logging stack
	@cd logging && $(DOCKER_COMPOSE) start

start-metrics: ## Start metrics stack
	@cd metrics && $(DOCKER_COMPOSE) start

start-telemetry: ## Start telemetry stack
	@cd telemetry && $(DOCKER_COMPOSE) start

# ==================== Stop ====================

stop: stop-logging stop-metrics stop-telemetry ## Stop all stacks
	@echo "$(GREEN)✓ All stacks stopped$(RESET)"

stop-logging: ## Stop logging stack
	@cd logging && $(DOCKER_COMPOSE) stop

stop-metrics: ## Stop metrics stack
	@cd metrics && $(DOCKER_COMPOSE) stop

stop-telemetry: ## Stop telemetry stack
	@cd telemetry && $(DOCKER_COMPOSE) stop

# ==================== Restart ====================

restart: restart-logging restart-metrics restart-telemetry ## Restart all stacks
	@echo "$(GREEN)✓ All stacks restarted$(RESET)"

restart-logging: ## Restart logging stack
	@cd logging && $(DOCKER_COMPOSE) restart

restart-metrics: ## Restart metrics stack
	@cd metrics && $(DOCKER_COMPOSE) restart

restart-telemetry: ## Restart telemetry stack
	@cd telemetry && $(DOCKER_COMPOSE) restart

# ==================== Uninstall ====================

uninstall: uninstall-logging uninstall-metrics uninstall-telemetry ## Remove all stacks and volumes
	@docker network rm oib-network 2>/dev/null || true
	@echo "$(GREEN)✓ All stacks removed$(RESET)"

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

# ==================== Status ====================

status: ## Show status of all stacks
	@echo ""
	@echo "$(BOLD)📋 Logging Stack$(RESET)"
	@cd logging && $(DOCKER_COMPOSE) ps 2>/dev/null || echo "  Not installed"
	@echo ""
	@echo "$(BOLD)📊 Metrics Stack$(RESET)"
	@cd metrics && $(DOCKER_COMPOSE) ps 2>/dev/null || echo "  Not installed"
	@echo ""
	@echo "$(BOLD)🔭 Telemetry Stack$(RESET)"
	@cd telemetry && $(DOCKER_COMPOSE) ps 2>/dev/null || echo "  Not installed"
	@echo ""

# ==================== Info ====================

info: ## Show integration endpoints for all stacks
	@echo ""
	@echo "$(BOLD)════════════════════════════════════════════════════════════════$(RESET)"
	@echo "$(BOLD)           🔭 Observability in a Box - Integration Guide$(RESET)"
	@echo "$(BOLD)════════════════════════════════════════════════════════════════$(RESET)"
	@$(MAKE) --no-print-directory info-logging
	@$(MAKE) --no-print-directory info-metrics
	@$(MAKE) --no-print-directory info-telemetry

info-logging: ## Show logging integration info
	@echo ""
	@echo "$(BOLD)$(CYAN)📋 LOGGING STACK (Loki + Alloy)$(RESET)"
	@echo "$(BOLD)────────────────────────────────────────$(RESET)"
	@echo ""
	@echo "$(GREEN)Grafana Dashboard:$(RESET)"
	@echo "  URL:      $(YELLOW)http://localhost:3000$(RESET)"
	@echo "  Login:    admin / admin"
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
	@echo "$(GREEN)Optional: Docker Logging Driver:$(RESET)"
	@echo "  Add to your docker-compose.yml:"
	@echo "  $(CYAN)logging:$(RESET)"
	@echo "  $(CYAN)  driver: loki$(RESET)"
	@echo "  $(CYAN)  options:$(RESET)"
	@echo "  $(CYAN)    loki-url: \"http://host.docker.internal:3100/loki/api/v1/push\"$(RESET)"
	@echo ""

info-metrics: ## Show metrics integration info
	@echo ""
	@echo "$(BOLD)$(CYAN)📊 METRICS STACK$(RESET)"
	@echo "$(BOLD)────────────────────────────────────────$(RESET)"
	@echo ""
	@echo "$(GREEN)Grafana Dashboard:$(RESET)"
	@echo "  URL:      $(YELLOW)http://localhost:3001$(RESET)"
	@echo "  Login:    admin / admin"
	@echo ""
	@echo "$(GREEN)Prometheus UI:$(RESET)"
	@echo "  URL:      $(YELLOW)http://localhost:9090$(RESET)"
	@echo ""
	@echo "$(GREEN)Prometheus Pushgateway:$(RESET)"
	@echo "  URL:      $(YELLOW)http://localhost:9091$(RESET)"
	@echo ""
	@echo "$(GREEN)Add scrape target:$(RESET)"
	@echo "  Edit $(CYAN)metrics/config/prometheus.yml$(RESET) and add:"
	@echo "  $(CYAN)- job_name: 'my-app'$(RESET)"
	@echo "  $(CYAN)  static_configs:$(RESET)"
	@echo "  $(CYAN)    - targets: ['host.docker.internal:8080']$(RESET)"
	@echo ""

info-telemetry: ## Show telemetry integration info
	@echo ""
	@echo "$(BOLD)$(CYAN)🔭 TELEMETRY STACK (Tempo + Alloy)$(RESET)"
	@echo "$(BOLD)────────────────────────────────────────$(RESET)"
	@echo ""
	@echo "$(GREEN)Grafana Dashboard:$(RESET)"
	@echo "  URL:      $(YELLOW)http://localhost:3002$(RESET)"
	@echo "  Login:    admin / admin"
	@echo ""
	@echo "$(GREEN)Alloy UI:$(RESET)"
	@echo "  URL:      $(YELLOW)http://localhost:12346$(RESET)"
	@echo ""
	@echo "$(GREEN)OpenTelemetry Endpoints (via Alloy):$(RESET)"
	@echo "  OTLP gRPC:  $(YELLOW)localhost:4317$(RESET)"
	@echo "  OTLP HTTP:  $(YELLOW)http://localhost:4318$(RESET)"
	@echo ""
	@echo "$(GREEN)Configure your app:$(RESET)"
	@echo "  Set environment variable:"
	@echo "  $(CYAN)OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318$(RESET)"
	@echo ""
	@echo "$(GREEN)Python example:$(RESET)"
	@echo "  $(CYAN)from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter$(RESET)"
	@echo "  $(CYAN)exporter = OTLPSpanExporter(endpoint=\"localhost:4317\", insecure=True)$(RESET)"
	@echo ""

# ==================== Logs ====================

logs: ## Tail logs from all stacks
	@echo "$(CYAN)Tailing all stack logs (Ctrl+C to stop)...$(RESET)"
	@docker compose -f logging/docker-compose.yml -f metrics/docker-compose.yml -f telemetry/docker-compose.yml logs -f

logs-logging: ## Tail logging stack logs
	@cd logging && $(DOCKER_COMPOSE) logs -f

logs-metrics: ## Tail metrics stack logs
	@cd metrics && $(DOCKER_COMPOSE) logs -f

logs-telemetry: ## Tail telemetry stack logs
	@cd telemetry && $(DOCKER_COMPOSE) logs -f
