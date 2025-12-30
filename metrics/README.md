# Metrics Stack

Metrics collection and monitoring using Prometheus and exporters.

## Components

| Service | Port | Description |
|---------|------|-------------|
| **Prometheus** | 9090 (localhost) | Metrics storage and querying |
| **Pushgateway** | 9091 (localhost) | Push metrics for batch jobs |
| **Node Exporter** | 9100 (localhost) | Host system metrics |
| **cAdvisor** | 8080 (localhost) | Container metrics |
| **Blackbox Exporter** | 9115 (localhost) | Endpoint probing |

## Features

- **Pull-based collection**: Prometheus scrapes metrics endpoints
- **Push support**: Pushgateway for batch jobs and scripts
- **Host monitoring**: CPU, memory, disk, network via Node Exporter
- **Container monitoring**: Per-container resources via cAdvisor
- **Endpoint probing**: HTTP, TCP, ICMP health checks via Blackbox

## Quick Start

```bash
# Install from repo root
make install-metrics

# Check status
make status

# View logs
make logs-metrics
```

## Configuration

### Prometheus Configuration
Edit `config/prometheus.yml`:
- `scrape_configs`: Define targets to scrape
- `global.scrape_interval`: How often to scrape (default: 15s)

### Blackbox Configuration
Edit `config/blackbox.yml`:
- Define probe modules (http, tcp, icmp, etc.)

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PROMETHEUS_PORT` | `9090` | Prometheus UI/API port |
| `PUSHGATEWAY_PORT` | `9091` | Pushgateway port |
| `NODE_EXPORTER_PORT` | `9100` | Node Exporter port |
| `CADVISOR_PORT` | `8080` | cAdvisor port |
| `BLACKBOX_PORT` | `9115` | Blackbox Exporter port |
| `PROMETHEUS_RETENTION_TIME` | `15d` | Data retention time |
| `PROMETHEUS_RETENTION_SIZE` | `5GB` | Max storage size |
| `PROMETHEUS_VERSION` | `v2.48.1` | Prometheus image tag |
| `PUSHGATEWAY_VERSION` | `v1.6.2` | Pushgateway image tag |
| `NODE_EXPORTER_VERSION` | `v1.7.0` | Node Exporter image tag |
| `CADVISOR_VERSION` | `v0.47.2` | cAdvisor image tag |
| `BLACKBOX_VERSION` | `v0.25.0` | Blackbox image tag |

## Adding Scrape Targets

Edit `config/prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'my-app'
    static_configs:
      - targets: ['host.docker.internal:8080']
    # Or from Docker network:
    # - targets: ['my-app:8080']
```

Then restart: `make restart-metrics`

## Pushing Metrics

### From Shell Scripts
```bash
# Push a simple metric
echo "backup_duration_seconds 42" | curl --data-binary @- \
  http://localhost:9091/metrics/job/backup/instance/server1
```

### From Applications
Use any Prometheus client library to push to `http://localhost:9091`.

## Endpoint Probing

Blackbox Exporter probes endpoints defined in `config/prometheus.yml`:

```yaml
- job_name: 'blackbox-http'
  metrics_path: /probe
  params:
    module: [http_2xx]
  static_configs:
    - targets:
      - http://my-app:8080/health
      - https://api.example.com
  relabel_configs:
    - source_labels: [__address__]
      target_label: __param_target
    - source_labels: [__param_target]
      target_label: instance
    - target_label: __address__
      replacement: oib-blackbox-exporter:9115
```

## Troubleshooting

```bash
# Check Prometheus targets
open http://localhost:9090/targets

# Query metrics
curl 'http://localhost:9090/api/v1/query?query=up'

# Check Pushgateway metrics
curl http://localhost:9091/metrics

# View Node Exporter metrics
curl http://localhost:9100/metrics
```
