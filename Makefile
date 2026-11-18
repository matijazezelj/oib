.PHONY: help preflight install install-grafana install-logging install-metrics install-telemetry install-profiling install-services \
        start start-grafana start-logging start-metrics start-telemetry start-profiling start-services \
        stop stop-grafana stop-logging stop-metrics stop-telemetry stop-profiling stop-services \
        restart restart-grafana restart-logging restart-metrics restart-telemetry restart-profiling restart-services \
        uninstall uninstall-grafana uninstall-logging uninstall-metrics uninstall-telemetry uninstall-profiling uninstall-services \
        status info info-grafana info-logging info-metrics info-telemetry info-profiling info-services \
        logs logs-grafana logs-logging logs-metrics logs-telemetry logs-profiling logs-services \
        install-mcp uninstall-mcp logs-mcp mcp-config test-mcp ask test-ask \
        network health doctor check-ports update update-grafana update-logging update-metrics update-telemetry update-profiling latest \
        clean ps validate open disk-usage version demo demo-examples demo-app demo-app-stop demo-traffic bootstrap \
        test-load test-stress test-spike test-api test-backup test-upgrade test-tempo-recovery test-isolation test-restricted \
        backup backup-prometheus backup-loki backup-tempo backup-grafana backup-pyroscope \
        migrate-grafana-volume migrate-tempo rollback-tempo tempo-guard restore restore-all restore-prometheus restore-loki restore-tempo restore-grafana restore-pyroscope

# Colors - real ESC bytes, so plain `echo` renders them under both dash and bash
CYAN := $(shell printf '\033[36m')
GREEN := $(shell printf '\033[32m')
YELLOW := $(shell printf '\033[33m')
RED := $(shell printf '\033[31m')
RESET := $(shell printf '\033[0m')
BOLD := $(shell printf '\033[1m')

# Read only endpoint values needed by Make and emit them only when they match
# their expected grammar. Raw .env text must never be spliced into shell recipes.
env_port = $(strip $(shell awk -F= '$$1 == "$(1)" { v=substr($$0,index($$0,"=")+1); if (v ~ /^[0-9]+$$/) print v; exit }' "$(CURDIR)/.env" 2>/dev/null))
env_addr = $(strip $(shell awk -F= '$$1 == "$(1)" { v=substr($$0,index($$0,"=")+1); if (v ~ /^[A-Za-z0-9_.:-]+$$/) print v; exit }' "$(CURDIR)/.env" 2>/dev/null))

# Deployment mode, read from .env (see .env.example):
#   standard   - everything, including the collectors that need the Docker
#                socket and host mounts (cAdvisor, Alloy container logs)
#   restricted - no Docker socket, host root filesystem or added capabilities;
#                each stack's compose.restricted.yaml is layered over compose.yaml
OIB_MODE := $(or $(call env_addr,OIB_MODE),standard)
ifeq ($(filter standard restricted,$(OIB_MODE)),)
$(error OIB_MODE in .env must be standard or restricted, not '$(OIB_MODE)')
endif
RESTRICTED := $(filter restricted,$(OIB_MODE))
# Evaluated by the shell in the stack directory each recipe cd's into, so stacks
# without a compose.restricted.yaml run unchanged.
COMPOSE_MODE_FILES := $(if $(RESTRICTED),$$(test -f compose.restricted.yaml && echo -f compose.yaml -f compose.restricted.yaml))

# Docker compose command - include root .env file for all stacks
DOCKER_COMPOSE := docker compose --env-file $(CURDIR)/.env $(COMPOSE_MODE_FILES)

BIND_ADDR := $(or $(call env_addr,BIND_ADDR),127.0.0.1)
GRAFANA_PORT := $(or $(call env_port,GRAFANA_PORT),3000)
LOKI_PORT := $(or $(call env_port,LOKI_PORT),3100)
ALLOY_LOGGING_PORT := $(or $(call env_port,ALLOY_LOGGING_PORT),12345)
PROMETHEUS_PORT := $(or $(call env_port,PROMETHEUS_PORT),9090)
ALLOY_METRICS_PORT := $(or $(call env_port,ALLOY_METRICS_PORT),12347)
CADVISOR_PORT := $(or $(call env_port,CADVISOR_PORT),8080)
BLACKBOX_PORT := $(or $(call env_port,BLACKBOX_PORT),9115)
TEMPO_HTTP_PORT := $(or $(call env_port,TEMPO_HTTP_PORT),3200)
TEMPO_GRPC_PORT := $(or $(call env_port,TEMPO_GRPC_PORT),9095)
OTEL_BIND_ADDR := $(or $(call env_addr,OTEL_BIND_ADDR),127.0.0.1)
OTEL_GRPC_PORT := $(or $(call env_port,OTEL_GRPC_PORT),4317)
OTEL_HTTP_PORT := $(or $(call env_port,OTEL_HTTP_PORT),4318)
ALLOY_TELEMETRY_PORT := $(or $(call env_port,ALLOY_TELEMETRY_PORT),12346)
PYROSCOPE_PORT := $(or $(call env_port,PYROSCOPE_PORT),4040)
MCP_PORT := $(or $(call env_port,MCP_PORT),3030)

GRAFANA_CONNECT_HOST := $(if $(filter 0.0.0.0,$(BIND_ADDR)),127.0.0.1,$(BIND_ADDR))
OTEL_CONNECT_HOST := $(if $(filter 0.0.0.0,$(OTEL_BIND_ADDR)),127.0.0.1,$(OTEL_BIND_ADDR))
GRAFANA_URL := http://$(GRAFANA_CONNECT_HOST):$(GRAFANA_PORT)
LOKI_URL := http://127.0.0.1:$(LOKI_PORT)
ALLOY_LOGGING_URL := http://127.0.0.1:$(ALLOY_LOGGING_PORT)
PROMETHEUS_URL := http://127.0.0.1:$(PROMETHEUS_PORT)
ALLOY_METRICS_URL := http://127.0.0.1:$(ALLOY_METRICS_PORT)
CADVISOR_URL := http://127.0.0.1:$(CADVISOR_PORT)
BLACKBOX_URL := http://127.0.0.1:$(BLACKBOX_PORT)
TEMPO_URL := http://127.0.0.1:$(TEMPO_HTTP_PORT)
ALLOY_TELEMETRY_URL := http://127.0.0.1:$(ALLOY_TELEMETRY_PORT)
OTEL_HTTP_URL := http://$(OTEL_CONNECT_HOST):$(OTEL_HTTP_PORT)
PYROSCOPE_URL := http://127.0.0.1:$(PYROSCOPE_PORT)
MCP_URL := http://127.0.0.1:$(MCP_PORT)

CORE_PORTS := $(GRAFANA_PORT) $(LOKI_PORT) $(ALLOY_LOGGING_PORT) $(PROMETHEUS_PORT) \
              $(ALLOY_METRICS_PORT) $(CADVISOR_PORT) $(BLACKBOX_PORT) \
              $(TEMPO_HTTP_PORT) $(TEMPO_GRPC_PORT) $(OTEL_GRPC_PORT) \
              $(OTEL_HTTP_PORT) $(ALLOY_TELEMETRY_PORT)

# Confirmation prompt; YES=1 skips it (for scripts and tests).
# Use as a shell command: @$(call confirm,Question?)
confirm = if [ "$(YES)" != "1" ]; then printf "$(1) [y/N] "; read confirm; case "$$confirm" in [yY]) ;; *) echo "Cancelled."; exit 1 ;; esac; fi

# Debug mode - set DEBUG=1 to enable verbose output
DEBUG ?= 0
ifeq ($(DEBUG),1)
  DOCKER_COMPOSE += --verbose
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
	@grep -E '^(install|install-grafana|install-logging|install-metrics|install-telemetry|install-profiling|install-mcp|mcp-config):.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(CYAN)Management:$(RESET)"
	@grep -E '^(start|stop|restart|status|info|logs)[^-]*:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(CYAN)Health & Diagnostics:$(RESET)"
	@grep -E '^(preflight|health|doctor|check-ports|ps|validate):.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(CYAN)Load Testing:$(RESET)"
	@grep -E '^(test-load|test-stress|test-spike|test-api):.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(CYAN)Acceptance Tests (delete all OIB data):$(RESET)"
	@grep -E '^(test-backup|test-upgrade|test-tempo-recovery|test-restricted|test-mcp|test-ask|test-isolation):.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(CYAN)Utilities:$(RESET)"
	@grep -E '^(ask|open|disk-usage|version|demo|demo-app|demo-app-stop|demo-traffic|demo-examples|bootstrap):.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(CYAN)Maintenance:$(RESET)"
	@grep -E '^(update|update-grafana|update-logging|update-metrics|update-telemetry|update-profiling|latest|clean|migrate-tempo|rollback-tempo|migrate-grafana-volume):.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(CYAN)Backup & Restore:$(RESET)"
	@grep -E '^(backup|restore|restore-all):.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(RESET) %s\n", $$1, $$2}'
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

preflight: ## Check prerequisites and port conflicts before first install
	@docker info >/dev/null 2>&1 || { echo "$(RED)✗ Docker is not running. Please start Docker first.$(RESET)"; exit 1; }
	@docker compose version >/dev/null 2>&1 || { echo "$(RED)✗ Docker Compose v2+ is required.$(RESET)"; exit 1; }
	@duplicates=$$(printf '%s\n' $(CORE_PORTS) | sort | uniq -d | tr '\n' ' '); \
	if [ -n "$$duplicates" ]; then \
		echo "$(RED)✗ The same host port is configured more than once: $$duplicates$(RESET)"; \
		echo "$(YELLOW)  Give each endpoint a unique port in .env.$(RESET)"; \
		exit 1; \
	fi
	@if command -v lsof >/dev/null 2>&1; then \
		conflicts=""; \
		for port in $(CORE_PORTS); do \
			if lsof -nP -iTCP:$$port -sTCP:LISTEN >/dev/null 2>&1 && \
			   ! docker ps --filter "publish=$$port" --format '{{.Names}}' | grep -q '^oib-'; then \
				conflicts="$$conflicts $$port"; \
			fi; \
		done; \
		if [ -n "$$conflicts" ]; then \
			echo "$(RED)✗ Required port(s) already in use:$$conflicts$(RESET)"; \
			echo "$(YELLOW)  Change the corresponding values in .env, then run make install again.$(RESET)"; \
			exit 1; \
		fi; \
	else \
		echo "$(YELLOW)! lsof is unavailable; skipping host port preflight.$(RESET)"; \
	fi

network: ## Create shared Docker network
	@docker info >/dev/null 2>&1 || { echo "$(RED)✗ Docker is not running. Please start Docker first.$(RESET)"; exit 1; }
	@docker network inspect oib-network >/dev/null 2>&1 || { \
		docker network create oib-network && \
		echo "$(GREEN)✓ Created oib-network$(RESET)" || \
		{ echo "$(RED)✗ Failed to create oib-network$(RESET)"; exit 1; }; \
	}

# ==================== Installation ====================

install: tempo-guard ## Install all observability stacks
	@if [ ! -f .env ]; then \
		echo "$(YELLOW)! No .env file found. Creating from .env.example...$(RESET)"; \
		cp .env.example .env; \
		echo "$(YELLOW)! Please edit .env and set a secure GRAFANA_ADMIN_PASSWORD$(RESET)"; \
		echo ""; \
		exit 1; \
	fi
	@if ! grep -Eq '^GRAFANA_ADMIN_PASSWORD=.+$$' .env 2>/dev/null || grep -Eq '^GRAFANA_ADMIN_PASSWORD=CHANGE_ME' .env 2>/dev/null; then \
		echo "$(RED)$(BOLD)✗ Grafana admin password is empty or still a placeholder$(RESET)"; \
		echo "$(YELLOW)  Set GRAFANA_ADMIN_PASSWORD before starting OIB.$(RESET)"; \
		echo ""; \
		exit 1; \
	fi
	@$(MAKE) --no-print-directory preflight
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
	@echo "  $(BOLD)Open Grafana:$(RESET)       $(YELLOW)$(GRAFANA_URL)$(RESET)"
	@echo "  $(BOLD)Send traces to:$(RESET)     $(YELLOW)$(OTEL_CONNECT_HOST):$(OTEL_GRPC_PORT)$(RESET) (gRPC) or $(YELLOW)$(OTEL_HTTP_URL)$(RESET) (HTTP)"
	@echo ""
	@echo "$(CYAN)Next steps:$(RESET)"
	@echo "  $(GREEN)make demo$(RESET)      Generate sample data to explore"
	@echo "  $(GREEN)make open$(RESET)      Open Grafana in browser"
	@echo "  $(GREEN)make health$(RESET)    Verify all services are healthy"
	@echo "  $(GREEN)make info$(RESET)      Show all integration endpoints"
	@echo ""

install-grafana: network ## Install Grafana (unified dashboard)
	@echo "$(CYAN)📊 Installing Grafana...$(RESET)"
	@$(MAKE) --no-print-directory migrate-grafana-volume
	@cd grafana && $(DOCKER_COMPOSE) up -d --remove-orphans
	@echo "$(GREEN)✓ Grafana installed$(RESET)"

# ==================== Tempo 2 -> 3 migration ====================
# Tempo 3 ignores the Tempo 2 write-ahead log, so traces Tempo 2 has not yet
# flushed to a block are lost if Tempo is simply recreated on the new image.
# tempo-guard stops install/update while Tempo 2 is still running;
# migrate-tempo flushes it first, backs it up, then upgrades it.

tempo_major = $$(docker inspect -f '{{.Config.Image}}' oib-tempo 2>/dev/null | sed -n 's/.*tempo:v\{0,1\}\([0-9][0-9]*\)\..*/\1/p')

tempo-guard:
	@major=$(tempo_major); \
	if [ "$$major" = "2" ] && [ "$(SKIP_TEMPO_MIGRATION)" != "1" ]; then \
		echo "$(RED)$(BOLD)✗ Tempo 2 is installed; this version runs Tempo 3.$(RESET)"; \
		echo "  Upgrading by recreating the container drops every trace Tempo 2 has not flushed"; \
		echo "  to disk yet (up to the last 5 minutes). Migrate first, then run your command again:"; \
		echo "    $(GREEN)make migrate-tempo$(RESET)   (flushes Tempo 2, backs it up, upgrades to Tempo 3)"; \
		echo "  To upgrade anyway and accept the loss: add SKIP_TEMPO_MIGRATION=1"; \
		exit 1; \
	fi

TEMPO_ROLLBACK_DIR = $(abspath $(BACKUP_DIR))/tempo2-rollback

migrate-tempo: ## Upgrade Tempo 2 -> 3 without losing traces (flush, backup, upgrade)
	@major=$(tempo_major); \
	if [ "$$major" != "2" ]; then echo "$(GREEN)✓$(RESET) Tempo is not on version 2 ($$(docker inspect -f '{{.Config.Image}}' oib-tempo 2>/dev/null || echo 'not installed')); nothing to migrate."; exit 0; fi; \
	if [ "$$(docker inspect -f '{{.State.Running}}' oib-tempo)" != "true" ]; then \
		echo "$(RED)✗ Tempo 2 is not running, so it cannot flush its write-ahead log.$(RESET)"; \
		echo "  Start it from the previous OIB release, or upgrade without flushing: make update SKIP_TEMPO_MIGRATION=1"; \
		exit 1; \
	fi; \
	echo "$(CYAN)[1/5] Pulling the new telemetry images...$(RESET)"; \
	(cd telemetry && $(DOCKER_COMPOSE) pull -q) || { echo "$(RED)✗ Pull failed; nothing was changed, Tempo 2 keeps running.$(RESET)"; exit 1; }; \
	dryrun() { \
		docker rm -f oib-tempo-dryrun >/dev/null 2>&1; \
		docker run -d --name oib-tempo-dryrun --tmpfs /var/tempo:mode=1777 -v "$$2":/etc/tempo/tempo.yaml:ro "$$1" -config.file=/etc/tempo/tempo.yaml >/dev/null || return 1; \
		i=0; until docker logs oib-tempo-dryrun 2>&1 | grep -q 'msg="Tempo started"'; do \
			i=$$((i+1)); \
			if [ $$i -gt 60 ] || [ "$$(docker inspect -f '{{.State.Running}}' oib-tempo-dryrun)" != true ]; then \
				docker logs --tail 8 oib-tempo-dryrun 2>&1 | sed 's/^/    /'; docker rm -f oib-tempo-dryrun >/dev/null 2>&1; return 1; \
			fi; sleep 1; \
		done; \
		docker rm -f oib-tempo-dryrun >/dev/null 2>&1; \
	}; \
	echo "$(CYAN)[2/5] Dry run: starting the new Tempo with the new config in a scratch container...$(RESET)"; \
	img=$$(cd telemetry && $(DOCKER_COMPOSE) config --images 2>/dev/null | grep '/tempo:' | head -1); \
	cfg="$${TEMPO_CONFIG:-./config/tempo.yaml}"; case "$$cfg" in /*) ;; *) cfg="$(CURDIR)/telemetry/$${cfg#./}" ;; esac; \
	dryrun "$$img" "$$cfg" || { echo "$(RED)✗ $$img does not start with $$cfg; nothing was changed, Tempo 2 keeps running.$(RESET)"; exit 1; }; \
	echo "  $(GREEN)✓$(RESET) $$img starts with the new config"; \
	echo "$(CYAN)[3/5] Backing up Tempo 2 and saving what make rollback-tempo needs...$(RESET)"; \
	snap="$(TEMPO_ROLLBACK_DIR)"; mkdir -p "$$snap"; \
	old_img=$$(docker inspect -f '{{.Config.Image}}' oib-tempo); \
	if [ "$(NO_ROLLBACK)" = 1 ]; then \
		echo "  $(YELLOW)!$(RESET) NO_ROLLBACK=1: no rollback snapshot; make rollback-tempo will not be available"; \
		for f in image tempo.yaml backup; do [ -e "$$snap/$$f" ] && mv -f "$$snap/$$f" "$$snap/$$f.old"; done; \
	else \
		docker cp oib-tempo:/etc/tempo/tempo.yaml "$$snap/tempo.yaml.new" >/dev/null 2>&1 \
			|| { echo "$(RED)✗ Could not copy Tempo 2's config out of the container; nothing was changed.$(RESET)"; exit 1; }; \
		dryrun "$$old_img" "$$snap/tempo.yaml.new" || { \
			echo "$(RED)✗ $$old_img does not start with the config copied from the running container, so a rollback$(RESET)"; \
			echo "$(RED)  would not work (was telemetry/config/tempo.yaml edited in place?). Nothing was changed.$(RESET)"; \
			echo "  Put Tempo 2's config back in telemetry/config/tempo.yaml and restart Tempo, or migrate without"; \
			echo "  a rollback option: make migrate-tempo NO_ROLLBACK=1"; \
			exit 1; }; \
	fi; \
	$(MAKE) --no-print-directory backup-tempo TIMESTAMP=$(TIMESTAMP) || exit 1; \
	if [ "$(NO_ROLLBACK)" != 1 ]; then \
		mv -f "$$snap/tempo.yaml.new" "$$snap/tempo.yaml"; \
		echo "$$old_img" > "$$snap/image"; \
		echo "$(abspath $(BACKUP_DIR))/tempo_$(TIMESTAMP).tar.gz" > "$$snap/backup"; \
		echo "  $(GREEN)✓$(RESET) rollback snapshot in $$snap ($$old_img starts with its saved config)"; \
	fi; \
	echo "$(CYAN)[4/5] Flushing Tempo 2 and stopping its ingester...$(RESET)"; \
	m() { curl -fsS $(TEMPO_URL)/metrics 2>/dev/null | awk -v n="$$1" '$$1 ~ "^"n"({|$$)" { s += $$2 } END { printf "%d", s }'; }; \
	curl -fsS -X POST $(TEMPO_URL)/shutdown >/dev/null || { echo "$(RED)✗ POST $(TEMPO_URL)/shutdown failed; nothing was changed, Tempo 2 keeps running.$(RESET)"; exit 1; }; \
	i=0; until [ "$$(m tempo_ingester_live_traces)" = 0 ] && [ "$$(m tempo_ingester_flush_queue_length)" = 0 ]; do \
		i=$$((i+1)); [ $$i -gt 60 ] && { echo "$(RED)✗ Tempo 2 did not finish flushing within 60s. It no longer accepts traces; run make migrate-tempo again, or make rollback-tempo.$(RESET)"; exit 1; }; \
		sleep 1; \
	done; \
	sleep 2; \
	echo "  $(GREEN)✓$(RESET) flushed; Tempo 2 no longer accepts traces (Alloy queues and retries them for up to 10 minutes)"; \
	echo "$(CYAN)[5/5] Recreating Tempo on the new version...$(RESET)"; \
	(cd telemetry && $(DOCKER_COMPOSE) up -d --remove-orphans tempo) || true; \
	i=0; until curl -fsS -o /dev/null $(TEMPO_URL)/ready 2>/dev/null; do \
		i=$$((i+1)); \
		if [ $$i -gt 120 ]; then \
			echo "$(RED)$(BOLD)✗ The new Tempo did not become ready within 2 minutes.$(RESET)"; \
			echo "  Tempo 2's traces are flushed to disk and safe. Alloy keeps retrying new traces for up to"; \
			echo "  10 minutes (1000 batches in memory); after that they are dropped. Either:"; \
			echo "    - fix forward: make logs-telemetry, fix the cause, then make update-telemetry SKIP_TEMPO_MIGRATION=1"; \
			echo "    - go back:     make rollback-tempo  (Tempo 2 with the data as it was before the migration)"; \
			exit 1; \
		fi; sleep 1; \
	done; \
	echo ""; \
	echo "$(GREEN)$(BOLD)✓ Tempo migrated to $$(docker inspect -f '{{.Config.Image}}' oib-tempo)$(RESET)"; \
	echo "  Every trace opens by ID right away. Traces received in the 15 minutes before the"; \
	echo "  migration show up in search once they are 15 minutes old (Tempo 3 searches only"; \
	echo "  its live store for the most recent 15 minutes). Continue with: make update"; \
	echo "  To go back to Tempo 2: make rollback-tempo (traces received after the migration are lost)"

rollback-tempo: ## Undo migrate-tempo: Tempo 2 with its data as before the migration
	@d="$(TEMPO_ROLLBACK_DIR)"; \
	if [ ! -s "$$d/image" ] || [ ! -s "$$d/tempo.yaml" ] || [ ! -s "$$d/backup" ]; then \
		echo "$(RED)✗ No rollback snapshot in $$d (it is written by make migrate-tempo).$(RESET)"; exit 1; fi; \
	img=$$(cat "$$d/image"); file=$$(cat "$$d/backup"); \
	[ -f "$$file" ] || { echo "$(RED)✗ Pre-migration backup $$file is missing.$(RESET)"; exit 1; }; \
	echo "$(YELLOW)$(BOLD)⚠️  This puts Tempo back to $$img with its data as it was before the migration.$(RESET)"; \
	echo "  Traces received since then are lost (Tempo 2 cannot read Tempo 3's data)."; \
	$(call confirm,Roll back?); \
	docker rm -f oib-tempo >/dev/null 2>&1; \
	docker rm -f oib-restore-tempo >/dev/null 2>&1; \
	docker run --rm --name oib-restore-tempo -v oib-tempo-data:/data -v "$$file":/backup.tar.gz:ro $(BACKUP_IMAGE) \
		sh -c "tar tzf /backup.tar.gz >/dev/null && find /data -mindepth 1 -delete && tar xzf /backup.tar.gz -C /data" \
		|| { echo "$(RED)✗ Restoring $$file failed$(RESET)"; exit 1; }; \
	(cd telemetry && TEMPO_VERSION="$${img##*:}" TEMPO_CONFIG="$$d/tempo.yaml" $(DOCKER_COMPOSE) up -d tempo) || exit 1; \
	i=0; until curl -fsS -o /dev/null $(TEMPO_URL)/ready 2>/dev/null; do i=$$((i+1)); [ $$i -gt 120 ] && { echo "$(RED)✗ Tempo 2 did not become ready$(RESET)"; exit 1; }; sleep 1; done; \
	echo "$(GREEN)✓ Tempo rolled back to $$img.$(RESET) make migrate-tempo migrates again when you are ready."

# Releases before 1.1.0 let Compose name Grafana's volume oib-grafana_oib-grafana-data;
# since 1.1.0 it is oib-grafana-data. Move the data over so upgrades keep it.
OLD_GRAFANA_VOLUME := oib-grafana_oib-grafana-data
# Written into the old volume after a move, so later runs stay quiet
GRAFANA_MIGRATED_MARKER := .oib-migrated-to-oib-grafana-data

migrate-grafana-volume: ## Move Grafana data from the pre-1.1.0 volume (FORCE=1 replaces existing data)
	@if ! docker volume inspect $(OLD_GRAFANA_VOLUME) >/dev/null 2>&1; then exit 0; fi; \
	if [ "$(FORCE)" != "1" ] && docker run --rm -v $(OLD_GRAFANA_VOLUME):/from:ro $(BACKUP_IMAGE) test -f /from/$(GRAFANA_MIGRATED_MARKER); then exit 0; fi; \
	if docker volume inspect oib-grafana-data >/dev/null 2>&1 && [ "$(FORCE)" != "1" ]; then \
		echo "$(YELLOW)!$(RESET) Found Grafana data from before 1.1.0 in volume $(OLD_GRAFANA_VOLUME)."; \
		echo "  The current Grafana uses oib-grafana-data. To bring back the old dashboards, users and"; \
		echo "  settings (replacing the current ones), run: $(GREEN)make migrate-grafana-volume FORCE=1$(RESET)"; \
		echo "  To keep the current data instead: docker volume rm $(OLD_GRAFANA_VOLUME)"; \
		exit 0; \
	fi; \
	if docker volume inspect oib-grafana-data >/dev/null 2>&1; then \
		echo "$(CYAN)Backing up current Grafana data before replacing it...$(RESET)"; \
		$(MAKE) --no-print-directory backup-grafana || exit 1; \
	fi; \
	echo "$(CYAN)Moving Grafana data from $(OLD_GRAFANA_VOLUME) to oib-grafana-data...$(RESET)"; \
	docker rm -f oib-grafana >/dev/null 2>&1 || true; \
	docker volume create oib-grafana-data >/dev/null && \
	docker run --rm -v $(OLD_GRAFANA_VOLUME):/from:ro -v oib-grafana-data:/to $(BACKUP_IMAGE) \
		sh -c "find /to -mindepth 1 -delete && cp -a /from/. /to/ && rm -f /to/$(GRAFANA_MIGRATED_MARKER)" || { echo "$(RED)✗ Grafana volume migration failed$(RESET)"; exit 1; }; \
	docker run --rm -v $(OLD_GRAFANA_VOLUME):/from $(BACKUP_IMAGE) touch /from/$(GRAFANA_MIGRATED_MARKER) || true; \
	echo "$(GREEN)✓$(RESET) Grafana data moved. The old volume is kept; remove it once you are happy:"; \
	echo "  docker volume rm $(OLD_GRAFANA_VOLUME)"

install-logging: network ## Install logging stack (Loki + Alloy)
	@echo "$(CYAN)📋 Installing Logging Stack...$(RESET)"
	@cd logging && $(DOCKER_COMPOSE) up -d --remove-orphans
	@echo "$(GREEN)✓ Logging stack installed$(RESET)"

install-metrics: network ## Install metrics stack (Prometheus + Exporters)
	@echo "$(CYAN)📊 Installing Metrics Stack...$(RESET)"
	@cd metrics && p=""; if docker inspect oib-pushgateway >/dev/null 2>&1; then p="--profile pushgateway"; fi; $(DOCKER_COMPOSE) $$p up -d --remove-orphans
	@echo "$(GREEN)✓ Metrics stack installed$(RESET)"

install-telemetry: network tempo-guard ## Install telemetry stack (Tempo + Alloy)
	@echo "$(CYAN)🔭 Installing Telemetry Stack...$(RESET)"
	@cd telemetry && $(DOCKER_COMPOSE) up -d --remove-orphans
	@echo "$(GREEN)✓ Telemetry stack installed$(RESET)"

install-profiling: network ## Install profiling stack (Pyroscope) - optional
	@echo "$(CYAN)🔥 Installing Profiling Stack...$(RESET)"
	@cd profiling && $(DOCKER_COMPOSE) up -d --remove-orphans
	@echo "$(GREEN)✓ Profiling stack installed$(RESET)"
	@echo ""
	@echo "$(YELLOW)Note: Restart Grafana to enable Pyroscope datasource: make restart-grafana$(RESET)"

install-mcp: network ## Install the read-only MCP endpoint for AI agents (hib, Claude Code, Codex) - optional
	@echo "$(CYAN)🤖 Installing the MCP endpoint...$(RESET)"
	@mcp/provision.sh "$(GRAFANA_URL)"
	@cd mcp && $(DOCKER_COMPOSE) up -d --remove-orphans
	@i=0; until curl -fsS -o /dev/null --max-time 2 "$(MCP_URL)/healthz" 2>/dev/null; do \
		i=$$((i + 1)); \
		if [ $$i -gt 30 ]; then \
			echo "$(RED)✗ The MCP endpoint is not healthy at $(MCP_URL)/healthz$(RESET)"; \
			docker logs --tail 20 oib-mcp-grafana 2>&1 | sed 's/^/    /'; exit 1; \
		fi; sleep 1; \
	done
	@echo "$(GREEN)✓ Read-only MCP endpoint at $(MCP_URL)/mcp$(RESET)"
	@$(MAKE) --no-print-directory mcp-config

mcp-config: ## Show how to connect hib, Claude Code or Codex to the MCP endpoint
	@echo ""
	@echo "$(BOLD)$(CYAN)🤖 MCP endpoint (read-only)$(RESET)"
	@echo "$(BOLD)────────────────────────────────────────$(RESET)"
	@echo "  URL:    $(YELLOW)$(MCP_URL)/mcp$(RESET)  (streamable HTTP, bearer token required)"
	@echo "  Token:  $(YELLOW)$(CURDIR)/mcp/secrets/mcp.env$(RESET) (MCP_GRAFANA_SERVER_TOKEN)"
	@echo ""
	@echo "$(GREEN)hib (guarded, no prompts; hib with trusted MCP support), in ~/.hib/config.toml:$(RESET)"
	@echo "  [mcp.oib]"
	@echo "  url = \"$(MCP_URL)/mcp\""
	@echo "  token_file = \"$(CURDIR)/mcp/secrets/mcp.env\""
	@echo "  token_key = \"MCP_GRAFANA_SERVER_TOKEN\""
	@echo "  read_only = true"
	@echo "  sensitive = true"
	@echo "  server = \"oib\"   # what mcp-grafana reports (--server-name=oib)"
	@echo "  # Checked read-only tools for investigations. Left out on purpose: alerting_manage_routing"
	@echo "  # (contact points can hold webhook URLs and tokens), dashboard versions and silences (author"
	@echo "  # names), whole-dashboard JSON and folders."
	@echo "  tools = ["
	@echo "    \"list_datasources\", \"check_datasources_health\","
	@echo "    \"query_loki_logs\", \"query_loki_stats\", \"query_loki_patterns\", \"list_loki_label_names\", \"list_loki_label_values\","
	@echo "    \"query_prometheus\", \"query_prometheus_histogram\", \"list_prometheus_metric_names\", \"list_prometheus_metric_metadata\", \"list_prometheus_label_names\", \"list_prometheus_label_values\","
	@echo "    \"search_tempo_traces\", \"get_tempo_trace\", \"query_tempo_metrics\", \"diff_tempo_traces\", \"list_tempo_attribute_names\", \"list_tempo_attribute_values\", \"get_tempo_traceql_docs\","
	@echo "    \"query_pyroscope\", \"list_pyroscope_profile_types\", \"list_pyroscope_label_names\", \"list_pyroscope_label_values\","
	@echo "    \"alerting_rules_read\", \"search_dashboards\", \"get_dashboard_summary\", \"get_dashboard_panel_queries\", \"generate_deeplink\","
	@echo "  ]"
	@echo "  then restart hib's daemon (hib daemon stop). hib serves the tools itself, guards every"
	@echo "  result and hides a same-named server from your Claude or Codex config in its sessions."
	@echo ""
	@echo "$(GREEN)Claude Code directly (unguarded; also what older hib releases use):$(RESET)"
	@echo "  claude mcp add --scope user --transport http oib $(MCP_URL)/mcp \\"
	@echo "    --header \"Authorization: Bearer \$$(sed -n 's/^MCP_GRAFANA_SERVER_TOKEN=//p' $(CURDIR)/mcp/secrets/mcp.env)\""
	@echo ""
	@echo "$(GREEN)Codex (and hib's Codex sessions), in ~/.codex/config.toml:$(RESET)"
	@echo "  [mcp_servers.oib]"
	@echo "  url = \"$(MCP_URL)/mcp\""
	@echo "  bearer_token_env_var = \"OIB_MCP_TOKEN\""
	@echo "  Plain codex: export OIB_MCP_TOKEN with the token above. hib passes Codex only its account's"
	@echo "  env, so under hib add OIB_MCP_TOKEN to that account's env in ~/.hib/config.toml (untested)."
	@echo ""
	@echo "  A hib account with its own CLAUDE_CONFIG_DIR: run the claude mcp add line with that"
	@echo "  CLAUDE_CONFIG_DIR set. hib asks before each MCP call."
	@echo ""

# Q is quoted for the shell here (single quotes, embedded ones escaped), never spliced raw.
ask: ## Ask an LLM about OIB's data through hib: make ask Q="why is checkout slow?" [SINCE=1h] [MODEL=...]
	@SINCE='$(subst ','\'',$(or $(SINCE),1h))' MODEL='$(subst ','\'',$(MODEL))' HIB='$(subst ','\'',$(or $(HIB),hib))' MCP_URL='$(MCP_URL)' \
		scripts/ask.sh '$(subst ','\'',$(Q))'

uninstall-mcp: ## Remove the MCP endpoint and its tokens
	@echo "$(YELLOW)Removing the MCP endpoint...$(RESET)"
	@if [ -f mcp/secrets/mcp.env ]; then cd mcp && $(DOCKER_COMPOSE) down --remove-orphans --timeout 2; \
	else docker rm -f oib-mcp-grafana >/dev/null 2>&1 || true; fi
	@rm -f mcp/secrets/mcp.env
	@echo "$(GREEN)✓ MCP endpoint removed$(RESET) (the Grafana service account oib-mcp is kept; its token is gone)"

logs-mcp: ## Tail MCP endpoint logs
	@docker logs -f oib-mcp-grafana

install-services: network ## Install shared services (PostgreSQL + Redis) - optional
	@echo "$(CYAN)🗄️  Installing Shared Services...$(RESET)"
	@cd services && $(DOCKER_COMPOSE) up -d --remove-orphans
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

# $(call check_volume_removed,<volume>): fail loudly if `down -v` could not delete it
check_volume_removed = if docker volume inspect $(1) >/dev/null 2>&1; then \
	echo "$(RED)✗ Volume $(1) was not removed; it is still used by:$(RESET)"; \
	docker ps -a --filter volume=$(1) --format '    {{.Names}} ({{.Image}}, {{.Status}})'; \
	echo "  Remove those containers (docker rm -f <name>) and run the uninstall again."; exit 1; fi

uninstall: ## Remove all stacks and volumes (with confirmation)
	@echo "$(RED)$(BOLD)⚠️  WARNING: This will delete ALL data (logs, metrics, traces)!$(RESET)"
	@echo ""
	@$(call confirm,Are you sure you want to uninstall?)
	@$(MAKE) --no-print-directory uninstall-grafana
	@$(MAKE) --no-print-directory uninstall-logging
	@$(MAKE) --no-print-directory uninstall-metrics
	@$(MAKE) --no-print-directory uninstall-telemetry
	@if docker inspect oib-mcp-grafana >/dev/null 2>&1; then $(MAKE) --no-print-directory uninstall-mcp; fi
	@docker network rm oib-network 2>/dev/null || true
	@echo "$(GREEN)✓ All stacks removed$(RESET)"

uninstall-grafana: ## Remove Grafana and volumes
	@echo "$(YELLOW)Removing Grafana...$(RESET)"
	@cd grafana && $(DOCKER_COMPOSE) --profile '*' down -v --remove-orphans --timeout 2
	@$(call check_volume_removed,oib-grafana-data)
	@echo "$(GREEN)✓ Grafana removed$(RESET)"

uninstall-logging: ## Remove logging stack and volumes
	@echo "$(YELLOW)Removing logging stack...$(RESET)"
	@cd logging && $(DOCKER_COMPOSE) --profile '*' down -v --remove-orphans --timeout 2
	@$(call check_volume_removed,oib-loki-data)
	@echo "$(GREEN)✓ Logging stack removed$(RESET)"

uninstall-metrics: ## Remove metrics stack and volumes
	@echo "$(YELLOW)Removing metrics stack...$(RESET)"
	@cd metrics && $(DOCKER_COMPOSE) --profile '*' down -v --remove-orphans --timeout 2
	@$(call check_volume_removed,oib-prometheus-data)
	@echo "$(GREEN)✓ Metrics stack removed$(RESET)"

uninstall-telemetry: ## Remove telemetry stack and volumes
	@echo "$(YELLOW)Removing telemetry stack...$(RESET)"
	@cd telemetry && $(DOCKER_COMPOSE) --profile '*' down -v --remove-orphans --timeout 2
	@$(call check_volume_removed,oib-tempo-data)
	@echo "$(GREEN)✓ Telemetry stack removed$(RESET)"

uninstall-profiling: ## Remove profiling stack and volumes
	@echo "$(YELLOW)Removing profiling stack...$(RESET)"
	@cd profiling && $(DOCKER_COMPOSE) --profile '*' down -v --remove-orphans --timeout 2
	@$(call check_volume_removed,oib-pyroscope-data)
	@echo "$(GREEN)✓ Profiling stack removed$(RESET)"

uninstall-services: ## Remove shared services and volumes (PostgreSQL + Redis)
	@echo "$(YELLOW)Removing shared services...$(RESET)"
	@cd services && $(DOCKER_COMPOSE) --profile '*' down -v --remove-orphans --timeout 2
	@echo "$(GREEN)✓ Shared services removed$(RESET)"

# ==================== Status ====================

status: ## Show status of all stacks with health indicators
	@echo ""
	@echo "$(BOLD)🔭 OIB Stack Status$(RESET)"
	@echo "  Mode: $(OIB_MODE)"
	@echo ""
	@printf "  %-20s %-12s %s\n" "SERVICE" "STATUS" "HEALTH"
	@echo "  ────────────────────────────────────────────────"
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx oib-grafana; then \
		health=$$(curl -sf $(GRAFANA_URL)/api/health >/dev/null 2>&1 && echo "$(GREEN)✓ healthy$(RESET)" || echo "$(YELLOW)? starting$(RESET)"); \
		printf "  %-20s $(GREEN)%-12s$(RESET) %b\n" "Grafana" "running" "$$health"; \
	else \
		printf "  %-20s $(RED)%-12s$(RESET)\n" "Grafana" "stopped"; \
	fi
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx oib-loki; then \
		health=$$(curl -sf $(LOKI_URL)/ready >/dev/null 2>&1 && echo "$(GREEN)✓ healthy$(RESET)" || echo "$(YELLOW)? starting$(RESET)"); \
		printf "  %-20s $(GREEN)%-12s$(RESET) %b\n" "Loki" "running" "$$health"; \
	else \
		printf "  %-20s $(RED)%-12s$(RESET)\n" "Loki" "stopped"; \
	fi
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx oib-alloy-logging; then \
		health=$$(curl -sf $(ALLOY_LOGGING_URL)/-/ready >/dev/null 2>&1 && echo "$(GREEN)✓ healthy$(RESET)" || echo "$(YELLOW)? starting$(RESET)"); \
		printf "  %-20s $(GREEN)%-12s$(RESET) %b\n" "Alloy (logging)" "running" "$$health"; \
	elif [ -n "$(RESTRICTED)" ]; then \
		printf "  %-20s $(YELLOW)%s$(RESET)\n" "Alloy (logging)" "not used (restricted mode)"; \
	else \
		printf "  %-20s $(RED)%-12s$(RESET)\n" "Alloy (logging)" "stopped"; \
	fi
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx oib-prometheus; then \
		health=$$(curl -sf $(PROMETHEUS_URL)/-/ready >/dev/null 2>&1 && echo "$(GREEN)✓ healthy$(RESET)" || echo "$(YELLOW)? starting$(RESET)"); \
		printf "  %-20s $(GREEN)%-12s$(RESET) %b\n" "Prometheus" "running" "$$health"; \
	else \
		printf "  %-20s $(RED)%-12s$(RESET)\n" "Prometheus" "stopped"; \
	fi
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx oib-alloy-metrics; then \
		health=$$(curl -sf $(ALLOY_METRICS_URL)/-/ready >/dev/null 2>&1 && echo "$(GREEN)✓ healthy$(RESET)" || echo "$(YELLOW)? starting$(RESET)"); \
		printf "  %-20s $(GREEN)%-12s$(RESET) %b\n" "Alloy (metrics)" "running" "$$health"; \
	else \
		printf "  %-20s $(RED)%-12s$(RESET)\n" "Alloy (metrics)" "stopped"; \
	fi
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx oib-cadvisor; then \
		health=$$(curl -sf $(CADVISOR_URL)/healthz >/dev/null 2>&1 && echo "$(GREEN)✓ healthy$(RESET)" || echo "$(YELLOW)? starting$(RESET)"); \
		printf "  %-20s $(GREEN)%-12s$(RESET) %b\n" "cAdvisor" "running" "$$health"; \
	elif [ -n "$(RESTRICTED)" ]; then \
		printf "  %-20s $(YELLOW)%s$(RESET)\n" "cAdvisor" "not used (restricted mode)"; \
	else \
		printf "  %-20s $(RED)%-12s$(RESET)\n" "cAdvisor" "stopped"; \
	fi
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx oib-blackbox-exporter; then \
		health=$$(curl -sf $(BLACKBOX_URL)/health >/dev/null 2>&1 && echo "$(GREEN)✓ healthy$(RESET)" || echo "$(YELLOW)? starting$(RESET)"); \
		printf "  %-20s $(GREEN)%-12s$(RESET) %b\n" "Blackbox Exporter" "running" "$$health"; \
	else \
		printf "  %-20s $(RED)%-12s$(RESET)\n" "Blackbox Exporter" "stopped"; \
	fi
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx oib-tempo; then \
		health=$$(curl -sf $(TEMPO_URL)/ready >/dev/null 2>&1 && echo "$(GREEN)✓ healthy$(RESET)" || echo "$(YELLOW)? starting$(RESET)"); \
		printf "  %-20s $(GREEN)%-12s$(RESET) %b\n" "Tempo" "running" "$$health"; \
	else \
		printf "  %-20s $(RED)%-12s$(RESET)\n" "Tempo" "stopped"; \
	fi
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx oib-alloy-telemetry; then \
		health=$$(curl -sf $(ALLOY_TELEMETRY_URL)/-/ready >/dev/null 2>&1 && echo "$(GREEN)✓ healthy$(RESET)" || echo "$(YELLOW)? starting$(RESET)"); \
		printf "  %-20s $(GREEN)%-12s$(RESET) %b\n" "Alloy (telemetry)" "running" "$$health"; \
	else \
		printf "  %-20s $(RED)%-12s$(RESET)\n" "Alloy (telemetry)" "stopped"; \
	fi
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx oib-pyroscope; then \
		health=$$(curl -sf $(PYROSCOPE_URL)/ready >/dev/null 2>&1 && echo "$(GREEN)✓ healthy$(RESET)" || echo "$(YELLOW)? starting$(RESET)"); \
		printf "  %-20s $(GREEN)%-12s$(RESET) %b\n" "Pyroscope" "running" "$$health"; \
	else \
		printf "  %-20s $(RED)%-12s$(RESET)\n" "Pyroscope" "stopped"; \
	fi
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx oib-postgres; then \
		health=$$(docker exec oib-postgres pg_isready -U oib >/dev/null 2>&1 && echo "$(GREEN)✓ healthy$(RESET)" || echo "$(YELLOW)? starting$(RESET)"); \
		printf "  %-20s $(GREEN)%-12s$(RESET) %b\n" "PostgreSQL" "running" "$$health"; \
	else \
		printf "  %-20s $(RED)%-12s$(RESET)\n" "PostgreSQL" "stopped"; \
	fi
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx oib-mcp-grafana; then \
		health=$$(curl -sf $(MCP_URL)/healthz >/dev/null 2>&1 && echo "$(GREEN)✓ healthy$(RESET)" || echo "$(YELLOW)? starting$(RESET)"); \
		printf "  %-20s $(GREEN)%-12s$(RESET) %b\n" "MCP (read-only)" "running" "$$health"; \
	fi
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx oib-redis; then \
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
	@echo "  URL:      $(YELLOW)$(GRAFANA_URL)$(RESET)"
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
	@echo "  URL:      $(YELLOW)$(ALLOY_LOGGING_URL)$(RESET)"
	@echo ""
	@echo "$(GREEN)Loki Push API:$(RESET)"
	@echo "  URL:      $(YELLOW)$(LOKI_URL)/loki/api/v1/push$(RESET)"
	@echo ""
	@echo "$(GREEN)Automatic Docker log collection:$(RESET)"
	@echo "  Alloy automatically collects logs from all Docker containers."
	@echo "  Review logging/config/alloy-config.alloy to limit collection on shared hosts."
	@echo ""

info-metrics: ## Show metrics integration info
	@echo ""
	@echo "$(BOLD)$(CYAN)📈 METRICS (Prometheus + Alloy + cAdvisor)$(RESET)"
	@echo "$(BOLD)────────────────────────────────────────$(RESET)"
	@echo ""
	@echo "$(GREEN)Prometheus UI:$(RESET)"
	@echo "  URL:      $(YELLOW)$(PROMETHEUS_URL)$(RESET)"
	@echo ""
	@echo "$(GREEN)Alloy Metrics UI:$(RESET)"
	@echo "  URL:      $(YELLOW)$(ALLOY_METRICS_URL)$(RESET)"
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
	@echo "  URL:      $(YELLOW)$(ALLOY_TELEMETRY_URL)$(RESET)"
	@echo ""
	@echo "$(GREEN)OpenTelemetry Endpoints:$(RESET)"
	@echo "  OTLP gRPC:  $(YELLOW)$(OTEL_CONNECT_HOST):$(OTEL_GRPC_PORT)$(RESET)"
	@echo "  OTLP HTTP:  $(YELLOW)$(OTEL_HTTP_URL)$(RESET)"
	@echo ""
	@echo "$(GREEN)Configure your app:$(RESET)"
	@echo "  $(CYAN)OTEL_EXPORTER_OTLP_ENDPOINT=http://<oib-host>:$(OTEL_HTTP_PORT)$(RESET)"
	@echo ""

info-profiling: ## Show profiling integration info
	@echo ""
	@echo "$(BOLD)$(CYAN)🔥 PROFILING (Pyroscope)$(RESET)"
	@echo "$(BOLD)────────────────────────────────────────$(RESET)"
	@echo ""
	@echo "$(GREEN)Pyroscope UI:$(RESET)"
	@echo "  URL:      $(YELLOW)$(PYROSCOPE_URL)$(RESET)"
	@echo ""
	@echo "$(GREEN)SDK Integration:$(RESET)"
	@echo "  Server:   $(YELLOW)http://<oib-host>:$(PYROSCOPE_PORT)$(RESET)"
	@echo ""
	@echo "$(GREEN)Configure your app:$(RESET)"
	@echo "  $(CYAN)PYROSCOPE_SERVER_ADDRESS=http://<oib-host>:$(PYROSCOPE_PORT)$(RESET)"
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
	@pids=""; trap 'kill $$pids 2>/dev/null' INT TERM; \
	for stack in grafana logging metrics telemetry; do \
		(cd $$stack && exec $(DOCKER_COMPOSE) logs -f) & pids="$$pids $$!"; \
	done; \
	wait

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
	@errors=0; \
	check_http() { \
		label="$$1"; container="$$2"; url="$$3"; \
		if [ "$$(docker inspect --format '{{.State.Running}}' "$$container" 2>/dev/null)" != "true" ]; then \
			echo "  $(RED)✗$(RESET) $$label is not running"; \
			errors=$$((errors + 1)); \
		elif curl -sf "$$url" >/dev/null 2>&1; then \
			echo "  $(GREEN)✓$(RESET) $$label is healthy"; \
		else \
			echo "  $(RED)✗$(RESET) $$label is not responding at $$url"; \
			errors=$$((errors + 1)); \
		fi; \
	}; \
	echo "$(CYAN)Grafana:$(RESET)"; \
	check_http "Grafana" "oib-grafana" "$(GRAFANA_URL)/api/health"; \
	echo ""; \
	echo "$(CYAN)Logging:$(RESET)"; \
	check_http "Loki" "oib-loki" "$(LOKI_URL)/ready"; \
	if [ -n "$(RESTRICTED)" ] && docker inspect oib-alloy-logging >/dev/null 2>&1; then \
		echo "  $(RED)✗$(RESET) Alloy (logging) still exists in restricted mode; run make install to remove it"; \
		errors=$$((errors + 1)); \
	elif [ -n "$(RESTRICTED)" ]; then echo "  $(YELLOW)-$(RESET) Alloy (logging) is not used in restricted mode"; \
	else check_http "Alloy (logging)" "oib-alloy-logging" "$(ALLOY_LOGGING_URL)/-/ready"; fi; \
	echo ""; \
	echo "$(CYAN)Metrics:$(RESET)"; \
	check_http "Prometheus" "oib-prometheus" "$(PROMETHEUS_URL)/-/ready"; \
	check_http "Alloy (metrics)" "oib-alloy-metrics" "$(ALLOY_METRICS_URL)/-/ready"; \
	if [ -n "$(RESTRICTED)" ] && docker inspect oib-cadvisor >/dev/null 2>&1; then \
		echo "  $(RED)✗$(RESET) cAdvisor still exists in restricted mode; run make install to remove it"; \
		errors=$$((errors + 1)); \
	elif [ -n "$(RESTRICTED)" ]; then echo "  $(YELLOW)-$(RESET) cAdvisor is not used in restricted mode"; \
	else check_http "cAdvisor" "oib-cadvisor" "$(CADVISOR_URL)/healthz"; fi; \
	check_http "Blackbox Exporter" "oib-blackbox-exporter" "$(BLACKBOX_URL)/health"; \
	echo ""; \
	echo "$(CYAN)Telemetry:$(RESET)"; \
	check_http "Tempo" "oib-tempo" "$(TEMPO_URL)/ready"; \
	check_http "Alloy (telemetry)" "oib-alloy-telemetry" "$(ALLOY_TELEMETRY_URL)/-/ready"; \
	echo ""; \
	echo "$(CYAN)Profiling (optional):$(RESET)"; \
	if docker inspect oib-pyroscope >/dev/null 2>&1; then \
		check_http "Pyroscope" "oib-pyroscope" "$(PYROSCOPE_URL)/ready"; \
	else \
		echo "  $(YELLOW)-$(RESET) Pyroscope is not installed"; \
	fi; \
	echo ""; \
	echo "$(CYAN)MCP endpoint (optional):$(RESET)"; \
	if docker inspect oib-mcp-grafana >/dev/null 2>&1; then \
		check_http "MCP (read-only)" "oib-mcp-grafana" "$(MCP_URL)/healthz"; \
	else \
		echo "  $(YELLOW)-$(RESET) MCP endpoint is not installed"; \
	fi; \
	echo ""; \
	if [ $$errors -gt 0 ]; then \
		echo "$(RED)$(BOLD)✗ Health check failed with $$errors unhealthy core service(s)$(RESET)"; \
		exit 1; \
	fi; \
	echo "$(GREEN)$(BOLD)✓ All installed core services are healthy$(RESET)"
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
		if ! grep -Eq '^GRAFANA_ADMIN_PASSWORD=.+$$' .env || grep -Eq '^GRAFANA_ADMIN_PASSWORD=CHANGE_ME' .env; then \
			echo "  $(YELLOW)!$(RESET) GRAFANA_ADMIN_PASSWORD is empty or still a placeholder in .env"; \
		else \
			echo "  $(GREEN)✓$(RESET) GRAFANA_ADMIN_PASSWORD is set"; \
		fi; \
	fi
	@echo ""
	@echo "$(CYAN)Checking network...$(RESET)"
	@docker network inspect oib-network >/dev/null 2>&1 && echo "  $(GREEN)✓$(RESET) oib-network exists" || echo "  $(YELLOW)!$(RESET) oib-network not created (run 'make install')"
	@echo ""
	@echo "$(CYAN)Checking ports...$(RESET)"
	@$(MAKE) --no-print-directory check-ports
	@echo ""

check-ports: ## Check if required ports are available
	@if ! command -v lsof >/dev/null 2>&1; then \
		echo "  $(YELLOW)!$(RESET) lsof is unavailable; port checks were skipped"; \
		exit 0; \
	fi; \
	for port in $(CORE_PORTS); do \
		if lsof -nP -iTCP:$$port -sTCP:LISTEN >/dev/null 2>&1; then \
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
	for file in \
		logging/config/loki-config.yml \
		metrics/config/prometheus.yml \
		metrics/config/scrape/cadvisor.yml \
		metrics/config/blackbox.yml \
		metrics/config/rules/oib-alerts.yml \
		telemetry/config/tempo.yaml \
		grafana/provisioning/datasources/datasources.yml \
		grafana/provisioning/dashboards/dashboards.yml; do \
		if [ -f "$$file" ]; then \
			if docker run --rm -v "$(CURDIR)/$$file:/file.yml:ro" mikefarah/yq '.' /file.yml >/dev/null 2>&1; then \
				echo "  $(GREEN)✓$(RESET) $$file"; \
			else \
				echo "  $(RED)✗$(RESET) $$file has syntax errors"; \
				ERRORS=$$((ERRORS + 1)); \
			fi; \
		fi; \
	done; \
	echo ""; \
	echo "$(CYAN)Checking Docker Compose files...$(RESET)"; \
	for file in \
		grafana/compose.yaml \
		logging/compose.yaml \
		metrics/compose.yaml \
		telemetry/compose.yaml \
		profiling/compose.yaml \
		mcp/compose.yaml \
		services/compose.yaml \
		testing/compose.yaml \
		examples/demo-app/compose.yaml \
		examples/node-express/compose.yaml \
		examples/python-flask/compose.yaml \
		examples/php-laravel/compose.yaml \
		examples/ruby-rails/compose.yaml; do \
		if $(DOCKER_COMPOSE) -f "$$file" config --quiet 2>/dev/null; then \
			echo "  $(GREEN)✓$(RESET) $$file"; \
		else \
			echo "  $(RED)✗$(RESET) $$file has errors"; \
			ERRORS=$$((ERRORS + 1)); \
		fi; \
	done; \
	for file in */compose.restricted.yaml; do \
		if $(DOCKER_COMPOSE) -f "$${file%/*}/compose.yaml" -f "$$file" config --quiet 2>/dev/null; then \
			echo "  $(GREEN)✓$(RESET) $$file (restricted mode)"; \
		else \
			echo "  $(RED)✗$(RESET) $$file has errors (restricted mode)"; \
			ERRORS=$$((ERRORS + 1)); \
		fi; \
	done; \
	echo ""; \
	echo "$(CYAN)Checking dashboard JSON...$(RESET)"; \
	for file in $$(find grafana logging metrics telemetry -path '*/provisioning/dashboards/json/*.json' -type f); do \
		if docker run --rm -v "$(CURDIR)/$$file:/file.json:ro" mikefarah/yq '.' /file.json >/dev/null 2>&1; then \
			echo "  $(GREEN)✓$(RESET) $$file"; \
		else \
			echo "  $(RED)✗$(RESET) $$file has syntax errors"; \
			ERRORS=$$((ERRORS + 1)); \
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

update: tempo-guard ## Pull pinned images and recreate the core stacks
	@echo "$(CYAN)Pulling latest images...$(RESET)"
	@cd grafana && $(DOCKER_COMPOSE) pull
	@cd logging && $(DOCKER_COMPOSE) pull
	@cd metrics && $(DOCKER_COMPOSE) pull
	@cd telemetry && $(DOCKER_COMPOSE) pull
	@echo ""
	@echo "$(CYAN)Recreating stacks with new images...$(RESET)"
	@cd logging && $(DOCKER_COMPOSE) up -d --remove-orphans
	@cd metrics && p=""; if docker inspect oib-pushgateway >/dev/null 2>&1; then p="--profile pushgateway"; fi; $(DOCKER_COMPOSE) $$p up -d --remove-orphans
	@cd telemetry && $(DOCKER_COMPOSE) up -d --remove-orphans
	@$(MAKE) --no-print-directory migrate-grafana-volume
	@cd grafana && $(DOCKER_COMPOSE) up -d --remove-orphans
	@echo ""
	@echo "$(GREEN)✓ All stacks updated$(RESET)"

update-grafana: ## Pull latest Grafana image and restart
	@echo "$(CYAN)Pulling latest Grafana image...$(RESET)"
	@cd grafana && $(DOCKER_COMPOSE) pull
	@echo "$(CYAN)Restarting Grafana...$(RESET)"
	@$(MAKE) --no-print-directory migrate-grafana-volume
	@cd grafana && $(DOCKER_COMPOSE) up -d --remove-orphans
	@echo "$(GREEN)✓ Grafana updated$(RESET)"

update-logging: ## Pull latest logging images (Loki, Alloy) and restart
	@echo "$(CYAN)Pulling latest logging images...$(RESET)"
	@cd logging && $(DOCKER_COMPOSE) pull
	@echo "$(CYAN)Restarting logging stack...$(RESET)"
	@cd logging && $(DOCKER_COMPOSE) up -d --remove-orphans
	@echo "$(GREEN)✓ Logging stack updated$(RESET)"

update-metrics: ## Pull latest metrics images (Prometheus, exporters) and restart
	@echo "$(CYAN)Pulling latest metrics images...$(RESET)"
	@cd metrics && $(DOCKER_COMPOSE) pull
	@echo "$(CYAN)Restarting metrics stack...$(RESET)"
	@cd metrics && p=""; if docker inspect oib-pushgateway >/dev/null 2>&1; then p="--profile pushgateway"; fi; $(DOCKER_COMPOSE) $$p up -d --remove-orphans
	@echo "$(GREEN)✓ Metrics stack updated$(RESET)"

update-telemetry: tempo-guard ## Pull latest telemetry images (Tempo, Alloy) and restart
	@echo "$(CYAN)Pulling latest telemetry images...$(RESET)"
	@cd telemetry && $(DOCKER_COMPOSE) pull
	@echo "$(CYAN)Restarting telemetry stack...$(RESET)"
	@cd telemetry && $(DOCKER_COMPOSE) up -d --remove-orphans
	@echo "$(GREEN)✓ Telemetry stack updated$(RESET)"

update-profiling: ## Pull latest profiling images (Pyroscope) and restart
	@echo "$(CYAN)Pulling latest profiling images...$(RESET)"
	@cd profiling && $(DOCKER_COMPOSE) pull
	@echo "$(CYAN)Restarting profiling stack...$(RESET)"
	@cd profiling && $(DOCKER_COMPOSE) up -d --remove-orphans
	@echo "$(GREEN)✓ Profiling stack updated$(RESET)"

latest: tempo-guard ## Pull and run :latest versions of all images
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
	@docker pull ghcr.io/google/cadvisor:latest
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
	@if docker inspect oib-pyroscope >/dev/null 2>&1; then \
		cd profiling && PYROSCOPE_VERSION=latest $(DOCKER_COMPOSE) up -d --remove-orphans --quiet-pull 2>&1 || true; \
	else \
		echo "    (not installed, skipped)"; \
	fi
	@echo "$(CYAN)  Grafana...$(RESET)"
	@$(MAKE) --no-print-directory migrate-grafana-volume
	@cd grafana && GRAFANA_VERSION=latest $(DOCKER_COMPOSE) up -d --remove-orphans --quiet-pull 2>&1 || true
	@echo ""
	@echo "$(CYAN)Waiting for services to be healthy...$(RESET)"
	@sleep 10
	@echo ""
	@$(MAKE) --no-print-directory status
	@echo ""
	@echo "$(GREEN)$(BOLD)✓ All stacks running with :latest images$(RESET)"
	@echo ""
	@echo "$(YELLOW)Note: To revert to pinned versions, run: make install$(RESET)"

clean: ## Prune unused Docker resources host-wide (stopped containers, networks, dangling images)
	@echo "$(CYAN)Cleaning up unused Docker resources...$(RESET)"
	@docker system prune -f
	@echo "$(GREEN)✓ Cleanup complete$(RESET)"

# ==================== Utilities ====================

open: ## Open Grafana dashboard in browser
	@echo "$(CYAN)Opening Grafana in browser...$(RESET)"
	@if curl -sf $(GRAFANA_URL)/api/health >/dev/null 2>&1; then \
		if command -v xdg-open >/dev/null 2>&1; then \
			xdg-open $(GRAFANA_URL) 2>/dev/null; \
		elif command -v open >/dev/null 2>&1; then \
			open $(GRAFANA_URL); \
		else \
			echo "$(YELLOW)Could not detect browser. Open manually: $(GRAFANA_URL)$(RESET)"; \
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
	@docker inspect oib-blackbox-exporter --format '  Blackbox Exporter    {{.Config.Image}}' 2>/dev/null || echo "  Blackbox Exporter    (not running)"
	@docker inspect oib-pyroscope --format '  Pyroscope            {{.Config.Image}}' 2>/dev/null || echo "  Pyroscope            (not installed)"
	@echo ""

demo: ## Generate sample data to demonstrate all stacks
	@echo ""
	@echo "$(BOLD)🎬 Generating demo data...$(RESET)"
	@echo ""
	@echo "$(CYAN)1. Generating logs...$(RESET)"
	@now=$$(date +%s); \
	timestamp_ns="$${now}000000000"; \
	log_id=$$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n'); \
	message="OIB demo log $$log_id"; \
	if ! curl -fsS -X POST "$(LOKI_URL)/loki/api/v1/push" \
		-H "Content-Type: application/json" \
		-d "{\"streams\":[{\"stream\":{\"job\":\"oib-demo\"},\"values\":[[\"$$timestamp_ns\",\"$$message\"]]}]}" \
		>/dev/null; then \
		echo "   $(RED)✗$(RESET) Could not send log (is Loki running at $(LOKI_URL)?)"; \
		exit 1; \
	fi; \
	found=false; \
	for attempt in 1 2 3 4 5; do \
		if curl -fsS -G "$(LOKI_URL)/loki/api/v1/query_range" \
			--data-urlencode "query={job=\"oib-demo\"} |= \"$$log_id\"" \
			--data-urlencode "start=$$((now - 5))000000000" \
			--data-urlencode "end=$$((now + 5))000000000" | grep -q "$$log_id"; then \
			found=true; \
			break; \
		fi; \
		sleep 1; \
	done; \
	if [ "$$found" = "true" ]; then \
		echo "   $(GREEN)✓$(RESET) Log is searchable in Loki (ID: $$log_id)"; \
	else \
		echo "   $(RED)✗$(RESET) Log was accepted but did not become searchable in Loki"; \
		exit 1; \
	fi
	@echo ""
	@echo "$(CYAN)2. Sending sample trace...$(RESET)"
	@now=$$(date +%s); \
	start_ns="$${now}000000000"; \
	end_ns="$$((now + 1))000000000"; \
	trace_id=$$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n'); \
	span_id=$$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n'); \
	if ! curl -fsS -X POST "$(OTEL_HTTP_URL)/v1/traces" \
		-H "Content-Type: application/json" \
		-d "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"oib-demo\"}}]},\"scopeSpans\":[{\"spans\":[{\"traceId\":\"$$trace_id\",\"spanId\":\"$$span_id\",\"name\":\"demo-span\",\"kind\":1,\"startTimeUnixNano\":\"$$start_ns\",\"endTimeUnixNano\":\"$$end_ns\"}]}]}]}" \
		>/dev/null; then \
		echo "   $(RED)✗$(RESET) Could not send trace (is Alloy telemetry running at $(OTEL_HTTP_URL)?)"; \
		exit 1; \
	fi; \
	found=false; \
	for attempt in 1 2 3 4 5 6 7 8 9 10; do \
		if curl -fsS "$(TEMPO_URL)/api/traces/$$trace_id" >/dev/null 2>&1; then found=true; break; fi; \
		sleep 1; \
	done; \
	if [ "$$found" = "true" ]; then \
		echo "   $(GREEN)✓$(RESET) Trace is searchable in Tempo (trace ID: $$trace_id)"; \
	else \
		echo "   $(RED)✗$(RESET) Trace was accepted but did not become searchable in Tempo"; \
		exit 1; \
	fi
	@echo ""
	@echo "$(GREEN)$(BOLD)Demo complete!$(RESET) Open Grafana to see the data:"
	@echo "  $(YELLOW)$(GRAFANA_URL)$(RESET)"
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
	@echo "  $(YELLOW)$(GRAFANA_URL)$(RESET)"
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
	@cd examples/demo-app && $(DOCKER_COMPOSE) --profile '*' down -v --remove-orphans --timeout 2
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
	@echo "  $(YELLOW)$(GRAFANA_URL)$(RESET)"
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

# ==================== Acceptance Tests ====================
# Both tests delete every OIB volume, so they refuse to run next to an existing
# install. ISOLATED=1 runs them against a throwaway Docker-in-Docker daemon
# instead, which works on any host with Docker (privileged containers allowed).

ACCEPTANCE_RUN = $(if $(filter 1,$(ISOLATED)),testing/acceptance/isolated.sh,testing/acceptance/run.sh)

test-backup: ## Backup -> wipe -> restore round trip (ISOLATED=1: in Docker-in-Docker)
	@$(ACCEPTANCE_RUN) backup-roundtrip.sh

test-upgrade: ## Upgrade from FROM=<tag> and verify data (ISOLATED=1: in Docker-in-Docker)
	@$(ACCEPTANCE_RUN) upgrade.sh $(FROM)

test-tempo-recovery: ## Tempo 2->3 migration failures, rerun and rollback (FROM=v1.0.0; ISOLATED=1)
	@$(ACCEPTANCE_RUN) tempo-migration-recovery.sh $(FROM)

test-restricted: ## Restricted mode: no socket/host mounts, works, switches both ways (ISOLATED=1: in Docker-in-Docker)
	@$(ACCEPTANCE_RUN) restricted.sh

test-mcp: ## MCP endpoint: read-only, authenticated, answers from OIB data (ISOLATED=1: in Docker-in-Docker)
	@$(ACCEPTANCE_RUN) mcp.sh

test-ask: ## make ask through hib against a staged Redis outage (local only: needs hib and a logged-in Claude)
	@testing/acceptance/ask-hib.sh

test-isolation: ## Self-test of ISOLATED=1: concurrent, interrupted and killed runs clean up
	@testing/acceptance/isolation-selftest.sh

# ==================== Backup & Restore ====================
#
# Every component keeps its data in the volume oib-<component>-data and runs
# as the container oib-<component> in the stack directory below.
# Each running component is frozen with `docker pause` while its volume is
# archived, so the copy is crash-consistent (the state the databases' write-ahead
# logs are built to recover from); it is unpaused right after, usually within a
# second. make test-backup verifies that every write acknowledged before the
# freeze is back after a restore, with archives taken under write load.

BACKUP_DIR := ./backups
TIMESTAMP := $(shell date +%Y%m%d_%H%M%S)
BACKUP_COMPONENTS := prometheus loki tempo grafana pyroscope
BACKUP_IMAGE := alpine:3.20
prometheus_STACK := metrics
loki_STACK := logging
tempo_STACK := telemetry
grafana_STACK := grafana
pyroscope_STACK := profiling
HOST_UID := $(shell id -u)
HOST_GID := $(shell id -g)

# $(call backup_volume,<component>)
define backup_volume
mkdir -p "$(BACKUP_DIR)"; \
echo "$(CYAN)Backing up $(1)...$(RESET)"; \
if ! docker volume inspect oib-$(1)-data >/dev/null 2>&1; then \
	echo "  $(YELLOW)!$(RESET) oib-$(1)-data volume not found (skipped)"; exit 0; \
fi; \
if [ -n "$$(docker ps -q -f name=^oib-$(1)$$ -f status=paused)" ]; then \
	echo "  $(YELLOW)!$(RESET) oib-$(1) was left paused (interrupted backup?), unpausing"; docker unpause oib-$(1) >/dev/null; \
fi; \
out="$(1)_$(TIMESTAMP).tar.gz"; \
running=$$(docker ps -q -f name=^oib-$(1)$$ -f status=running); \
resume() { docker rm -f oib-backup-$(1) >/dev/null 2>&1; if [ -n "$$running" ]; then docker unpause oib-$(1) >/dev/null 2>&1; fi; }; \
docker rm -f oib-backup-$(1) >/dev/null 2>&1; \
if [ -n "$$running" ]; then \
	trap 'resume; rm -f "$(BACKUP_DIR)/'"$$out"'.partial"; exit 130' INT TERM; \
	docker pause oib-$(1) >/dev/null || exit 1; \
fi; \
docker run --rm --name oib-backup-$(1) -v oib-$(1)-data:/data:ro -v "$(abspath $(BACKUP_DIR))":/backup $(BACKUP_IMAGE) \
	sh -c "tar czf /backup/$$out.partial -C /data . && chown $(HOST_UID):$(HOST_GID) /backup/$$out.partial && mv /backup/$$out.partial /backup/$$out"; rc=$$?; \
resume; \
if [ $$rc -ne 0 ]; then rm -f "$(BACKUP_DIR)/$$out.partial"; echo "  $(RED)✗$(RESET) $(1) backup failed (nothing written)"; exit $$rc; fi; \
echo "  $(GREEN)✓$(RESET) $(1): $(BACKUP_DIR)/$$out"
endef

# $(call restore_volume,<component>,<file>)
define restore_volume
if [ -z "$(2)" ]; then \
	echo "$(RED)Error: FILE parameter required$(RESET)"; \
	echo "Usage: make restore-$(1) FILE=$(BACKUP_DIR)/$(1)_YYYYMMDD_HHMMSS.tar.gz"; exit 1; \
fi; \
if [ ! -f "$(2)" ]; then echo "$(RED)Error: File not found: $(2)$(RESET)"; exit 1; fi; \
if ! docker inspect oib-$(1) >/dev/null 2>&1; then \
	echo "$(RED)Error: container oib-$(1) not found. Install the $($(1)_STACK) stack first.$(RESET)"; exit 1; \
fi; \
echo "$(YELLOW)$(BOLD)⚠️  WARNING: This will overwrite existing $(1) data!$(RESET)"; \
$(call confirm,Are you sure?); \
echo "$(CYAN)Stopping $(1) (its data is about to be replaced, so no graceful shutdown)...$(RESET)"; \
(cd $($(1)_STACK) && $(DOCKER_COMPOSE) kill $(1)) >/dev/null 2>&1 || true; \
echo "$(CYAN)Restoring from $(2)...$(RESET)"; \
docker rm -f oib-restore-$(1) >/dev/null 2>&1; \
docker run --rm --name oib-restore-$(1) -v oib-$(1)-data:/data -v "$(abspath $(2))":/backup.tar.gz:ro $(BACKUP_IMAGE) \
	sh -c "tar tzf /backup.tar.gz >/dev/null && find /data -mindepth 1 -delete && tar xzf /backup.tar.gz -C /data" \
	|| { echo "$(RED)✗ Restore failed (archive unreadable or extraction error)$(RESET)"; (cd $($(1)_STACK) && $(DOCKER_COMPOSE) start $(1)) >/dev/null 2>&1; exit 1; }; \
echo "$(CYAN)Starting $(1)...$(RESET)"; \
(cd $($(1)_STACK) && $(DOCKER_COMPOSE) start $(1)) >/dev/null; \
echo "$(GREEN)✓ $(1) restored from $(2)$(RESET)"
endef

backup: ## Backup all OIB data volumes (each component is frozen briefly)
	@echo ""
	@echo "$(BOLD)💾 Backing up all OIB data...$(RESET)"
	@echo ""
	@for c in $(BACKUP_COMPONENTS); do \
		$(MAKE) --no-print-directory backup-$$c TIMESTAMP=$(TIMESTAMP) || exit 1; \
	done
	@echo ""
	@echo "$(GREEN)$(BOLD)✓ All backups complete!$(RESET)  Restore with: $(YELLOW)make restore-all STAMP=$(TIMESTAMP)$(RESET)"
	@ls -lh $(BACKUP_DIR)/*_$(TIMESTAMP).tar.gz 2>/dev/null
	@echo ""

backup-prometheus: ## Backup Prometheus data
	@$(call backup_volume,prometheus)

backup-loki: ## Backup Loki data
	@$(call backup_volume,loki)

backup-tempo: ## Backup Tempo data
	@$(call backup_volume,tempo)

backup-grafana: ## Backup Grafana data
	@$(call backup_volume,grafana)

backup-pyroscope: ## Backup Pyroscope data (if the profiling stack is installed)
	@$(call backup_volume,pyroscope)

restore: ## List backups and show how to restore them
	@echo ""
	@echo "$(BOLD)📥 Restore OIB Data$(RESET)"
	@echo ""
	@echo "$(YELLOW)Available backups:$(RESET)"
	@ls -lh $(BACKUP_DIR)/*.tar.gz 2>/dev/null || echo "  No backups found in $(BACKUP_DIR)/"
	@echo ""
	@echo "$(CYAN)Restore everything from one backup run:$(RESET)"
	@echo "  make restore-all STAMP=YYYYMMDD_HHMMSS"
	@echo "$(CYAN)Or a single component:$(RESET)"
	@for c in $(BACKUP_COMPONENTS); do echo "  make restore-$$c FILE=$(BACKUP_DIR)/$${c}_YYYYMMDD_HHMMSS.tar.gz"; done
	@echo "$(CYAN)Add YES=1 to skip the confirmation prompts.$(RESET)"
	@echo ""

restore-all: ## Restore every component from one backup run (STAMP=YYYYMMDD_HHMMSS)
	@if [ -z "$(STAMP)" ]; then echo "$(RED)Error: STAMP parameter required, e.g. STAMP=20260101_120000$(RESET)"; exit 1; fi
	@ls $(BACKUP_DIR)/*_$(STAMP).tar.gz >/dev/null 2>&1 || { echo "$(RED)Error: no backups matching $(BACKUP_DIR)/*_$(STAMP).tar.gz$(RESET)"; exit 1; }
	@echo "$(YELLOW)$(BOLD)⚠️  WARNING: This will overwrite existing data of every component in this backup!$(RESET)"
	@$(call confirm,Are you sure?)
	@for c in $(BACKUP_COMPONENTS); do \
		f="$(BACKUP_DIR)/$${c}_$(STAMP).tar.gz"; \
		if [ -f "$$f" ]; then $(MAKE) --no-print-directory restore-$$c FILE="$$f" YES=1 || exit 1; \
		else echo "$(YELLOW)!$(RESET) no $$c backup in this run (skipped)"; fi; \
	done

restore-prometheus: ## Restore Prometheus data (FILE=path/to/backup.tar.gz)
	@$(call restore_volume,prometheus,$(FILE))

restore-loki: ## Restore Loki data (FILE=path/to/backup.tar.gz)
	@$(call restore_volume,loki,$(FILE))

restore-tempo: ## Restore Tempo data (FILE=path/to/backup.tar.gz)
	@$(call restore_volume,tempo,$(FILE))

restore-grafana: ## Restore Grafana data (FILE=path/to/backup.tar.gz)
	@$(call restore_volume,grafana,$(FILE))

restore-pyroscope: ## Restore Pyroscope data (FILE=path/to/backup.tar.gz)
	@$(call restore_volume,pyroscope,$(FILE))
