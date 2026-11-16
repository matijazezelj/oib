# Metrics Stack

Metrics collection and monitoring using Prometheus and Alloy.

## Components

| Service | Port | Description |
|---------|------|-------------|
| **Prometheus** | 9090 (localhost) | Metrics storage and querying |
| **Alloy** | 12347 (localhost) | Host system metrics collection |
| **cAdvisor** | 8080 (localhost) | Container metrics |
| **Blackbox Exporter** | 9115 (localhost) | Endpoint probing |
| **Pushgateway** (optional) | 9091 (localhost) | Metrics pushed by batch jobs; off unless the `pushgateway` profile is enabled |

Containers: `oib-prometheus`, `oib-alloy-metrics`, `oib-cadvisor`, `oib-blackbox-exporter`, `oib-pushgateway`. Volume: `oib-prometheus-data`. All ports are bound to `127.0.0.1`; `BIND_ADDR` does not change them. `oib-prometheus` loads the whole root `.env` (`env_file`), so its values, including `GRAFANA_ADMIN_PASSWORD`, are visible through `docker inspect oib-prometheus`.

## Features

- **Pull-based collection**: Prometheus scrapes metrics endpoints
- **Host monitoring**: CPU, memory, disk, network via Alloy (built-in unix exporter), remote-written to Prometheus (the dashboards query them as `job="integrations/unix"`)
- **Container monitoring**: Per-container resources via cAdvisor
- **Endpoint probing**: HTTP health checks via Blackbox (TCP, ICMP, DNS, and gRPC modules are defined but not used by any active job)
- **Alert rules**: Prometheus loads `config/rules/*.yml` (see [Alert Rules](#alert-rules))
- **Remote-write receiver**: Prometheus accepts `POST /api/v1/write` (`--web.enable-remote-write-receiver`), used by Alloy and k6

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

> [!NOTE]
> The unix exporter sets no `procfs_path`/`sysfs_path`/`rootfs_path`, and Alloy does not read the `HOST_PROC`/`HOST_SYS`/`HOST_ROOT` variables set in `compose.yaml`. So it reads the container's own `/proc` and `/sys`, and network metrics are those of the container's network namespace, not the host's. Host filesystems show up under the `/rootfs` mount (the dashboards query `mountpoint=~"/rootfs.*"`). The System Overview disk gauge queries `mountpoint="/"`, the container's own root, so it can disagree with the Host Metrics disk panels.

### Blackbox Configuration
Edit `config/blackbox.yml`:
- Define probe modules (http, tcp, icmp, etc.)
- The default `http_2xx` module sets `insecure_skip_verify: true`, so it does not fail on invalid certificates. Use `https_2xx` for strict TLS checks.

### Storage Retention
Prometheus keeps data for `PROMETHEUS_RETENTION_TIME` or until it reaches `PROMETHEUS_RETENTION_SIZE`, whichever comes first (`--storage.tsdb.retention.*` flags in `compose.yaml`). Apply changes with `make install-metrics`, which recreates the container; `make restart-metrics` keeps the old flags.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PROMETHEUS_PORT` | `9090` | Prometheus UI/API port |
| `ALLOY_METRICS_PORT` | `12347` | Alloy metrics UI port |
| `CADVISOR_PORT` | `8080` | cAdvisor port |
| `BLACKBOX_PORT` | `9115` | Blackbox Exporter port |
| `PROMETHEUS_RETENTION_TIME` | `15d` | Data retention time |
| `PROMETHEUS_RETENTION_SIZE` | `5GB` | Max storage size |
| `PROMETHEUS_VERSION` | `v3.16.0` | Prometheus image tag |
| `ALLOY_VERSION` | `v1.22.0` | Alloy image tag |
| `CADVISOR_VERSION` | `v0.60.6` | cAdvisor image tag |
| `BLACKBOX_VERSION` | `v0.29.1` | Blackbox image tag |
| `PUSHGATEWAY_PORT` | `9091` | Pushgateway port (optional profile) |
| `PUSHGATEWAY_VERSION` | `v1.11.4` | Pushgateway image tag (optional profile) |

## Scrape Jobs

Active jobs in `config/prometheus.yml` (every 15s):

| Job | Target | What |
|-----|--------|------|
| `prometheus` | `localhost:9090` | Prometheus self-metrics |
| `alloy-metrics` | `alloy-metrics:12345` | Alloy's own metrics (host metrics arrive by remote write, not this scrape) |
| `cadvisor` | `cadvisor:8080` | Container metrics |
| `blackbox-exporter` | `blackbox-exporter:9115` | Blackbox self-metrics |
| `blackbox-http` | Grafana, Prometheus, Loki, Tempo health URLs | HTTP probes with `http_2xx` |

There is no scrape job for the example apps in `examples/` or for Pyroscope; add one if you want their metrics.

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

`host.docker.internal` resolves to the host gateway (`extra_hosts` in `compose.yaml`). On Linux this only reaches host services listening on `0.0.0.0` or the bridge address, not ones bound to `127.0.0.1`.

## Optional: Pushgateway

For batch jobs that need to push metrics, enable Pushgateway:

```bash
# Start with pushgateway profile (--env-file picks up overrides from the root .env)
cd metrics && docker compose --env-file ../.env --profile pushgateway up -d

# Then push metrics from your scripts
echo "backup_duration_seconds 42" | curl --data-binary @- \
  http://localhost:9091/metrics/job/backup/instance/server1
```

Prometheus does not scrape the Pushgateway until you uncomment the `pushgateway` job in `config/prometheus.yml` and run `make restart-metrics`. No make target starts or stops the Pushgateway; manage it with `docker compose --profile pushgateway ...` from `metrics/`. It has no volume, so pushed metrics are lost when the container is recreated.

## Alert Rules

`config/rules/oib-alerts.yml` is mounted at `/etc/prometheus/rules` and loaded via `rule_files`. No Alertmanager is configured (the `alerting:` block in `prometheus.yml` is commented out), so alerts do not notify anyone. You see them on Prometheus's `/alerts` page and in the Firing/Pending Alerts panels of the **OIB Stack Health** dashboard.

| Group | Alerts |
|-------|--------|
| `oib_infrastructure` | `PrometheusDown`, `LokiDown`, `TempoDown`, `GrafanaDown` (from blackbox probes), `PrometheusScrapeFailure` (`up == 0` for 5m) |
| `host_resources` | `HostHighCpuUsage` (>80%) / `HostCriticalCpuUsage` (>95%), `HostHighMemoryUsage` (>80%) / `HostCriticalMemoryUsage` (>95%), `HostDiskSpaceLow` (<20% free) / `HostDiskSpaceCritical` (<10% free), `HostHighDiskIO` |
| `container_resources` | `ContainerHighCpuUsage` (>80%), `ContainerHighMemoryUsage` (>80% of limit) / `ContainerMemoryNearLimit` (>95% of limit; only containers with a memory limit), `ContainerRestarting` |
| `prometheus_self` | `PrometheusConfigReloadFailed`, `PrometheusStorageRunningFull`, `PrometheusHighScrapeLatency` |
| `blackbox_probes` | `EndpointDown`, `EndpointSlowResponse` (>2s), `SSLCertificateExpiring` (<30 days), `SSLCertificateExpiringSoon` (<7 days) |

Known issues, from reading the rules (not checked against a running instance):
- `ContainerRestarting` uses `container_restart_count`, which cAdvisor is not believed to export, so it is expected never to fire.
- `PrometheusHighScrapeLatency` uses metric names that are not believed to be Prometheus self-metrics, so it is expected never to fire.
- The host alerts inherit the host-metrics caveats above (container network namespace, `/rootfs` mountpoints).

Add your own rules as another `*.yml` file in `config/rules/` and run `make restart-metrics`. `make validate` checks YAML syntax only, not PromQL.

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

Only the `blackbox-http` job is active. The TCP and ICMP jobs in `prometheus.yml` are commented-out templates. The `prometheus.yml` comment notes that ICMP needs the `NET_RAW` capability; `compose.yaml` neither adds nor drops capabilities for the Blackbox container, so ICMP probing has not been tested here. `EndpointDown` fires for any target in these jobs that fails for 2 minutes.

## Security

> [!WARNING]
> - `oib-cadvisor` mounts `/var/run/docker.sock` (and `/var/run`). The `:ro` flag does not restrict Docker API calls, so this is root-equivalent on the host.
> - `oib-alloy-metrics` and `oib-cadvisor` mount the host root filesystem read-only at `/rootfs`, so they can read every file on the host. cAdvisor also has `SYS_PTRACE`.
> - The remote-write receiver accepts writes from anything on `oib-network` without authentication.

## Backup and Restore

```bash
make backup-prometheus                     # writes ./backups/prometheus_<YYYYMMDD_HHMMSS>.tar.gz
make restore-prometheus FILE=./backups/prometheus_YYYYMMDD_HHMMSS.tar.gz
```

Restore asks for confirmation, stops Prometheus, replaces the contents of `oib-prometheus-data`, and starts it again. `make uninstall-metrics` deletes the volume.

## Troubleshooting

```bash
# Check Prometheus status
curl http://localhost:9090/-/ready

# Check Alloy metrics pipeline
curl http://localhost:12347/-/ready

# Check that host metrics arrive (they are remote-written, not exposed on Alloy's /metrics)
curl -s 'http://localhost:9090/api/v1/query?query=count(node_cpu_seconds_total)'

# Check cAdvisor
curl http://localhost:8080/healthz

# List scrape targets and their health
curl -s http://localhost:9090/api/v1/targets
```
