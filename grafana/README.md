# Grafana

Unified visualization dashboard for logs, metrics, and traces.

## Components

| Service | Port | Description |
|---------|------|-------------|
| **Grafana** | 3000 (`BIND_ADDR`, default `127.0.0.1`) | Web UI for visualization |

## Features

- **Unified observability**: Single pane for logs, metrics, and traces
- **Pre-configured datasources**: Loki, Prometheus, Tempo, and Pyroscope auto-provisioned
- **Built-in dashboards**: Seven dashboards for metrics, logs, traces, profiling, probing, and stack health; **OIB Stack Health** is the home dashboard
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

`GRAFANA_ADMIN_PASSWORD` has no default: `make install` refuses to run while it is empty or starts with `CHANGE_ME`, and Compose refuses to start Grafana while it is unset. Self sign-up is disabled (`GF_USERS_ALLOW_SIGN_UP=false`).

The container also loads the whole root `.env` through `env_file`, so any `GF_*` variable you put there reaches Grafana. Every other variable in `.env` (including `POSTGRES_PASSWORD`) ends up in the container environment too, visible through `docker inspect`.

### Provisioning
- **Datasources**: `provisioning/datasources/datasources.yml`
- **Dashboards**: `provisioning/dashboards/json/` (provider in `provisioning/dashboards/dashboards.yml`)

The `provisioning/` directory is mounted read-only at `/etc/grafana/provisioning`. It is the only provisioning directory in the repo; the logging, metrics, and telemetry stacks do not have their own.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GRAFANA_ADMIN_USER` | `admin` | Admin username |
| `GRAFANA_ADMIN_PASSWORD` | (required) | Admin password |
| `BIND_ADDR` | `127.0.0.1` | Host address the web UI is published on. Set `0.0.0.0` only to expose Grafana on your LAN |
| `GRAFANA_PORT` | `3000` | Web UI port (also used in `GF_SERVER_ROOT_URL=http://localhost:<port>`) |
| `GRAFANA_VERSION` | `13.3.1` | Grafana image tag |

## Pre-built Dashboards

All dashboards are provisioned into the **OIB** folder.

| Dashboard (title in Grafana) | File | Description |
|-----------|------|-------------|
| **OIB Stack Health** (home dashboard) | `oib-internals.json` | OIB component health, scrape targets, firing/pending alerts, Prometheus ingestion and storage, OIB container CPU/memory |
| **OIB - System Overview** | `system-overview.json` | Host metrics, container CPU/memory, disk usage |
| **OIB - Host Metrics** | `host-metrics.json` | Detailed host CPU, memory, disk, and network metrics |
| **OIB - Logs Explorer** | `logs-explorer.json` | Log volume, live logs, errors/warnings panel |
| **OIB - Traces Explorer** | `traces-explorer.json` | TraceQL examples, language-specific code samples |
| **OIB - Profiles Explorer** | `profiles-explorer.json` | Continuous profiling views and integration guidance (needs `make install-profiling`) |
| **OIB - Request Latency** | `request-latency.json` | Blackbox endpoint probing, k6 load test metrics |

## Adding Custom Dashboards

The file provider rescans `provisioning/dashboards/json/` every 30 seconds (`updateIntervalSeconds: 30`), so new or changed JSON files appear without a restart. `allowUiUpdates: true` lets you edit provisioned dashboards in the UI, but the JSON file on disk wins the next time it changes; export your edits back into the file to keep them.

### Method 1: Grafana UI
1. Create dashboard in Grafana
2. Save it
3. Export JSON via Share → Export → Save to file
4. Place in `provisioning/dashboards/json/`

### Method 2: Direct JSON
1. Create JSON file in `provisioning/dashboards/json/`
2. Wait up to 30 seconds, or restart Grafana: `make restart-grafana`

`make validate` checks that every dashboard JSON file parses.

## Datasources

Pre-configured datasources (all `editable: false`; change them in `datasources.yml`, not in the UI):

| Name | UID | Type | URL |
|------|-----|------|-----|
| Prometheus (default) | `prometheus` | Metrics | `http://oib-prometheus:9090` |
| Loki | `loki` | Logs | `http://oib-loki:3100` |
| Tempo | `tempo` | Traces | `http://oib-tempo:3200` |
| Pyroscope | `pyroscope` | Profiles | `http://oib-pyroscope:4040` |

The Pyroscope datasource is always provisioned, but it only works after `make install-profiling`. Until then, queries against it fail.

The Tempo datasource is linked to the others:
- **Trace to logs** (Loki): filters by trace ID. It also maps the span attribute `service.name` to the Loki label `service_name`, which Loki derives from the container name (e.g. `oib-grafana`). The link only finds logs when an app's `OTEL_SERVICE_NAME` equals its container name; the bundled examples use different names, so for them it returns nothing.
- **Trace to profiles** (Pyroscope): uses `service.name` → `service_name` and the CPU profile type.
- **Service graph** (Prometheus): Tempo's metrics generator runs, but `telemetry/config/tempo.yaml` has `remote_write: []`, so no service-graph series reach Prometheus and the Service Graph view in Explore stays empty.

## Backup and Restore

Dashboards created in the UI, users, and preferences live in the `oib-grafana-data` volume.

```bash
make backup-grafana                        # writes ./backups/grafana_<YYYYMMDD_HHMMSS>.tar.gz
make restore-grafana FILE=./backups/grafana_YYYYMMDD_HHMMSS.tar.gz
```

Restore asks for confirmation, stops Grafana, replaces the volume contents, and starts Grafana again. `make uninstall-grafana` deletes the volume.

## Troubleshooting

```bash
# Check Grafana health
curl http://localhost:3000/api/health

# View logs
make logs-grafana

# Reset password (if forgotten)
docker exec -it oib-grafana grafana-cli admin reset-admin-password newpassword

# Restart Grafana
make restart-grafana
```

## Useful Links

- **Grafana UI**: http://localhost:3000
- **API Health**: http://localhost:3000/api/health
- **Datasources API**: http://localhost:3000/api/datasources
