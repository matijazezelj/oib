/**
 * k6 Multi-Endpoint Load Test
 * 
 * Tests multiple endpoints with different HTTP methods.
 * Useful for API load testing.
 * 
 * Usage:
 *   docker compose --profile test run -e TARGET_URL=http://your-api:8080 k6 run /scripts/api-load.js
 */

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate, Counter, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const requestCount = new Counter('requests');
const latencyTrend = new Trend('latency', true);

export const options = {
  scenarios: {
    // Constant load scenario
    constant_load: {
      executor: 'constant-vus',
      vus: 10,
      duration: '2m',
    },
    // Spike test scenario (uncomment to enable)
    // spike_test: {
    //   executor: 'ramping-vus',
    //   startVUs: 0,
    //   stages: [
    //     { duration: '10s', target: 50 },
    //     { duration: '1m', target: 50 },
    //     { duration: '10s', target: 0 },
    //   ],
    //   startTime: '2m30s',
    // },
  },
  
  thresholds: {
    http_req_duration: ['p(95)<1000', 'p(99)<2000'],
    errors: ['rate<0.05'],
    http_req_failed: ['rate<0.05'],
  },
  
  tags: {
    testid: 'api-load-test',
  },
};

const BASE_URL = __ENV.TARGET_URL || 'http://oib-grafana:3000';

export default function () {
  // Group: Health checks
  group('health_checks', function () {
    const res = http.get(`${BASE_URL}/api/health`);
    check(res, { 'health OK': (r) => r.status === 200 });
    errorRate.add(res.status !== 200);
    requestCount.add(1);
    latencyTrend.add(res.timings.duration);
  });

  sleep(0.5);

  // Group: API endpoints (customize for your API)
  group('api_endpoints', function () {
    // GET request
    const getRes = http.get(`${BASE_URL}/api/health`);
    check(getRes, { 
      'GET status 200': (r) => r.status === 200,
      'GET duration < 500ms': (r) => r.timings.duration < 500,
    });
    errorRate.add(getRes.status !== 200);
    requestCount.add(1);
    latencyTrend.add(getRes.timings.duration);
  });

  sleep(1);
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
  };
}

// Text summary helper
function textSummary(data, options) {
  const { metrics } = data;
  let summary = '\n=== Test Summary ===\n';
  
  if (metrics.http_req_duration) {
    const duration = metrics.http_req_duration.values;
    summary += `\nHTTP Request Duration:\n`;
    summary += `  avg: ${duration.avg.toFixed(2)}ms\n`;
    summary += `  p95: ${duration['p(95)'].toFixed(2)}ms\n`;
    summary += `  p99: ${duration['p(99)'].toFixed(2)}ms\n`;
  }
  
  if (metrics.http_reqs) {
    summary += `\nTotal Requests: ${metrics.http_reqs.values.count}\n`;
    summary += `Requests/sec: ${metrics.http_reqs.values.rate.toFixed(2)}\n`;
  }
  
  if (metrics.errors) {
    summary += `\nError Rate: ${(metrics.errors.values.rate * 100).toFixed(2)}%\n`;
  }
  
  return summary;
}
