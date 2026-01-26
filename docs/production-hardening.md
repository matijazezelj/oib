# Production Hardening Guide

This guide covers security and reliability improvements for running OIB in production environments.

## Security Checklist

- [ ] Change default Grafana password
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

OIB ships with basic auth enabled. For production:

1. **Change the default password:**
   ```bash
   # Edit .env
   GRAFANA_ADMIN_PASSWORD=your-secure-password-here
   ```

2. **Disable anonymous access** (already done by default):
   ```yaml
   # In grafana/compose.yaml environment
   GF_USERS_ALLOW_SIGN_UP=false
   ```

3. **Enable OAuth/LDAP** for enterprise environments:
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
     httpHeaderName1: X-Scope-OrgID
     httpHeaderValue1: tenant1
   ```

### Prometheus Authentication

For production Prometheus:

1. **Use a reverse proxy** (nginx/traefik) with basic auth
2. **Or enable built-in basic auth:**
   ```yaml
   # Add to metrics/config/web.yml
   basic_auth_users:
     admin: $2y$10$... # bcrypt hash
   ```

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

Only these are exposed publicly by default:
- Grafana (port 3000) - For web access
- OTLP endpoints (ports 4317, 4318) - For trace ingestion

### Firewall Rules

Configure your firewall to only allow necessary ports:

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

---

## Resource Management

### Memory Limits

The default limits are suitable for small deployments. For larger environments:

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

**Loki** (`logging/config/loki-config.yml`):
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

For production HA, consider:

### Prometheus HA

Run multiple Prometheus instances with shared storage:

```yaml
services:
  prometheus-1:
    # ... existing config
    command:
      - '--storage.tsdb.path=/prometheus'
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--web.enable-lifecycle'

  prometheus-2:
    # Duplicate of prometheus-1
```

Use Thanos or Cortex for long-term storage and deduplication.

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

### Backup Verification

Periodically test restores:

```bash
# Test restore to a temporary environment
make backup
docker volume create oib-prometheus-test
docker run --rm \
  -v ./backups/prometheus_latest.tar.gz:/backup.tar.gz:ro \
  -v oib-prometheus-test:/data \
  alpine tar xzf /backup.tar.gz -C /data
```

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

OIB includes an "OIB Stack Health" dashboard that shows:
- Service health status
- Prometheus storage and ingestion rates
- Container resource usage
- Active alerts

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

1. **Filter sensitive fields in Alloy:**
   ```
   loki.process "filter" {
     forward_to = [loki.write.loki.receiver]

     stage.replace {
       expression = "(password|token|secret)=\\S+"
       replace    = "$1=[REDACTED]"
     }
   }
   ```

---

## Checklist Before Going Live

1. [ ] Changed all default passwords
2. [ ] Configured appropriate retention periods
3. [ ] Set up automated backups
4. [ ] Configured alerting
5. [ ] Tested restore procedure
6. [ ] Documented custom configurations
7. [ ] Set up external health monitoring
8. [ ] Reviewed firewall rules
9. [ ] Configured TLS if exposed to internet
10. [ ] Tested under expected load
