# Telemetry Stack

Distributed tracing using Grafana Tempo and Alloy.

## Components

| Service | Port | Description |
|---------|------|-------------|
| **Tempo** | 3200 (localhost) | Trace storage and querying |
| **Alloy** | 12346 (localhost) | OTLP receiver and processor |

**Public Ports** (for external trace ingestion):
| Protocol | Port | Description |
|----------|------|-------------|
| OTLP gRPC | 4317 | gRPC trace receiver |
| OTLP HTTP | 4318 | HTTP trace receiver |

## Features

- **OpenTelemetry native**: Accepts OTLP traces (gRPC and HTTP)
- **TraceQL**: Query traces using Grafana's TraceQL language
- **Efficient storage**: Object-storage compatible backend
- **Trace-to-logs**: Link traces to logs in Grafana

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
- `retention_duration`: How long to keep traces (default: 72h = 3 days)
- `max_bytes_per_trace`: Maximum trace size

### Alloy Configuration
Edit `config/alloy-config.alloy`:
- OTLP receiver settings
- Batch processing configuration
- Tempo exporter endpoint

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TEMPO_HTTP_PORT` | `3200` | Tempo HTTP API port |
| `TEMPO_GRPC_PORT` | `9095` | Tempo gRPC port |
| `OTEL_GRPC_PORT` | `4317` | OTLP gRPC receiver (public) |
| `OTEL_HTTP_PORT` | `4318` | OTLP HTTP receiver (public) |
| `ALLOY_TELEMETRY_PORT` | `12346` | Alloy UI port |
| `TEMPO_VERSION` | `2.6.1` | Tempo image tag |
| `ALLOY_VERSION` | `v1.5.1` | Alloy image tag |

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
```yaml
services:
  my-app:
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://host.docker.internal:4318
      - OTEL_SERVICE_NAME=my-app
```

Or on `oib-network`:
```yaml
services:
  my-app:
    networks:
      - oib-network
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://oib-alloy-telemetry:4318
      - OTEL_SERVICE_NAME=my-app
```

## Troubleshooting

```bash
# Check if Tempo is ready
curl http://localhost:3200/ready

# Check Alloy pipeline status
open http://localhost:12346

# Verify OTLP endpoint is accessible
curl -v http://localhost:4318/v1/traces

# View Tempo logs
docker logs oib-tempo
```

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
