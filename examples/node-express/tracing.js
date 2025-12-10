/**
 * OpenTelemetry Tracing Setup
 * 
 * This file must be loaded BEFORE any other modules using:
 *   node --require ./tracing.js app.js
 * 
 * Or via NODE_OPTIONS environment variable:
 *   NODE_OPTIONS="--require ./tracing.js" node app.js
 */

const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { Resource } = require('@opentelemetry/resources');
const { SemanticResourceAttributes } = require('@opentelemetry/semantic-conventions');
const { diag, DiagConsoleLogger, DiagLogLevel } = require('@opentelemetry/api');
const grpc = require('@grpc/grpc-js');

// Enable OTEL diagnostics
diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.INFO);

const otelEndpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'localhost:4317';
console.log(`[tracing] OTEL Endpoint: ${otelEndpoint}`);
console.log(`[tracing] Service Name: ${process.env.OTEL_SERVICE_NAME || 'example-express-app'}`);

const sdk = new NodeSDK({
  resource: new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: process.env.OTEL_SERVICE_NAME || 'example-express-app',
  }),
  traceExporter: new OTLPTraceExporter({
    url: `http://${otelEndpoint}`,
    credentials: grpc.credentials.createInsecure(),
  }),
  instrumentations: [getNodeAutoInstrumentations({
    '@opentelemetry/instrumentation-fs': {
      enabled: false, // Disable fs instrumentation (too noisy)
    },
  })],
});

sdk.start();
console.log('[tracing] OTEL SDK started');

// Graceful shutdown
process.on('SIGTERM', () => {
  sdk.shutdown()
    .then(() => console.log('[tracing] OTEL SDK shut down'))
    .catch((err) => console.error('[tracing] Error shutting down OTEL SDK', err))
    .finally(() => process.exit(0));
});
