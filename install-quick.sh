#!/bin/bash

# Quick installation script for Observability in a Box (OIB)
# This script simplifies the installation process for developers

set -e  # Exit on any error

echo "🔍 Checking system requirements..."

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    echo "   Visit https://docs.docker.com/get-docker/ for installation instructions."
    exit 1
fi

# Check if Docker Compose is available
if ! docker compose version >/dev/null 2>&1; then
    echo "❌ Docker Compose is not available. Please install Docker Compose."
    echo "   For Docker Desktop, it's included automatically."
    echo "   For standalone installation, see: https://docs.docker.com/compose/install/"
    exit 1
fi

# Check if Make is available
if ! command -v make &> /dev/null; then
    echo "❌ Make is not installed. Please install Make."
    exit 1
fi

echo "✅ All requirements satisfied"

# Read a variable from .env or fall back to default.
get_env_value() {
    local key="$1"
    local default_value="$2"
    local value=""

    if [ -f ".env" ]; then
        value="$(awk -F= -v k="$key" '$1==k {print $2}' .env | tail -n 1)"
    fi

    if [ -z "$value" ]; then
        value="$default_value"
    fi

    echo "$value"
}

# Set or update a variable in .env (uncommenting if needed).
set_env_value() {
    local key="$1"
    local value="$2"
    local tmp_file=""

    if grep -Eq "^[[:space:]]*#?[[:space:]]*${key}=" .env 2>/dev/null; then
        tmp_file="$(mktemp)"
        awk -v k="$key" -v v="$value" '
          BEGIN {updated=0}
          {
            if (!updated && $0 ~ "^[[:space:]]*#?[[:space:]]*"k"=") {
              print k"="v
              updated=1
            } else {
              print $0
            }
          }
        ' .env > "$tmp_file"
        mv "$tmp_file" .env
    else
        echo "${key}=${value}" >> .env
    fi
}

# Check if a port is already in use.
is_port_in_use() {
    local port="$1"

    if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
        return $?
    fi

    if command -v nc >/dev/null 2>&1; then
        nc -z 127.0.0.1 "${port}" >/dev/null 2>&1
        return $?
    fi

    return 1
}

find_next_available_port() {
    local port="$1"

    while is_port_in_use "$port"; do
        port=$((port + 1))
    done

    echo "$port"
}

# Check if .env file exists, if not create it from example
if [ ! -f ".env" ]; then
    echo "📋 Creating .env file from example..."
    cp .env.example .env
    echo "✅ .env file created"
fi

# Check user-facing ports and offer adjustments if needed.
port_keys=("GRAFANA_PORT" "PROMETHEUS_PORT" "ALLOY_LOGGING_PORT" "ALLOY_TELEMETRY_PORT")
port_defaults=("3000" "9090" "12345" "12346")
port_labels=("Grafana UI" "Prometheus UI" "Alloy Logging UI" "Alloy Telemetry UI")

if [ -t 0 ]; then
    for i in "${!port_keys[@]}"; do
        key="${port_keys[$i]}"
        default_port="${port_defaults[$i]}"
        label="${port_labels[$i]}"

        current_port="$(get_env_value "$key" "$default_port")"

        if is_port_in_use "$current_port"; then
            echo "⚠️  ${label} port ${current_port} is already in use."
            while true; do
                echo "Choose: [n] next available, [c] custom port"
                read -r choice
                case "$choice" in
                    n|N)
                        new_port="$(find_next_available_port "$current_port")"
                        echo "✅ Using ${label} port ${new_port}"
                        set_env_value "$key" "$new_port"
                        break
                        ;;
                    c|C)
                        echo "Enter a custom port for ${label}:"
                        read -r custom_port
                        if [ -z "$custom_port" ] || ! [[ "$custom_port" =~ ^[0-9]+$ ]]; then
                            echo "❌ Please enter a valid numeric port."
                            continue
                        fi
                        if is_port_in_use "$custom_port"; then
                            echo "❌ Port ${custom_port} is already in use."
                            continue
                        fi
                        echo "✅ Using ${label} port ${custom_port}"
                        set_env_value "$key" "$custom_port"
                        break
                        ;;
                    *)
                        echo "Please choose 'n' or 'c'."
                        ;;
                esac
            done
        fi
    done
else
    echo "ℹ️  Non-interactive shell detected; skipping port conflict prompts."
fi

# Generate a secure Grafana password if the default placeholder is present
generated_password=""
if grep -q "CHANGE_ME_TO_SECURE_PASSWORD" .env 2>/dev/null; then
    generated_password="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)"
    tmp_file="$(mktemp)"
    sed "s/CHANGE_ME_TO_SECURE_PASSWORD/${generated_password}/" .env > "$tmp_file"
    mv "$tmp_file" .env
    echo "✅ Generated Grafana admin password and saved it to .env"
fi

# Check if network exists, if not create it
echo "🔧 Setting up Docker network..."
if ! docker network inspect oib-network &> /dev/null; then
    docker network create oib-network
    echo "✅ Docker network 'oib-network' created"
else
    echo "✅ Docker network 'oib-network' already exists"
fi

# Install all components with a single command
echo "🚀 Installing all observability stacks..."
make install

echo ""
echo "🎉 Installation completed successfully!"
echo ""
echo "📊 Your observability stack is now ready:"
echo "   • Grafana: http://localhost:3000 (credentials in .env)"
echo "   • Logging: http://localhost:12345 (Alloy UI)"
echo "   • Metrics: http://localhost:9090 (Prometheus)"
echo "   • Telemetry: http://localhost:12346 (Alloy UI)"
if [ -n "$generated_password" ]; then
    echo ""
    echo "🔑 Grafana login:"
    echo "   • Username: admin"
    echo "   • Password: $generated_password"
fi
echo ""
echo "💡 Next steps:"
echo "   1. Check the integration guide with 'make info'"
echo "   2. Run example applications to test observability"
echo "   3. View dashboards in Grafana"
echo ""
echo "✨ Happy observability testing!"
