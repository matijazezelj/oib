# Grafana

Unified visualization dashboard for logs, metrics, and traces.

## Components

| Service | Port | Description |
|---------|------|-------------|
| **Grafana** | 3000 (public) | Web UI for visualization |

## Features

- **Unified observability**: Single pane for logs, metrics, and traces
- **Pre-configured datasources**: Loki, Prometheus, and Tempo auto-provisioned
- **Built-in dashboards**: System Overview, Logs Explorer, Traces Explorer, Request Latency
- **Explore mode**: Ad-hoc querying with LogQL, PromQL, and TraceQL

## Quick Start

```bash
# Install from repo root
make install-grafana

# Open in browser
make open

# Check status
make status
```

## Configuration

### Credentials
Set in root `.env` file:
```bash
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=your-secure-password
```

### Provisioning
- **Datasources**: `provisioning/datasources/datasources.yml`
- **Dashboards**: `provisioning/dashboards/json/`

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GRAFANA_ADMIN_USER` | `admin` | Admin username |
| `GRAFANA_ADMIN_PASSWORD` | (required) | Admin password |
| `GRAFANA_PORT` | `3000` | Web UI port |
| `GRAFANA_VERSION` | `11.3.1` | Grafana image tag |

## Pre-built Dashboards

| Dashboard | Description |
|-----------|-------------|
| **System Overview** | Host metrics, container CPU/memory, disk usage |
| **Logs Explorer** | Log volume, live logs, errors/warnings panel |
| **Traces Explorer** | TraceQL examples, language-specific code samples |
| **Request Latency** | Endpoint probing, k6 load test metrics |

## Adding Custom Dashboards

### Method 1: Grafana UI
1. Create dashboard in Grafana
2. Save it
3. Export JSON via Share → Export → Save to file
4. Place in `provisioning/dashboards/json/`

### Method 2: Direct JSON
1. Create JSON file in `provisioning/dashboards/json/`
2. Restart Grafana: `make restart-grafana`

## Datasources

Pre-configured datasources:

| Name | Type | URL |
|------|------|-----|
| Loki | Logs | `http://oib-loki:3100` |
| Prometheus | Metrics | `http://oib-prometheus:9090` |
| Tempo | Traces | `http://oib-tempo:3200` |

## Troubleshooting

```bash
# Check Grafana health
curl http://localhost:3000/api/health

# View logs
docker logs oib-grafana

# Reset password (if forgotten)
docker exec -it oib-grafana grafana-cli admin reset-admin-password newpassword

# Restart Grafana
make restart-grafana
```

## Useful Links

- **Grafana UI**: http://localhost:3000
- **API Health**: http://localhost:3000/api/health
- **Datasources API**: http://localhost:3000/api/datasources
