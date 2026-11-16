# Telemetry Stack

Distributed tracing using Grafana Tempo and Alloy.

## Components

| Service | Port | Description |
|---------|------|-------------|
| **Tempo** | 3200 (localhost) | Trace storage and querying |
| **Tempo gRPC** | 9095 (localhost) | Tempo's internal gRPC API; not an OTLP port, do not send traces here |
| **Alloy** | 12346 (localhost) | OTLP receiver and processor (UI at `/`) |

Containers: `oib-tempo`, `oib-alloy-telemetry`. Volume: `oib-tempo-data`. `oib-tempo` loads the whole root `.env` (`env_file`), so its values, including `GRAFANA_ADMIN_PASSWORD`, are visible through `docker inspect oib-tempo`.

**Trace ingestion ports** (`OTEL_BIND_ADDR`, default `127.0.0.1`), served by `oib-alloy-telemetry`:

| Protocol | Port | Description |
|----------|------|-------------|
| OTLP gRPC | 4317 | gRPC trace receiver |
| OTLP HTTP | 4318 | HTTP trace receiver (`/v1/traces`) |

Set `OTEL_BIND_ADDR=0.0.0.0` only when applications on other hosts need to send traces, and protect the endpoints with appropriate network controls. The receivers have no authentication.

## Features

- **OpenTelemetry native**: Accepts OTLP traces (gRPC and HTTP)
- **TraceQL**: Query traces using Grafana's TraceQL language
- **Local storage**: Blocks and WAL on the `oib-tempo-data` volume (`backend: local`)
- **Trace-to-logs and trace-to-profiles**: Links from a span to Loki and Pyroscope in Grafana (see the [Grafana README](../grafana/README.md#datasources) for the caveats)

## Limitations

- **Traces only.** The Alloy pipeline only has a traces output. The OTLP receiver has no metrics or logs output, so OTLP metrics and logs sent to 4317/4318 are not stored anywhere. Send metrics to Prometheus and logs to stdout (collected by the logging stack).
- **Span attributes are overwritten.** Alloy upserts `environment="homelab"` and `collector="alloy"` on every span (`otelcol.processor.attributes`), replacing any `environment` attribute your app sets. Edit or remove those actions in `config/alloy-config.alloy`.
- **No service graph or span metrics in Prometheus.** Tempo's metrics generator runs the `service-graphs` and `span-metrics` processors, but `metrics_generator.storage.remote_write` is empty, so no `traces_service_graph_*` or `traces_spanmetrics_*` series are written anywhere. Grafana's Service Graph view stays empty.

## Quick Start

```bash
# Install from repo root
make install-telemetry

# Check status
make status

# View logs
make logs-telemetry
```

## Configuration

### Tempo Configuration
Edit `config/tempo.yaml`:
- `backend_scheduler.provider.compaction.compaction.block_retention` and `backend_worker.compaction.block_retention`: How long to keep traces (default: 72h = 3 days). Tempo 3 has no `compactor` block; set both to the same value.

Retention is set only in this file; there is no environment variable for it. Apply changes with `make restart-telemetry`.

### Alloy Configuration
Edit `config/alloy-config.alloy`:
- OTLP receiver settings
- Batch processing configuration (1s timeout, 1024 spans)
- Span attributes added to every span
- Tempo exporter endpoint (`oib-tempo:4317`, plaintext)
- An optional, commented-out debug exporter that logs received traces

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TEMPO_HTTP_PORT` | `3200` | Tempo HTTP API port |
| `TEMPO_GRPC_PORT` | `9095` | Tempo gRPC port |
| `OTEL_BIND_ADDR` | `127.0.0.1` | OTLP receiver bind address |
| `OTEL_GRPC_PORT` | `4317` | OTLP gRPC receiver port |
| `OTEL_HTTP_PORT` | `4318` | OTLP HTTP receiver port |
| `ALLOY_TELEMETRY_PORT` | `12346` | Alloy UI port |
| `TEMPO_VERSION` | `3.1.1` | Tempo image tag |
| `ALLOY_VERSION` | `v1.22.0` | Alloy image tag |

## Sending Traces

### Python (OpenTelemetry)
```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

# Setup
provider = TracerProvider()
exporter = OTLPSpanExporter(endpoint="localhost:4317", insecure=True)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)

# Create spans
tracer = trace.get_tracer(__name__)
with tracer.start_as_current_span("my-operation"):
    # Your code here
    pass
```

### Node.js (OpenTelemetry)
```javascript
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({
    url: 'http://localhost:4317',
  }),
});
sdk.start();
```

### Environment Variable Configuration
Most OpenTelemetry SDKs support auto-configuration:
```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
export OTEL_SERVICE_NAME=my-service
```

### Docker Compose Integration
Recommended: join `oib-network` and use the container name.
```yaml
services:
  my-app:
    networks:
      - oib-network
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://oib-alloy-telemetry:4318
      - OTEL_SERVICE_NAME=my-app

networks:
  oib-network:
    external: true
```

Without `oib-network`, go through the host:
```yaml
services:
  my-app:
    extra_hosts:
      - "host.docker.internal:host-gateway"   # needed on Linux
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://host.docker.internal:4318
      - OTEL_SERVICE_NAME=my-app
```

On Linux this only works with `OTEL_BIND_ADDR=0.0.0.0`: with the default `127.0.0.1`, the OTLP ports are not reachable through the Docker bridge gateway.

## Troubleshooting

```bash
# Check if Tempo is ready
curl http://localhost:3200/ready

# Check Alloy pipeline status
open http://localhost:12346

# Verify OTLP endpoint is accessible
curl -v http://localhost:4318/v1/traces

# View Tempo and Alloy logs
make logs-telemetry

# Show the endpoints to configure in your app
make info-telemetry
```

The Tempo image is distroless, so the container has no Docker healthcheck. `make health` and the Blackbox probe on `http://oib-tempo:3200/ready` report its readiness instead.

## Backup and Restore

```bash
make backup-tempo                          # writes ./backups/tempo_<YYYYMMDD_HHMMSS>.tar.gz
make restore-tempo FILE=./backups/tempo_YYYYMMDD_HHMMSS.tar.gz
```

Restore asks for confirmation, stops Tempo, replaces the contents of `oib-tempo-data`, and starts Tempo again. `make uninstall-telemetry` deletes the volume.

## Querying Traces

In Grafana, use the Tempo datasource with TraceQL:

```
# Find traces by service
{ resource.service.name = "my-app" }

# Find slow traces
{ duration > 1s }

# Find errors
{ status = error }
```
