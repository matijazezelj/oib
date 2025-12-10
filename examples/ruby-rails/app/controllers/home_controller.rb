# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    Rails.logger.info "Home accessed"
    render json: { message: "Hello from OIB Example App!", status: "healthy" }
  end
end
