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
- **Push logs via Loki API**: `http://<host>:3100/loki/api/v1/push`
- **Alloy UI**: `http://<host>:12345` (view pipeline status)
- **Auto-collection**: Alloy automatically collects logs from all Docker containers

### Metrics Stack
- **Prometheus**: `http://<host>:9090`
- **Push metrics**: `http://<host>:9091` (Pushgateway)
- **Node Exporter**: `http://<host>:9100` (host metrics)
- **cAdvisor**: `http://<host>:8080` (container metrics)

### Telemetry Stack
- **OTLP gRPC**: `<host>:4317` (from Docker: `oib-alloy-telemetry:4317`)
- **OTLP HTTP**: `http://<host>:4318`

### Grafana
- **Grafana UI**: `http://<host>:3000`
- **Default credentials**: `admin` / `admin`

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
    ├── python-flask/           # Python Flask example app
    └── nodejs-express/         # Node.js Express example app
```
│   ├── docker-compose.yml
│   └── config/
│       └── prometheus.yml
├── telemetry/
│   ├── docker-compose.yml
│   └── config/
│       └── otel-collector-config.yml
└── grafana/
    └── provisioning/
        ├── datasources/
        └── dashboards/
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
// Node.js example
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');

const exporter = new OTLPTraceExporter({
  url: 'http://localhost:4317',
});
```

## 🌐 Network

All stacks run on a shared Docker network `oib-network` allowing inter-service communication.

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
