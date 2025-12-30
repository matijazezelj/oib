# Profiling Stack

Continuous profiling using Grafana Pyroscope.

## Components

| Service | Port | Description |
|---------|------|-------------|
| **Pyroscope** | 4040 (localhost) | Continuous profiling storage and UI |

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

# Check status
make status

# View logs
make logs-profiling
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PYROSCOPE_PORT` | `4040` | Pyroscope UI/API port |
| `PYROSCOPE_VERSION` | `1.7.1` | Pyroscope image tag |

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

## Trace-to-Profile Integration

When you instrument your app with both OpenTelemetry (traces) and Pyroscope (profiles), you can link them:

1. Add span links in your tracing
2. View a trace in Tempo
3. Click "Profiles" to see what code was running during that span

## Troubleshooting

```bash
# Check if Pyroscope is ready
curl http://localhost:4040/ready

# Check ingested applications
curl http://localhost:4040/api/apps

# View Pyroscope logs
docker logs oib-pyroscope
```

## Data Retention

Configure retention by adding to docker-compose command:
```yaml
command:
  - "server"
  - "-storage.retention-period=168h"  # 7 days
```
