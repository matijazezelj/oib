# Logging Stack

Centralized log aggregation using Grafana Loki and Alloy.

## Components

| Service | Port | Description |
|---------|------|-------------|
| **Loki** | 3100 (localhost) | Log storage and querying |
| **Alloy** | 12345 (localhost) | Log collection agent |

## Features

- **Auto-collection**: Alloy automatically collects logs from all Docker containers
- **Efficient storage**: Loki uses label-based indexing (like Prometheus for logs)
- **LogQL**: Query logs using Grafana's LogQL language

## Quick Start

```bash
# Install from repo root
make install-logging

# Check status
make status

# View logs
make logs-logging
```

## Configuration

### Loki Configuration
Edit `config/loki-config.yml`:
- `retention_period`: How long to keep logs (default: 168h = 7 days)
- `ingestion_rate_mb`: Max ingestion rate per tenant

### Alloy Configuration
Edit `config/alloy-config.alloy`:
- Docker log collection pipeline
- Label extraction rules
- Loki push endpoint

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LOKI_PORT` | `3100` | Loki API port |
| `ALLOY_LOGGING_PORT` | `12345` | Alloy UI port |
| `LOKI_VERSION` | `3.6.5` | Loki image tag |
| `ALLOY_VERSION` | `v1.13.0` | Alloy image tag |

## Sending Logs

### From Docker Containers (Automatic)
Alloy discovers and collects logs from every running container through the Docker socket, including containers outside `oib-network`.

> [!IMPORTANT]
> Container logs can contain credentials, tokens, personal data, or other sensitive values. Add discovery relabel rules in `config/alloy-config.alloy` if collection should be limited to selected containers.

### Direct Push to Loki
```bash
curl -X POST "http://localhost:3100/loki/api/v1/push" \
  -H "Content-Type: application/json" \
  -d '{"streams":[{"stream":{"app":"test"},"values":[["'"$(date +%s)000000000"'","Hello from curl!"]]}]}'
```

### Using Loki Docker Driver
```yaml
services:
  my-app:
    logging:
      driver: loki
      options:
        loki-url: "http://host.docker.internal:3100/loki/api/v1/push"
```

## Troubleshooting

```bash
# Check if Loki is ready
curl http://localhost:3100/ready

# View Alloy pipeline status
open http://localhost:12345

# Check Loki logs
docker logs oib-loki
```
