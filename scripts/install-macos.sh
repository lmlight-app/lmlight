#!/bin/bash
# LM Light Installer for macOS
set -e

BASE_URL="${LMLIGHT_BASE_URL:-https://github.com/lmlight-app/dist/releases/latest/download}"
INSTALL_DIR="${LMLIGHT_INSTALL_DIR:-$HOME/.local/lmlight}"
ARCH="$(uname -m)"
case "$ARCH" in x86_64|amd64) ARCH="amd64" ;; aarch64|arm64) ARCH="arm64" ;; esac

echo "Installing LM Light ($ARCH) to $INSTALL_DIR"

mkdir -p "$INSTALL_DIR"/{web,logs}

[ -f "$INSTALL_DIR/stop.sh" ] && "$INSTALL_DIR/stop.sh" 2>/dev/null || true

curl -fSL "$BASE_URL/lmlight-api-macos-$ARCH" -o "$INSTALL_DIR/api"
chmod +x "$INSTALL_DIR/api"

curl -fSL "$BASE_URL/lmlight-web.tar.gz" -o "/tmp/lmlight-web.tar.gz"
rm -rf "$INSTALL_DIR/web" && mkdir -p "$INSTALL_DIR/web"
tar -xzf "/tmp/lmlight-web.tar.gz" -C "$INSTALL_DIR/web"
rm -f /tmp/lmlight-web.tar.gz

[ ! -f "$INSTALL_DIR/.env" ] && cat > "$INSTALL_DIR/.env" << EOF
# LM Light Configuration

# PostgreSQL
DATABASE_URL=postgresql://lmlight:lmlight@localhost:5432/lmlight

# Ollama
OLLAMA_BASE_URL=http://localhost:11434

# License (absolute path for Nuitka binary)
LICENSE_FILE_PATH=$INSTALL_DIR/license.lic

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
    psql -U postgres -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';" 2>/dev/null || true
    psql -U postgres -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" 2>/dev/null || true
    psql -U postgres -c "ALTER USER $DB_USER CREATEDB;" 2>/dev/null || true
    psql -U postgres -d $DB_NAME -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>/dev/null || true

    # Run migrations
    psql -U $DB_USER -d $DB_NAME << 'SQLEOF'
-- Enums
DO $$ BEGIN CREATE TYPE "UserRole" AS ENUM ('ADMIN', 'USER'); EXCEPTION WHEN duplicate_object THEN null; END $$;
DO $$ BEGIN CREATE TYPE "UserStatus" AS ENUM ('ACTIVE', 'INACTIVE'); EXCEPTION WHEN duplicate_object THEN null; END $$;
DO $$ BEGIN CREATE TYPE "MessageRole" AS ENUM ('USER', 'ASSISTANT', 'SYSTEM'); EXCEPTION WHEN duplicate_object THEN null; END $$;
DO $$ BEGIN CREATE TYPE "ShareType" AS ENUM ('PRIVATE', 'TAG'); EXCEPTION WHEN duplicate_object THEN null; END $$;

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

CREATE TABLE IF NOT EXISTS "UserSettings" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "userId" TEXT NOT NULL UNIQUE,
    "historyLimit" INTEGER NOT NULL DEFAULT 2,
    "temperature" DOUBLE PRECISION NOT NULL DEFAULT 0.7,
    "maxTokens" INTEGER NOT NULL DEFAULT 2048,
    "numCtx" INTEGER NOT NULL DEFAULT 8192,
    "topP" DOUBLE PRECISION NOT NULL DEFAULT 0.9,
    "topK" INTEGER NOT NULL DEFAULT 40,
    "repeatPenalty" DOUBLE PRECISION NOT NULL DEFAULT 1.1,
    "reasoningMode" TEXT NOT NULL DEFAULT 'normal',
    "ragTopK" INTEGER NOT NULL DEFAULT 5,
    "ragMinSimilarity" DOUBLE PRECISION NOT NULL DEFAULT 0.45,
    "embeddingModel" TEXT NOT NULL DEFAULT 'nomic-embed-text:latest',
    "chunkSize" INTEGER NOT NULL DEFAULT 600,
    "chunkOverlap" INTEGER NOT NULL DEFAULT 100,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS "Tag" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "name" TEXT NOT NULL UNIQUE,
    "description" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS "UserTag" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "userId" TEXT NOT NULL,
    "tagId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE ("userId", "tagId")
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
    "shareType" "ShareType" NOT NULL DEFAULT 'PRIVATE',
    "shareTagId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
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
CREATE INDEX IF NOT EXISTS "UserTag_userId_idx" ON "UserTag"("userId");
CREATE INDEX IF NOT EXISTS "UserTag_tagId_idx" ON "UserTag"("tagId");
CREATE INDEX IF NOT EXISTS "Bot_userId_idx" ON "Bot"("userId");
CREATE INDEX IF NOT EXISTS "Bot_shareTagId_idx" ON "Bot"("shareTagId");
CREATE INDEX IF NOT EXISTS "Chat_sessionId_idx" ON "Chat"("sessionId");
CREATE INDEX IF NOT EXISTS "Chat_userId_model_idx" ON "Chat"("userId", "model");
CREATE INDEX IF NOT EXISTS "Chat_userId_idx" ON "Chat"("userId");
CREATE INDEX IF NOT EXISTS "Chat_botId_idx" ON "Chat"("botId");
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
set -a; [ -f .env ] && source .env; set +a

# Check dependencies
command -v node &>/dev/null || { echo "❌ Node.js not found"; exit 1; }
pg_isready -q 2>/dev/null || { echo "❌ PostgreSQL not running"; exit 1; }
pgrep -x ollama >/dev/null || { ollama serve &>/dev/null & sleep 2; }

# Stop existing
pkill -f "lmlight.*api" 2>/dev/null; pkill -f "node.*server.js" 2>/dev/null; sleep 1

echo "🚀 Starting LM Light..."

# Start API
./api &
API_PID=$!

# Start Web
cd web && node server.js &
WEB_PID=$!

echo "✅ Started - API: http://localhost:${API_PORT:-8000} | Web: http://localhost:${WEB_PORT:-3000}"
echo "   Press Ctrl+C to stop"

trap "kill $API_PID $WEB_PID 2>/dev/null; echo 'Stopped'" EXIT
wait
EOF
chmod +x "$INSTALL_DIR/start.sh"

cat > "$INSTALL_DIR/stop.sh" << 'EOF'
#!/bin/bash
# Kill start.sh first (which will trigger its trap to kill API/Web)
pkill -f "lmlight/start\.sh" 2>/dev/null
sleep 1
# Clean up any remaining processes
pkill -f "\./api$" 2>/dev/null
pkill -f "lmlight/web.*server\.js" 2>/dev/null
echo "Stopped"
EOF
chmod +x "$INSTALL_DIR/stop.sh"

# Create .app bundles in /Applications
APP_DIR="/Applications/LM Light.app"
mkdir -p "$APP_DIR/Contents/MacOS"
cat > "$APP_DIR/Contents/MacOS/LM Light" << 'APPEOF'
#!/bin/bash
INSTALL_DIR="$HOME/.local/lmlight"
cd "$INSTALL_DIR"

# Load .env
set -a; [ -f .env ] && source .env; set +a

# Check if already running
if curl -s http://localhost:${API_PORT:-8000}/health >/dev/null 2>&1; then
    # Already running - ask to stop or open browser
    CHOICE=$(osascript -e 'button returned of (display dialog "LM Light is running." buttons {"Open Browser", "Stop", "Cancel"} default button "Open Browser")')
    case "$CHOICE" in
        "Open Browser")
            open "http://localhost:${WEB_PORT:-3000}"
            ;;
        "Stop")
            "$INSTALL_DIR/stop.sh"
            osascript -e 'display notification "LM Light stopped" with title "LM Light"'
            ;;
    esac
    exit 0
fi

# Not running - start services
"$INSTALL_DIR/start.sh" &

# Wait for API to be ready (max 30 sec)
for i in {1..30}; do
    if curl -s http://localhost:${API_PORT:-8000}/health >/dev/null 2>&1; then
        sleep 1
        open "http://localhost:${WEB_PORT:-3000}"
        osascript -e 'display notification "LM Light is running" with title "LM Light"'
        exit 0
    fi
    sleep 1
done

osascript -e 'display alert "LM Light" message "Failed to start. Check ~/.local/lmlight/logs/"'
APPEOF
chmod +x "$APP_DIR/Contents/MacOS/LM Light"
cat > "$APP_DIR/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>LM Light</string>
    <key>CFBundleName</key>
    <string>LM Light</string>
    <key>CFBundleIdentifier</key>
    <string>app.lmlight</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
</dict>
</plist>
EOF

echo "App created: /Applications/LM Light.app"

echo "Done. Edit $INSTALL_DIR/.env then run: $INSTALL_DIR/start.sh"
