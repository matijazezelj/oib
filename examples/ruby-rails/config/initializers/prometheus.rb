# frozen_string_literal: true

# Prometheus Metrics Configuration

require "prometheus/client"

# Create a global registry
PROMETHEUS_REGISTRY = Prometheus::Client.registry

# Custom metrics
HTTP_REQUESTS_TOTAL = PROMETHEUS_REGISTRY.counter(
  :http_requests_total,
  docstring: "Total number of HTTP requests",
  labels: [:method, :path, :status]
)

HTTP_REQUEST_DURATION = PROMETHEUS_REGISTRY.histogram(
  :http_request_duration_seconds,
  docstring: "Duration of HTTP requests in seconds",
  labels: [:method, :path],
  buckets: [0.1, 0.3, 0.5, 0.7, 1, 3, 5, 7, 10]
)

Rails.logger.info "[metrics] Prometheus metrics initialized"
