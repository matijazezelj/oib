# frozen_string_literal: true

class ApplicationController < ActionController::API
  around_action :track_metrics

  private

  def track_metrics
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
  ensure
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    HTTP_REQUESTS_TOTAL.increment(
      labels: { method: request.method, path: request.path, status: response.status }
    )
    HTTP_REQUEST_DURATION.observe(
      duration,
      labels: { method: request.method, path: request.path }
    )
  end
end
