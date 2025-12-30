# 🔥 OIB Load Testing with k6

Load test your applications with [k6](https://k6.io/) and visualize the results in Grafana.

## Quick Start

```bash
# Run basic load test
make test-load

# Run stress test (find breaking point)
make test-stress

# Run spike test (sudden traffic)
make test-spike

# Run API load test
make test-api
```

## Available Test Scripts

| Script | Purpose | Duration | Max VUs |
|--------|---------|----------|---------|
| `basic-load.js` | Standard load pattern with stages | ~4 min | 20 |
| `stress-test.js` | Find system limits | ~13 min | 200 |
| `spike-test.js` | Sudden traffic spikes | ~5 min | 150 |
| `api-load.js` | Multi-endpoint API testing | ~2 min | 10 |

## Custom Tests

### Test a Custom Target

```bash
cd testing
docker compose --profile test run --rm \
  -e TARGET_URL=http://your-app:8080 \
  k6 run /scripts/basic-load.js
```

### Mount Your Own Script

```bash
docker compose --profile test run --rm \
  -v /path/to/your-script.js:/scripts/custom.js \
  k6 run /scripts/custom.js
```

### Run with More Options

```bash
# Run with 50 VUs for 2 minutes
docker compose --profile test run --rm \
  k6 run --vus 50 --duration 2m /scripts/basic-load.js

# Run with custom output
docker compose --profile test run --rm \
  k6 run --out json=output.json /scripts/basic-load.js
```

## Viewing Results

All k6 metrics are automatically sent to Prometheus and visible in Grafana:

1. Open Grafana at `http://localhost:3000`
2. Navigate to **Dashboards** → **OIB - Request Latency**
3. Look for the "k6 Load Test Metrics" section

### Key Metrics

- **Virtual Users (VUs)**: Active concurrent users
- **Request Rate**: Requests per second
- **Error Rate**: Percentage of failed requests
- **HTTP Request Duration**: Latency percentiles (p50, p90, p95, p99)
- **Timing Breakdown**: Blocked, Connecting, TLS, Sending, Waiting (TTFB), Receiving

## Writing k6 Scripts

### Basic Structure

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 10 },  // Ramp up
    { duration: '1m', target: 10 },   // Hold
    { duration: '30s', target: 0 },   // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.01'],
  },
};

const BASE_URL = __ENV.TARGET_URL || 'http://oib-grafana:3000';

export default function () {
  const res = http.get(`${BASE_URL}/api/health`);
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(1);
}
```

### Custom Metrics

```javascript
import { Rate, Counter, Trend } from 'k6/metrics';

const errorRate = new Rate('custom_errors');
const requestCount = new Counter('custom_requests');
const responseTime = new Trend('custom_response_time');

export default function () {
  const res = http.get('http://example.com');
  errorRate.add(res.status !== 200);
  requestCount.add(1);
  responseTime.add(res.timings.duration);
}
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TARGET_URL` | `http://oib-grafana:3000` | Target URL to test |
| `K6_VUS` | (from script) | Number of virtual users |
| `K6_DURATION` | (from script) | Test duration |

## Network

The k6 container runs on the `oib-network`, so you can test any container in the OIB stack using their Docker hostnames:

- `http://oib-grafana:3000`
- `http://oib-prometheus:9090`
- `http://oib-loki:3100`
- `http://oib-tempo:3200`

For example apps:
- `http://oib-example-python:5000`
- `http://oib-example-node:3000`
- `http://oib-example-ruby:3000`
- `http://oib-example-php:80`
