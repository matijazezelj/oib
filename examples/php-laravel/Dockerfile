FROM php:8.2-cli

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    unzip \
    libzip-dev \
    && docker-php-ext-install zip \
    && rm -rf /var/lib/apt/lists/*

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Create non-root user
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Copy composer files first for layer caching
COPY composer.json ./
RUN composer install --no-dev --no-scripts --no-autoloader

# Copy application code
COPY . .

# Generate autoloader
RUN composer dump-autoload --optimize

# Set ownership and switch to non-root user
RUN chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

CMD ["php", "-S", "0.0.0.0:8000", "-t", "public", "public/index.php"]
