# frozen_string_literal: true

class HealthController < ApplicationController
  # Skip metrics tracking for health checks
  skip_around_action :track_metrics

  def show
    render json: { status: "healthy", service: "example-rails-app" }
  end
end
