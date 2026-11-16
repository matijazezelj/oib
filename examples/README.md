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

This builds and starts the Flask, Express, Rails, and PHP examples, waits for their `/health` endpoints, and sends 10 rounds of requests to `/`, `/api/data`, and `/api/error` on each. There is no make target to stop them; run `docker compose down` in each example directory.

## At a Glance

| Example | Host URL | Container (Loki `container_name`) | `OTEL_SERVICE_NAME` (Tempo) | OTLP | Started by |
|---------|----------|-----------------------------------|-----------------------------|------|-----------|
| `demo-app/` | http://localhost:5000 | `oib-demo-app` | `oib-demo-app` | gRPC | `make demo-app` |
| `python-flask/` | http://localhost:5000 | `example-flask-app` | `example-flask-app` | gRPC | `make demo-examples` |
| `node-express/` | http://localhost:3003 | `example-express-app` | `example-express-app` | gRPC | `make demo-examples` |
| `ruby-rails/` | http://localhost:3004 | `example-ruby-rails` | `example-rails-app` | HTTP | `make demo-examples` |
| `php-laravel/` | http://localhost:3005 | `example-php-laravel` | `example-php-app` | HTTP | `make demo-examples` |

Host ports are bound to `DEMO_BIND_ADDR` (default `127.0.0.1`). Only the demo app's port is configurable (`DEMO_APP_PORT`), and the make targets still probe `localhost:5000` regardless. For Rails and PHP the Tempo service name differs from the Loki container name, so search each under its own name.

## Known Limitations

- **Port 5000 clash.** `demo-app` and `python-flask` both publish host port 5000, so `make demo-app` and `make demo-examples` cannot run at the same time; the second fails with "port is already allocated". Stop one first (`make demo-app-stop`, or `docker compose down` in `python-flask/`).
- **Container name clash with the shared services.** `demo-app` starts its own `oib-postgres` and `oib-redis` containers, with the same names as `services/compose.yaml` (`make install-services`). Only one of the two can run; the other fails with "name already in use". Before `make demo-app`, run `make uninstall-services`, which deletes the shared PostgreSQL and Redis data (`down -v`), or `make stop-services` and then `docker rm oib-postgres oib-redis`, which keeps the volumes. In the other direction, `make demo-app-stop` removes the demo's containers and volumes.
- **No metrics scraping by default.** Every example exposes `/metrics`, but `metrics/config/prometheus.yml` has no scrape job for them. Add one (see [Expose Prometheus metrics](#2-expose-prometheus-metrics)) before querying app metrics in Prometheus.
- **PHP metrics do not accumulate.** `php-laravel/bootstrap/metrics.php` keeps counters in `$GLOBALS`, which is reset on every request, so `/metrics` shows only `php_info`, never `http_requests_total` samples. `promphp/prometheus_client_php` is installed but not used.
- **The "Laravel" example is plain PHP.** It is a small router in `public/index.php` served by `php -S` (PHP's single-threaded built-in server), not a Laravel app.
- **Rails metrics are per worker.** Puma runs 2 workers (`WEB_CONCURRENCY`, default 2) and `prometheus-client` uses its default in-process store, so each scrape sees only one worker's counts. Add `WEB_CONCURRENCY=0` (single mode) to the `environment:` list in `ruby-rails/compose.yaml` for consistent counters.
- **Hardcoded demo secrets.** `ruby-rails/compose.yaml` sets a fixed `SECRET_KEY_BASE`, and the demo app defaults to the PostgreSQL password `oib_secret`. Do not copy them into anything real.
- **`docker compose up` in an example directory does not read the root `.env`.** The make targets pass `--env-file` for you. When you run Compose by hand, use `docker compose --env-file ../../.env up -d` so `DEMO_BIND_ADDR` and the `POSTGRES_*` overrides apply.

## 📊 Pre-built Dashboards

OIB comes with dashboards ready to visualize your data (all in the **OIB** folder in Grafana):

| Dashboard | Description |
|-----------|-------------|
| **OIB Stack Health** | Home dashboard: OIB component health, scrape targets, alerts |
| **OIB - System Overview** | Host metrics, container CPU/memory, disk usage |
| **OIB - Host Metrics** | Detailed host CPU, memory, disk, and network metrics |
| **OIB - Logs Explorer** | Log volume, live logs, errors/warnings panel |
| **OIB - Traces Explorer** | TraceQL examples, Python, Node.js, Ruby & PHP code samples |
| **OIB - Profiles Explorer** | Pyroscope profiles (demo app only; needs `make install-profiling`) |
| **OIB - Request Latency** | Endpoint health, probe latency, k6 load test metrics |

## Quick Integration

### 1. Add logging to your containers

Nothing to do for containers on the OIB host: Alloy collects stdout/stderr from every container through the Docker socket. Write logs to stdout, ideally as JSON. The Loki Docker driver below is an alternative that needs the `grafana/loki-docker-driver` plugin installed; with both in place, lines may arrive twice. See [logging/README.md](../logging/README.md#using-loki-docker-driver) for the driver URL to use on Linux.

```yaml
# In your compose.yaml
services:
  my-app:
    image: my-app:latest
    logging:
      driver: loki
      options:
        loki-url: "http://localhost:3100/loki/api/v1/push"
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

If the app is on `oib-network`, scrape it by container name and container port instead, e.g. for the examples:
```yaml
  - job_name: 'examples'
    static_configs:
      - targets:
        - 'oib-demo-app:5000'
        - 'example-flask-app:5000'
        - 'example-express-app:3000'
        - 'example-ruby-rails:3000'
        - 'example-php-laravel:8000'
```

Apply with `make restart-metrics`.

### 3. Send traces via OpenTelemetry

Join `oib-network` (see [Network Integration](#network-integration)) and send to the Alloy container:

```yaml
services:
  my-app:
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://oib-alloy-telemetry:4318
      - OTEL_SERVICE_NAME=my-app
```

`http://host.docker.internal:4318` is an alternative (Docker Desktop behaviour not verified here). On Linux it needs `extra_hosts: ["host.docker.internal:host-gateway"]` and `OTEL_BIND_ADDR=0.0.0.0`, because the OTLP ports are bound to `127.0.0.1` by default.

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
- Pyroscope (optional): `oib-pyroscope:4040`

## Complete Examples

### Demo App with PostgreSQL & Redis (`demo-app/`)

A Python Flask API backed by PostgreSQL and Redis, meant to produce multi-span traces (HTTP → SQL queries, Redis cache hits and misses, an order transaction).

**Features:**
- **Traces**: OpenTelemetry with Flask, `psycopg2`, and `redis` instrumentation plus custom spans (OTLP gRPC to `oib-alloy-telemetry:4317`)
- **Metrics**: `app_requests_total`, `app_request_latency_seconds`, `app_db_queries_total`, `app_cache_operations_total` on `/metrics`
- **Profiles**: Pyroscope SDK sending to `http://oib-pyroscope:4040` (needs `make install-profiling`; set `PYROSCOPE_ENABLED=false` in `.env` to turn it off)
- **Logs**: Plain-text Python logging to the container log (stderr; no JSON, no trace IDs)

**Run (from the repo root):**
```bash
make demo-app        # build and start app, PostgreSQL and Redis
make demo-traffic    # 50 rounds of requests across all endpoints
make demo-app-stop   # stop and remove the containers AND their volumes (docker compose down -v)
```

`make demo-traffic` checks `http://localhost:5000/health` first and exits if the app is not running.

**Endpoints:**
| Endpoint | Description |
|----------|-------------|
| `GET /` | API documentation |
| `GET /health` | Health check (DB + Redis) |
| `GET /users` | List users (DB query) |
| `GET /users/<id>` | User with items (multiple queries) |
| `GET /items` | List items (cached in Redis) |
| `GET /items/<id>` | Item with view counter (Redis `INCR`) |
| `GET /orders`, `POST /orders` | List orders / create an order in a transaction |
| `GET /slow` | Slow endpoint (DB + cache) |
| `GET /error` | Simulated errors |
| `GET /metrics` | Prometheus metrics endpoint |

The database schema and seed data come from `services/init/`, mounted into the demo's PostgreSQL. The default credentials are `oib` / `oib_secret` (`POSTGRES_USER`/`POSTGRES_PASSWORD` in `.env`). PostgreSQL and Redis are only reachable on `oib-network`: the demo publishes no host ports for them, even though `make demo-app` prints `localhost:5432` and `localhost:6379`. See [Known Limitations](#known-limitations) for the port and container-name clashes.

---

### Python Flask (`python-flask/`)

A fully instrumented Flask application demonstrating all three pillars of observability.

**Features:**
- **Logs**: Structured JSON logging via structlog to stdout, with `trace_id`/`span_id` added inside a span (collected by Alloy)
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
docker compose --env-file ../../.env up -d
# App available at http://localhost:5000 (conflicts with the demo app's port)
```

**Key Files:**
- `app.py` - Main application with OTEL instrumentation
- `compose.yaml` - Container configuration with OIB network
- `requirements.txt` - Python dependencies

**Dependencies:**
```
flask
opentelemetry-api
opentelemetry-sdk
opentelemetry-exporter-otlp
opentelemetry-instrumentation-flask
prometheus-client
structlog
```

---

### Node.js Express (`node-express/`)

A fully instrumented Express application with proper OpenTelemetry setup.

**Features:**
- **Logs**: Structured JSON logging via Pino to stdout; trace context is meant to be added by the OpenTelemetry Pino instrumentation (not verified with these dependency versions)
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
docker compose --env-file ../../.env up -d
# App available at http://localhost:3003
```

**Key Files:**
- `tracing.js` - OpenTelemetry setup (loaded via `--require` flag)
- `app.js` - Main Express application
- `compose.yaml` - Container configuration with OIB network
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
  "@opentelemetry/exporter-trace-otlp-grpc": "^0.45.1",
  "@opentelemetry/resources": "^1.18.1",
  "@opentelemetry/semantic-conventions": "^1.18.1"
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
docker compose --env-file ../../.env up -d
# App available at http://localhost:3004
```

**Key Files:**
- `config/initializers/opentelemetry.rb` - OpenTelemetry setup
- `config/initializers/prometheus.rb` - Prometheus metrics setup
- `app/controllers/` - Controller implementations
- `compose.yaml` - Container configuration with OIB network

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

A lightweight plain-PHP application (no Laravel framework; served by `php -S`) with OpenTelemetry tracing, a `/metrics` endpoint, and JSON log messages.

**Features:**
- **Logs**: JSON messages written with `error_log()` (collected by Alloy); no trace IDs
- **Metrics**: Hand-written Prometheus text output in `bootstrap/metrics.php`. Counters reset on every request, so only `php_info` is ever exported (see [Known Limitations](#known-limitations))
- **Traces**: OpenTelemetry with OTLP HTTP exporter. Only `/api/data` creates a span (`process_data`); there is no per-request server span and no incoming `traceparent` extraction

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
docker compose --env-file ../../.env up -d
# App available at http://localhost:3005
```

**Key Files:**
- `public/index.php` - Main application with routing
- `bootstrap/tracing.php` - OpenTelemetry setup
- `bootstrap/metrics.php` - Prometheus metrics setup
- `compose.yaml` - Container configuration with OIB network

**Dependencies (composer.json):**
```json
{
  "require": {
    "open-telemetry/sdk": "^1.0",
    "open-telemetry/exporter-otlp": "^1.0",
    "guzzlehttp/guzzle": "^7.0",
    "nyholm/psr7": "^1.8",
    "promphp/prometheus_client_php": "^2.6"
  }
}
```

`guzzlehttp/guzzle` and `nyholm/psr7` provide the HTTP client the OTLP exporter discovers at runtime. `promphp/prometheus_client_php` is installed but not used by the code.

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

## What the Examples Demonstrate

| | Flask | Express | Rails | PHP | Demo app |
|---|---|---|---|---|---|
| Automatic HTTP server spans | ✅ | ✅ | ✅ | ❌ (one manual span on `/api/data`) | ✅ |
| Trace IDs in log lines | ✅ (structlog) | ⚠️ (via Pino instrumentation, unverified) | ✅ (Lograge request lines only) | ❌ | ❌ |
| JSON logs | ✅ | ✅ | ⚠️ (Lograge lines; `Rails.logger` calls are plain text) | ⚠️ (`error_log`, may carry a prefix) | ❌ |
| Request metrics on `/metrics` | ✅ | ✅ | ⚠️ (per Puma worker) | ❌ | ✅ |
| Profiles in Pyroscope | ❌ | ❌ | ❌ | ❌ | ✅ |

Trace-to-log correlation in Grafana filters Loki by trace ID, so it only finds lines from apps that log the trace ID.

## Viewing in Grafana

1. **Logs**: Explore → Loki → `{container_name="example-flask-app"}` or `{container_name="example-express-app"}` or `{container_name="example-ruby-rails"}` or `{container_name="example-php-laravel"}` or `{container_name="oib-demo-app"}`
2. **Traces**: Explore → Tempo → Search by service name (the `OTEL_SERVICE_NAME` column in [At a Glance](#at-a-glance), e.g. `example-rails-app`, not the container name)
3. **Trace-to-Log**: Click a trace in Tempo → "Logs for this span" to see correlated logs (see the table above for which apps support this)
4. **Metrics**: Explore → Prometheus → Query app metrics, after adding a scrape job (see [Expose Prometheus metrics](#2-expose-prometheus-metrics))

## Environment Variables

All examples use these environment variables (set in compose.yaml):

| Variable | Description | Example |
|----------|-------------|---------|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Alloy OTLP endpoint | `oib-alloy-telemetry:4317` (gRPC, Express and demo app), `http://oib-alloy-telemetry:4317` (Flask), `http://oib-alloy-telemetry:4318` (HTTP, Rails and PHP) |
| `OTEL_SERVICE_NAME` | Service name for traces | `example-flask-app` |

Values read from the root `.env` (via `make` or `--env-file`):

| Variable | Default | Used by |
|----------|---------|---------|
| `DEMO_BIND_ADDR` | `127.0.0.1` | Host bind address of all five apps |
| `DEMO_APP_PORT` | `5000` | Demo app host port (the make targets still use 5000) |
| `PYROSCOPE_ENABLED` | `true` | Demo app Pyroscope SDK |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | `oib` / `oib_secret` / `oib_demo` | Demo app and its PostgreSQL |

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
- Prometheus (`http://oib-prometheus:9090/-/healthy`)
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
      - http://oib-prometheus:9090/-/healthy
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
| `http_2xx` | HTTP GET, expect 2xx response (skips TLS certificate verification) |
| `http_post_2xx` | HTTP POST, expect 2xx response |
| `http_2xx_content` | HTTP GET + body content match |
| `https_2xx` | HTTPS with TLS verification |
| `tcp_connect` | TCP connection check |
| `tcp_tls` | TCP with TLS handshake |
| `icmp` | Ping check (needs the `NET_RAW` capability; untested here) |
| `dns_lookup` | DNS resolution test (queries `google.com` A records) |
| `grpc` | gRPC health check |
| `grpc_tls` | gRPC health check over TLS |

Only `http_2xx` is used by an active job. To use another module, add a job with that module in `params` (the commented `blackbox-tcp` and `blackbox-icmp` jobs in `prometheus.yml` are templates).

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
| `basic-load.js` | Standard load with stages | ~3.5 min | 20 |
| `stress-test.js` | Find system limits | ~14 min | 200 |
| `spike-test.js` | Sudden traffic spikes | ~4 min | 150 |
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
- **HTTP Duration**: p99 latency (k6's Prometheus remote-write output only exports `p(99)` for trends unless `K6_PROMETHEUS_RW_TREND_STATS` is set)
- **Timing Breakdown**: Blocked, Connecting, TLS, Sending, Waiting, Receiving (p99)

### Docker Network

k6 runs on `oib-network`, so you can test any container using internal hostnames:

| Service | Internal URL |
|---------|--------------|
| Example Flask | `http://example-flask-app:5000` |
| Example Express | `http://example-express-app:3000` |
| Example Rails | `http://example-ruby-rails:3000` |
| Example Laravel | `http://example-php-laravel:8000` |
| Demo app | `http://oib-demo-app:5000` |

See the [testing/README.md](../testing/README.md) for more details.
