#!/bin/bash
# LM Light Installer for Linux
set -e

BASE_URL="${LMLIGHT_BASE_URL:-https://github.com/lmlight-app/dist/releases/latest/download}"
INSTALL_DIR="${LMLIGHT_INSTALL_DIR:-$HOME/.local/lmlight}"
ARCH="$(uname -m)"
case "$ARCH" in x86_64|amd64) ARCH="amd64" ;; aarch64|arm64) ARCH="arm64" ;; esac

echo "Installing LM Light ($ARCH) to $INSTALL_DIR"

mkdir -p "$INSTALL_DIR"/{web,logs}

[ -f "$INSTALL_DIR/stop.sh" ] && "$INSTALL_DIR/stop.sh" 2>/dev/null || true

curl -fSL "$BASE_URL/lmlight-api-linux-$ARCH" -o "$INSTALL_DIR/api"
chmod +x "$INSTALL_DIR/api"

curl -fSL "$BASE_URL/lmlight-web.tar.gz" -o "/tmp/lmlight-web.tar.gz"
rm -rf "$INSTALL_DIR/web" && mkdir -p "$INSTALL_DIR/web"
tar -xzf "/tmp/lmlight-web.tar.gz" -C "$INSTALL_DIR/web"
rm -f /tmp/lmlight-web.tar.gz

[ ! -f "$INSTALL_DIR/.env" ] && cat > "$INSTALL_DIR/.env" << 'EOF'
# LM Light Configuration

# PostgreSQL
DATABASE_URL=postgresql://lmlight:lmlight@localhost:5432/lmlight

# Ollama
OLLAMA_BASE_URL=http://localhost:11434

# License
LICENSE_PATH=./license.lic

# NextAuth
NEXTAUTH_SECRET=randomsecret123
NEXTAUTH_URL=http://localhost:3000

# API
NEXT_PUBLIC_API_URL=http://localhost:8000
API_PORT=8000

# Web
WEB_PORT=3000
EOF

# Database setup
DB_USER="lmlight"
DB_PASS="lmlight"
DB_NAME="lmlight"

echo "Setting up database..."
if command -v psql &>/dev/null; then
    # Create user and database
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';" 2>/dev/null || true
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" 2>/dev/null || true
    sudo -u postgres psql -c "ALTER USER $DB_USER CREATEDB;" 2>/dev/null || true
    sudo -u postgres psql -d $DB_NAME -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>/dev/null || true

    # Run migrations
    PGPASSWORD=$DB_PASS psql -U $DB_USER -d $DB_NAME -h localhost << 'SQLEOF'
-- Enums
DO $$ BEGIN CREATE TYPE "UserRole" AS ENUM ('ADMIN', 'USER'); EXCEPTION WHEN duplicate_object THEN null; END $$;
DO $$ BEGIN CREATE TYPE "UserStatus" AS ENUM ('ACTIVE', 'INACTIVE'); EXCEPTION WHEN duplicate_object THEN null; END $$;
DO $$ BEGIN CREATE TYPE "MessageRole" AS ENUM ('USER', 'ASSISTANT', 'SYSTEM'); EXCEPTION WHEN duplicate_object THEN null; END $$;

-- Tables
CREATE TABLE IF NOT EXISTS "User" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "name" TEXT,
    "email" TEXT NOT NULL UNIQUE,
    "emailVerified" TIMESTAMP(3),
    "image" TEXT,
    "hashedPassword" TEXT,
    "role" "UserRole" NOT NULL DEFAULT 'USER',
    "status" "UserStatus" NOT NULL DEFAULT 'ACTIVE',
    "lastLoginAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS "Account" (
    "userId" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "provider" TEXT NOT NULL,
    "providerAccountId" TEXT NOT NULL,
    "refresh_token" TEXT,
    "access_token" TEXT,
    "expires_at" INTEGER,
    "token_type" TEXT,
    "scope" TEXT,
    "id_token" TEXT,
    "session_state" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY ("provider","providerAccountId")
);

CREATE TABLE IF NOT EXISTS "Session" (
    "sessionToken" TEXT NOT NULL PRIMARY KEY,
    "userId" TEXT NOT NULL,
    "expires" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS "Bot" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "userId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "systemPrompt" TEXT,
    "model" TEXT,
    "isPublic" BOOLEAN DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS "Tag" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "name" TEXT NOT NULL UNIQUE,
    "color" TEXT DEFAULT '#3B82F6',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS "_BotToTag" (
    "A" TEXT NOT NULL,
    "B" TEXT NOT NULL,
    PRIMARY KEY ("A", "B")
);

CREATE TABLE IF NOT EXISTS "Chat" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "userId" TEXT NOT NULL,
    "model" TEXT NOT NULL,
    "sessionId" TEXT NOT NULL,
    "botId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS "Message" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "chatId" TEXT NOT NULL,
    "role" "MessageRole" NOT NULL,
    "content" TEXT NOT NULL,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- pgvector schema
CREATE SCHEMA IF NOT EXISTS pgvector;
CREATE TABLE IF NOT EXISTS pgvector.embeddings (
    id SERIAL PRIMARY KEY,
    bot_id VARCHAR(255) NOT NULL,
    user_id VARCHAR(255) NOT NULL,
    document_id VARCHAR(255) NOT NULL,
    chunk_id INTEGER NOT NULL,
    content TEXT NOT NULL,
    embedding vector(768),
    metadata JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS "Bot_userId_idx" ON "Bot"("userId");
CREATE INDEX IF NOT EXISTS "Chat_userId_idx" ON "Chat"("userId");
CREATE INDEX IF NOT EXISTS "Message_chatId_createdAt_idx" ON "Message"("chatId", "createdAt");
CREATE INDEX IF NOT EXISTS idx_bot_user ON pgvector.embeddings (bot_id, user_id);
CREATE INDEX IF NOT EXISTS idx_document ON pgvector.embeddings (document_id);

-- Admin user (admin@local / admin123)
INSERT INTO "User" ("id", "email", "name", "hashedPassword", "role", "status", "updatedAt")
VALUES (
    'admin-user-id',
    'admin@local',
    'Admin',
    '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.V4ferGqaJe.rHe',
    'ADMIN',
    'ACTIVE',
    CURRENT_TIMESTAMP
) ON CONFLICT ("id") DO NOTHING;

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO lmlight;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO lmlight;
GRANT ALL PRIVILEGES ON SCHEMA pgvector TO lmlight;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA pgvector TO lmlight;
SQLEOF
    echo "✅ Database setup complete"
else
    echo "⚠️  psql not found. Please set up database manually."
fi

cat > "$INSTALL_DIR/start.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
[ -f .env ] && { set -a; source .env; set +a; }
command -v node &>/dev/null || { echo "❌ Node.js not found"; exit 1; }
pg_isready -q 2>/dev/null || { echo "❌ PostgreSQL not running"; exit 1; }
pgrep -x "ollama" >/dev/null || { echo "Starting Ollama..."; ollama serve >/dev/null 2>&1 & sleep 2; }
fuser -k ${API_PORT:-8000}/tcp 2>/dev/null || true
fuser -k ${WEB_PORT:-3000}/tcp 2>/dev/null || true
mkdir -p logs
ROOT="$(pwd)"
nohup ./api > logs/api.log 2>&1 & echo $! > logs/api.pid
cd web && nohup node server.js > "$ROOT/logs/web.log" 2>&1 & echo $! > "$ROOT/logs/web.pid"
echo "LM Light Started:"
echo "  API: http://localhost:${API_PORT:-8000}"
echo "  Web: http://localhost:${WEB_PORT:-3000}"
EOF
chmod +x "$INSTALL_DIR/start.sh"

cat > "$INSTALL_DIR/stop.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
[ -f .env ] && source .env
[ -f logs/web.pid ] && kill $(cat logs/web.pid) 2>/dev/null
[ -f logs/api.pid ] && kill $(cat logs/api.pid) 2>/dev/null
rm -f logs/*.pid
lsof -ti:${WEB_PORT:-3000},${API_PORT:-8000} 2>/dev/null | xargs kill -9 2>/dev/null || true
echo "Stopped"
EOF
chmod +x "$INSTALL_DIR/stop.sh"

echo "Done. Edit $INSTALL_DIR/.env then run: $INSTALL_DIR/start.sh"
