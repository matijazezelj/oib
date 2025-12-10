# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_model/railtie"
require "action_controller/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

module ExampleRailsApp
  class Application < Rails::Application
    config.load_defaults 7.1

    # API-only mode
    config.api_only = true

    # Structured JSON logging via Lograge
    config.lograge.enabled = true
    config.lograge.formatter = Lograge::Formatters::Json.new
    config.lograge.custom_options = lambda do |event|
      {
        time: Time.now.iso8601,
        service: "example-rails-app",
        host: Socket.gethostname,
        request_id: event.payload[:request_id],
        trace_id: OpenTelemetry::Trace.current_span.context.hex_trace_id,
        span_id: OpenTelemetry::Trace.current_span.context.hex_span_id
      }
    end

    # Enable stdout logging for Docker
    config.logger = Logger.new($stdout)
    config.log_level = :info
  end
end
