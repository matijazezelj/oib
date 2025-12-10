# frozen_string_literal: true

# Development secret (production should use RAILS_MASTER_KEY or SECRET_KEY_BASE env var)
Rails.application.credentials.secret_key_base ||= ENV["SECRET_KEY_BASE"] || "dev_secret_key_base_only"
