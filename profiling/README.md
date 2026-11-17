# Profiling Stack

Continuous profiling using Grafana Pyroscope.

## Components

| Service | Port | Description |
|---------|------|-------------|
| **Pyroscope** | 4040 (always `127.0.0.1`) | Continuous profiling storage and UI |

Container: `oib-pyroscope`. Volume: `oib-pyroscope-data`.

## Features

- **CPU Profiling** — See which functions consume the most CPU time
- **Memory Profiling** — Track allocations and identify memory leaks
- **Flame Graphs** — Visual representation of where time is spent
- **Trace-to-Profile** — Link traces in Tempo to profiles in Pyroscope
- **Multi-language** — Go, Python, Java, .NET, Ruby, Node.js, Rust

## Quick Start

```bash
# Install from repo root (requires core stacks first)
make install
make install-profiling

# install-profiling recommends restarting Grafana afterwards
make restart-grafana

# Check status
make status

# On a brand-new install the first profile takes about a minute to become
# queryable; after that, profiles show up within a second or two.

# Show the endpoints to configure in your app
make info-profiling

# View logs
make logs-profiling
```

Pyroscope is an optional stack, so the all-stack targets leave it alone:
- `make start`, `make stop`, `make restart`, `make update`, and `make uninstall` do not touch it. Use `start-profiling`, `stop-profiling`, `restart-profiling`, `update-profiling`, and `uninstall-profiling`. Run `make uninstall-profiling` before `make uninstall`, otherwise `oib-network` cannot be removed while Pyroscope is still attached.
- `make backup` includes `oib-pyroscope-data` when it exists; `make backup-pyroscope` / `make restore-pyroscope FILE=...` handle it alone.
- `make health` checks it only when it is installed; `make status` lists it as stopped when it is not running. `make latest` updates it only when it is installed.

## Limitations

- **Host-only port.** Pyroscope is published on `127.0.0.1:4040`, and there is no bind-address variable (unlike `OTEL_BIND_ADDR`). `make info-profiling` prints `http://<oib-host>:4040`, but that only works from the OIB host itself. Containers should join `oib-network` and use `http://oib-pyroscope:4040` (see [Docker Compose Integration](#docker-compose-integration)).
- **No Blackbox probe.** It is not probed by Prometheus, so no alert fires when it is down. Only `make health` and `make status` check it.
- **Credentials in the environment.** Like the core stacks, the container loads the whole root `.env` (`env_file`), so `GRAFANA_ADMIN_PASSWORD` and the other values are visible through `docker inspect oib-pyroscope`.
- **Only the demo app sends profiles.** `make demo-app` profiles `oib-demo-app` (set `PYROSCOPE_ENABLED=false` in `.env` to turn that off). The other examples in `examples/` have no Pyroscope SDK.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PYROSCOPE_PORT` | `4040` | Pyroscope UI/API port |
| `PYROSCOPE_VERSION` | `2.4.3` | Pyroscope image tag |

## Sending Profiles

### Python

```python
import pyroscope

pyroscope.configure(
    application_name="my-app",
    server_address="http://localhost:4040",
    tags={
        "env": "dev",
    }
)

# Profiles are automatically collected
```

**Install:** `pip install pyroscope-io`

### Node.js

```javascript
const Pyroscope = require('@pyroscope/nodejs');

Pyroscope.init({
  serverAddress: 'http://localhost:4040',
  appName: 'my-app',
  tags: {
    env: 'dev',
  },
});

Pyroscope.start();
```

**Install:** `npm install @pyroscope/nodejs`

### Go

```go
import "github.com/grafana/pyroscope-go"

pyroscope.Start(pyroscope.Config{
    ApplicationName: "my-app",
    ServerAddress:   "http://localhost:4040",
    Tags:            map[string]string{"env": "dev"},
})
```

### Java

```java
// Add agent to JVM args:
// -javaagent:pyroscope.jar
// -Dpyroscope.application.name=my-app
// -Dpyroscope.server.address=http://localhost:4040
```

### Ruby

```ruby
require 'pyroscope'

Pyroscope.configure do |config|
  config.application_name = "my-app"
  config.server_address = "http://localhost:4040"
  config.tags = { "env" => "dev" }
end
```

**Install:** `gem install pyroscope`

## Docker Compose Integration

```yaml
services:
  my-app:
    environment:
      - PYROSCOPE_SERVER_ADDRESS=http://oib-pyroscope:4040
      - PYROSCOPE_APPLICATION_NAME=my-app
    networks:
      - oib-network

networks:
  oib-network:
    external: true
```

Not every SDK reads these variables by itself; check your SDK's documentation. In the Python example above you pass `server_address` and `application_name` in code. `examples/demo-app/app.py` reads `PYROSCOPE_SERVER_ADDRESS` with `os.getenv` and passes it to `pyroscope.configure`.

## Viewing Profiles in Grafana

1. Open Grafana at http://localhost:3000
2. Go to **Explore** → Select **Pyroscope** datasource
3. Choose a profile type (cpu, memory, etc.)
4. Select your application
5. View flame graph

### Useful Queries

**CPU profile for an app:**
```
process_cpu:cpu:nanoseconds:cpu:nanoseconds{service_name="my-app"}
```

**Memory allocations:**
```
memory:alloc_objects:count:space:bytes{service_name="my-app"}
```

The **OIB - Profiles Explorer** dashboard shows the same data with integration notes.

## Trace-to-Profile Integration

The Tempo datasource is provisioned with a link to Pyroscope (`tracesToProfiles` in `grafana/provisioning/datasources/datasources.yml`). It matches the span's `service.name` to the profile label `service_name` and opens the `process_cpu` profile type. For the link to find anything:

1. Instrument the app with both OpenTelemetry (traces) and a Pyroscope SDK
2. Use the same name for `OTEL_SERVICE_NAME` and the Pyroscope application name (the demo app uses `oib-demo-app` for both)
3. View a trace in Tempo and open the profiles link on a span

Linking a profile to a single span (rather than to the service and time range) needs span-profile support in the SDK; see the Pyroscope documentation for your language. None of the examples here set that up.

## Troubleshooting

```bash
# Check if Pyroscope is ready
curl http://localhost:4040/ready

# View Pyroscope logs
make logs-profiling
```

To see which applications are sending profiles, open the Pyroscope UI at http://localhost:4040 or use Explore → Pyroscope in Grafana.

## Data Retention

`compose.yaml` runs Pyroscope with only the `server` argument and no retention settings, so Pyroscope's built-in defaults apply. Check the [Pyroscope configuration reference](https://grafana.com/docs/pyroscope/latest/configure-server/) for the retention options of the version you run (`PYROSCOPE_VERSION`, default `2.4.3`) and add them to the `command:` list. An unknown flag stops Pyroscope from starting, so check `make logs-profiling` after the change.
