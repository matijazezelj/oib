# Observability in a Box (OIB)

A plug-and-play observability stack for homelab users. Clone, run, and get instant observability for your projects using Grafana's LGTM stack.

## 🚀 Quick Start

```bash
# Clone the repo
git clone <repo-url> oib && cd oib

# Install all stacks
make install

# Or install individual stacks
make install-logging    # Loki + Alloy
make install-metrics    # Prometheus + Node Exporter + cAdvisor
make install-telemetry  # Tempo + Alloy
make install-grafana    # Unified Grafana with all datasources
```

## 📦 What's Included

| Stack | Components | Purpose |
|-------|------------|--------|
| **Logging** | Loki, Alloy | Centralized log aggregation |
| **Metrics** | Prometheus, Pushgateway, Node Exporter, cAdvisor | Metrics collection (host & containers) |
| **Telemetry** | Tempo, Alloy | Distributed tracing |
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
- **Pushgateway**: `http://localhost:9091` (localhost only)
- **Node Exporter**: `http://localhost:9100` (localhost only)
- **cAdvisor**: `http://localhost:8080` (localhost only)

> **From Docker containers**: Use hostnames like `oib-prometheus:9090` on `oib-network`

### Telemetry Stack
- **OTLP gRPC**: `<host>:4317` ✅ Public - accepts traces from anywhere
- **OTLP HTTP**: `http://<host>:4318` ✅ Public - accepts traces from anywhere
- **Tempo API**: `http://localhost:3200` (localhost only)

> **From Docker containers**: Use `oib-alloy-telemetry:4317` on `oib-network`

### Grafana
- **Grafana UI**: `http://<host>:3000` ✅ Public
- **Credentials**: Set in root `.env` (copy from `.env.example`)

### 📊 Pre-built Dashboards

OIB comes with three ready-to-use dashboards:

| Dashboard | Description |
|-----------|-------------|
| **System Overview** | Host metrics, container CPU/memory, disk usage |
| **Logs Explorer** | Log volume, live logs, errors/warnings panel |
| **Traces Explorer** | TraceQL examples, Python & Node.js code samples |

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
| `PUSHGATEWAY_PORT` | `9091` | Pushgateway port (localhost only) |
| `NODE_EXPORTER_PORT` | `9100` | Node Exporter port (localhost only) |
| `CADVISOR_PORT` | `8080` | cAdvisor port (localhost only) |
| `TEMPO_HTTP_PORT` | `3200` | Tempo HTTP API port (localhost only) |
| `TEMPO_GRPC_PORT` | `9095` | Tempo gRPC port (localhost only) |
| `OTEL_GRPC_PORT` | `4317` | OTLP gRPC receiver (public) |
| `OTEL_HTTP_PORT` | `4318` | OTLP HTTP receiver (public) |
| `PROMETHEUS_RETENTION_TIME` | `15d` | Prometheus data retention time |
| `PROMETHEUS_RETENTION_SIZE` | `5GB` | Prometheus data retention size |

> **Note**: Loki and Tempo retention are configured in their respective config files, not via environment variables.

## 🛠️ Commands

```bash
# Installation
make install              # Install all stacks
make install-logging      # Install logging stack only
make install-metrics      # Install metrics stack only
make install-telemetry    # Install telemetry stack only
make install-grafana      # Install unified Grafana

# Status & Info
make status               # Show status of all stacks
make info                 # Show integration endpoints for all stacks
make info-logging         # Show logging integration info
make info-metrics         # Show metrics integration info
make info-telemetry       # Show telemetry integration info
make info-grafana         # Show Grafana info

# Management
make stop                 # Stop all stacks
make stop-logging         # Stop logging stack
make stop-metrics         # Stop metrics stack
make stop-telemetry       # Stop telemetry stack
make stop-grafana         # Stop Grafana

make start                # Start all stacks
make restart              # Restart all stacks

# Cleanup
make uninstall            # Remove all stacks and volumes
make uninstall-logging    # Remove logging stack
make uninstall-metrics    # Remove metrics stack
make uninstall-telemetry  # Remove telemetry stack
make uninstall-grafana    # Remove Grafana

# Logs
make logs                 # Tail logs from all stacks
make logs-logging         # Tail logging stack logs
make logs-metrics         # Tail metrics stack logs
make logs-telemetry       # Tail telemetry stack logs
make logs-grafana         # Tail Grafana logs
```

## 📁 Project Structure

```
oib/
├── Makefile                    # Main entry point
├── README.md
├── logging/
│   ├── docker-compose.yml
│   └── config/
│       ├── loki-config.yml
│       └── alloy-config.alloy
├── metrics/
│   ├── docker-compose.yml
│   └── config/
│       └── prometheus.yml
├── telemetry/
│   ├── docker-compose.yml
│   └── config/
│       └── alloy-config.alloy
├── grafana/
│   ├── docker-compose.yml
│   └── provisioning/
│       ├── datasources/
│       │   └── datasources.yml
│       └── dashboards/
│           └── json/
│               ├── system-overview.json
│               ├── logs-explorer.json
│               └── traces-explorer.json
└── examples/
    ├── README.md               # Example integration guide
    ├── python-flask/           # Python Flask example app
    └── node-express/           # Node.js Express example app
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
# In your app's docker-compose.yml
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

> 💡 See `examples/` for complete working Python Flask and Node.js Express apps with full observability.

## 🌐 Network

All stacks run on a shared Docker network `oib-network` allowing inter-service communication.

## 🔒 Security

OIB includes security hardening for homelab use:

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
| Prometheus (metrics) | 15 days or 5GB | `metrics/docker-compose.yml` |

## 💡 Tips

1. **Persist data**: All data is stored in Docker volumes prefixed with `oib-`
2. **Resource limits**: Adjust memory/CPU limits in docker-compose files for your hardware
3. **Ports**: Default ports can be changed via environment variables (see `.env.example`)

## 📋 Requirements

- Docker 20.10+
- Docker Compose v2+
- Make
- 2GB+ RAM recommended

## 🤝 Contributing

PRs welcome! Please follow the existing structure when adding new stacks.

## 📄 License

MIT
