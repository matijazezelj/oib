# frozen_string_literal: true

require "prometheus/client/formats/text"

class MetricsController < ApplicationController
  # Skip metrics tracking for the metrics endpoint itself
  skip_around_action :track_metrics

  def show
    render plain: Prometheus::Client::Formats::Text.marshal(PROMETHEUS_REGISTRY),
           content_type: Prometheus::Client::Formats::Text::CONTENT_TYPE
  end
end
