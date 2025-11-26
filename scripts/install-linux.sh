#!/bin/bash
# LM Light Installer for Linux
# Usage: curl -fsSL https://raw.githubusercontent.com/lmlight-app/lmlight/main/scripts/install-linux.sh | bash

set -e

BASE_URL="${LMLIGHT_BASE_URL:-https://github.com/lmlight-app/lmlight/releases/latest/download}"
INSTALL_DIR="${LMLIGHT_INSTALL_DIR:-$HOME/.local/lmlight}"
ARCH="$(uname -m)"

# Normalize arch
case "$ARCH" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
esac

info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[1;32m[OK]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; exit 1; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }

echo ""
echo "============================================================"
echo "  LM Light Installer for Linux"
echo "============================================================"
echo ""

info "Architecture: $ARCH"
info "Install directory: $INSTALL_DIR"

# Create directories
mkdir -p "$INSTALL_DIR"/{bin,frontend,data}

# Download backend
info "Downloading backend..."
BACKEND_FILE="lmlight-api-linux-$ARCH"
curl -fSL "$BASE_URL/$BACKEND_FILE" -o "$INSTALL_DIR/bin/lmlight-api"
chmod +x "$INSTALL_DIR/bin/lmlight-api"
success "Backend downloaded"

# Download frontend
info "Downloading frontend..."
curl -fSL "$BASE_URL/lmlight-web.tar.gz" -o "/tmp/lmlight-web.tar.gz"
tar -xzf "/tmp/lmlight-web.tar.gz" -C "$INSTALL_DIR/frontend"
rm /tmp/lmlight-web.tar.gz
success "Frontend downloaded"

# Check dependencies
MISSING_DEPS=()

if command -v node &>/dev/null; then
    success "Node.js found: $(node -v)"
else
    warn "Node.js not found"
    MISSING_DEPS+=("nodejs")
fi

if command -v ollama &>/dev/null; then
    success "Ollama found"
else
    warn "Ollama not found"
    MISSING_DEPS+=("ollama")
fi

if command -v psql &>/dev/null; then
    success "PostgreSQL found"
else
    warn "PostgreSQL not found"
    MISSING_DEPS+=("postgresql")
fi

# Create launcher scripts
cat > "$INSTALL_DIR/start-api.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")/bin"
./lmlight-api
EOF
chmod +x "$INSTALL_DIR/start-api.sh"

cat > "$INSTALL_DIR/start-web.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")/frontend"
PORT=${PORT:-3000} node server.js
EOF
chmod +x "$INSTALL_DIR/start-web.sh"

cat > "$INSTALL_DIR/start.sh" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "Starting LM Light..."
"$SCRIPT_DIR/start-api.sh" &
sleep 3
"$SCRIPT_DIR/start-web.sh" &
echo ""
echo "LM Light is running!"
echo "  API: http://localhost:8000"
echo "  Web: http://localhost:3000"
echo ""
echo "Press Ctrl+C to stop"
trap "kill 0" EXIT
wait
EOF
chmod +x "$INSTALL_DIR/start.sh"

echo ""
echo "============================================================"
success "LM Light installed successfully!"
echo "============================================================"
echo ""

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    warn "Missing dependencies: ${MISSING_DEPS[*]}"
    echo ""
    echo "  Install on Ubuntu/Debian:"
    echo "    sudo apt install nodejs postgresql"
    echo "    curl -fsSL https://ollama.com/install.sh | sh"
    echo ""
fi

echo "  To start: $INSTALL_DIR/start.sh"
echo ""
