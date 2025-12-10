# frozen_string_literal: true

Rails.application.routes.draw do
  root "home#index"

  get "/api/data", to: "api#data"
  get "/api/error", to: "api#error"
  get "/health", to: "health#show"
  get "/metrics", to: "metrics#show"
end
