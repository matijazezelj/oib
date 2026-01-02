# Metrics Stack

Metrics collection and monitoring using Prometheus and Alloy.

## Components

| Service | Port | Description |
|---------|------|-------------|
| **Prometheus** | 9090 (localhost) | Metrics storage and querying |
| **Alloy** | 12347 (localhost) | Host system metrics collection |
| **cAdvisor** | 8080 (localhost) | Container metrics |
| **Blackbox Exporter** | 9115 (localhost) | Endpoint probing |

## Features

- **Pull-based collection**: Prometheus scrapes metrics endpoints
- **Host monitoring**: CPU, memory, disk, network via Alloy (built-in unix exporter)
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

### Alloy Metrics Configuration
Edit `config/alloy-metrics.alloy`:
- `prometheus.exporter.unix`: Configure host metrics collectors
- `prometheus.remote_write`: Configure Prometheus endpoint

### Blackbox Configuration
Edit `config/blackbox.yml`:
- Define probe modules (http, tcp, icmp, etc.)

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PROMETHEUS_PORT` | `9090` | Prometheus UI/API port |
| `ALLOY_METRICS_PORT` | `12347` | Alloy metrics UI port |
| `CADVISOR_PORT` | `8080` | cAdvisor port |
| `BLACKBOX_PORT` | `9115` | Blackbox Exporter port |
| `PROMETHEUS_RETENTION_TIME` | `15d` | Data retention time |
| `PROMETHEUS_RETENTION_SIZE` | `5GB` | Max storage size |
| `PROMETHEUS_VERSION` | `v2.48.1` | Prometheus image tag |
| `ALLOY_VERSION` | `v1.5.1` | Alloy image tag |
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

## Optional: Pushgateway

For batch jobs that need to push metrics, enable Pushgateway:

```bash
# Start with pushgateway profile
cd metrics && docker compose --profile pushgateway up -d

# Then push metrics from your scripts
echo "backup_duration_seconds 42" | curl --data-binary @- \
  http://localhost:9091/metrics/job/backup/instance/server1
```

## Endpoint Probing

Blackbox Exporter probes endpoints defined in `config/prometheus.yml`:

```yaml
- job_name: 'blackbox-http'
  metrics_path: /probe
  params:
    module: [http_2xx]
  static_configs:
    - targets:
      - http://your-app:8080/health
  relabel_configs:
    - source_labels: [__address__]
      target_label: __param_target
    - source_labels: [__param_target]
      target_label: instance
    - target_label: __address__
      replacement: blackbox-exporter:9115
```

## Troubleshooting

```bash
# Check Prometheus status
curl http://localhost:9090/-/ready

# Check Alloy metrics pipeline
curl http://localhost:12347/-/ready

# View metrics being collected
curl http://localhost:12347/metrics | grep node_

# Check cAdvisor
curl http://localhost:8080/healthz
```
