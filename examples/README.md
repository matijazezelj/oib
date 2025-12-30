# Example: Integrate Your Docker Compose Project with OIB

This directory contains examples showing how to integrate your applications with the OIB observability stack.

## Prerequisites

From the repo root, install the OIB stack:

```bash
# Configure credentials
cp .env.example .env
# Edit .env and set GRAFANA_ADMIN_PASSWORD

# Install all stacks
make install

# Verify installation
make health
```

## One-Command Demo

From the repo root, you can start all example apps and generate traffic:

```bash
make demo-examples
```

## 📊 Pre-built Dashboards

OIB comes with dashboards ready to visualize your data:

| Dashboard | Description |
|-----------|-------------|
| **System Overview** | Host metrics, container CPU/memory, disk usage |
| **Logs Explorer** | Log volume, live logs, errors/warnings panel |
| **Traces Explorer** | TraceQL examples, Python, Node.js, Ruby & PHP code samples |
| **Request Latency** | Endpoint health, probe latency, k6 load test metrics |

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

### PHP Laravel (`php-laravel/`)

A lightweight PHP application with OpenTelemetry tracing, Prometheus metrics, and structured JSON logging.

**Features:**
- **Logs**: Structured JSON logging to stdout (collected by Alloy)
- **Metrics**: Prometheus metrics via simple PHP implementation
- **Traces**: OpenTelemetry with OTLP HTTP exporter

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
cd php-laravel
docker compose up -d
# App available at http://localhost:3005
```

**Key Files:**
- `public/index.php` - Main application with routing
- `bootstrap/tracing.php` - OpenTelemetry setup
- `bootstrap/metrics.php` - Prometheus metrics setup
- `docker-compose.yml` - Container configuration with OIB network

**Dependencies (composer.json):**
```json
{
  "require": {
    "open-telemetry/sdk": "^1.0",
    "open-telemetry/exporter-otlp": "^1.0",
    "promphp/prometheus_client_php": "^2.6"
  }
}
```

**HTTP Exporter Configuration:**

PHP's OpenTelemetry uses the HTTP exporter:

```php
use OpenTelemetry\Contrib\Otlp\SpanExporter;
use OpenTelemetry\Contrib\Otlp\OtlpHttpTransportFactory;

$transport = (new OtlpHttpTransportFactory())->create(
    $otelEndpoint . '/v1/traces',
    'application/json'
);
$exporter = new SpanExporter($transport);
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

1. **Logs**: Explore → Loki → `{service_name="example-flask-app"}` or `{service_name="example-express-app"}` or `{service_name="example-rails-app"}` or `{service_name="example-laravel-app"}`
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

# Generate traffic to Laravel app
for i in {1..10}; do
  curl -s http://localhost:3005/
  curl -s http://localhost:3005/api/data
  curl -s http://localhost:3005/api/error 2>/dev/null
done
```

---

## 🔍 Blackbox Exporter (Endpoint Probing)

OIB includes [Blackbox Exporter](https://github.com/prometheus/blackbox_exporter) for synthetic monitoring - probing your endpoints from the outside.

### What It Does

- HTTP/HTTPS endpoint health checks
- TCP port connectivity tests
- ICMP ping checks
- DNS resolution tests
- SSL certificate validation

### Default Monitored Endpoints

By default, Blackbox probes these OIB services:
- Grafana (`http://oib-grafana:3000/api/health`)
- Prometheus (`http://oib-prometheus:9090/-/ready`)
- Loki (`http://oib-loki:3100/ready`)
- Tempo (`http://oib-tempo:3200/ready`)

### Add Your Own Endpoints

Edit `metrics/config/prometheus.yml` and add targets to the `blackbox-http` job:

```yaml
- job_name: 'blackbox-http'
  metrics_path: /probe
  params:
    module: [http_2xx]
  static_configs:
    - targets:
      # OIB services (default)
      - http://oib-grafana:3000/api/health
      - http://oib-prometheus:9090/-/ready
      # Add your endpoints
      - http://your-app:8080/health
      - https://api.example.com/status
  relabel_configs:
    - source_labels: [__address__]
      target_label: __param_target
    - source_labels: [__param_target]
      target_label: instance
    - target_label: __address__
      replacement: oib-blackbox-exporter:9115
```

### Available Probe Modules

| Module | Description |
|--------|-------------|
| `http_2xx` | HTTP GET, expect 2xx response |
| `http_post_2xx` | HTTP POST, expect 2xx response |
| `http_2xx_content` | HTTP GET + body content match |
| `https_2xx` | HTTPS with TLS verification |
| `tcp_connect` | TCP connection check |
| `tcp_tls` | TCP with TLS handshake |
| `icmp` | Ping check (requires privileges) |
| `dns_lookup` | DNS resolution test |
| `grpc` | gRPC health check |

### Viewing Results

Open Grafana → **Dashboards** → **OIB - Request Latency** to see:
- Endpoint UP/DOWN status
- 24h availability percentage
- Response time by phase (DNS, Connect, TLS, Processing, Transfer)
- Probe history timeline

---

## 🔥 k6 Load Testing

OIB includes [k6](https://k6.io/) for load testing your applications with real-time metrics in Grafana.

### Quick Start

```bash
# Run basic load test against Grafana
make test-load

# Run stress test (find breaking point)
make test-stress

# Run spike test (sudden traffic)
make test-spike

# Run API load test
make test-api
```

### Test a Custom Target

```bash
cd testing
docker compose --profile test run --rm \
  -e TARGET_URL=http://your-app:8080 \
  k6 run /scripts/basic-load.js
```

### Available Test Scripts

| Script | Purpose | Duration | Max VUs |
|--------|---------|----------|---------|
| `basic-load.js` | Standard load with stages | ~4 min | 20 |
| `stress-test.js` | Find system limits | ~13 min | 200 |
| `spike-test.js` | Sudden traffic spikes | ~5 min | 150 |
| `api-load.js` | Multi-endpoint API testing | ~2 min | 10 |

### Writing Custom Tests

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 10 },  // Ramp up to 10 users
    { duration: '1m', target: 10 },   // Stay at 10 users
    { duration: '30s', target: 0 },   // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],  // 95% of requests < 500ms
    http_req_failed: ['rate<0.01'],    // Error rate < 1%
  },
};

const BASE_URL = __ENV.TARGET_URL || 'http://oib-grafana:3000';

export default function () {
  const res = http.get(`${BASE_URL}/api/health`);
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(1);
}
```

### Viewing Results

k6 metrics are automatically sent to Prometheus. View them in:

**Grafana** → **Dashboards** → **OIB - Request Latency** → "k6 Load Test Metrics" section

Key metrics:
- **Virtual Users (VUs)**: Active concurrent users
- **Request Rate**: Requests per second
- **Error Rate**: Percentage of failed requests
- **HTTP Duration**: Latency percentiles (p50, p90, p95, p99)
- **Timing Breakdown**: Blocked, Connecting, TLS, Sending, Waiting, Receiving

### Docker Network

k6 runs on `oib-network`, so you can test any container using internal hostnames:

| Service | Internal URL |
|---------|--------------|
| Example Flask | `http://oib-example-python:5000` |
| Example Express | `http://oib-example-node:3000` |
| Example Rails | `http://oib-example-ruby:3000` |
| Example Laravel | `http://oib-example-php:80` |

See the [testing/README.md](../testing/README.md) for more details.
