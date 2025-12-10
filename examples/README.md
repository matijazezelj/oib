# Example: Integrate Your Docker Compose Project with OIB

This directory contains examples showing how to integrate your applications with the OIB observability stack.

## Quick Integration

### 1. Add logging to your containers

```yaml
# In your docker-compose.yml
services:
  my-app:
    image: my-app:latest
    logging:
      driver: loki
      options:
        loki-url: "http://host.docker.internal:3100/loki/api/v1/push"
        loki-batch-size: "400"
        labels: "app,environment"
    labels:
      app: "my-app"
      environment: "dev"
```

### 2. Expose Prometheus metrics

```yaml
services:
  my-app:
    ports:
      - "8080:8080"
    # Your app should expose /metrics endpoint
```

Then add to `metrics/config/prometheus.yml`:
```yaml
scrape_configs:
  - job_name: 'my-app'
    static_configs:
      - targets: ['host.docker.internal:8080']
```

### 3. Send traces via OpenTelemetry

```yaml
services:
  my-app:
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://host.docker.internal:4318
      - OTEL_SERVICE_NAME=my-app
```

## Network Integration

To connect your app to the OIB network:

```yaml
services:
  my-app:
    networks:
      - oib-network
      - default

networks:
  oib-network:
    external: true
```

This allows your app to communicate with OIB services using internal hostnames:
- Loki: `oib-loki:3100`
- Prometheus: `oib-prometheus:9090`
- Tempo (via Alloy): `oib-alloy-telemetry:4317` (gRPC) or `oib-alloy-telemetry:4318` (HTTP)

## Complete Examples

### Python Flask (`python-flask/`)

A fully instrumented Flask application with:
- **Logs**: Sent via stdout (collected by Alloy)
- **Metrics**: Exposed on `/metrics` endpoint
- **Traces**: Sent via OpenTelemetry to Tempo

```bash
cd python-flask
docker compose up -d
# Visit http://localhost:5001
```

### Node.js Express (`node-express/`)

A fully instrumented Express application with:
- **Logs**: Sent via pino (collected by Alloy)
- **Metrics**: Exposed on `/metrics` endpoint via prom-client
- **Traces**: Sent via OpenTelemetry to Tempo

```bash
cd node-express
docker compose up -d
# Visit http://localhost:3003
```

Both examples demonstrate:
- Automatic trace context propagation
- Custom spans and attributes
- Error tracking
- Request duration metrics
