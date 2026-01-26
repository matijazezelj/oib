# Storage and Retention Guide

Understanding and tuning storage for OIB components.

## Default Retention Settings

| Component | Default Retention | Config Location |
|-----------|------------------|-----------------|
| Prometheus | 15 days OR 5GB | `.env` |
| Loki | 7 days (168h) | `logging/config/loki-config.yml` |
| Tempo | 3 days (72h) | `telemetry/config/tempo.yaml` |
| Grafana | Unlimited | N/A (settings only) |

---

## Storage Estimation

### Prometheus

**Formula:** `storage = series_count × scrape_interval × retention × 2 bytes`

| Scenario | Series | Retention | Estimated Storage |
|----------|--------|-----------|-------------------|
| Small (homelab) | 1,000 | 15 days | ~250 MB |
| Medium (small team) | 10,000 | 15 days | ~2.5 GB |
| Large (production) | 100,000 | 15 days | ~25 GB |

Check your current series count:
```bash
curl -s http://localhost:9090/api/v1/query?query=count%28%7B__name__%21%3D%22%22%7D%29 | jq '.data.result[0].value[1]'
```

### Loki

**Formula:** Depends heavily on log volume and compression ratio.

| Scenario | Log Volume | Retention | Estimated Storage |
|----------|------------|-----------|-------------------|
| Small | 10 MB/day | 7 days | ~50 MB |
| Medium | 100 MB/day | 7 days | ~500 MB |
| Large | 1 GB/day | 7 days | ~5 GB |

Loki compresses logs ~10:1, so actual storage is much less than raw log volume.

### Tempo

**Formula:** `storage = traces_per_second × avg_trace_size × retention`

| Scenario | Traces/sec | Retention | Estimated Storage |
|----------|------------|-----------|-------------------|
| Small | 10 | 3 days | ~2.5 GB |
| Medium | 100 | 3 days | ~25 GB |
| Large | 1,000 | 3 days | ~250 GB |

---

## Configuring Retention

### Prometheus

Edit `.env`:
```bash
# Time-based retention
PROMETHEUS_RETENTION_TIME=30d

# Size-based retention (first limit wins)
PROMETHEUS_RETENTION_SIZE=10GB
```

Restart to apply:
```bash
make restart-metrics
```

### Loki

Edit `logging/config/loki-config.yml`:
```yaml
limits_config:
  retention_period: 336h  # 14 days

compactor:
  retention_enabled: true
  retention_delete_delay: 2h
  retention_delete_worker_count: 150
```

Restart to apply:
```bash
make restart-logging
```

### Tempo

Edit `telemetry/config/tempo.yaml`:
```yaml
compactor:
  compaction:
    block_retention: 168h  # 7 days
```

Restart to apply:
```bash
make restart-telemetry
```

---

## Monitoring Storage Usage

### Check Current Usage

```bash
# Quick overview
make disk-usage

# Detailed Docker volume sizes
docker system df -v | grep oib

# Per-component breakdown
for vol in oib-prometheus-data oib-loki-data oib-tempo-data oib-grafana-data; do
  echo "$vol:"
  docker run --rm -v $vol:/data alpine du -sh /data 2>/dev/null
done
```

### Using the OIB Dashboard

The "OIB Stack Health" dashboard shows:
- Prometheus storage size over time
- Storage growth rate
- Active time series count

---

## Storage Optimization

### Prometheus

1. **Reduce cardinality:**
   - Drop unused labels in scrape configs
   - Use `metric_relabel_configs` to filter

2. **Adjust scrape intervals:**
   ```yaml
   # Less frequent scraping = less storage
   scrape_configs:
     - job_name: 'low-priority'
       scrape_interval: 60s  # Instead of 15s
   ```

3. **Use recording rules** for commonly queried aggregations

### Loki

1. **Filter logs at source:**
   ```
   # In alloy-config.alloy
   loki.process "filter" {
     stage.drop {
       expression = "healthcheck|readiness"
     }
   }
   ```

2. **Increase chunk size** for better compression:
   ```yaml
   # loki-config.yml
   ingester:
     chunk_target_size: 1572864  # 1.5MB
   ```

### Tempo

1. **Implement sampling:**
   ```
   # In alloy-config.alloy
   otelcol.processor.probabilistic_sampler "sampler" {
     sampling_percentage = 10  # Keep 10% of traces
   }
   ```

2. **Reduce span attributes:**
   Drop large or unnecessary attributes at ingestion

---

## Backup and Recovery

### Regular Backups

```bash
# Backup all data
make backup

# Backup specific component
make backup-prometheus
make backup-loki
make backup-tempo
make backup-grafana
```

### Restore from Backup

```bash
# List available backups
ls -la backups/

# Restore specific component
make restore-prometheus FILE=./backups/prometheus_20240101_120000.tar.gz
```

### Backup Schedule Recommendations

| Environment | Frequency | Retention |
|-------------|-----------|-----------|
| Development | Weekly | 2 backups |
| Staging | Daily | 7 backups |
| Production | Daily | 30 backups |

---

## Volume Management

### Using External Storage

For production, consider mounting external volumes:

```yaml
# Example: Using NFS for Prometheus data
volumes:
  oib-prometheus-data:
    driver: local
    driver_opts:
      type: nfs
      o: addr=nfs-server.local,rw
      device: ":/exports/prometheus"
```

### Volume Cleanup

To completely reset storage:

```bash
# Stop services
make stop

# Remove volumes (WARNING: deletes all data)
docker volume rm oib-prometheus-data oib-loki-data oib-tempo-data

# Reinstall
make install
```

---

## Troubleshooting Storage Issues

### "No space left on device"

1. Check usage:
   ```bash
   docker system df
   make disk-usage
   ```

2. Clean up:
   ```bash
   make clean
   docker system prune -a --volumes  # CAREFUL: removes unused volumes
   ```

3. Reduce retention and restart

### Slow queries

1. Check Prometheus cardinality:
   ```promql
   count({__name__!=""}) by (__name__)
   ```

2. Check Loki chunk statistics:
   ```bash
   curl http://localhost:3100/metrics | grep loki_chunk
   ```

3. Consider adding indexes or reducing query time ranges

### Data corruption

If a volume becomes corrupted:

1. Stop the affected service
2. Restore from backup:
   ```bash
   make restore-prometheus FILE=./backups/prometheus_latest.tar.gz
   ```
3. If no backup, recreate the volume:
   ```bash
   docker volume rm oib-prometheus-data
   make install-metrics
   ```

---

## Quick Reference

### Change Retention

| Component | Quick Change |
|-----------|-------------|
| Prometheus | Edit `.env`: `PROMETHEUS_RETENTION_TIME=30d` |
| Loki | Edit `logging/config/loki-config.yml`: `retention_period: 336h` |
| Tempo | Edit `telemetry/config/tempo.yaml`: `block_retention: 168h` |

### Check Storage

```bash
# All components
make disk-usage

# Prometheus specific
curl -s http://localhost:9090/api/v1/status/tsdb | jq '.data.headStats'

# Loki specific
curl -s http://localhost:3100/metrics | grep loki_ingester_memory_chunks
```

### Backup Commands

```bash
make backup              # All components
make backup-prometheus   # Prometheus only
make backup-loki         # Loki only
make backup-tempo        # Tempo only
make backup-grafana      # Grafana only
```
