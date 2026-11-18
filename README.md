# Observability in a Box (OIB)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Website](https://img.shields.io/badge/Website-in--a--box--tools.tech-blue)](https://in-a-box-tools.tech)

A preconfigured, self-hosted observability stack for local development, homelabs, and small teams. Run Prometheus, Loki, Tempo, Alloy, Grafana, and optional Pyroscope in Docker with ready-made dashboards and instrumented examples.
> **Quick Reference**: `make install` → `make demo` → `make open` → Explore your data!  
> **One-command path**: `make bootstrap`
## 📋 Prerequisites

Before you begin, ensure you have:

- **Docker** 20.10+ ([Install Docker](https://docs.docker.com/get-docker/)) or **Podman** 4.0+ with podman-compose (the Makefile always calls `docker` / `docker compose` and the collectors mount `/var/run/docker.sock`, so Podman only works where those resolve to Podman)
- **Docker Compose** v2+ (included with Docker Desktop)
- **Make** (pre-installed on macOS/Linux, [Windows](https://gnuwin32.sourceforge.net/packages/make.htm))
- **2GB+ RAM** recommended
- **curl** for health checks (pre-installed on most systems)

Verify your setup:
```bash
docker --version     # Should be 20.10+ (or podman --version)
docker compose version  # Should be v2+
make --version
```

## 🚀 Quick Start

```bash
# Clone the repo
git clone https://github.com/matijazezelj/oib.git && cd oib

# Configure credentials (required)
cp .env.example .env
# Edit .env and set GRAFANA_ADMIN_PASSWORD (it ships empty; make install
# refuses to run while it is empty or starts with CHANGE_ME)

# Install all stacks (logging, metrics, telemetry, Grafana)
make install

# Verify installation
make health
```

**Install individual stacks:**
```bash
make install-logging    # Loki + Alloy
make install-metrics    # Prometheus + Alloy + cAdvisor
make install-telemetry  # Tempo + Alloy
make install-grafana    # Unified Grafana with all datasources
make install-profiling  # Pyroscope (optional, not part of make install)
make install-services   # PostgreSQL + Redis (optional, not part of make install)
```

`make install` runs `make preflight` first, which stops if Docker is not running, if two endpoints share a port in `.env`, or (when `lsof` is available) if a required port is already taken by a non-OIB process.

### ✅ Verify Installation

After installation, verify everything is working:

```bash
# Check health of all services
make health

# Expected output: all services show ✓
# 🏥 Health Check
# Grafana:
#   ✓ Grafana is healthy
# Logging:
#   ✓ Loki is healthy
#   ✓ Alloy (logging) is healthy
# ...
```

Then open **http://localhost:3000** (or your configured `GRAFANA_PORT`) and log in with credentials from your `.env` file. Grafana opens on the OIB Stack Health dashboard.

### 🎬 Try It Out

After installation, generate some demo data to see everything working:

```bash
# Push a test log line to Loki and a test trace through Alloy to Tempo
make demo

# Open Grafana in your browser
make open
```

`make demo` sends one log line (label `job="oib-demo"`) and one trace (service `oib-demo`) and checks that both become searchable. Metrics need no demo step: host, container and probe metrics are collected as soon as the metrics stack is running.

For richer data, `make demo-app` starts a Python app with PostgreSQL and Redis and `make demo-traffic` sends it requests; `make demo-examples` starts the Flask, Express, Rails and PHP examples and sends traffic to them. See [examples/README.md](examples/README.md) and the [known limitations](docs/troubleshooting.md#known-limitations) (the demo app and the examples cannot all run at once).

## 📦 What's Included

| Stack | Components | Purpose |
|-------|------------|--------|
| **Logging** | Loki, Alloy | Centralized log aggregation |
| **Metrics** | Prometheus, Alloy, cAdvisor, Blackbox Exporter | Metrics collection (host, containers & endpoint probing) |
| **Telemetry** | Tempo, Alloy | Distributed tracing |
| **Profiling** | Pyroscope | Continuous profiling (optional) |
| **Testing** | k6 | Load testing with Prometheus metrics output |
| **Grafana** | Grafana (unified) | Visualization for all stacks |

## 🔌 Integration Endpoints

After installation, each stack will display integration endpoints:

### Logging Stack
- **Loki API**: `http://localhost:3100` (localhost only - use from host or oib-network)
- **Alloy UI**: `http://localhost:12345` (view pipeline status)
- **Auto-collection**: Alloy collects stdout/stderr of every container on the host through the Docker socket, whatever network it is on. Logs are labelled `container_name`, `compose_project`, `compose_service`, `image` and `container_id`.

> **From Docker containers**: Use `oib-loki:3100` on `oib-network`

### Metrics Stack
- **Prometheus**: `http://localhost:9090` (localhost only)
- **Alloy Metrics UI**: `http://localhost:12347` (host metrics pipeline)
- **cAdvisor**: `http://localhost:8080` (localhost only)
- **Blackbox Exporter**: `http://localhost:9115` (localhost only)
- **Pushgateway** (optional): `http://localhost:9091`, started with `cd metrics && docker compose --env-file ../.env --profile pushgateway up -d`; then uncomment its scrape job in `metrics/config/prometheus.yml`

> **From Docker containers**: Use hostnames like `oib-prometheus:9090` on `oib-network`

### Telemetry Stack
- **OTLP gRPC**: `localhost:4317` by default; set `OTEL_BIND_ADDR=0.0.0.0` to accept traces from LAN clients
- **OTLP HTTP**: `http://localhost:4318` by default; set `OTEL_BIND_ADDR=0.0.0.0` to accept traces from LAN clients
- **Tempo API**: `http://localhost:3200` (localhost only); Tempo gRPC on `localhost:9095`
- **Alloy Telemetry UI**: `http://localhost:12346` (localhost only)

> **From Docker containers**: Use `oib-alloy-telemetry:4317` (gRPC) or `http://oib-alloy-telemetry:4318` (HTTP) on `oib-network`. On Linux, `host.docker.internal:4318` does not reach the receivers while `OTEL_BIND_ADDR` is the default `127.0.0.1`.

### Profiling Stack (Optional)
- **Pyroscope**: `http://localhost:4040` (localhost only; there is no bind-address setting, so SDKs on other hosts cannot reach it)
- **Install**: `make install-profiling`, then `make restart-grafana`

> **From Docker containers**: Use `oib-pyroscope:4040` on `oib-network`

### Grafana
- **Grafana UI**: `http://localhost:3000` by default; set `BIND_ADDR=0.0.0.0` to expose it on the LAN
- **Credentials**: Set in root `.env` (copy from `.env.example`)

### 📊 Pre-built Dashboards

OIB comes with seven ready-to-use dashboards, provisioned from `grafana/provisioning/dashboards/json/` into the **OIB** folder:

| Dashboard | File | Description |
|-----------|------|-------------|
| **OIB - System Overview** | `system-overview.json` | Container CPU/memory, disk usage, network I/O |
| **OIB - Host Metrics** | `host-metrics.json` | Detailed host system metrics (CPU, memory, disk, network) via Alloy |
| **OIB - Logs Explorer** | `logs-explorer.json` | Log volume, live logs, errors/warnings panel |
| **OIB - Traces Explorer** | `traces-explorer.json` | TraceQL examples, Python, Node.js, Ruby & PHP code samples |
| **OIB - Profiles Explorer** | `profiles-explorer.json` | Pyroscope setup guidance and per-language examples (text panels; view profiles in Explore → Pyroscope after `make install-profiling`) |
| **OIB - Request Latency** | `request-latency.json` | Endpoint probing (Blackbox), k6 load test metrics (p99) |
| **OIB Stack Health** | `oib-internals.json` | Grafana's home dashboard: component status, Prometheus storage and ingestion, scrape targets, firing/pending alerts |

Dashboards are re-read from disk every 30 seconds and can be edited in the UI (`allowUiUpdates: true`), but UI edits are overwritten when the JSON file changes.

### Provisioned Datasources

Defined in `grafana/provisioning/datasources/datasources.yml` (not editable in the UI):

| Name (uid) | URL | Notes |
|------------|-----|-------|
| Prometheus (`prometheus`) | `http://oib-prometheus:9090` | Default datasource |
| Loki (`loki`) | `http://oib-loki:3100` | |
| Tempo (`tempo`) | `http://oib-tempo:3200` | Trace-to-logs, trace-to-metrics, trace-to-profiles links, node graph |
| Pyroscope (`pyroscope`) | `http://oib-pyroscope:4040` | Always provisioned; errors until `make install-profiling` |

Tempo's service graph view is configured but stays empty; see [known limitations](docs/troubleshooting.md#known-limitations).

## ⚙️ Configuration

All configuration is managed through a single `.env` file at the project root.

```bash
# Copy the example and customize
cp .env.example .env
```

### Available Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `GRAFANA_ADMIN_USER` | `admin` | Grafana admin username |
| `GRAFANA_ADMIN_PASSWORD` | (required, empty in `.env.example`) | Grafana admin password. Grafana uses it when it first creates its database; changing it later has no effect on an existing `oib-grafana-data` volume (change it in the Grafana UI instead) |
| `BIND_ADDR` | `127.0.0.1` | Bind address for Grafana/browser-facing endpoints |
| `GRAFANA_PORT` | `3000` | Grafana web UI port |
| `LOKI_PORT` | `3100` | Loki API port (localhost only) |
| `ALLOY_LOGGING_PORT` | `12345` | Alloy logging UI port (localhost only) |
| `PROMETHEUS_PORT` | `9090` | Prometheus API port (localhost only) |
| `ALLOY_METRICS_PORT` | `12347` | Alloy metrics UI port (localhost only) |
| `CADVISOR_PORT` | `8080` | cAdvisor port (localhost only) |
| `BLACKBOX_PORT` | `9115` | Blackbox Exporter port (localhost only) |
| `TEMPO_HTTP_PORT` | `3200` | Tempo HTTP API port (localhost only) |
| `TEMPO_GRPC_PORT` | `9095` | Tempo gRPC port (localhost only) |
| `OTEL_BIND_ADDR` | `127.0.0.1` | Bind address for OTLP receivers; use `0.0.0.0` for LAN trace ingestion |
| `OTEL_GRPC_PORT` | `4317` | OTLP gRPC receiver |
| `OTEL_HTTP_PORT` | `4318` | OTLP HTTP receiver |
| `ALLOY_TELEMETRY_PORT` | `12346` | Alloy telemetry UI port (localhost only) |
| `PROMETHEUS_RETENTION_TIME` | `15d` | Prometheus data retention time |
| `PROMETHEUS_RETENTION_SIZE` | `5GB` | Prometheus data retention size |
| `PYROSCOPE_PORT` | `4040` | Pyroscope port (localhost only, optional stack) |
| `PUSHGATEWAY_PORT` | `9091` | Pushgateway port (localhost only, optional `pushgateway` profile) |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | `oib` / `oib_secret` / `oib_demo` | Shared services and demo app database (change the password if the host is shared) |
| `POSTGRES_PORT` / `REDIS_PORT` | `5432` / `6379` | Shared services host ports (localhost only) |
| `DEMO_BIND_ADDR` | `127.0.0.1` | Bind address for the demo app and example apps |
| `DEMO_APP_PORT` | `5000` | Demo app host port (`make demo-app` / `demo-traffic` still probe `localhost:5000`) |
| `PYROSCOPE_ENABLED` | `true` | Pyroscope SDK in the demo app |
| `TZ` | `UTC` | Timezone; only reaches containers that load `.env` via `env_file` (Grafana, Loki, Prometheus, Tempo, Pyroscope) |

> **Note**: Loki and Tempo retention are configured in their respective config files, not via environment variables.
>
> **Applying changes**: `.env` values are read when containers are created. After changing a port, bind address, retention or version, run `make install` (or `make install-<stack>`), which recreates only the changed containers and keeps data. `make restart` does **not** apply `.env` changes.

### Image Version Overrides

By default, OIB uses pinned (stable) versions for all images. You can override these in your `.env` file:

| Variable | Default | Description |
|----------|---------|-------------|
| `GRAFANA_VERSION` | `13.3.1` | Grafana image tag |
| `LOKI_VERSION` | `3.7.10` | Loki image tag |
| `ALLOY_VERSION` | `v1.22.0` | Alloy image tag |
| `PROMETHEUS_VERSION` | `v3.16.0` | Prometheus image tag |
| `CADVISOR_VERSION` | `v0.60.6` | cAdvisor image tag |
| `BLACKBOX_VERSION` | `v0.29.1` | Blackbox Exporter image tag |
| `TEMPO_VERSION` | `3.1.1` | Tempo image tag |
| `PYROSCOPE_VERSION` | `2.4.3` | Pyroscope image tag |
| `PUSHGATEWAY_VERSION` | `v1.11.4` | Pushgateway image tag (optional profile) |

**Quick commands:**
```bash
# Run all services with :latest images
make latest

# Revert to pinned (stable) versions
make install    # make install-profiling too, if Pyroscope was switched to :latest

# Override a single service version
GRAFANA_VERSION=12.0.0 make update-grafana
```

## 🛠️ Commands

Run `make help` for the grouped list. Stack-specific variants take a `-grafana`, `-logging`, `-metrics`, `-telemetry`, `-profiling` or `-services` suffix (for example `make stop-metrics`, `make logs-services`).

```bash
# Installation
make install              # Install all core stacks (runs preflight first)
make install-logging      # Install logging stack only
make install-metrics      # Install metrics stack only
make install-telemetry    # Install telemetry stack only
make install-grafana      # Install unified Grafana
make install-profiling    # Install Pyroscope (optional)
make install-services     # Install PostgreSQL + Redis (optional)
make network              # Create the shared oib-network (done by every install-*)

# Health & Diagnostics
make preflight            # Check Docker, Compose and port conflicts
make health               # Quick health check of all services (exits non-zero on failure)
make doctor               # Diagnose common issues (Docker, .env, network, ports)
make status               # Show all services with health indicators
make check-ports          # Check if required ports are available (needs lsof)
make ps                   # Show running containers on oib-network
make validate             # Validate YAML configs, compose files and dashboard JSON

# Load Testing
make test-load            # Run k6 basic load test
make test-stress          # Run stress test (find breaking point)
make test-spike           # Run spike test (sudden traffic)
make test-api             # Run API endpoint load test

# Utilities
make open                 # Open Grafana in browser
make demo                 # Send a test log and trace and check they are searchable
make demo-app             # Start the demo app with PostgreSQL & Redis
make demo-traffic         # Send requests to the demo app
make demo-app-stop        # Stop the demo app and delete its volumes
make demo-examples        # Run the four example apps and generate traffic
make bootstrap            # Install + demo + open Grafana
make disk-usage           # Show disk space used by OIB
make version              # Show image versions of running components

# Management (core stacks only: grafana, logging, metrics, telemetry)
make stop                 # Stop all core stacks
make start                # Start all core stacks
make restart              # Restart all core stacks (does not apply .env changes)
make info                 # Show integration endpoints
make info-profiling       # Show Pyroscope endpoints
make info-services        # Show PostgreSQL/Redis endpoints

# Logs
make logs                 # Tail logs from all core stacks
make logs-grafana         # Tail Grafana logs
make logs-logging         # Tail Loki + Alloy logs
make logs-metrics         # Tail Prometheus + exporters logs
make logs-telemetry       # Tail Tempo + Alloy logs
make logs-profiling       # Tail Pyroscope logs
make logs-services        # Tail PostgreSQL + Redis logs

# Maintenance
make update               # Pull pinned images and recreate all core stacks
make update-grafana       # Update Grafana only
make update-logging       # Update Loki + Alloy
make update-metrics       # Update Prometheus + exporters
make update-telemetry     # Update Tempo + Alloy
make update-profiling     # Update Pyroscope
make latest               # Pull and run :latest versions of all images
make clean                # docker system prune -f (HOST-WIDE, see below)

# Backup & Restore (see "Backup and Restore" below)
make backup               # Back up all data volumes (each component is frozen briefly)
make restore              # List backups and show restore commands
make restore-all STAMP=…  # Restore everything from one backup run

# Acceptance tests (ISOLATED=1 runs them in Docker-in-Docker; without it they need a
# host without an OIB install, because they delete all OIB data)
make test-backup ISOLATED=1            # backup -> wipe -> restore round trip with data checks
make test-upgrade FROM=v1.1.0 ISOLATED=1  # install an older release, upgrade, check data and function

# Cleanup
make uninstall            # Remove core stacks, their volumes and oib-network (with confirmation)
make uninstall-profiling  # Remove Pyroscope and its volume
make uninstall-services   # Remove PostgreSQL + Redis and their volumes
```

Notes:
- `start`, `stop`, `restart`, `update`, `info`, `logs` and `uninstall` act on the four core stacks only. Use the `-profiling` / `-services` targets for the optional stacks. `make uninstall` tries to remove `oib-network` and silently leaves it in place if Pyroscope, the shared services or any other container is still attached.
- `make update` runs `up -d` for every core stack, so it also creates any core stack that was not installed. It needs `oib-network` to exist.
- `make latest` runs the core stacks on `:latest` images and switches Pyroscope only if it is already installed. Run `make install` to return to the pinned versions.
- `make clean` runs `docker system prune -f` for the **whole Docker host**: it removes every stopped container, unused network, dangling image and build cache, not only OIB's. It does not remove volumes. If OIB is stopped at that moment, its stopped containers and `oib-network` are removed too (run `make install` to recreate them; data in volumes is kept).
- `DEBUG=1` (e.g. `make install DEBUG=1`) adds `--verbose` to every `docker compose` call.

### Shell Completions

Tab-completion for all `make` targets in this directory is available for zsh (`completions/_oib`) and bash (`completions/oib.bash`). Installation steps are in [completions/README.md](completions/README.md).

## 📁 Project Structure

```
oib/
├── Makefile                    # Main entry point
├── README.md
├── .env.example                # Environment variables template
├── logging/
│   ├── README.md               # Logging stack documentation
│   ├── compose.yaml
│   └── config/
│       ├── loki-config.yml
│       └── alloy-config.alloy
├── metrics/
│   ├── README.md               # Metrics stack documentation
│   ├── compose.yaml
│   └── config/
│       ├── prometheus.yml
│       ├── alloy-metrics.alloy # Host metrics via Alloy
│       ├── blackbox.yml        # Blackbox exporter probe modules
│       └── rules/
│           └── oib-alerts.yml  # Prometheus alert rules (loaded, no Alertmanager)
├── telemetry/
│   ├── README.md               # Telemetry stack documentation
│   ├── compose.yaml
│   └── config/
│       ├── tempo.yaml
│       └── alloy-config.alloy
├── grafana/
│   ├── README.md               # Grafana documentation
│   ├── compose.yaml
│   └── provisioning/
│       ├── datasources/
│       │   └── datasources.yml
│       └── dashboards/
│           ├── dashboards.yml  # Dashboard provider (folder "OIB")
│           └── json/
│               ├── oib-internals.json   # OIB Stack Health (home dashboard)
│               ├── system-overview.json
│               ├── host-metrics.json
│               ├── logs-explorer.json
│               ├── traces-explorer.json
│               ├── profiles-explorer.json
│               └── request-latency.json
├── profiling/
│   ├── README.md               # Profiling stack documentation
│   └── compose.yaml            # Pyroscope (optional)
├── mcp/
│   ├── compose.yaml            # Read-only MCP endpoint for AI agents (optional)
│   └── provision.sh            # Viewer service account and tokens (make install-mcp)
├── scripts/
│   └── ask.sh                  # make ask: one question to hib's agent over OIB's data
├── services/
│   ├── compose.yaml            # PostgreSQL + Redis (optional)
│   └── init/                   # Database schema and seed data (also used by the demo app)
├── completions/                # zsh and bash completion for make targets
├── docs/                       # GitHub Pages site and guides
├── testing/
│   ├── README.md               # Load testing documentation
│   ├── compose.yaml      # k6 load testing
│   └── scripts/
│       ├── basic-load.js
│       ├── stress-test.js
│       ├── spike-test.js
│       └── api-load.js
└── examples/
    ├── README.md               # Example integration guide
    ├── demo-app/               # Python demo app with PostgreSQL + Redis (make demo-app)
    ├── python-flask/           # Python Flask example app
    ├── node-express/           # Node.js Express example app
    ├── ruby-rails/             # Ruby on Rails example app
    └── php-laravel/            # Plain PHP example app (built-in server, no Laravel framework)
```

## 🔧 Configuration

### Custom Prometheus Scrape Targets

Prometheus only scrapes static targets (there is no Docker service discovery). Edit `metrics/config/prometheus.yml` to add your services:

```yaml
scrape_configs:
  - job_name: 'my-app'
    static_configs:
      - targets: ['host.docker.internal:8080']   # app on the host
      # - targets: ['my-app:8080']              # container on oib-network
```

Then reload Prometheus with `docker exec oib-prometheus kill -HUP 1` or `make restart-metrics`. The example apps expose `/metrics`, but no scrape job for them ships, so add one if you want their metrics.

### Alert Rules

`metrics/config/rules/oib-alerts.yml` is loaded by Prometheus and defines alerts for OIB components, host resources, containers, Prometheus itself and Blackbox probes (endpoint down, slow response, TLS certificate expiry). No Alertmanager is configured, so alerts are only visible in Prometheus (`http://localhost:9090/alerts`) and on the OIB Stack Health dashboard. See the [production hardening guide](docs/production-hardening.md#alerting) to route them somewhere.

### Container Metrics

cAdvisor collects container metrics automatically. In the System Overview dashboard, containers are displayed by their **short ID** (first 12 characters), which matches the output of `docker ps`. Use `docker ps` on your host to map IDs to container names.

## 🐳 Docker Integration Examples

### Send container logs to Loki

Nothing to configure: Alloy already ships the stdout/stderr of every container on the host. Query them in Grafana with, for example, `{container_name="my-app"}` or `{compose_service="my-app"}`.

Applications outside Docker can push to the Loki API at `http://localhost:3100/loki/api/v1/push`.

### Expose Prometheus metrics

Labels such as `prometheus.scrape=true` are **not** read by OIB. Add a static scrape job instead (see [Custom Prometheus Scrape Targets](#custom-prometheus-scrape-targets)):

```yaml
  - job_name: 'my-app'
    static_configs:
      - targets: ['my-app:8080']   # my-app attached to oib-network
```

### Send traces via OTLP

```python
# Python example with OpenTelemetry
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

exporter = OTLPSpanExporter(endpoint="localhost:4317", insecure=True)
```

```javascript
// Node.js example - note: requires insecure credentials for non-TLS
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const grpc = require('@grpc/grpc-js');

const exporter = new OTLPTraceExporter({
  url: 'http://localhost:4317',
  credentials: grpc.credentials.createInsecure(),
});
```

> 💡 See `examples/` for complete working Python Flask, Node.js Express, Ruby on Rails, and PHP apps with full observability.

## 🔍 Endpoint Probing (Blackbox Exporter)

Blackbox Exporter performs synthetic monitoring by probing your endpoints from the outside.

### Features

Probe modules are defined in `metrics/config/blackbox.yml`. Only the `blackbox-http` job (module `http_2xx`) is active; TCP and ICMP jobs are commented templates in `prometheus.yml`.

- HTTP/HTTPS endpoint health checks (`http_2xx`, `http_post_2xx`, `http_2xx_content`)
- TCP port connectivity tests (`tcp_connect`, `tcp_tls`)
- ICMP ping, DNS resolution, gRPC health checks (`icmp`, `dns_lookup`, `grpc`, `grpc_tls`)
- TLS certificate checks: the default `http_2xx` module sets `insecure_skip_verify: true`, so invalid certificates do not fail the probe. Use the `https_2xx` module for strict validation.

### Default Monitored Endpoints

OIB probes its own services by default:
- Grafana, Prometheus, Loki, Tempo (not Pyroscope, which is optional)

### Add Your Own Endpoints

Edit `metrics/config/prometheus.yml`:

```yaml
- job_name: 'blackbox-http'
  static_configs:
    - targets:
      - http://your-app:8080/health
      - https://api.example.com/status
```

View results in Grafana → **OIB - Request Latency** dashboard.

## 🔥 Load Testing (k6)

Run load tests with metrics streaming to Prometheus:

```bash
make test-load    # Basic load test
make test-stress  # Find breaking point
make test-spike   # Sudden traffic spikes

# Test custom target
cd testing
docker compose --profile test run --rm \
  -e TARGET_URL=http://your-app:8080 \
  k6 run /scripts/basic-load.js
```

See [testing/README.md](testing/README.md) for custom test scripts.

## 🤖 AI Agents (MCP)

`make install-mcp` adds an optional, read-only [MCP](https://modelcontextprotocol.io) endpoint. Through it, AI agents such as [hib](https://github.com/matijazezelj/hib), Claude Code or Codex can query OIB's data while they help you debug:
- logs (LogQL)
- metrics (PromQL)
- traces (TraceQL and lookup by ID)
- profiles
- dashboards and alert rules

```bash
make install-mcp    # needs Grafana running; prints the client setup below
make mcp-config     # show it again
```

It is [Grafana's MCP server](https://github.com/grafana/mcp-grafana) (`oib-mcp-grafana`), listening on `http://127.0.0.1:3030/mcp` (`MCP_PORT`).

- **Read-only, twice over:**
  - Write tools are not registered (`--disable-write`), and only the categories that read OIB's data are enabled.
  - It queries through a Grafana service account (`oib-mcp`) that has only the Viewer role, which Grafana lets read but not change anything. `make install-mcp` sets the role back to Viewer if it was changed, and replaces the Grafana token if it stopped working (after a Grafana restore or reinstall, say).
- **Authenticated:**
  - Clients must send `Authorization: Bearer <token>`. The token is generated at install and kept in `mcp/secrets/mcp.env` (mode 0600, not committed); reinstalling keeps it.
  - Requests with a foreign `Host` header or a browser `Origin` are rejected, which blocks DNS-rebinding attacks from web pages.
- **Localhost only**, like the other APIs. It runs non-root with a read-only filesystem and no capabilities.
- `make uninstall-mcp` removes the container and the tokens.
- `make test-mcp` checks all of the above, and that queries through MCP return known logs, metrics and traces. CI runs it on every change.

**Connecting hib.** hib 0.5.0 and later (trusted MCP servers) take an `[mcp.oib]` block in `~/.hib/config.toml`, which `make mcp-config` prints.
- hib's daemon then calls the endpoint itself and keeps the token.
- It offers the agent, without prompts, only tools that are on the block's `tools` list and also marked read-only by the server. The list leaves out tools that could expose secrets or author names, such as alerting contact points and dashboard versions.
- It runs every result through its guard (IPs, emails, secrets and user fields become tokens), and also works in sensitive folders.
- It hides any same-named server from your Claude or Codex config in its sessions.

Older hib releases (before 0.5.0) use the unguarded route below.

hib's agent sessions run Claude Code or Codex with your user-level MCP servers. Register the endpoint once with the command `make mcp-config` prints (`claude mcp add --scope user --transport http oib …`), then ask hib things like "why did checkout errors jump in the last hour?".
- **Claude accounts:** the command covers hib's default Claude account. For an account with its own `CLAUDE_CONFIG_DIR`, run it again with that variable set.
- **Codex:** use the `[mcp_servers.oib]` block it prints. hib passes Codex only its account's environment, so put `OIB_MCP_TOKEN` in that account's `env` in `~/.hib/config.toml`. This path is untested.
- **Approvals:** hib asks before each MCP call, because "Always" for an MCP tool covers only that exact call.
- **What leaves the machine:** what the tools return goes to the model provider like any other tool output, so treat logs with personal data accordingly.
- **Sensitive folders:** hib's sensitive folders deliberately load no MCP servers but hib's own.

**Asking from the command line.** `make ask` puts one question to hib's agent and prints its answer:

```bash
make ask Q="Why did checkout latency increase?" SINCE=1h
make ask                                    # "is anything wrong?" over the last hour
make ask Q="..." MODEL=claude@default/sonnet
```

- **What it runs:** one `hib ask --workspace` turn with the question and the time window.
- **Where it runs:** in an empty folder, never this checkout, which holds `mcp/secrets`.
- **Tools:**
  - The agent can use only the guarded OIB tools.
  - Anything that would need your approval, such as file edits, commands or other network hosts, is denied, and the command exits with status 3.
- **Requirements:** hib 0.5.0 or later (for `hib ask --workspace`), the `[mcp.oib]` block in its config, and `make install-mcp`.

`make test-ask` checks it end to end on this machine; it needs hib and a logged-in Claude, so it doesn't run in CI. See [testing/acceptance/README.md](testing/acceptance/README.md#ask-hibsh-make-test-ask).

## 🌐 Network

All stacks run on a shared Docker network `oib-network` allowing inter-service communication.

## 🔒 Security

OIB includes safer defaults for local and self-hosted evaluation:

- **Required Grafana password**: `make install` stops while `GRAFANA_ADMIN_PASSWORD` is empty or starts with `CHANGE_ME`, and Grafana's compose file refuses to start without it
- **Localhost binding**: Internal services (Prometheus, Loki, Tempo, etc.) only listen on `127.0.0.1`
- **Non-privileged containers**: cAdvisor uses minimal capabilities (`SYS_PTRACE`) instead of privileged mode
- **Resource limits**: All OIB stack containers have CPU/memory limits (not all example containers do)
- **No-new-privileges**: Set on all OIB stack containers
- **Non-root users**: Example apps run as non-root users
- **Docker HEALTHCHECK**: All example Dockerfiles include health checks for container orchestration

No browser-facing or ingestion ports are publicly exposed by default. To accept LAN traffic, explicitly set `BIND_ADDR=0.0.0.0` for Grafana or `OTEL_BIND_ADDR=0.0.0.0` for OTLP, then apply appropriate firewall and TLS controls.

> [!IMPORTANT]
> Automatic Docker log collection reads logs from every running container through the Docker socket, not only containers created by OIB. Container logs can contain credentials, tokens, personal data, or other sensitive values. Review `logging/config/alloy-config.alloy` and your applications' logging practices before enabling OIB on a shared host.

> [!WARNING]
> - `/var/run/docker.sock` is mounted into `oib-alloy-logging` and `oib-cadvisor`. Docker API access is root-equivalent on the host, and `:ro` on the mount does not restrict API calls.
> - The host root filesystem is mounted read-only (`/:/rootfs:ro`) into `oib-alloy-metrics` and `oib-cadvisor`, so they can read any file on the host.
> - `oib-alloy-metrics` runs as root with the host's `/proc`, so it can also read the environment variables of root processes in other containers.
> - Grafana, Loki, Prometheus, Tempo and Pyroscope load the whole root `.env` (`env_file: ../.env`), so `GRAFANA_ADMIN_PASSWORD` and `POSTGRES_PASSWORD` are visible in all of them via `docker inspect`.
>
> Anyone who can control these containers or run `docker` on the host has full access to it.

**Restricted mode** removes the first three. Set `OIB_MODE=restricted` in `.env` and run `make install`. No OIB container then gets the Docker socket, the host's root filesystem, `/var/run`, `/var/lib/docker` or an added capability. Alloy (metrics) also runs as a non-root user with no capabilities. You give up automatic container log collection (push logs to Loki instead), container metrics (cAdvisor) and disk space per mount. Logs your apps push, host metrics, traces and profiles keep working. `make test-restricted` proves all of this on every change; see [restricted mode](docs/production-hardening.md#restricted-mode) for details.

The default single-host configuration is intended for development, homelabs, learning, and evaluation. Review the [production hardening guide](docs/production-hardening.md) before considering a production deployment.

## 📊 Data Retention

Default retention policies (adjust based on storage):

| Component | Retention | Where to change it |
|-----------|-----------|-------------|
| Loki (logs) | 7 days (`retention_period: 168h`, deleted by the compactor) | `logging/config/loki-config.yml` |
| Tempo (traces) | 3 days (`block_retention: 72h`) | `telemetry/config/tempo.yaml` |
| Prometheus (metrics) | 15 days or 5GB, whichever is hit first | `.env`: `PROMETHEUS_RETENTION_TIME` / `PROMETHEUS_RETENTION_SIZE` |
| Pyroscope (profiles) | Not set by OIB (Pyroscope's own defaults) | — |

See [docs/storage-retention.md](docs/storage-retention.md) for sizing and tuning.

## ⬆️ Upgrading

```bash
make backup                 # 1. consistent backup first (see below)
git pull                    # 2. new release (or: git checkout vX.Y.Z)
make migrate-tempo          # 3. only when coming from Tempo 2 (v1.0.0); a no-op otherwise
make update                 # 4. pull the pinned images and recreate the core stacks
make update-profiling       #    only if the profiling stack is installed
make health
```

`make update` also removes containers of services a release dropped (for example v1.0.0's `oib-node-exporter`) and keeps an installed Pushgateway on the pinned version.

What survives an upgrade is checked in CI on every change to the stacks (`make test-upgrade`, see [testing/acceptance](testing/acceptance/README.md)):

| Upgrading from | Logs | Metrics | Traces | Profiles | Grafana dashboards/users |
|---|---|---|---|---|---|
| v1.1.0 | kept | kept | kept | kept | kept |
| v1.0.0 | kept | kept | kept, with `make migrate-tempo` (see below) | kept | kept (volume migrated) |

- **Tempo 2 → 3** (upgrading from v1.0.0) is a migration, not an image refresh:
  - Tempo 3 ignores Tempo 2's write-ahead log, so recreating the container drops every trace Tempo 2 has not flushed to disk yet, which can be up to the last 5 minutes.
  - `make install`, `make update`, `make update-telemetry` and `make latest` therefore refuse to run while Tempo 2 is installed.
  - `make migrate-tempo` runs these steps. Afterwards every trace opens by ID, including those sent during the switch. The upgrade test checks this under continuous trace load.
    1. Pull the new images.
    2. Dry-run the new Tempo with the new config in a scratch container.
    3. Back up Tempo 2, and save its image and the config file it runs with, so a rollback is possible. That saved config is dry-run as well; if Tempo 2 would not start with it, the migration stops before changing anything. `NO_ROLLBACK=1` migrates without a rollback option.
    4. Make Tempo 2 flush everything to disk and stop accepting traces. Alloy queues them and retries.
    5. Recreate Tempo as version 3.
  - **If something goes wrong:**
    - If the pull or the dry run fails, nothing has changed and Tempo 2 keeps running.
    - If the run is interrupted after step 4, Tempo 2 is up but accepts no traces. Run `make migrate-tempo` again.
    - If the new Tempo does not become ready, Tempo 2's traces are already safe on disk. Either fix the cause and run `make update-telemetry SKIP_TEMPO_MIGRATION=1`, or go back with `make rollback-tempo`. The rollback restores Tempo 2 with its data from just before the migration; traces received after that are lost.
    - `make test-tempo-recovery` checks each of these cases.
  - **How long Alloy holds traces while Tempo is down:** up to 10 minutes per batch, and at most 1000 batches, in memory. After that, or if the Alloy container restarts, queued traces are dropped.
  - Run it right after `git pull`, before anything restarts Tempo: the pulled `tempo.yaml` is Tempo 3 syntax, so a restarted Tempo 2 crash-loops and can no longer be flushed. If that has already happened, its unflushed traces are gone; continue with `make update SKIP_TEMPO_MIGRATION=1`.
  - Search lags for a while: traces received in the 15 minutes before the migration appear in search once they are 15 minutes old. Tempo 3 answers searches over the last 15 minutes from its live store only.
  - To skip the migration and accept the loss, add `SKIP_TEMPO_MIGRATION=1`. Tempo 2 must be running for the flush; a stopped Tempo 2 cannot be flushed.
- **Grafana data from before 1.1.0.** Releases before 1.1.0 kept Grafana's data in the volume `oib-grafana_oib-grafana-data`; since 1.1.0 it is `oib-grafana-data`. `make install`/`make update` now move the data across automatically. If you already upgraded to 1.1.0, Grafana started empty there, but your old dashboards, users and settings are still in the old volume: `make update` points this out, and `make migrate-grafana-volume FORCE=1` brings them back (it backs up the current Grafana data first). Remove the old volume afterwards with `docker volume rm oib-grafana_oib-grafana-data`.

## 💾 Backup and Restore

```bash
make backup                  # Back up Prometheus, Loki, Tempo, Grafana (+ Pyroscope if installed)
make backup-loki             # Or one component: backup-prometheus/-loki/-tempo/-grafana/-pyroscope
make restore                 # List backups in ./backups and print restore commands
make restore-all STAMP=YYYYMMDD_HHMMSS             # Everything from one backup run
make restore-loki FILE=./backups/loki_YYYYMMDD_HHMMSS.tar.gz
```

- Backups are `./backups/<component>_YYYYMMDD_HHMMSS.tar.gz` (override with `make backup BACKUP_DIR=/path`), owned by the user who ran `make`; `backups/` is git-ignored. One `make backup` run gives every file the same timestamp.
- Each running component is **frozen with `docker pause` while its volume is archived** and unpaused right after. The freeze takes under a second, or about 10 s for a 90 MB Grafana volume. Requests arriving during a freeze wait.

**What a backup does and does not guarantee**

- **Guaranteed by design:**
  - An archive is the volume exactly as it was at one instant, because nothing in the container can write while it is frozen. That is a *crash-consistent* copy: the same state the disk would hold if the process had been killed at that moment.
  - Archives are complete or absent, never partial (see below).
- **Not guaranteed:** an *application-consistent* backup. OIB does not ask Prometheus, Loki, Tempo, Grafana or Pyroscope to checkpoint or flush first.
  - Whatever a component held only in memory at the freeze is not in the archive.
  - Restoring relies on each component's crash recovery: write-ahead-log replay, or SQLite journal recovery for Grafana.
  - Derived files can be caught mid-write too. CI has seen Pyroscope's bucket index (a cached listing of its blocks) come back corrupt from a frozen copy. Pyroscope logged `corrupted bucket index found, falling back to fetching directly from bucket` and rebuilt the index; every profile was restored.
  - Prometheus would need its snapshot API (`--web.enable-admin-api`) for an application-consistent copy. Tempo 3 has no flush API at all.
- **Observed under test, not guaranteed:** `make test-backup` restores archives taken while logs and traces are being written. It has always found:
  - every log line Loki acknowledged before its freeze;
  - every trace sent more than 10 s before Tempo's freeze;
  - no corruption or repair messages from any component.

  These are results under the tested load and versions (CI runs them on every change and weekly), not a promise for every workload. Traces from the last seconds before a freeze can be lost, as in a crash: they may still be in Alloy's batch or in Tempo's newest, unfinished block.
- If you need application-consistent backups, stop the stack for the backup (`make stop && make backup && make start`) and accept the gap in collection.

- Covers Prometheus, Loki, Tempo, Grafana and, when the profiling stack is installed, Pyroscope. The shared-services volumes (PostgreSQL, Redis) are not backed up.
- An archive is written under a `.partial` name and renamed only when complete. A failed or interrupted backup unpauses the container and leaves no file behind. A container left paused by a killed backup is unpaused by the next one.
- `restore-*` asks for confirmation (`YES=1` skips it), checks that the archive is readable, stops that one service, **replaces the current volume contents** with the archive and starts the service again. `FILE` may be relative or absolute. The component's stack must be installed first.
- `make test-backup ISOLATED=1` proves the whole cycle in a throwaway Docker-in-Docker daemon, so it is safe next to your install. It writes known data, backs up under write load, wipes every volume, restores and checks the data is back. It also checks that failed and interrupted backups clean up (see [testing/acceptance](testing/acceptance/README.md)).

## 💡 Tips

1. **Persist data**: Data is stored in named Docker volumes (`oib-grafana-data`, `oib-loki-data`, `oib-prometheus-data`, `oib-tempo-data`, `oib-pyroscope-data`). `make uninstall*` deletes them.
2. **Resource limits**: Adjust memory/CPU limits in the stacks' `compose.yaml` files for your hardware
3. **Ports**: Default ports can be changed via environment variables (see `.env.example`), then applied with `make install`
4. **Known limitations**: see [docs/troubleshooting.md](docs/troubleshooting.md#known-limitations)

## 🧰 Troubleshooting

### Common Issues

<details>
<summary><b>Docker is not running</b></summary>

```bash
# Check Docker status
docker info

# macOS: Start Docker Desktop from Applications
# Linux: sudo systemctl start docker
```
</details>

<details>
<summary><b>Port already in use</b></summary>

```bash
# Check which ports are in use
make check-ports

# Find what's using a specific port
lsof -i :3000

# Change ports in .env file
GRAFANA_PORT=3001

# Apply (recreates the affected containers, keeps data)
make install
```
</details>

<details>
<summary><b>Services not healthy</b></summary>

```bash
# Run diagnostics
make doctor

# Check service logs
make logs-grafana
make logs-logging
make logs-metrics
make logs-telemetry

# Restart services
make restart
```
</details>

<details>
<summary><b>Permission denied (Linux)</b></summary>

```bash
# Add your user to docker group
sudo usermod -aG docker $USER

# Log out and back in, or run:
newgrp docker
```
</details>

<details>
<summary><b>Traces not appearing in Tempo</b></summary>

```bash
# Verify OTLP endpoint is accessible
curl -v http://localhost:4318/v1/traces

# Check Alloy telemetry logs
make logs-telemetry

# Ensure your app uses correct endpoint:
# - From host: localhost:4317 (gRPC) or localhost:4318 (HTTP)
# - From Docker: oib-alloy-telemetry:4317 on oib-network
```
</details>

<details>
<summary><b>Logs not appearing in Loki</b></summary>

```bash
# Verify Loki is ready
curl http://localhost:3100/ready

# Check Alloy logging pipeline
curl http://localhost:12345/metrics | grep loki

# Push a test line and check it is searchable
make demo

# Alloy reads every container through the Docker socket (no network
# membership needed); check its log for socket or push errors
docker logs oib-alloy-logging
```
</details>

<details>
<summary><b>High memory usage</b></summary>

```bash
# Check container resource usage
docker stats

# Reduce retention:
# - logging/config/loki-config.yml: retention_period (then make restart-logging)
# - telemetry/config/tempo.yaml: block_retention (then make restart-telemetry)
# - .env: PROMETHEUS_RETENTION_SIZE / _TIME (then make install-metrics)
```
</details>

### Still having issues?

1. Run `make doctor` for automated diagnostics
2. Check `make logs` for error messages
3. [Open an issue](https://github.com/matijazezelj/oib/issues) with the output of `make doctor`

## 🤝 Contributing

PRs welcome! Please follow the existing structure when adding new stacks.

## 📄 License

This project is licensed under the [MIT License](LICENSE).

Third-party containers and software retain their upstream licenses and are not relicensed under MIT. See [NOTICE.md](NOTICE.md) for attribution, trademark, and third-party licensing information.

The Grafana Labs Marks are trademarks of Grafana Labs, and are used with Grafana Labs’ permission. We are not affiliated with, endorsed or sponsored by Grafana Labs or its affiliates.

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=matijazezelj/oib&type=date&legend=top-left)](https://www.star-history.com/#matijazezelj/oib&type=date&legend=top-left)
