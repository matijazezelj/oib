# frozen_string_literal: true

# Puma configuration for production
workers ENV.fetch("WEB_CONCURRENCY", 2).to_i
threads_count = ENV.fetch("RAILS_MAX_THREADS", 5).to_i
threads threads_count, threads_count

preload_app!

port ENV.fetch("PORT", 3000)
environment ENV.fetch("RAILS_ENV", "production")

# Allow puma to be restarted
plugin :tmp_restart
