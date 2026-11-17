---
layout: default
title: Observability in a Box
---

# 🔭 Observability in a Box

**A preconfigured, self-hosted observability stack for local development, homelabs, and small teams.**

Run Prometheus, Loki, Tempo, Alloy, Grafana, and optional Pyroscope in Docker with ready-made dashboards and instrumented examples.

<a href="https://in-a-box-tools.tech" class="btn">Website</a>
<a href="https://github.com/matijazezelj/oib" class="btn">View on GitHub</a>
<a href="https://github.com/matijazezelj/oib#-quick-start" class="btn">Documentation</a>

---

## ⚡ Quick Start

```bash
# Clone and configure
git clone https://github.com/matijazezelj/oib.git && cd oib
cp .env.example .env  # Edit and set GRAFANA_ADMIN_PASSWORD (empty by default)

# Install and explore
make install
make demo    # Sends a test log line and trace, checks both are searchable
make open
```

Open [http://localhost:3000](http://localhost:3000), or your configured `GRAFANA_PORT`, and start on the OIB Stack Health dashboard.

---

## 📦 What's Included

| Stack | Components | What It Does |
|-------|------------|--------------|
| **Logging** | Loki + Alloy | Centralized log aggregation with automatic Docker log collection |
| **Metrics** | Prometheus + Alloy + cAdvisor | Host metrics via Alloy, container metrics via cAdvisor, endpoint probing |
| **Tracing** | Tempo + Alloy | Distributed tracing with OpenTelemetry support |
| **Profiling** | Pyroscope | Continuous profiling (optional: `make install-profiling`) |
| **Visualization** | Grafana | Pre-built dashboards for all four pillars |
| **Testing** | k6 | Load testing with metrics streaming to Prometheus |

---

## 🔌 Integration Endpoints

Once installed, your applications can send data to:

| Data Type | Endpoint | Protocol |
|-----------|----------|----------|
| **Traces** | `localhost:4317` | OTLP gRPC |
| **Traces** | `http://localhost:4318` | OTLP HTTP |
| **Profiles** | `http://localhost:4040` | Pyroscope SDK (optional, localhost only) |
| **Logs** | Automatic | Every container on the host is collected through the Docker socket |
| **Logs** | `http://localhost:3100/loki/api/v1/push` | Loki push API |
| **Metrics** | Static scrape jobs in `metrics/config/prometheus.yml` | Prometheus scrape |

Containers on `oib-network` use `oib-alloy-telemetry:4317` / `http://oib-alloy-telemetry:4318` for traces and `oib-pyroscope:4040` for profiles. OTLP listens on `127.0.0.1` unless `OTEL_BIND_ADDR=0.0.0.0` is set in `.env`.

---

## 📊 Pre-built Dashboards

OIB comes with seven ready-to-use Grafana dashboards in the **OIB** folder, provisioned with Prometheus, Loki, Tempo and Pyroscope datasources:

- **System Overview** — Container CPU/memory, disk usage, network I/O
- **Host Metrics** — Detailed host system metrics (CPU, memory, disk, network) via Alloy
- **Logs Explorer** — Log volume, live logs, errors/warnings panel
- **Traces Explorer** — TraceQL examples with code samples for Python, Node.js, Ruby, and PHP
- **Profiles Explorer** — Pyroscope setup guidance and per-language examples (text panels; view profiles in Explore → Pyroscope after `make install-profiling`)
- **Request Latency** — Endpoint probing results and k6 load test metrics
- **Stack Health** — Grafana's home dashboard: health and ingestion status for the OIB components, scrape targets and alerts

---

## 🖼️ How It Looks

### Dashboard Overview
All OIB dashboards organized in one folder, with tags for easy filtering.

![OIB Dashboards](assets/images/dashboards.png)

### Stack Health
At-a-glance status for the OIB services, Prometheus ingestion, scrape targets, and alerts.

![OIB Stack Health](assets/images/stack-health.png)

### System Overview
Host CPU and memory gauges with system and container resource charts.

![System Overview](assets/images/system-overview.png)

### Logs Explorer
Log volume by container, live log stream, and dedicated errors/warnings panel.

![Logs Explorer](assets/images/logs-explorer.png)

### Traces Explorer
TraceQL examples and OpenTelemetry setup guidance for the included example languages.

![Traces Explorer](assets/images/traces-explorer.png)

### Request Latency & Probing
Endpoint health status, probe latency breakdown, and k6 load test metrics.

![Request Latency](assets/images/request-latency.png)

### Host Metrics
Detailed host system metrics: CPU, memory, disk I/O, filesystem, and network.

![Host Metrics](assets/images/host-metrics.png)

### Profiles Explorer
Pyroscope integration guidance and language-specific setup examples.

![Profiles Explorer](assets/images/profiles-explorer.png)

---

## 📖 The Story Behind OIB

I've spent 25 years in infrastructure. Started as a sysadmin, moved through DevOps, now I'm in SecOps. Along the way I've worked on systems handling petabytes of data and hundreds of thousands of requests per second.

And in all that time, one thing hasn't changed: **many teams still lack a clear view of how their applications behave after deployment.**

I don't mean that as criticism. It's not their job to know the internals of Prometheus or wrestle with Loki configurations. They're busy writing features, fixing bugs, shipping code. But the gap between "it works on my machine" and "it works at scale" is where careers get made or broken — and where outages happen at 3 AM.

### The Pattern I Keep Seeing

A dev writes an app. It works locally. It passes CI. It gets deployed. Then, weeks later:

- "Why is the API slow?"
- "Is this endpoint even being used?"
- "What was happening when that error occurred?"
- "How much memory does this thing actually need?"

The answers are hard to find without observability. Maybe there's basic logging that writes to stdout and disappears into the void. Maybe someone set up metrics once but the dashboard is broken and nobody remembers the password.

So everyone's flying blind, and when something breaks, the debugging process is pure archaeology.

### Why Observability Gets Skipped

Setting up proper observability is annoying. You need:

- A metrics stack (Prometheus, exporters, maybe a pushgateway)
- A logging stack (Loki or Elasticsearch, log shippers, retention policies)
- A tracing stack (Tempo or Jaeger, instrumentation, sampling)
- Grafana to visualize all of it
- Everything wired together correctly
- Dashboards that actually show useful information

That's a lot of YAML. A lot of documentation. A lot of "I'll do it later" that turns into never.

I get it. I've set this up dozens of times and it still takes me a few hours to do it right. For someone who just wants to see if their app is healthy, the barrier is too high.

### So I Built OIB

It's a single repo that gives you a Grafana-based Prometheus, Loki, and Tempo stack configured and ready to explore. Clone it, set a password, and run `make install`.

The whole thing runs in Docker. The default configuration is designed for local development, homelabs, learning, and single-host evaluation. The individual components can be deployed in production architectures, but OIB's default Compose topology is not a high-availability production platform.

---

## 👥 Who This Is For

- **Developers** who want to understand how their app behaves without becoming observability experts
- **Self-hosters** who want proper monitoring without the enterprise complexity
- **Small teams** who need observability but don't have dedicated SRE staff
- **Anyone learning** about metrics, logs, and traces in a hands-on way

---

## 🛠️ Commands Reference

```bash
# Installation
make install              # Install all core stacks (logging, metrics, telemetry, Grafana)
make install-logging      # Install logging stack only
make install-metrics      # Install metrics stack only
make install-telemetry    # Install telemetry stack only
make install-grafana      # Install Grafana only
make install-profiling    # Install Pyroscope (optional)
make install-services     # Install PostgreSQL + Redis (optional)

# Health & Status
make health               # Quick health check
make status               # Show all services
make doctor               # Diagnose common issues
make validate             # Validate configs, compose files and dashboards

# Demo & Testing
make demo                 # Send a test log line and trace
make demo-app             # Start demo app with PostgreSQL & Redis
make demo-traffic         # Generate traffic to the demo app
make test-load            # Run k6 load test

# Maintenance
make update               # Pull pinned images and recreate the core stacks
make latest               # Run with :latest image tags (make install reverts)
make logs                 # Tail logs from all core stacks
make backup               # Back up all data volumes (each component pauses briefly)
make clean                # docker system prune -f for the whole Docker host
make uninstall            # Remove core stacks and their data volumes
```

`make help` lists every target. `start`, `stop`, `restart`, `update`, `logs` and `uninstall` cover the core stacks only; the optional stacks have their own `-profiling` and `-services` targets. Shell completion for the targets is in [`completions/`](https://github.com/matijazezelj/oib/tree/main/completions).

---

## 💻 Example Integration

### Python (Flask with OpenTelemetry)

```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

provider = TracerProvider()
exporter = OTLPSpanExporter(endpoint="localhost:4317", insecure=True)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)

tracer = trace.get_tracer(__name__)

@app.route('/api/users')
def get_users():
    with tracer.start_as_current_span("get-users"):
        # Your code here
        return users
```

### Node.js (Express with OpenTelemetry)

```javascript
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({
    url: 'http://localhost:4317',
  }),
  serviceName: 'my-node-app',
});
sdk.start();
```

### Docker Compose Integration

```yaml
services:
  my-app:
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://oib-alloy-telemetry:4318
      - OTEL_SERVICE_NAME=my-app
    networks:
      - oib-network

networks:
  oib-network:
    external: true
```

---

## 📈 Instrumenting Multiple Application Instances

Multiple application instances can send telemetry to one OIB host for development and evaluation. This does not make the OIB backend highly available; see the [production hardening guide](production-hardening.md) before using the pattern outside a controlled environment.

### Docker Compose with Multiple Instances

```yaml
services:
  api:
    image: my-api:latest
    deploy:
      replicas: 3
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://oib-alloy-telemetry:4318
      - OTEL_SERVICE_NAME=api
      - OTEL_RESOURCE_ATTRIBUTES=service.instance.id={{.Task.Slot}}
    networks:
      - oib-network
      - default

  worker:
    image: my-worker:latest
    deploy:
      replicas: 5
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://oib-alloy-telemetry:4318
      - OTEL_SERVICE_NAME=worker
      - OTEL_RESOURCE_ATTRIBUTES=service.instance.id={{.Task.Slot}}
    networks:
      - oib-network
      - default

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - api
    networks:
      - oib-network
      - default

networks:
  oib-network:
    external: true
```

The `.Task.Slot` placeholder is a Docker Swarm template (`docker stack deploy`); plain `docker compose` passes it through literally. With Compose, set `service.instance.id` some other way (for example from the container hostname in your app), or leave it out.

### Scale with Docker Compose

```bash
# Start with 3 API instances and 5 workers
docker compose up -d --scale api=3 --scale worker=5

# Scale up during peak hours
docker compose up -d --scale api=10 --scale worker=20

# Scale down
docker compose up -d --scale api=2 --scale worker=3
```

### What You'll See in Grafana

With multiple instances, OIB gives you:

**Traces** — Each request shows the full journey across instances:
```
[nginx] → [api-1] → [worker-3] → [postgres]
[nginx] → [api-2] → [worker-1] → [redis]
```

**Metrics** — Per-instance breakdown:
- CPU/memory usage per container instance (cAdvisor, automatic)
- Request rate and error rate per instance, once you add a scrape job for your app's `/metrics` endpoint in `metrics/config/prometheus.yml` (OIB has no automatic discovery of app metrics)

**Logs** — Correlated by trace ID, if your app writes `trace_id` into its JSON logs. Alloy labels container logs with `compose_service`, `compose_project` and `container_name`:
```logql
{compose_service="api"} | json | trace_id="abc123"
```

### Querying Across Instances

**Find slow instances (TraceQL):**
```
{ resource.service.name = "api" && duration > 500ms } | by(resource.service.instance.id)
```

**Compare instance performance (PromQL):**
```promql
histogram_quantile(0.95, 
  sum by (instance, le) (
    rate(http_request_duration_seconds_bucket{service="api"}[5m])
  )
)
```

**Aggregate logs from all instances:**
```logql
{compose_service="api"} | json | level="error" | line_format "{{.container_name}}: {{.message}}"
```

---

## 💡 The Real Point

Observability shouldn't be a barrier. You shouldn't need to read 50 pages of documentation just to see how much memory your app is using.

I built OIB because I was tired of watching smart people debug production issues with `print` statements and hope. The tools exist. They're free. They just need to be easier to set up.

**If you've ever wondered what your app is actually doing once it leaves your laptop — [give it a try](https://github.com/matijazezelj/oib).**

---

## 🔗 Links

- **GitHub Repository**: [github.com/matijazezelj/oib](https://github.com/matijazezelj/oib)
- **Full Documentation**: [README](https://github.com/matijazezelj/oib#readme)
- **Examples**: [Python, Node.js, Ruby, PHP](https://github.com/matijazezelj/oib/tree/main/examples)
- **Licensing and Attributions**: [NOTICE](https://github.com/matijazezelj/oib/blob/main/NOTICE.md)

---

The Grafana Labs Marks are trademarks of Grafana Labs, and are used with Grafana Labs’ permission. We are not affiliated with, endorsed or sponsored by Grafana Labs or its affiliates.

*Questions or feedback? Find me on Reddit: [u/matijaz](https://reddit.com/u/matijaz). If you build something cool with OIB, I'd love to hear about it.*
