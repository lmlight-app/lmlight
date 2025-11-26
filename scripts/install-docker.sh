#!/bin/bash
# LM Light Docker Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/lmlight-app/lmlight/main/scripts/install-docker.sh | bash

set -e

REPO_URL="https://github.com/lmlight-app/lmlight"
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

# Download docker-compose.yml
info "Downloading docker-compose.yml..."
curl -fsSL "$REPO_URL/raw/main/docker-compose.yml" -o docker-compose.yml

# Download Dockerfiles
info "Downloading Dockerfiles..."
mkdir -p api-license web
curl -fsSL "$REPO_URL/raw/main/api-license/Dockerfile" -o api-license/Dockerfile
curl -fsSL "$REPO_URL/raw/main/web/Dockerfile" -o web/Dockerfile

# Create .env file
info "Creating .env file..."
cat > .env << 'EOF'
DATABASE_URL=postgresql://lmlight:lmlight@postgres:5432/lmlight
NEXTAUTH_SECRET=change-this-to-a-secure-random-string
NEXTAUTH_URL=http://localhost:3000
EOF

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
echo "  To start:"
echo "    cd $INSTALL_DIR && ./start.sh"
echo ""
echo "  To stop:"
echo "    cd $INSTALL_DIR && ./stop.sh"
echo ""
echo "  Note: Make sure Ollama is running before starting LM Light."
echo "        ollama serve"
echo ""
