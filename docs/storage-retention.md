# Storage and Retention Guide

Understanding and tuning storage for OIB components.

## Default Retention Settings

| Component | Default Retention | Config Location |
|-----------|------------------|-----------------|
| Prometheus | 15 days OR 5GB | `.env` (`PROMETHEUS_RETENTION_TIME`, `PROMETHEUS_RETENTION_SIZE`) |
| Loki | 7 days (168h), deleted by the compactor | `logging/config/loki-config.yml` |
| Tempo | 3 days (72h) | `telemetry/config/tempo.yaml` |
| Pyroscope (optional) | Not set by OIB | N/A |
| Grafana | Unlimited | N/A (settings only) |

Data lives in the named volumes `oib-prometheus-data`, `oib-loki-data`, `oib-tempo-data`, `oib-grafana-data` and, if installed, `oib-pyroscope-data`.

---

## Storage Estimation

### Prometheus

**Formula:** `storage ≈ series_count × (retention ÷ scrape_interval) × ~2 bytes per sample` (OIB's global `scrape_interval` is 15s)

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

Recreate Prometheus to apply (the values are command-line flags, so `make restart-metrics` is not enough; data is kept):
```bash
make install-metrics
```

### Loki

Retention is already enforced: the shipped config enables it in the compactor. To change the period, edit `retention_period` in `logging/config/loki-config.yml`:
```yaml
limits_config:
  retention_period: 336h  # 14 days

# Already present in the shipped config; keep it, retention_period does nothing without it
compactor:
  working_directory: /loki/compactor
  retention_enabled: true
  delete_request_store: filesystem
```

**Upgrading an existing install:** older OIB versions set `retention_period` without enabling the compactor, so nothing was ever deleted. After updating, the first compaction deletes all logs older than `retention_period`. Run `make backup-loki` first, or raise `retention_period`, if you want to keep them.

`reject_old_samples_max_age: 168h` in the same file is unrelated to retention: it rejects incoming log lines older than 7 days.

Restart to apply:
```bash
make restart-logging
```

### Tempo

Edit `telemetry/config/tempo.yaml`:
```yaml
backend_scheduler:
  provider:
    compaction:
      compaction:
        block_retention: 168h  # 7 days
backend_worker:
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

1. **Filter logs at source:** add a `stage.drop` to the existing `loki.process "docker"` block in `logging/config/alloy-config.alloy`, then `make restart-logging`:
   ```
   loki.process "docker" {
     forward_to = [loki.write.loki.receiver]

     stage.drop {
       expression = "healthcheck|readiness"
     }

     // ... existing stages ...
   }
   ```
   Every container on the host is collected by default, so dropping noisy containers (with a `discovery.relabel` rule) is often the biggest saving.

2. **Increase chunk size** for better compression:
   ```yaml
   # loki-config.yml
   ingester:
     chunk_target_size: 1572864  # 1.5MB
   ```

### Tempo

1. **Implement sampling:** in `telemetry/config/alloy-config.alloy`, add a sampler and point the receiver's `output` at it instead of the batch processor, then `make restart-telemetry`:
   ```
   otelcol.processor.probabilistic_sampler "sampler" {
     sampling_percentage = 10  // Keep 10% of traces

     output {
       traces = [otelcol.processor.batch.default.input]
     }
   }

   // in otelcol.receiver.otlp "default":
   //   output { traces = [otelcol.processor.probabilistic_sampler.sampler.input] }
   ```
   With sampling on, `make demo` (and `make bootstrap`) usually fail, because their single test trace is dropped.

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

What `make backup` does and does not do:
- Writes `./backups/<component>_YYYYMMDD_HHMMSS.tar.gz` (use `make backup BACKUP_DIR=/path` for another directory). A component whose volume does not exist is skipped.
- Copies the volumes while the services keep running, so a backup is not guaranteed to be consistent. Run `make stop` before backing up if you need a clean copy, then `make start`.
- Does not cover `oib-pyroscope-data` or the shared-services PostgreSQL/Redis volumes.

### Restore from Backup

```bash
# List available backups and the restore commands
make restore

# Restore specific component (relative or absolute path)
make restore-prometheus FILE=./backups/prometheus_20240101_120000.tar.gz
```

Each `restore-*` target asks for confirmation, stops that service, deletes the current contents of its volume, extracts the archive and starts the service again. Targets: `restore-prometheus`, `restore-loki`, `restore-tempo`, `restore-grafana`.

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

To completely reset storage (`docker volume rm` fails while the containers exist, even stopped, so remove the stacks instead):

```bash
# Remove core stacks and their volumes (WARNING: deletes all data, asks for confirmation)
make uninstall

# Or reset a single stack, e.g. metrics only
make uninstall-metrics

# Reinstall
make install
```

Pyroscope and the shared services are not touched by `make uninstall`; use `make uninstall-profiling` / `make uninstall-services`.

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
   make clean                         # docker system prune -f for the WHOLE host (not only OIB); keeps volumes
   docker system prune -a --volumes   # CAREFUL: also removes all unused images and unused volumes host-wide
   ```
   Neither command shrinks OIB's own data volumes while OIB is installed; reduce retention for that.

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

1. Restore from backup (the target stops and restarts the service itself):
   ```bash
   make restore-prometheus FILE=./backups/prometheus_YYYYMMDD_HHMMSS.tar.gz
   ```
2. If no backup, recreate the stack and its volume (deletes that stack's data):
   ```bash
   make uninstall-metrics
   make install-metrics
   ```

---

## Quick Reference

### Change Retention

| Component | Quick Change |
|-----------|-------------|
| Prometheus | Edit `.env`: `PROMETHEUS_RETENTION_TIME=30d`, then `make install-metrics` |
| Loki | Edit `logging/config/loki-config.yml`: `retention_period: 336h`, then `make restart-logging` |
| Tempo | Edit `telemetry/config/tempo.yaml`: `block_retention: 168h`, then `make restart-telemetry` |

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
