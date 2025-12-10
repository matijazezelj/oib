# frozen_string_literal: true

class ApiController < ApplicationController
  def data
    # Create a custom span for the processing work
    tracer = OpenTelemetry.tracer_provider.tracer("example-rails-app")
    
    tracer.in_span("process_data") do |span|
      # Simulate some work with random delay
      delay = rand(0.05..0.5)
      sleep(delay)
      
      span.set_attribute("delay_seconds", delay)
      Rails.logger.info "Data processed with delay: #{delay.round(3)}s"
      
      render json: { data: [1, 2, 3, 4, 5], processed_in: delay.round(3) }
    end
  end

  def error
    Rails.logger.error "Error triggered intentionally"
    render json: { error: "Something went wrong!" }, status: :internal_server_error
  end
end
