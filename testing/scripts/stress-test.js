/**
 * k6 Stress Test
 * 
 * Finds the breaking point of your system by ramping up
 * virtual users beyond normal limits.
 * 
 * Usage:
 *   docker compose --profile test run -e TARGET_URL=http://your-app:8080 k6 run /scripts/stress-test.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Counter } from 'k6/metrics';

const errorRate = new Rate('errors');
const breakingPoint = new Counter('breaking_point_requests');

export const options = {
  stages: [
    // Warm up
    { duration: '1m', target: 10 },
    // Normal load
    { duration: '2m', target: 10 },
    // Stress - push limits
    { duration: '1m', target: 50 },
    { duration: '2m', target: 50 },
    // Extreme stress
    { duration: '1m', target: 100 },
    { duration: '2m', target: 100 },
    // Max stress
    { duration: '1m', target: 200 },
    { duration: '2m', target: 200 },
    // Recovery
    { duration: '2m', target: 0 },
  ],
  
  thresholds: {
    // During stress test, we expect some failures
    http_req_duration: ['p(95)<3000'],
    errors: ['rate<0.30'], // Allow up to 30% errors during stress
  },
  
  tags: {
    testid: 'stress-test',
  },
};

const BASE_URL = __ENV.TARGET_URL || 'http://oib-grafana:3000';

export default function () {
  const res = http.get(`${BASE_URL}/api/health`);
  
  const success = check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 2s': (r) => r.timings.duration < 2000,
  });
  
  if (!success) {
    errorRate.add(1);
    breakingPoint.add(1);
  } else {
    errorRate.add(0);
  }
  
  sleep(0.1); // Aggressive request rate
}

export function handleSummary(data) {
  const { metrics } = data;
  let summary = '\n🔥 STRESS TEST RESULTS 🔥\n';
  summary += '='.repeat(40) + '\n';
  
  if (metrics.http_reqs) {
    summary += `Total Requests: ${metrics.http_reqs.values.count}\n`;
    summary += `Max RPS: ${metrics.http_reqs.values.rate.toFixed(2)}\n`;
  }
  
  if (metrics.http_req_duration) {
    const d = metrics.http_req_duration.values;
    summary += `\nLatency:\n`;
    summary += `  avg: ${d.avg.toFixed(2)}ms\n`;
    summary += `  p95: ${d['p(95)'].toFixed(2)}ms\n`;
    summary += `  max: ${d.max.toFixed(2)}ms\n`;
  }
  
  if (metrics.errors) {
    summary += `\nError Rate: ${(metrics.errors.values.rate * 100).toFixed(2)}%\n`;
  }
  
  if (metrics.breaking_point_requests) {
    summary += `Failed Requests: ${metrics.breaking_point_requests.values.count}\n`;
  }
  
  return { stdout: summary };
}
