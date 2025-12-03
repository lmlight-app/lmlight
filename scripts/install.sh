#!/bin/bash
# LM Light Installer (auto-detect OS)
# Usage: curl -fsSL https://raw.githubusercontent.com/lmlight-app/lmlight/main/scripts/install.sh | bash
set -e

BASE_URL="${LMLIGHT_BASE_URL:-https://github.com/lmlight-app/lmlight/releases/latest/download}"
INSTALL_DIR="${LMLIGHT_INSTALL_DIR:-$HOME/.local/lmlight}"

OS="$(uname -s)"
ARCH="$(uname -m)"
case "$ARCH" in x86_64|amd64) ARCH="amd64" ;; aarch64|arm64) ARCH="arm64" ;; esac
case "$OS" in Linux) OS="linux" ;; Darwin) OS="macos" ;; *) echo "Unsupported OS: $OS"; exit 1 ;; esac

echo "Installing LM Light ($OS-$ARCH) to $INSTALL_DIR"

mkdir -p "$INSTALL_DIR"/{web,logs}

[ -f "$INSTALL_DIR/stop.sh" ] && "$INSTALL_DIR/stop.sh" 2>/dev/null || true

# Download API binary (directly to INSTALL_DIR, not bin/)
curl -fSL "$BASE_URL/lmlight-api-$OS-$ARCH" -o "$INSTALL_DIR/api"
chmod +x "$INSTALL_DIR/api"

# Download Web
curl -fSL "$BASE_URL/lmlight-web.tar.gz" -o "/tmp/lmlight-web.tar.gz"
rm -rf "$INSTALL_DIR/web" && mkdir -p "$INSTALL_DIR/web"
tar -xzf "/tmp/lmlight-web.tar.gz" -C "$INSTALL_DIR/web"
rm -f /tmp/lmlight-web.tar.gz

# Create .env template only if not exists
[ ! -f "$INSTALL_DIR/.env" ] && cat > "$INSTALL_DIR/.env" << 'EOF'
# LM Light Configuration

# PostgreSQL
DATABASE_URL=postgresql://lmlight:lmlight@localhost:5432/lmlight

# Ollama
OLLAMA_BASE_URL=http://localhost:11434

# License
LICENSE_FILE_PATH=./license.lic

# NextAuth
NEXTAUTH_SECRET=randomsecret123
NEXTAUTH_URL=http://localhost:3000

# API
NEXT_PUBLIC_API_URL=http://localhost:8000
API_PORT=8000

# Web
WEB_PORT=3000
EOF

# start.sh
cat > "$INSTALL_DIR/start.sh" << 'STARTEOF'
#!/bin/bash
cd "$(dirname "$0")"

# Load .env
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

# Check requirements
command -v node &>/dev/null || { echo "Node.js not found"; exit 1; }
pg_isready -q 2>/dev/null || { echo "PostgreSQL not running"; exit 1; }

# Start Ollama if not running
pgrep -x "ollama" >/dev/null || { ollama serve >/dev/null 2>&1 & sleep 2; }

# Kill existing processes on ports
lsof -ti:${API_PORT:-8000} 2>/dev/null | xargs kill -9 2>/dev/null || true
lsof -ti:${WEB_PORT:-3000} 2>/dev/null | xargs kill -9 2>/dev/null || true

mkdir -p logs

# Run Prisma migrations (first run or updates)
if [ -f web/node_modules/.prisma/client/schema.prisma ]; then
    cd web
    npx prisma db push --skip-generate 2>/dev/null || true
    cd ..
fi

# Start API
ROOT="$(pwd)"
nohup ./api > logs/api.log 2>&1 & echo $! > logs/api.pid

# Start Web
cd web
nohup node server.js > "$ROOT/logs/web.log" 2>&1 & echo $! > "$ROOT/logs/web.pid"

echo "Started: http://localhost:${WEB_PORT:-3000}"
STARTEOF
chmod +x "$INSTALL_DIR/start.sh"

# stop.sh
cat > "$INSTALL_DIR/stop.sh" << 'STOPEOF'
#!/bin/bash
cd "$(dirname "$0")"

# Load .env for port numbers
[ -f .env ] && source .env

[ -f logs/web.pid ] && kill $(cat logs/web.pid) 2>/dev/null
[ -f logs/api.pid ] && kill $(cat logs/api.pid) 2>/dev/null
rm -f logs/*.pid

lsof -ti:${WEB_PORT:-3000},${API_PORT:-8000} 2>/dev/null | xargs kill -9 2>/dev/null || true
echo "Stopped"
STOPEOF
chmod +x "$INSTALL_DIR/stop.sh"

echo "Done. Edit $INSTALL_DIR/.env then run: $INSTALL_DIR/start.sh"
