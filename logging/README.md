# Logging Stack

Centralized log aggregation using Grafana Loki and Alloy.

## Components

| Service | Port | Description |
|---------|------|-------------|
| **Loki** | 3100 (always `127.0.0.1`) | Log storage and querying |
| **Alloy** | 12345 (always `127.0.0.1`) | Log collection agent (UI at `/`) |

Containers: `oib-loki`, `oib-alloy-logging`. Volume: `oib-loki-data`. Both ports are bound to loopback in `compose.yaml`; `BIND_ADDR` does not change them. `oib-loki` loads the whole root `.env` (`env_file`), so its values, including `GRAFANA_ADMIN_PASSWORD`, are visible through `docker inspect oib-loki`.

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
- `limits_config.retention_period`: How long to keep logs (default: `168h` = 7 days). The compactor enforces it (`compactor.retention_enabled: true`), deleting older chunks as it runs. Shortening the period deletes existing logs older than the new value.
- `limits_config.reject_old_samples_max_age`: Entries older than this (default `168h`) are rejected at ingestion
- `limits_config.ingestion_rate_mb` / `ingestion_burst_size_mb`: Max ingestion rate per tenant (default `16` / `24`)
- `limits_config.max_line_size`: Longest accepted log line (default `256kb`)

Retention is set only in this file; there is no environment variable for it. Apply changes with `make restart-logging`.

### Alloy Configuration
Edit `config/alloy-config.alloy`:
- Docker log collection pipeline
- Label extraction rules
- Loki push endpoint (`http://oib-loki:3100/loki/api/v1/push`)
- An optional, commented-out block for host files under `/var/log` (the only use of the `/var/log` mount)

### Labels

Every container log line gets these labels:

| Label | Source |
|-------|--------|
| `container_name` | Container name without the leading `/` (e.g. `oib-grafana`) |
| `container_id` | Docker container ID |
| `image` | Image name |
| `compose_project` | Compose project label, if any |
| `compose_service` | Compose service label, if any |
| `stream` | `stdout` or `stderr` |
| `job` | Always `docker` |

Example query: `{container_name="oib-grafana"} |= "error"`.

> [!NOTE]
> The pipeline also runs a `stage.json` step that expects Docker's JSON log wrapper (`log`, `stream`, `time`). `loki.source.docker` already delivers the raw line, so this step is believed to affect only applications whose own JSON logs contain a top-level `log` or `time` field: the line is replaced by the `log` value, and `time` overrides the timestamp. Not verified against a running instance.

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

> [!WARNING]
> `oib-alloy-logging` mounts `/var/run/docker.sock`. The `:ro` flag does not restrict Docker API calls, so anything that controls this container has root-equivalent access to the host. It also mounts the host's `/var/log` read-only.

### Direct Push to Loki
```bash
curl -X POST "http://localhost:3100/loki/api/v1/push" \
  -H "Content-Type: application/json" \
  -d '{"streams":[{"stream":{"app":"test"},"values":[["'"$(date +%s)000000000"'","Hello from curl!"]]}]}'
```

### Using Loki Docker Driver
Not needed for containers on the same host, since Alloy already collects their logs; with both, lines may arrive twice if Docker still serves them to Alloy through its API (not verified). The driver is a Docker plugin you install separately (`grafana/loki-docker-driver`).

```yaml
services:
  my-app:
    logging:
      driver: loki
      options:
        loki-url: "http://localhost:3100/loki/api/v1/push"
```

The plugin runs in the host's network namespace, not in a container network. On Linux, use `localhost` (Loki is published on `127.0.0.1:3100`), because `host.docker.internal` does not resolve there. The Docker Desktop behaviour was not verified.

## Backup and Restore

```bash
make backup-loki                           # writes ./backups/loki_<YYYYMMDD_HHMMSS>.tar.gz
make restore-loki FILE=./backups/loki_YYYYMMDD_HHMMSS.tar.gz
```

Restore asks for confirmation, stops Loki, replaces the contents of `oib-loki-data`, and starts Loki again. `make uninstall-logging` deletes the volume.

## Troubleshooting

```bash
# Check if Loki is ready
curl http://localhost:3100/ready

# View Alloy pipeline status
open http://localhost:12345

# Check Loki logs
make logs-logging
```

The Loki image is distroless (no shell, `wget`, or `curl`), so the container has no Docker healthcheck. `make health` and the Blackbox probe on `http://oib-loki:3100/ready` report its readiness instead.
