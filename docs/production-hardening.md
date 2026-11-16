# Production Hardening Guide

This guide covers security and reliability work required before adapting OIB to a production environment. The default Docker Compose topology is single-host, unauthenticated between components, and not highly available; this guide is not a production-readiness guarantee.

## Security Checklist

- [ ] Set a strong Grafana admin password (there is no default)
- [ ] Change the default PostgreSQL password if you use the shared services or demo app
- [ ] Review the privileged host mounts (see [Host Access](#host-access))
- [ ] Enable authentication on services
- [ ] Configure firewall rules
- [ ] Set up TLS/HTTPS
- [ ] Review volume permissions
- [ ] Enable log rotation
- [ ] Set up alerting
- [ ] Configure backups

---

## Authentication

### Grafana Authentication

Grafana uses its built-in login. For production:

1. **Set a strong admin password before the first start:**
   ```bash
   # Edit .env
   GRAFANA_ADMIN_PASSWORD=your-secure-password-here
   ```
   `.env.example` ships it empty and `make install` refuses to run until it is set. Grafana only applies it when it creates its database; to change it later, use the Grafana UI or `docker exec -it oib-grafana grafana cli admin reset-admin-password '<new-password>'`.

2. **Sign-up is disabled** (already set in `grafana/compose.yaml`); anonymous access stays off because OIB does not enable it:
   ```yaml
   # In grafana/compose.yaml environment
   GF_USERS_ALLOW_SIGN_UP=false
   ```

3. **Set the public URL** if Grafana sits behind a proxy or another hostname. `grafana/compose.yaml` hard-codes `GF_SERVER_ROOT_URL=http://localhost:${GRAFANA_PORT:-3000}`, which produces wrong links and redirects otherwise.

4. **Enable OAuth/LDAP** for enterprise environments:
   ```yaml
   environment:
     - GF_AUTH_GENERIC_OAUTH_ENABLED=true
     - GF_AUTH_GENERIC_OAUTH_NAME=OAuth
     - GF_AUTH_GENERIC_OAUTH_CLIENT_ID=${OAUTH_CLIENT_ID}
     # ... see Grafana docs for full config
   ```

### Loki Authentication

By default, Loki has authentication disabled. For production:

1. **Enable multi-tenancy:**
   Edit `logging/config/loki-config.yml`:
   ```yaml
   auth_enabled: true
   ```

2. **Configure Alloy to send tenant ID:**
   Edit `logging/config/alloy-config.alloy`:
   ```
   loki.write "loki" {
     endpoint {
       url = "http://oib-loki:3100/loki/api/v1/push"
       headers = {
         "X-Scope-OrgID" = "tenant1",
       }
     }
   }
   ```

3. **Update Grafana datasource:**
   Edit `grafana/provisioning/datasources/datasources.yml`:
   ```yaml
   - name: Loki
     # ... existing fields ...
     jsonData:
       maxLines: 1000
       httpHeaderName1: X-Scope-OrgID
     secureJsonData:
       httpHeaderValue1: tenant1
   ```
   Then `make restart-logging` and `make restart-grafana`. `make demo` pushes to Loki without a tenant header and will fail once `auth_enabled` is on.

### Prometheus Authentication

For production Prometheus:

1. **Use a reverse proxy** (nginx/traefik) with basic auth
2. **Or enable built-in basic auth.** OIB ships no web config, so create one:
   ```yaml
   # metrics/config/web.yml (new file)
   basic_auth_users:
     admin: $2y$10$... # bcrypt hash
   ```
   Then, in `metrics/compose.yaml`, mount it (`./config/web.yml:/etc/prometheus/web.yml:ro`) and add `--web.config.file=/etc/prometheus/web.yml` to the Prometheus `command`. Everything that talks to Prometheus then needs the credentials: the Grafana datasource, Alloy's `remote_write`, the k6 tests, the Blackbox probe of `/-/healthy`, the `prometheus` self-scrape job and the container healthcheck (`wget .../-/healthy`).

---

## Network Security

### Restrict Service Exposure

OIB binds internal services to localhost by default. Verify this in your `.env`:

```bash
# These should bind to 127.0.0.1, not 0.0.0.0
PROMETHEUS_PORT=9090    # Bound to 127.0.0.1 in compose
LOKI_PORT=3100          # Bound to 127.0.0.1 in compose
TEMPO_HTTP_PORT=3200    # Bound to 127.0.0.1 in compose
```

No OIB ports are publicly exposed by default. Grafana and OTLP bind to `127.0.0.1` unless you explicitly set `BIND_ADDR=0.0.0.0` or `OTEL_BIND_ADDR=0.0.0.0`. The demo and example apps follow `DEMO_BIND_ADDR`. Every other port (Loki, Prometheus, Tempo, the Alloy UIs, cAdvisor, Blackbox, Pyroscope, PostgreSQL, Redis) is hard-wired to `127.0.0.1`. If you expose Grafana or OTLP, add firewall restrictions, authentication where supported, and TLS before accepting untrusted traffic. The OTLP receivers have no authentication.

### Firewall Rules

Configure your firewall to only allow necessary ports. Note that Docker writes its own iptables rules for published ports, and these take precedence over `ufw`'s default rules, so a `ufw deny` does not block a port that Docker publishes on `0.0.0.0`. Filter Docker-published ports in the `DOCKER-USER` chain, or keep them bound to specific addresses via `BIND_ADDR` / `OTEL_BIND_ADDR`.

```bash
# Allow Grafana from specific IPs
ufw allow from 10.0.0.0/8 to any port 3000

# Allow OTLP from your application servers
ufw allow from 192.168.1.0/24 to any port 4317
ufw allow from 192.168.1.0/24 to any port 4318

# Block everything else by default
ufw default deny incoming
```

### TLS Configuration

For HTTPS, use a reverse proxy. Example with Traefik:

```yaml
# traefik/compose.yaml
services:
  traefik:
    image: traefik:v2.10
    command:
      - "--providers.docker=true"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.tlschallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.email=you@example.com"
    ports:
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./acme.json:/acme.json
    networks:
      - oib-network

# Add labels to grafana in grafana/compose.yaml
services:
  grafana:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.grafana.rule=Host(`grafana.yourdomain.com`)"
      - "traefik.http.routers.grafana.tls.certresolver=letsencrypt"
```

Also set `GF_SERVER_ROOT_URL` to the public `https://` URL (see [Grafana Authentication](#grafana-authentication)).

---

## Host Access

Several collectors need privileged views of the host. Treat these containers as part of your host's trusted computing base:

| Container | Mount | Why | Risk |
|-----------|-------|-----|------|
| `oib-alloy-logging` | `/var/run/docker.sock:ro` | Discover containers and read their logs | Docker API access is root-equivalent; `:ro` does not limit API calls |
| `oib-alloy-logging` | `/var/log:/var/log:ro` | Only used by the commented system-logs block in `logging/config/alloy-config.alloy` | Read access to host logs |
| `oib-cadvisor` | `/var/run/docker.sock:ro`, `/:/rootfs:ro`, `/sys`, `/var/lib/docker`, `/dev/disk` | Container metrics | Root-equivalent (socket) and read access to the whole host filesystem |
| `oib-alloy-metrics` | `/:/rootfs:ro`, `/proc`, `/sys` | Host filesystem metrics | Read access to the whole host filesystem |

To reduce exposure, put a Docker socket proxy that only allows read-only container endpoints in front of the socket, or disable the stacks you do not need.

The root `.env` is loaded with `env_file` into Grafana, Loki, Prometheus, Tempo and Pyroscope. Every variable in it, including `GRAFANA_ADMIN_PASSWORD` and `POSTGRES_PASSWORD`, is visible through `docker inspect` on those containers. Restrict who can run `docker` on the host. Do not put unrelated secrets in `.env`.

The shared services (`services/compose.yaml`) and the demo app default to `POSTGRES_PASSWORD=oib_secret`, and Redis has no password. Both are bound to `127.0.0.1` or only reachable on `oib-network`; change the password in `.env` before using them on a shared host.

---

## Resource Management

### Memory Limits

The default limits are suitable for small deployments (Prometheus, Loki, Tempo and Pyroscope: 1G memory each; Grafana and the Alloy logging/telemetry collectors: 512M; Alloy metrics: 256M). For larger environments:

```yaml
# metrics/compose.yaml - Prometheus
deploy:
  resources:
    limits:
      memory: 4G      # Increase for more series
    reservations:
      memory: 1G

# logging/compose.yaml - Loki
deploy:
  resources:
    limits:
      memory: 2G      # Increase for more logs
    reservations:
      memory: 512M
```

### Storage Sizing

Estimate storage needs:

| Component | Typical Usage | Notes |
|-----------|---------------|-------|
| Prometheus | 1-2 bytes per sample | ~50MB/day for small setup |
| Loki | Varies by log volume | ~100MB-1GB/day typical |
| Tempo | ~1KB per trace | Depends on sampling rate |
| Grafana | ~100MB | Dashboards and settings |

### Retention Configuration

Adjust retention based on your needs:

**Prometheus** (`.env`):
```bash
PROMETHEUS_RETENTION_TIME=30d    # Or adjust as needed
PROMETHEUS_RETENTION_SIZE=10GB   # First limit hit wins
```

Apply with `make install-metrics`; `make restart-metrics` does not pick up `.env` changes.

**Loki** (`logging/config/loki-config.yml`, enforced by the compactor with `retention_enabled: true`, already set):
```yaml
limits_config:
  retention_period: 168h  # 7 days, adjust as needed
```

**Tempo** (`telemetry/config/tempo.yaml`):
```yaml
compactor:
  compaction:
    block_retention: 72h  # 3 days, adjust as needed
```

---

## High Availability

OIB does not provide a high-availability deployment. Do not point multiple Prometheus processes at the same TSDB volume. For an HA architecture, use upstream-supported deployment patterns and externalize state before adding replicas.

### Prometheus HA

Run independent Prometheus replicas and use a system designed for deduplication and long-term storage, such as Thanos or Grafana Mimir. Each Prometheus replica must have its own local storage.

### Loki HA

For production Loki, use the distributed deployment:
- See [Loki Simple Scalable Deployment](https://grafana.com/docs/loki/latest/setup/install/helm/install-scalable/)

### Grafana HA

Run multiple Grafana instances with shared database:

```yaml
environment:
  - GF_DATABASE_TYPE=postgres
  - GF_DATABASE_HOST=postgres:5432
  - GF_DATABASE_NAME=grafana
  - GF_DATABASE_USER=grafana
  - GF_DATABASE_PASSWORD=${GRAFANA_DB_PASSWORD}
```

---

## Backup Strategy

### Automated Backups

Create a cron job for regular backups:

```bash
# /etc/cron.d/oib-backup
0 2 * * * root cd /path/to/oib && make backup >> /var/log/oib-backup.log 2>&1
```

Limits of `make backup` to plan around:
- It covers the Prometheus, Loki, Tempo and Grafana volumes only, not `oib-pyroscope-data` or the shared PostgreSQL/Redis volumes.
- It archives the volumes while the services are running, so a backup is not guaranteed to be consistent. For a consistent copy, run `make stop`, `make backup`, `make start` in the cron job, and accept the gap in collection.
- Files are written to `./backups/<component>_YYYYMMDD_HHMMSS.tar.gz` and are never pruned; rotate them yourself.

### Backup Verification

Periodically test restores:

```bash
# Test restore to a temporary environment
make backup
docker volume create oib-prometheus-test
docker run --rm \
  -v "$PWD/backups/prometheus_YYYYMMDD_HHMMSS.tar.gz":/backup.tar.gz:ro \
  -v oib-prometheus-test:/data \
  alpine tar xzf /backup.tar.gz -C /data
```

`make restore-<component> FILE=...` restores into the live volume: it asks for confirmation, stops the service, deletes the existing data, extracts the archive and starts the service.

### Off-site Backup

Sync backups to remote storage:

```bash
# Using rclone
rclone sync ./backups remote:oib-backups/

# Using AWS S3
aws s3 sync ./backups s3://your-bucket/oib-backups/
```

---

## Monitoring OIB Itself

### Use the Self-Monitoring Dashboard

OIB includes an "OIB Stack Health" dashboard (`grafana/provisioning/dashboards/json/oib-internals.json`, Grafana's home dashboard) that shows:
- Service health status
- Prometheus storage and ingestion rates
- Container resource usage
- Firing and pending alerts

### External Health Checks

Set up external monitoring for the OIB stack:

```bash
# Simple health check script
#!/bin/bash
SERVICES="http://localhost:3000/api/health http://localhost:9090/-/healthy http://localhost:3100/ready"
for svc in $SERVICES; do
  if ! curl -sf "$svc" > /dev/null; then
    echo "CRITICAL: $svc is down"
    # Send alert
  fi
done
```

---

## Alerting

### Shipped Alert Rules

Prometheus loads `metrics/config/rules/oib-alerts.yml` (mounted at `/etc/prometheus/rules`). It contains these groups:

| Group | Alerts |
|-------|--------|
| `oib_infrastructure` | `PrometheusDown`, `LokiDown`, `TempoDown`, `GrafanaDown`, `PrometheusScrapeFailure` |
| `host_resources` | `HostHighCpuUsage`, `HostCriticalCpuUsage`, `HostHighMemoryUsage`, `HostCriticalMemoryUsage`, `HostDiskSpaceLow`, `HostDiskSpaceCritical`, `HostHighDiskIO` |
| `container_resources` | `ContainerHighCpuUsage`, `ContainerHighMemoryUsage`, `ContainerMemoryNearLimit`, `ContainerRestarting` |
| `prometheus_self` | `PrometheusConfigReloadFailed`, `PrometheusStorageRunningFull`, `PrometheusHighScrapeLatency` |
| `blackbox_probes` | `EndpointDown`, `EndpointSlowResponse`, `SSLCertificateExpiring`, `SSLCertificateExpiringSoon` |

No Alertmanager is configured (the `alerting:` block in `metrics/config/prometheus.yml` is commented out), so alerts are only visible at `http://localhost:9090/alerts` and on the OIB Stack Health dashboard; nobody is notified. According to the audit (not verified against a running instance), `ContainerRestarting` and `PrometheusHighScrapeLatency` use metrics that are not exported and will never fire. Reload rules after editing with `docker exec oib-prometheus kill -HUP 1`.

### Enable Alertmanager

For production alerting:

1. **Add Alertmanager to metrics stack:**
   ```yaml
   # metrics/compose.yaml
   alertmanager:
     image: prom/alertmanager:v0.26.0
     ports:
       - "127.0.0.1:9093:9093"
     volumes:
       - ./config/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
     networks:
       - oib-network   # required: Prometheus is only on oib-network
   ```

2. **Configure Prometheus to use it:**
   Edit `metrics/config/prometheus.yml`:
   ```yaml
   alerting:
     alertmanagers:
       - static_configs:
           - targets:
             - alertmanager:9093
   ```

3. **Set up notification channels** in `alertmanager.yml`:
   ```yaml
   route:
     receiver: 'slack'
   receivers:
     - name: 'slack'
       slack_configs:
         - api_url: 'https://hooks.slack.com/services/...'
           channel: '#alerts'
   ```

---

## Log Management

### Docker Log Collection Scope

The default Alloy configuration discovers every running Docker container through `/var/run/docker.sock`. This includes containers outside the OIB project. Before using it on a shared host:

- Review logs for credentials, tokens, personal data, and other sensitive values.
- Add discovery relabel rules if only selected containers should be collected.
- Treat Docker socket access as privileged host integration, even when the socket is mounted read-only (see [Host Access](#host-access)).

### Log Rotation

Docker handles log rotation, but verify settings:

```json
// /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

### Sensitive Data

Ensure logs don't contain sensitive information:

1. **Filter sensitive fields in Alloy:** add a `stage.replace` to the existing `loki.process "docker"` block in `logging/config/alloy-config.alloy` (a separate `loki.process` component would receive nothing unless you rewire `forward_to`). Each capture group in `expression` is replaced by `replace`:
   ```
   loki.process "docker" {
     forward_to = [loki.write.loki.receiver]

     stage.replace {
       expression = "(?:password|token|secret)=(\\S+)"
       replace    = "[REDACTED]"
     }

     // ... existing stages ...
   }
   ```
   Then `make restart-logging`.

---

## Checklist Before Going Live

1. [ ] Set a strong Grafana password and changed `POSTGRES_PASSWORD` if the shared services are used
2. [ ] Configured appropriate retention periods
3. [ ] Set up automated backups
4. [ ] Configured alerting
5. [ ] Tested restore procedure
6. [ ] Documented custom configurations
7. [ ] Set up external health monitoring
8. [ ] Reviewed firewall rules
9. [ ] Configured TLS if exposed to internet
10. [ ] Tested under expected load
