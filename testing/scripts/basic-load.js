/**
 * k6 Basic Load Test Script
 * 
 * This script demonstrates basic load testing patterns.
 * Metrics are exported to Prometheus for visualization in Grafana.
 * 
 * Usage:
 *   cd testing
 *   docker compose --profile test run k6 run /scripts/basic-load.js
 *   
 *   Or with custom options:
 *   docker compose --profile test run k6 run --vus 20 --duration 2m /scripts/basic-load.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const requestDuration = new Trend('request_duration', true);

// Test configuration
export const options = {
  // Stages define the load pattern
  stages: [
    { duration: '30s', target: 10 },  // Ramp up to 10 users
    { duration: '1m', target: 10 },   // Stay at 10 users
    { duration: '30s', target: 20 },  // Ramp up to 20 users
    { duration: '1m', target: 20 },   // Stay at 20 users
    { duration: '30s', target: 0 },   // Ramp down to 0
  ],
  
  // Thresholds define pass/fail criteria
  thresholds: {
    http_req_duration: ['p(95)<500'],  // 95% of requests should be < 500ms
    errors: ['rate<0.1'],               // Error rate should be < 10%
  },
  
  // Tags for Prometheus metrics
  tags: {
    testid: 'basic-load-test',
  },
};

// Default target (change to your endpoint)
const BASE_URL = __ENV.TARGET_URL || 'http://oib-grafana:3000';

export default function () {
  // Test the health endpoint
  const healthRes = http.get(`${BASE_URL}/api/health`);
  
  check(healthRes, {
    'health status is 200': (r) => r.status === 200,
    'health response time < 200ms': (r) => r.timings.duration < 200,
  });
  
  errorRate.add(healthRes.status !== 200);
  requestDuration.add(healthRes.timings.duration);
  
  // Random sleep between requests (1-3 seconds)
  sleep(Math.random() * 2 + 1);
}

// Setup function - runs once before the test
export function setup() {
  console.log(`Starting load test against: ${BASE_URL}`);
  
  // Verify target is reachable
  const res = http.get(`${BASE_URL}/api/health`);
  if (res.status !== 200) {
    throw new Error(`Target ${BASE_URL} is not healthy. Status: ${res.status}`);
  }
  
  return { startTime: new Date().toISOString() };
}

// Teardown function - runs once after the test
export function teardown(data) {
  console.log(`Test started at: ${data.startTime}`);
  console.log(`Test completed at: ${new Date().toISOString()}`);
}
