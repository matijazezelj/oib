/**
 * k6 Spike Test
 * 
 * Tests how your system handles sudden traffic spikes.
 * Simulates viral content or flash sales scenarios.
 * 
 * Usage:
 *   docker compose --profile test run -e TARGET_URL=http://your-app:8080 k6 run /scripts/spike-test.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const errorRate = new Rate('errors');

export const options = {
  stages: [
    // Baseline
    { duration: '30s', target: 5 },
    { duration: '1m', target: 5 },
    // SPIKE! 🚀
    { duration: '5s', target: 100 },
    { duration: '30s', target: 100 },
    // Spike ends
    { duration: '5s', target: 5 },
    { duration: '1m', target: 5 },
    // Second spike
    { duration: '5s', target: 150 },
    { duration: '30s', target: 150 },
    // Recovery
    { duration: '30s', target: 0 },
  ],
  
  thresholds: {
    http_req_duration: ['p(95)<2000'],
    errors: ['rate<0.20'], // Allow 20% errors during spikes
    http_req_failed: ['rate<0.20'],
  },
  
  tags: {
    testid: 'spike-test',
  },
};

const BASE_URL = __ENV.TARGET_URL || 'http://oib-grafana:3000';

export default function () {
  const res = http.get(`${BASE_URL}/api/health`, {
    tags: { name: 'health_check' },
  });
  
  const success = check(res, {
    'status 200': (r) => r.status === 200,
    'response time < 1s': (r) => r.timings.duration < 1000,
  });
  
  errorRate.add(!success);
  
  sleep(0.1);
}

export function handleSummary(data) {
  const { metrics } = data;
  let summary = '\n⚡ SPIKE TEST RESULTS ⚡\n';
  summary += '='.repeat(40) + '\n';
  
  if (metrics.http_reqs) {
    summary += `Total Requests: ${metrics.http_reqs.values.count}\n`;
    summary += `Peak RPS: ${metrics.http_reqs.values.rate.toFixed(2)}\n`;
  }
  
  if (metrics.http_req_duration) {
    const d = metrics.http_req_duration.values;
    summary += `\nLatency Under Spike:\n`;
    summary += `  avg: ${d.avg.toFixed(2)}ms\n`;
    summary += `  p95: ${d['p(95)'].toFixed(2)}ms\n`;
    summary += `  max: ${d.max.toFixed(2)}ms\n`;
  }
  
  if (metrics.errors) {
    const rate = metrics.errors.values.rate * 100;
    summary += `\nError Rate: ${rate.toFixed(2)}%`;
    if (rate < 5) summary += ' ✅ Excellent spike handling!';
    else if (rate < 20) summary += ' ⚠️  Acceptable degradation';
    else summary += ' ❌ System struggled with spikes';
    summary += '\n';
  }
  
  return { stdout: summary };
}
