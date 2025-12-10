FROM ruby:3.2-slim

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libyaml-dev \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Copy Gemfile first for layer caching
COPY Gemfile Gemfile.lock* ./
RUN bundle install --without development test

# Copy application code
COPY . .

# Precompile bootsnap cache
RUN bundle exec bootsnap precompile --gemfile app/ lib/

# Set ownership and switch to non-root user
RUN chown -R appuser:appuser /app
USER appuser

# Rails configuration
ENV RAILS_ENV=production
ENV RAILS_LOG_TO_STDOUT=true

EXPOSE 3000

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
