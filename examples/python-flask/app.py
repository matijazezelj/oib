# Example: Instrumented Python Flask App
# 
# This example shows how to integrate a Python Flask app with all OIB stacks:
# - Logs -> Loki (via structlog + HTTP)
# - Metrics -> Prometheus (via prometheus_client)
# - Traces -> Tempo (via OpenTelemetry)
#
# Install dependencies:
#   pip install flask prometheus-client opentelemetry-api opentelemetry-sdk \
#               opentelemetry-exporter-otlp opentelemetry-instrumentation-flask \
#               structlog requests

import logging
import random
import time

from flask import Flask, jsonify
import structlog

# ==================== Metrics Setup ====================
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

REQUEST_COUNT = Counter('app_requests_total', 'Total requests', ['method', 'endpoint', 'status'])
REQUEST_LATENCY = Histogram('app_request_latency_seconds', 'Request latency', ['endpoint'])

# ==================== Tracing Setup ====================
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.sdk.resources import Resource

# Configure tracer
import os
otel_endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "localhost:4317")
resource = Resource.create({"service.name": os.environ.get("OTEL_SERVICE_NAME", "example-flask-app")})
provider = TracerProvider(resource=resource)
processor = BatchSpanProcessor(OTLPSpanExporter(
    endpoint=otel_endpoint,
    insecure=True
))
provider.add_span_processor(processor)
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)

# ==================== Logging Setup ====================
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.JSONRenderer()
    ],
    wrapper_class=structlog.stdlib.BoundLogger,
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger()

# ==================== Flask App ====================
app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)

@app.route('/')
def home():
    with REQUEST_LATENCY.labels(endpoint='/').time():
        logger.info("home_accessed", endpoint="/")
        REQUEST_COUNT.labels(method='GET', endpoint='/', status='200').inc()
        return jsonify({"message": "Hello from OIB Example App!", "status": "healthy"})

@app.route('/api/data')
def get_data():
    with REQUEST_LATENCY.labels(endpoint='/api/data').time():
        # Create a custom span
        with tracer.start_as_current_span("process_data") as span:
            # Simulate some work
            delay = random.uniform(0.1, 0.5)
            time.sleep(delay)
            
            span.set_attribute("delay_seconds", delay)
            logger.info("data_processed", endpoint="/api/data", delay=delay)
            
        REQUEST_COUNT.labels(method='GET', endpoint='/api/data', status='200').inc()
        return jsonify({"data": [1, 2, 3, 4, 5], "processed_in": delay})

@app.route('/api/error')
def trigger_error():
    logger.error("error_triggered", endpoint="/api/error", error="Intentional error")
    REQUEST_COUNT.labels(method='GET', endpoint='/api/error', status='500').inc()
    return jsonify({"error": "Something went wrong!"}), 500

@app.route('/metrics')
def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

@app.route('/health')
def health():
    return jsonify({"status": "healthy"})

if __name__ == '__main__':
    logger.info("app_starting", port=5000)
    app.run(host='0.0.0.0', port=5000, debug=True)
