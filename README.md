# Observability in a Box (OIB)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A plug-and-play observability stack for developers. Zero config, production-ready patterns. Clone, run, and get instant observability for your projects using Grafana's LGTM stack.
> **Quick Reference**: `make install` → `make demo` → `make open` → Explore your data!  
> **One-command path**: `make bootstrap`
## 📋 Prerequisites

Before you begin, ensure you have:

- **Docker** 20.10+ ([Install Docker](https://docs.docker.com/get-docker/)) or **Podman** 4.0+ with podman-compose
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
# Edit .env and set a secure GRAFANA_ADMIN_PASSWORD

# Install all stacks
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
```

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

Then open **http://localhost:3000** in your browser and log in with credentials from your `.env` file.

### 🎬 Try It Out

After installation, generate some demo data to see everything working:

```bash
# Generate sample logs, metrics, and traces
make demo

# Open Grafana in your browser
make open
```

This creates sample data across all three pillars so you can immediately explore the dashboards.

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
- **Auto-collection**: Alloy automatically collects logs from all Docker containers

> **From Docker containers**: Use `oib-loki:3100` on `oib-network`

### Metrics Stack
- **Prometheus**: `http://localhost:9090` (localhost only)
- **Alloy Metrics UI**: `http://localhost:12347` (host metrics pipeline)
- **cAdvisor**: `http://localhost:8080` (localhost only)

> **From Docker containers**: Use hostnames like `oib-prometheus:9090` on `oib-network`

### Telemetry Stack
- **OTLP gRPC**: `<host>:4317` ✅ Public - accepts traces from anywhere
- **OTLP HTTP**: `http://<host>:4318` ✅ Public - accepts traces from anywhere
- **Tempo API**: `http://localhost:3200` (localhost only)

> **From Docker containers**: Use `oib-alloy-telemetry:4317` on `oib-network`

### Profiling Stack (Optional)
- **Pyroscope**: `http://localhost:4040` (localhost only)
- **Install**: `make install-profiling`

> **From Docker containers**: Use `oib-pyroscope:4040` on `oib-network`

### Grafana
- **Grafana UI**: `http://<host>:3000` ✅ Public
- **Credentials**: Set in root `.env` (copy from `.env.example`)

### 📊 Pre-built Dashboards

OIB comes with six ready-to-use dashboards:

| Dashboard | Description |
|-----------|-------------|
| **System Overview** | Container CPU/memory, disk usage, network I/O |
| **Host Metrics** | Detailed host system metrics (CPU, memory, disk, network) via Alloy |
| **Logs Explorer** | Log volume, live logs, errors/warnings panel |
| **Traces Explorer** | TraceQL examples, Python, Node.js, Ruby & PHP code samples |
| **Profiles Explorer** | CPU, memory, and goroutine profiling with Pyroscope |
| **Request Latency** | Endpoint probing (Blackbox), k6 load test metrics, latency percentiles |

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
| `GRAFANA_ADMIN_PASSWORD` | (required) | Grafana admin password |
| `GRAFANA_PORT` | `3000` | Grafana web UI port |
| `LOKI_PORT` | `3100` | Loki API port (localhost only) |
| `PROMETHEUS_PORT` | `9090` | Prometheus API port (localhost only) |
| `ALLOY_METRICS_PORT` | `12347` | Alloy metrics UI port (localhost only) |
| `CADVISOR_PORT` | `8080` | cAdvisor port (localhost only) |
| `BLACKBOX_PORT` | `9115` | Blackbox Exporter port (localhost only) |
| `TEMPO_HTTP_PORT` | `3200` | Tempo HTTP API port (localhost only) |
| `TEMPO_GRPC_PORT` | `9095` | Tempo gRPC port (localhost only) |
| `OTEL_GRPC_PORT` | `4317` | OTLP gRPC receiver (public) |
| `OTEL_HTTP_PORT` | `4318` | OTLP HTTP receiver (public) |
| `PROMETHEUS_RETENTION_TIME` | `15d` | Prometheus data retention time |
| `PROMETHEUS_RETENTION_SIZE` | `5GB` | Prometheus data retention size |

> **Note**: Loki and Tempo retention are configured in their respective config files, not via environment variables.

### Image Version Overrides

By default, OIB uses pinned (stable) versions for all images. You can override these in your `.env` file:

| Variable | Default | Description |
|----------|---------|-------------|
| `GRAFANA_VERSION` | `11.3.1` | Grafana image tag |
| `LOKI_VERSION` | `3.3.2` | Loki image tag |
| `ALLOY_VERSION` | `v1.5.1` | Alloy image tag |
| `PROMETHEUS_VERSION` | `v2.48.1` | Prometheus image tag |
| `CADVISOR_VERSION` | `v0.47.2` | cAdvisor image tag |
| `BLACKBOX_VERSION` | `v0.25.0` | Blackbox Exporter image tag |
| `TEMPO_VERSION` | `2.6.1` | Tempo image tag |

**Quick commands:**
```bash
# Run all services with :latest images
make latest

# Revert to pinned (stable) versions
make install

# Override a single service version
GRAFANA_VERSION=12.0.0 make update-grafana
```

## 🛠️ Commands

```bash
# Installation
make install              # Install all stacks
make install-logging      # Install logging stack only
make install-metrics      # Install metrics stack only
make install-telemetry    # Install telemetry stack only
make install-grafana      # Install unified Grafana

# Health & Diagnostics
make health               # Quick health check of all services
make doctor               # Diagnose common issues (Docker, ports, config)
make status               # Show all services with health indicators
make check-ports          # Check if required ports are available
make ps                   # Show running OIB containers
make validate             # Validate configuration files

# Load Testing
make test-load            # Run k6 basic load test
make test-stress          # Run stress test (find breaking point)
make test-spike           # Run spike test (sudden traffic)
make test-api             # Run API endpoint load test

# Utilities
make open                 # Open Grafana in browser
make demo                 # Generate sample data (logs, metrics, traces)
make demo-examples        # Run example apps and generate traffic
make bootstrap            # Install + demo + open Grafana
make disk-usage           # Show disk space used by OIB
make version              # Show versions of running components

# Management
make stop                 # Stop all stacks
make start                # Start all stacks
make restart              # Restart all stacks
make info                 # Show integration endpoints

# Logs
make logs                 # Tail logs from all stacks
make logs-grafana         # Tail Grafana logs
make logs-logging         # Tail Loki + Alloy logs
make logs-metrics         # Tail Prometheus + exporters logs
make logs-telemetry       # Tail Tempo + Alloy logs
make logs-profiling       # Tail Pyroscope logs

# Maintenance
make update               # Pull pinned version images and restart
make update-grafana       # Update Grafana only
make update-logging       # Update Loki + Alloy
make update-metrics       # Update Prometheus + exporters
make update-telemetry     # Update Tempo + Alloy
make latest               # Pull and run :latest versions of all images
make clean                # Remove unused Docker resources

# Cleanup
make uninstall            # Remove all stacks and volumes (with confirmation)
```

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
│       └── rules/              # Alerting rules (future)
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
│           └── json/
│               ├── system-overview.json
│               ├── host-metrics.json
│               ├── logs-explorer.json
│               ├── traces-explorer.json
│               ├── profiles-explorer.json
│               └── request-latency.json
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
    ├── python-flask/           # Python Flask example app
    ├── node-express/           # Node.js Express example app
    ├── ruby-rails/             # Ruby on Rails example app
    └── php-laravel/            # PHP Laravel example app
```

## 🔧 Configuration

### Custom Prometheus Scrape Targets

Edit `metrics/config/prometheus.yml` to add your services:

```yaml
scrape_configs:
  - job_name: 'my-app'
    static_configs:
      - targets: ['host.docker.internal:8080']
```

### Container Metrics

cAdvisor collects container metrics automatically. In the System Overview dashboard, containers are displayed by their **short ID** (first 12 characters), which matches the output of `docker ps`. Use `docker ps` on your host to map IDs to container names.

## 🐳 Docker Integration Examples

### Send container logs to Loki

```yaml
# In your app's compose.yaml
services:
  my-app:
    logging:
      driver: loki
      options:
        loki-url: "http://localhost:3100/loki/api/v1/push"
        labels: "app"
```

### Expose Prometheus metrics

```yaml
services:
  my-app:
    labels:
      - "prometheus.scrape=true"
      - "prometheus.port=8080"
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

- HTTP/HTTPS endpoint health checks
- TCP port connectivity tests  
- ICMP ping, DNS resolution, gRPC health checks
- SSL certificate validation

### Default Monitored Endpoints

OIB monitors its own services by default:
- Grafana, Prometheus, Loki, Tempo

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

## 🌐 Network

All stacks run on a shared Docker network `oib-network` allowing inter-service communication.

## 🔒 Security

OIB includes security hardening for local and self-hosted deployments:

- **No default passwords**: Grafana credentials configured via `.env` file
- **Localhost binding**: Internal services (Prometheus, Loki, Tempo, etc.) only listen on `127.0.0.1`
- **Non-privileged containers**: cAdvisor uses minimal capabilities instead of privileged mode
- **Resource limits**: All containers have CPU/memory limits
- **No-new-privileges**: Containers cannot gain additional privileges
- **Non-root users**: Example apps run as non-root users

**Public ports** (intentionally exposed for external access):
- `3000` - Grafana UI
- `4317/4318` - OTLP endpoints for trace ingestion

## 📊 Data Retention

Default retention policies (adjust in config files based on storage):

| Component | Retention | Config File |
|-----------|-----------|-------------|
| Loki (logs) | 7 days | `logging/config/loki-config.yml` |
| Tempo (traces) | 3 days | `telemetry/config/tempo.yaml` |
| Prometheus (metrics) | 15 days or 5GB | `metrics/compose.yaml` |

## 💡 Tips

1. **Persist data**: All data is stored in Docker volumes prefixed with `oib-`
2. **Resource limits**: Adjust memory/CPU limits in docker-compose files for your hardware
3. **Ports**: Default ports can be changed via environment variables (see `.env.example`)

## � Troubleshooting

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

# Ensure containers are on oib-network for auto-collection
docker network inspect oib-network
```
</details>

<details>
<summary><b>High memory usage</b></summary>

```bash
# Check container resource usage
docker stats

# Reduce retention in config files:
# - logging/config/loki-config.yml: retention_period
# - telemetry/config/tempo.yaml: block_retention
# - metrics/compose.yaml: --storage.tsdb.retention.size
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

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=matijazezelj/oib&type=date&legend=top-left)](https://www.star-history.com/#matijazezelj/oib&type=date&legend=top-left)
