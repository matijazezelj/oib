# Troubleshooting Guide

Common issues and their solutions when running OIB.

## Quick Diagnostics

Run the built-in diagnostics:

```bash
make doctor    # Check Docker, ports, configuration
make health    # Check service health
make status    # View service status
make validate  # Validate configuration files
```

---

## Service Issues

### Grafana shows "No data" in dashboards

**Symptoms:**
- Dashboards load but panels show "No data"
- Data source tests fail

**Solutions:**

1. **Check if services are healthy:**
   ```bash
   make health
   ```

2. **Verify network connectivity:**
   ```bash
   docker network inspect oib-network
   ```

3. **Check if data is being ingested:**
   ```bash
   # For metrics
   curl http://localhost:9090/api/v1/query?query=up

   # For logs
   curl http://localhost:3100/ready

   # For traces
   curl http://localhost:3200/ready
   ```

4. **Restart services:**
   ```bash
   make restart
   ```

### Service fails to start

**Symptoms:**
- Container exits immediately
- Health check fails repeatedly

**Solutions:**

1. **Check container logs:**
   ```bash
   make logs-logging    # For Loki/Alloy logging issues
   make logs-metrics    # For Prometheus issues
   make logs-telemetry  # For Tempo issues
   make logs-grafana    # For Grafana issues
   ```

2. **Check for port conflicts:**
   ```bash
   make check-ports
   ```

3. **Verify Docker resources:**
   ```bash
   docker system df
   docker stats --no-stream
   ```

4. **Reset the service:**
   ```bash
   make uninstall-logging && make install-logging
   ```

### Loki not receiving logs

**Symptoms:**
- No logs appear in Grafana
- Alloy logging shows errors

**Solutions:**

1. **Verify Alloy can access Docker socket:**
   ```bash
   docker logs oib-alloy-logging
   ```

2. **Check if containers are on the right network:**
   ```bash
   docker network inspect oib-network | grep -A5 "Containers"
   ```

3. **Test log ingestion manually:**
   ```bash
   docker run --rm --network oib-network alpine echo "test log message"
   ```

### Prometheus not scraping targets

**Symptoms:**
- Targets show as "down" in Prometheus
- Metrics are missing

**Solutions:**

1. **Check target status:**
   Open http://localhost:9090/targets

2. **Verify scrape config:**
   ```bash
   cat metrics/config/prometheus.yml
   ```

3. **Test target connectivity:**
   ```bash
   docker exec oib-prometheus wget -qO- http://cadvisor:8080/metrics | head
   ```

### Tempo not receiving traces

**Symptoms:**
- No traces in Grafana
- Application logs show OTLP errors

**Solutions:**

1. **Verify OTLP endpoints are accessible:**
   ```bash
   # Test gRPC endpoint
   curl -v http://localhost:4317

   # Test HTTP endpoint
   curl -v http://localhost:4318/v1/traces
   ```

2. **Check Alloy telemetry logs:**
   ```bash
   docker logs oib-alloy-telemetry
   ```

3. **Send a test trace:**
   ```bash
   make demo  # Sends sample trace
   ```

---

## Network Issues

### Port already in use

**Symptoms:**
- Error: "bind: address already in use"
- Service won't start

**Solutions:**

1. **Find what's using the port:**
   ```bash
   lsof -i :3000  # For Grafana
   lsof -i :9090  # For Prometheus
   lsof -i :3100  # For Loki
   ```

2. **Change the port in .env:**
   ```bash
   # Edit .env
   GRAFANA_PORT=3001
   PROMETHEUS_PORT=9091
   ```

3. **Restart the stack:**
   ```bash
   make restart
   ```

### Containers can't communicate

**Symptoms:**
- Connection refused errors between services
- DNS resolution failures

**Solutions:**

1. **Verify network exists:**
   ```bash
   docker network ls | grep oib-network
   ```

2. **Recreate network:**
   ```bash
   docker network rm oib-network
   make network
   ```

3. **Check container DNS:**
   ```bash
   docker exec oib-grafana nslookup oib-prometheus
   ```

---

## Resource Issues

### High memory usage

**Symptoms:**
- Services become slow or unresponsive
- Docker reports high memory usage

**Solutions:**

1. **Check current usage:**
   ```bash
   docker stats --no-stream | grep oib
   ```

2. **Reduce retention periods:**
   Edit the following files:
   - `logging/config/loki-config.yml`: Set `retention_period: 72h`
   - `telemetry/config/tempo.yaml`: Set `block_retention: 48h`
   - `.env`: Set `PROMETHEUS_RETENTION_TIME=7d`

3. **Restart to apply changes:**
   ```bash
   make restart
   ```

### Disk space full

**Symptoms:**
- Services fail to write data
- Docker volume errors

**Solutions:**

1. **Check disk usage:**
   ```bash
   make disk-usage
   docker system df
   ```

2. **Clean up old data:**
   ```bash
   make clean  # Removes unused Docker resources
   ```

3. **Reduce retention (see High memory usage above)**

4. **Backup and delete old data:**
   ```bash
   make backup
   make uninstall  # Removes all data
   make install
   ```

---

## Configuration Issues

### Changes to prometheus.yml not taking effect

**Solution:**
Prometheus requires a restart or reload:
```bash
# Full restart
make restart-metrics

# Or send SIGHUP to reload config
docker exec oib-prometheus kill -HUP 1
```

### Grafana dashboards not loading

**Symptoms:**
- Dashboard shows error
- Panels fail to render

**Solutions:**

1. **Check Grafana logs:**
   ```bash
   docker logs oib-grafana | grep -i error
   ```

2. **Re-provision dashboards:**
   ```bash
   make restart-grafana
   ```

3. **Verify dashboard files:**
   ```bash
   ls -la grafana/provisioning/dashboards/json/
   ```

### Environment variables not applied

**Solutions:**

1. **Verify .env exists:**
   ```bash
   ls -la .env
   ```

2. **Check for syntax errors:**
   ```bash
   # No spaces around =
   GOOD_VAR=value
   BAD_VAR = value  # This won't work
   ```

3. **Recreate containers:**
   ```bash
   make uninstall && make install
   ```

---

## Debug Mode

For verbose output during troubleshooting:

```bash
make install DEBUG=1
make restart DEBUG=1
```

This enables Docker Compose verbose mode and shows more details about what's happening.

---

## Getting Help

If you're still stuck:

1. **Check existing issues:** [GitHub Issues](https://github.com/matijazezelj/oib/issues)
2. **Open a new issue** with:
   - Output of `make doctor`
   - Output of `make status`
   - Relevant container logs
   - Your Docker and OS version

---

## Common Error Messages

| Error | Meaning | Solution |
|-------|---------|----------|
| `connection refused` | Service not running or wrong port | Check `make health`, verify ports in `.env` |
| `no such network` | oib-network doesn't exist | Run `make network` |
| `permission denied` | Docker socket access issue | Add user to docker group or run with sudo |
| `name already in use` | Container name conflict | Run `make uninstall` then `make install` |
| `out of memory` | Container hit memory limit | Increase limits in compose.yaml or reduce retention |
