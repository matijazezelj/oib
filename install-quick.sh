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
if ! command -v docker compose &> /dev/null; then
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

# Check if .env file exists, if not create it from example
if [ ! -f ".env" ]; then
    echo "📋 Creating .env file from example..."
    cp .env.example .env
    echo "✅ .env file created"
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
echo "   • Grafana: http://localhost:3000 (admin / admin)"
echo "   • Logging: http://localhost:12345 (Alloy UI)"
echo "   • Metrics: http://localhost:9090 (Prometheus)"
echo "   • Telemetry: http://localhost:12346 (Alloy UI)"
echo ""
echo "💡 Next steps:"
echo "   1. Check the integration guide with 'make info'"
echo "   2. Run example applications to test observability"
echo "   3. View dashboards in Grafana"
echo ""
echo "✨ Happy observability testing!"
