# frozen_string_literal: true

# OpenTelemetry Configuration
# This initializer sets up distributed tracing

require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"
require "opentelemetry/instrumentation/all"

otel_endpoint = ENV.fetch("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")

OpenTelemetry::SDK.configure do |c|
  c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "example-rails-app")

  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      OpenTelemetry::Exporter::OTLP::Exporter.new(
        endpoint: "#{otel_endpoint}/v1/traces"
      )
    )
  )

  # Auto-instrument Rails, Net::HTTP, etc.
  c.use_all
end

Rails.logger.info "[tracing] OpenTelemetry initialized with endpoint: #{otel_endpoint}"
