# Observability in a Box (OIB)

A plug-and-play observability stack for homelab users. Clone, run, and get instant observability for your projects using Grafana's LGTM stack.

## 🚀 Quick Start

```bash
# Clone the repo
git clone <repo-url> oib && cd oib

# Install all stacks
make install

# Or install individual stacks
make install-logging    # Loki + Alloy + Grafana
make install-metrics    # Prometheus + Grafana
make install-telemetry  # Tempo + Alloy + Grafana
```

## 📦 What's Included

| Stack | Components | Purpose |
|-------|------------|---------||
| **Logging** | Loki, Alloy, Grafana | Centralized log aggregation |
| **Metrics** | Prometheus, Grafana | Metrics collection and visualization |
| **Telemetry** | Tempo, Alloy, Grafana | Distributed tracing |

## 🔌 Integration Endpoints

After installation, each stack will display integration endpoints:

### Logging Stack
- **Push logs via Loki API**: `http://localhost:3100/loki/api/v1/push`
- **Alloy UI**: `http://localhost:12345` (view pipeline status)
- **Auto-collection**: Alloy automatically collects logs from all Docker containers
- **Grafana UI**: `http://localhost:3000`

### Metrics Stack
- **Prometheus scrape endpoint**: Configure your apps to expose `/metrics` on port `9090`
- **Push metrics**: `http://localhost:9091` (Pushgateway)
- **Grafana UI**: `http://localhost:3001`

### Telemetry Stack
- **OTLP gRPC**: `localhost:4317`
- **OTLP HTTP**: `http://localhost:4318`
- **Grafana UI**: `http://localhost:3002`

## 🛠️ Commands

```bash
# Installation
make install              # Install all stacks
make install-logging      # Install logging stack only
make install-metrics      # Install metrics stack only
make install-telemetry    # Install telemetry stack only

# Status & Info
make status               # Show status of all stacks
make info                 # Show integration endpoints for all stacks
make info-logging         # Show logging integration info
make info-metrics         # Show metrics integration info
make info-telemetry       # Show telemetry integration info

# Management
make stop                 # Stop all stacks
make stop-logging         # Stop logging stack
make stop-metrics         # Stop metrics stack
make stop-telemetry       # Stop telemetry stack

make start                # Start all stacks
make restart              # Restart all stacks

# Cleanup
make uninstall            # Remove all stacks and volumes
make uninstall-logging    # Remove logging stack
make uninstall-metrics    # Remove metrics stack
make uninstall-telemetry  # Remove telemetry stack

# Logs
make logs                 # Tail logs from all stacks
make logs-logging         # Tail logging stack logs
make logs-metrics         # Tail metrics stack logs
make logs-telemetry       # Tail telemetry stack logs
```

## 📁 Project Structure

```
oib/
├── Makefile                    # Main entry point
├── README.md
├── scripts/
│   ├── info.sh                 # Display integration info
│   └── status.sh               # Check stack status
├── logging/
│   ├── docker-compose.yml
│   └── config/
│       ├── loki-config.yml
│       └── promtail-config.yml
├── metrics/
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

### Custom Log Sources

Edit `logging/config/promtail-config.yml` to add log sources:

```yaml
scrape_configs:
  - job_name: my-app
    static_configs:
      - targets:
          - localhost
        labels:
          job: my-app
          __path__: /var/log/my-app/*.log
```

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

## 📊 Default Credentials

- **Grafana**: `admin` / `admin` (you'll be prompted to change on first login)

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
