# Troubleshooting Guide

Common issues and their solutions when running OIB.

## Quick Diagnostics

Run the built-in diagnostics:

```bash
make doctor    # Check Docker, .env, network, ports
make preflight # Check Docker, Compose and port conflicts (what make install runs first)
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

4. **Recreate the stack's containers (keeps data):**
   ```bash
   make install-logging
   ```
   Only as a last resort, reset the stack. This **deletes its volume** (all stored logs, here):
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
   Alloy discovers every container on the host through `/var/run/docker.sock`; containers do not need to be on `oib-network`. With rootless Docker or Podman the socket lives elsewhere and must be mounted at `/var/run/docker.sock` in `logging/compose.yaml`. In restricted mode (`OIB_MODE=restricted`) `oib-alloy-logging` is not run at all and container logs are not collected; push logs to Loki instead.

2. **Test log ingestion end to end:**
   ```bash
   make demo   # pushes a line with {job="oib-demo"} and checks it is searchable
   ```
   To test container collection, run something that lives longer than Alloy's 5-second discovery interval:
   ```bash
   docker run --rm --name oib-logtest alpine sh -c 'for i in $(seq 1 20); do echo "test log $i"; sleep 1; done'
   ```
   Then query `{container_name="oib-logtest"}` in Grafana Explore → Loki.

3. **Check the Alloy pipeline UI:** http://localhost:12345

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

4. **Check where the app sends from:** the OTLP ports listen on `127.0.0.1` unless `OTEL_BIND_ADDR=0.0.0.0` is set (then run `make install`). Containers should use `oib-alloy-telemetry:4317` / `:4318` on `oib-network`; on Linux, `host.docker.internal` cannot reach the loopback-bound ports.

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
   Note that `PUSHGATEWAY_PORT` defaults to `9091` too, if you use the pushgateway profile.

3. **Recreate the containers with the new ports** (`make restart` keeps the old port mappings):
   ```bash
   make install
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

2. **Recreate network** (only possible when no container is attached; `docker network rm` refuses otherwise, so remove the stacks first):
   ```bash
   docker network inspect oib-network   # "Containers" must be empty
   docker network rm oib-network
   make network
   make install   # recreates the core stacks on the new network
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

3. **Apply the changes:**
   ```bash
   make restart-logging     # loki-config.yml
   make restart-telemetry   # tempo.yaml
   make install-metrics     # .env values are only read when the container is recreated
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

2. **Clean up unused Docker resources:**
   ```bash
   make clean  # docker system prune -f
   ```
   This is **host-wide**: it removes every stopped container, unused network, dangling image and build cache on the Docker host, not only OIB's. It does not remove volumes, so it does not shrink OIB's stored data.

3. **Reduce retention (see High memory usage above)**

4. **Backup and delete old data:**
   ```bash
   make backup
   make uninstall  # Removes all core-stack data (asks for confirmation)
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

# Or send SIGHUP to reload config (also reloads metrics/config/rules/*.yml)
docker exec oib-prometheus kill -HUP 1
```

`prometheus.yml` is bind-mounted as a single file. Editors or tools that replace the file instead of writing in place (for example `sed -i`) leave the container on the old copy, and a reload does not see the change; use `make restart-metrics` in that case. The same applies to the Loki, Tempo and Alloy config files.

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
   Dashboard JSON files are re-read every 30 seconds. Datasource changes need a restart:
   ```bash
   make restart-grafana
   ```

3. **Verify dashboard files:**
   ```bash
   ls -la grafana/provisioning/dashboards/json/
   make validate   # checks the JSON syntax
   ```

### Pyroscope datasource shows errors

The Pyroscope datasource is always provisioned, but `oib-pyroscope` only exists after `make install-profiling`. Install it, then `make restart-grafana`, or ignore the error if you don't use profiling.

### Cannot log in to Grafana after changing the password in .env

`GRAFANA_ADMIN_PASSWORD` is only applied when Grafana first creates its database in the `oib-grafana-data` volume. Later changes to `.env` do not change the stored password. Log in with the original password and change it in the Grafana UI. If it is lost, reset it:
```bash
docker exec -it oib-grafana grafana cli admin reset-admin-password '<new-password>'
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

3. **Recreate containers** (`make restart` does not re-read `.env`; this keeps your data):
   ```bash
   make install
   ```
   For the optional stacks use `make install-profiling` / `make install-services`.

4. **Know which containers see `.env`:** Compose reads it for variable substitution in every stack. Only Grafana, Loki, Prometheus, Tempo and Pyroscope also load it as container environment (`env_file`), so for example `TZ` does not reach the Alloy containers or cAdvisor.

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
| `name ... already in use` | Another container has the same name | For `oib-postgres` / `oib-redis`: the demo app and the shared services both define them (see [Known limitations](#known-limitations)). Stopping is not enough: remove the other stack's containers with `make demo-app-stop` or `make uninstall-services` (both also delete their volumes), or keep the data with `cd services && docker compose --env-file ../.env down`. Otherwise `docker ps -a` to find the leftover container and `docker rm` it, then rerun the target that failed |
| `port is already allocated` | Host port taken, e.g. 5000 by both the demo app and the Flask example | Stop the other user of the port (e.g. `make demo-app-stop`), or for core stacks change the port in `.env`, then rerun the target that failed |
| `Set GRAFANA_ADMIN_PASSWORD in the root .env file` | Password empty in `.env` | Set `GRAFANA_ADMIN_PASSWORD` |
| `env file .../.env not found` | No root `.env` | `cp .env.example .env` and set the password (`make install` creates it for you) |
| `out of memory` | Container hit memory limit | Increase limits in compose.yaml or reduce retention |

---

## Known Limitations

Behaviour of the current code that users hit and that is not fixed yet:

- **Demo app and shared services conflict.** `examples/demo-app/compose.yaml` and `services/compose.yaml` both create containers named `oib-postgres` and `oib-redis`, so `make demo-app` and `make install-services` cannot both be installed (a stopped container still holds its name). The demo app's PostgreSQL and Redis publish no host ports, even though `make demo-app` prints `localhost:5432` and `localhost:6379`.
- **Port 5000 is used twice.** The demo app and the Python Flask example (`make demo-examples`) both publish host port 5000, so only one can run. `make demo-app`, `make demo-traffic` and `make demo-examples` always probe `localhost:5000` (and `3003`-`3005`), ignoring `DEMO_APP_PORT` and `DEMO_BIND_ADDR`.
- **Example app metrics are not scraped.** The example apps expose `/metrics`, but `metrics/config/prometheus.yml` has no job for them. Add one yourself (for example `example-flask-app:5000`, `example-express-app:3000`, `example-ruby-rails:3000`, `example-php-laravel:8000`, `oib-demo-app:5000`).
- **PHP example metrics do not persist.** The PHP example keeps its counters per request, so its `/metrics` shows no request counts. Its folder is named `php-laravel`, but it is plain PHP on the built-in server.
- **Tempo service graph is empty.** Tempo's metrics generator runs, but `remote_write` is empty in `telemetry/config/tempo.yaml`, so no `traces_service_graph_*` or `traces_spanmetrics_*` series reach Prometheus and the Service Graph view in Explore → Tempo shows nothing.
- **Trace-to-logs may find nothing.** The Tempo datasource maps `service.name` to the Loki label `service_name`, which Loki derives from the container name. It only matches when `OTEL_SERVICE_NAME` equals the container name, which is not the case for the bundled examples. Query Loki directly instead, e.g. `{compose_service="my-app"} |= "<trace-id>"`.
- **Optional stacks are outside the umbrella targets.** `start`, `stop`, `restart`, `update`, `info`, `logs` and `uninstall` ignore profiling and services. `make uninstall` leaves `oib-network` in place if those (or any other containers) are still attached.
- **Pyroscope is localhost-only.** There is no bind-address setting for port 4040, so SDKs on other hosts cannot reach it; use `oib-pyroscope:4040` from containers on `oib-network`.
- **Two alert rules probably never fire.** According to the audit (not checked against a running instance), `ContainerRestarting` and `PrometheusHighScrapeLatency` in `metrics/config/rules/oib-alerts.yml` use metric names that cAdvisor and Prometheus do not export.
- **Missing `.env` gives Compose errors.** Most targets that call `docker compose` fail with `env file .../.env not found` instead of a friendly message. `make install` creates `.env` from `.env.example`.
