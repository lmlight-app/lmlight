#!/bin/bash
# LM Light Docker Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/lmlight-app/dist/main/scripts/install-docker.sh | bash

set -e

INSTALL_DIR="${LMLIGHT_INSTALL_DIR:-$HOME/.local/lmlight}"

info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[1;32m[OK]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; exit 1; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }

echo ""
echo "============================================================"
echo "  LM Light Docker Installer"
echo "============================================================"
echo ""

# Check Docker
if ! command -v docker &>/dev/null; then
    error "Docker not found. Please install Docker first: https://docs.docker.com/get-docker/"
fi

if ! command -v docker compose &>/dev/null && ! command -v docker-compose &>/dev/null; then
    error "Docker Compose not found. Please install Docker Compose."
fi

success "Docker found: $(docker --version)"

# Check Ollama
if command -v ollama &>/dev/null; then
    success "Ollama found: $(ollama --version 2>/dev/null || echo 'installed')"
else
    warn "Ollama not found. Install from: https://ollama.com"
    warn "LM Light requires Ollama to run LLM models."
fi

# Create install directory
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Download and load Docker images
BASE_URL="${LMLIGHT_BASE_URL:-https://github.com/lmlight-app/dist/releases/latest/download}"

info "Downloading API image..."
curl -fsSL "$BASE_URL/lmlight-api-docker.tar.gz" | docker load

info "Downloading Web image..."
curl -fsSL "$BASE_URL/lmlight-web-docker.tar.gz" | docker load

# Create docker-compose.yml
info "Creating docker-compose.yml..."
cat > docker-compose.yml << 'COMPOSE'
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: lmlight
      POSTGRES_PASSWORD: lmlight
      POSTGRES_DB: lmlight
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U lmlight"]
      interval: 5s
      timeout: 5s
      retries: 5

  api:
    image: lmlight-api
    ports:
      - "${API_PORT:-8000}:8000"
    env_file: .env
    volumes:
      - ./license.lic:/app/license.lic:ro
    depends_on:
      postgres:
        condition: service_healthy

  web:
    image: lmlight-web
    ports:
      - "${WEB_PORT:-3000}:3000"
    env_file: .env
    depends_on:
      - api

volumes:
  pgdata:
COMPOSE

# Create .env file (only if not exists)
if [ ! -f .env ]; then
    info "Creating .env file..."
    cat > .env << 'EOF'
# LM Light Configuration (Docker)

# PostgreSQL (container)
DATABASE_URL=postgresql://lmlight:lmlight@postgres:5432/lmlight

# Ollama (host machine)
OLLAMA_BASE_URL=http://host.docker.internal:11434

# License
LICENSE_FILE_PATH=/app/license.lic

# NextAuth
NEXTAUTH_SECRET=randomsecret123
NEXTAUTH_URL=http://localhost:3000

# API
NEXT_PUBLIC_API_URL=http://localhost:8000
API_PORT=8000

# Web
WEB_PORT=3000
EOF
fi

# Create start script
cat > start.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "Starting LM Light..."

# Check if Ollama is running
if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "Warning: Ollama is not running. Start it with: ollama serve"
fi

docker compose up -d

echo ""
echo "LM Light is starting..."
echo "  Web UI: http://localhost:3000"
echo "  API:    http://localhost:8000"
echo ""
echo "To view logs: docker compose logs -f"
echo "To stop:      docker compose down"
EOF
chmod +x start.sh

# Create stop script
cat > stop.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
docker compose down
echo "LM Light stopped."
EOF
chmod +x stop.sh

echo ""
echo "============================================================"
success "LM Light Docker setup complete!"
echo "============================================================"
echo ""
echo "  Install location: $INSTALL_DIR"
echo ""
echo "  Next steps:"
echo "    1. Place license.lic in $INSTALL_DIR"
echo "    2. Start Ollama: ollama serve"
echo "    3. Start LM Light: $INSTALL_DIR/start.sh"
echo ""
echo "  Default login: admin@local / admin123"
echo ""
