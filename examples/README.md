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

A fully instrumented Flask application demonstrating all three pillars of observability.

**Features:**
- **Logs**: Structured JSON logging via Python's logging module (collected by Alloy)
- **Metrics**: Prometheus metrics exposed on `/metrics` endpoint
- **Traces**: OpenTelemetry auto-instrumentation with trace context in logs

**Endpoints:**
| Endpoint | Description |
|----------|-------------|
| `GET /` | Home page - returns welcome message |
| `GET /api/data` | Simulates processing with random delay (50-500ms) |
| `GET /api/error` | Triggers an intentional error for testing |
| `GET /metrics` | Prometheus metrics endpoint |
| `GET /health` | Health check endpoint |

**Run:**
```bash
cd python-flask
docker compose up -d
# App available at http://localhost:5000
```

**Key Files:**
- `app.py` - Main application with OTEL instrumentation
- `docker-compose.yml` - Container configuration with OIB network
- `requirements.txt` - Python dependencies

**Dependencies:**
```
flask
opentelemetry-distro
opentelemetry-exporter-otlp
opentelemetry-instrumentation-flask
prometheus-client
```

---

### Node.js Express (`node-express/`)

A fully instrumented Express application with proper OpenTelemetry setup.

**Features:**
- **Logs**: Structured JSON logging via Pino with trace context injection
- **Metrics**: Prometheus metrics via `prom-client` library
- **Traces**: OpenTelemetry auto-instrumentation for Express, HTTP, and more

**Endpoints:**
| Endpoint | Description |
|----------|-------------|
| `GET /` | Home page - returns welcome message |
| `GET /api/data` | Simulates processing with random delay (50-500ms) |
| `GET /api/error` | Triggers an intentional error for testing |
| `GET /metrics` | Prometheus metrics endpoint |
| `GET /health` | Health check endpoint |

**Run:**
```bash
cd node-express
docker compose up -d
# App available at http://localhost:3003
```

**Key Files:**
- `tracing.js` - OpenTelemetry setup (loaded via `--require` flag)
- `app.js` - Main Express application
- `docker-compose.yml` - Container configuration with OIB network
- `package.json` - Node.js dependencies and scripts

**Dependencies:**
```json
{
  "express": "^4.18.2",
  "prom-client": "^15.1.0",
  "pino": "^8.17.2",
  "@grpc/grpc-js": "^1.9.13",
  "@opentelemetry/api": "^1.7.0",
  "@opentelemetry/sdk-node": "^0.45.1",
  "@opentelemetry/auto-instrumentations-node": "^0.40.1",
  "@opentelemetry/exporter-trace-otlp-grpc": "^0.45.1"
}
```

**Important: OTEL Instrumentation Loading**

Node.js OpenTelemetry auto-instrumentation **must be loaded before any other modules**. This is achieved using the `--require` flag:

```json
{
  "scripts": {
    "start": "node --require ./tracing.js app.js"
  }
}
```

The `tracing.js` file sets up the OpenTelemetry SDK before Express or any other instrumented module is imported.

**gRPC Exporter Configuration:**

When connecting to Alloy's OTLP receiver (which uses plaintext), you must disable TLS:

```javascript
const grpc = require('@grpc/grpc-js');

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({
    url: `http://${otelEndpoint}`,
    credentials: grpc.credentials.createInsecure(),
  }),
  // ...
});
```

---

### Ruby on Rails (`ruby-rails/`)

A fully instrumented Rails API application with OpenTelemetry, Prometheus metrics, and structured logging.

**Features:**
- **Logs**: Structured JSON logging via Lograge with trace context injection
- **Metrics**: Prometheus metrics via `prometheus-client` gem
- **Traces**: OpenTelemetry auto-instrumentation for Rails, HTTP, and more

**Endpoints:**
| Endpoint | Description |
|----------|-------------|
| `GET /` | Home page - returns welcome message |
| `GET /api/data` | Simulates processing with random delay (50-500ms) |
| `GET /api/error` | Triggers an intentional error for testing |
| `GET /metrics` | Prometheus metrics endpoint |
| `GET /health` | Health check endpoint |

**Run:**
```bash
cd ruby-rails
docker compose up -d
# App available at http://localhost:3004
```

**Key Files:**
- `config/initializers/opentelemetry.rb` - OpenTelemetry setup
- `config/initializers/prometheus.rb` - Prometheus metrics setup
- `app/controllers/` - Controller implementations
- `docker-compose.yml` - Container configuration with OIB network

**Dependencies (Gemfile):**
```ruby
gem "opentelemetry-sdk"
gem "opentelemetry-exporter-otlp"
gem "opentelemetry-instrumentation-all"
gem "prometheus-client"
gem "lograge"  # Structured JSON logging
```

**HTTP Exporter Configuration:**

Ruby's OpenTelemetry uses the HTTP exporter by default. Configure it to use Alloy's OTLP HTTP endpoint:

```ruby
# config/initializers/opentelemetry.rb
OpenTelemetry::SDK.configure do |c|
  c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "example-rails-app")

  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      OpenTelemetry::Exporter::OTLP::Exporter.new(
        endpoint: "#{ENV['OTEL_EXPORTER_OTLP_ENDPOINT']}/v1/traces"
      )
    )
  )

  c.use_all  # Auto-instrument Rails, Net::HTTP, etc.
end
```

---

## What All Examples Demonstrate

- ✅ Automatic trace context propagation
- ✅ Trace IDs injected into log messages
- ✅ Custom spans and attributes
- ✅ Error tracking with stack traces
- ✅ Request duration metrics
- ✅ Trace-to-log correlation in Grafana

## Viewing in Grafana

1. **Logs**: Explore → Loki → `{service_name="example-flask-app"}` or `{service_name="example-express-app"}` or `{service_name="example-rails-app"}`
2. **Traces**: Explore → Tempo → Search by service name
3. **Trace-to-Log**: Click a trace in Tempo → "Logs for this span" to see correlated logs
4. **Metrics**: Explore → Prometheus → Query app metrics

## Environment Variables

All examples use these environment variables (set in docker-compose.yml):

| Variable | Description | Example |
|----------|-------------|---------|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Alloy OTLP endpoint | `oib-alloy-telemetry:4317` (gRPC) or `:4318` (HTTP) |
| `OTEL_SERVICE_NAME` | Service name for traces | `example-flask-app` |

## Generating Test Traffic

```bash
# Generate traffic to Flask app
for i in {1..10}; do
  curl -s http://localhost:5000/
  curl -s http://localhost:5000/api/data
  curl -s http://localhost:5000/api/error 2>/dev/null
done

# Generate traffic to Express app
for i in {1..10}; do
  curl -s http://localhost:3003/
  curl -s http://localhost:3003/api/data
  curl -s http://localhost:3003/api/error 2>/dev/null
done

# Generate traffic to Rails app
for i in {1..10}; do
  curl -s http://localhost:3004/
  curl -s http://localhost:3004/api/data
  curl -s http://localhost:3004/api/error 2>/dev/null
done
```
