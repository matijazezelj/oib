# 🔥 OIB Load Testing with k6

Load test your applications with [k6](https://k6.io/) and visualize the results in Grafana.

For the backup/restore and upgrade acceptance tests (`make test-backup`, `make test-upgrade`), see [acceptance/README.md](acceptance/README.md).

## Quick Start

Needs the metrics stack running (`make install` or `make install-metrics`): k6 remote-writes its results to `http://oib-prometheus:9090/api/v1/write`. The make targets create `oib-network` if it is missing, run k6 in a throwaway `oib-k6` container (`--rm`), and all target Grafana (`http://oib-grafana:3000`) unless the script is pointed elsewhere.

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
| `basic-load.js` | Standard load pattern with stages | ~3.5 min | 20 |
| `stress-test.js` | Find system limits | ~14 min | 200 |
| `spike-test.js` | Sudden traffic spikes | ~4 min | 150 |
| `api-load.js` | Multi-endpoint API testing | ~2 min | 10 |

The make targets map to scripts as follows: `test-load` → `basic-load.js`, `test-stress` → `stress-test.js`, `test-spike` → `spike-test.js`, `test-api` → `api-load.js`. Scripts live in `testing/scripts/`, mounted read-only at `/scripts`.

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
  -v /path/to/your-script.js:/custom.js:ro \
  k6 run /custom.js
```

Mount it outside `/scripts`: that directory is already a read-only bind mount of `testing/scripts/`. Or simply copy the script into `testing/scripts/`.

### Run with More Options

```bash
# Run with 50 VUs for 2 minutes
docker compose --profile test run --rm \
  k6 run --vus 50 --duration 2m /scripts/basic-load.js

# Write raw results to a JSON file on the host
mkdir -p results
docker compose --profile test run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$PWD/results:/results" \
  k6 run --out json=/results/output.json /scripts/basic-load.js
```

The container is removed after the run (`--rm`), so files written inside it are lost unless they go to a mounted directory as above. Whether `--out` on the command line replaces or adds to `K6_OUT` from `compose.yaml` (the Prometheus output) was not checked; if the Grafana panels stay empty, pass both: `--out experimental-prometheus-rw --out json=/results/output.json`.

## Viewing Results

All k6 metrics are automatically sent to Prometheus and visible in Grafana:

1. Open Grafana at `http://localhost:3000`
2. Navigate to **Dashboards** → **OIB - Request Latency**
3. Look for the "k6 Load Test Metrics" section

### Key Metrics

- **Virtual Users (VUs)**: Active concurrent users
- **Request Rate**: Requests per second
- **Error Rate**: Percentage of failed requests
- **HTTP Request Duration**: p99 latency (k6's Prometheus remote-write output only exports `p(99)` for trends unless `K6_PROMETHEUS_RW_TREND_STATS` is set)
- **Timing Breakdown**: Blocked, Connecting, TLS, Sending, Waiting (TTFB), Receiving (p99)

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
import http from 'k6/http';
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
| `TARGET_URL` | `http://oib-grafana:3000` | Target URL to test (read by all four scripts) |
| `K6_VUS` | (from script) | Number of virtual users |
| `K6_DURATION` | (from script) | Test duration |

Pass these with `-e` on `docker compose ... run` (as in [Test a Custom Target](#test-a-custom-target)). The root `.env` is not forwarded into the k6 container, and the make targets do not accept them.

Set in `compose.yaml` (k6 image `grafana/k6:2.4.0`):

| Variable | Value |
|----------|-------|
| `K6_OUT` | `experimental-prometheus-rw` |
| `K6_PROMETHEUS_RW_SERVER_URL` | `http://oib-prometheus:9090/api/v1/write` |
| `K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM` | `false` |
| `K6_PROMETHEUS_RW_STALE_MARKERS` | `true` |

## Network

The k6 container runs on the `oib-network`, so you can test any container in the OIB stack using their Docker hostnames:

- `http://oib-grafana:3000`
- `http://oib-prometheus:9090`
- `http://oib-loki:3100`
- `http://oib-tempo:3200`

For example apps:
- `http://example-flask-app:5000`
- `http://example-express-app:3000`
- `http://example-ruby-rails:3000`
- `http://example-php-laravel:8000`
- `http://oib-demo-app:5000`
