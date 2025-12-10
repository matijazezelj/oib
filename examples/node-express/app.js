/**
 * Example: Instrumented Node.js Express App
 * 
 * This example shows how to integrate a Node.js Express app with all OIB stacks:
 * - Logs -> Loki (via pino + stdout, collected by Alloy)
 * - Metrics -> Prometheus (via prom-client)
 * - Traces -> Tempo (via OpenTelemetry - loaded via tracing.js)
 * 
 * Tracing is initialized via: node --require ./tracing.js app.js
 * This ensures instrumentation loads before any other modules.
 */

const express = require('express');
const client = require('prom-client');
const pino = require('pino');

// ==================== Logging Setup ====================
const logger = pino({
  level: 'info',
  transport: {
    targets: [
      // Console output
      {
        target: 'pino-pretty',
        options: { colorize: true },
        level: 'info',
      },
      // Loki transport (optional - uncomment if using pino-loki)
      // {
      //   target: 'pino-loki',
      //   options: {
      //     host: 'http://localhost:3100',
      //     labels: { app: 'example-express-app' },
      //   },
      //   level: 'info',
      // },
    ],
  },
});

// ==================== Metrics Setup ====================
const register = new client.Registry();

// Add default metrics (CPU, memory, etc.)
client.collectDefaultMetrics({ register });

// Custom metrics
const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'path', 'status'],
  registers: [register],
});

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'path'],
  buckets: [0.1, 0.3, 0.5, 0.7, 1, 3, 5, 7, 10],
  registers: [register],
});

// ==================== Express App ====================
const app = express();
const PORT = process.env.PORT || 3000;

// Metrics middleware
app.use((req, res, next) => {
  const start = Date.now();
  
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    httpRequestsTotal.inc({ method: req.method, path: req.path, status: res.statusCode });
    httpRequestDuration.observe({ method: req.method, path: req.path }, duration);
  });
  
  next();
});

// Routes
app.get('/', (req, res) => {
  logger.info({ endpoint: '/' }, 'Home accessed');
  res.json({ message: 'Hello from OIB Example App!', status: 'healthy' });
});

app.get('/api/data', async (req, res) => {
  const delay = Math.random() * 500;
  await new Promise(resolve => setTimeout(resolve, delay));
  
  logger.info({ endpoint: '/api/data', delay_ms: delay.toFixed(2) }, 'Data processed');
  res.json({ data: [1, 2, 3, 4, 5], processed_in_ms: delay.toFixed(2) });
});

app.get('/api/error', (req, res) => {
  logger.error({ endpoint: '/api/error', error: 'Intentional error' }, 'Error triggered');
  res.status(500).json({ error: 'Something went wrong!' });
});

// Prometheus metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

// Start server
app.listen(PORT, () => {
  logger.info({ port: PORT }, 'App starting');
});
