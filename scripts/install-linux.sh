#!/bin/bash
# LM Light インストーラー for Linux (Ubuntu/Debian)
# 使い方: curl -fsSL https://raw.githubusercontent.com/lmlight-app/lmlight/main/scripts/install-linux.sh | bash

set -e

BASE_URL="${LMLIGHT_BASE_URL:-https://github.com/lmlight-app/lmlight/releases/latest/download}"
INSTALL_DIR="${LMLIGHT_INSTALL_DIR:-$HOME/.local/lmlight}"
ARCH="$(uname -m)"

# アーキテクチャ正規化
case "$ARCH" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
esac

# データベース設定
DB_USER="lmlight"
DB_PASSWORD="lmlight"
DB_NAME="lmlight"

# カラー定義
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${BLUE}[情報]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
error() { echo -e "${RED}[エラー]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[警告]${NC} $1"; }

echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║      LM Light インストーラー for Linux                ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""

info "アーキテクチャ: $ARCH"
info "インストール先: $INSTALL_DIR"

# root権限チェック
NEED_SUDO=""
if [ "$EUID" -ne 0 ]; then
    NEED_SUDO="sudo"
    warn "root権限なしで実行中。システム設定にはsudoを使用します。"
fi

# ディレクトリ作成
mkdir -p "$INSTALL_DIR"/{bin,frontend,data,logs,scripts}

# 既存インストールチェック
if [ -f "$INSTALL_DIR/bin/lmlight-api" ]; then
    info "既存のインストールを検出しました。アップデート中..."

    # 既存プロセス停止
    info "既存のプロセスを停止中..."
    [ -f "$INSTALL_DIR/logs/web.pid" ] && kill $(cat "$INSTALL_DIR/logs/web.pid") 2>/dev/null || true
    [ -f "$INSTALL_DIR/logs/api.pid" ] && kill $(cat "$INSTALL_DIR/logs/api.pid") 2>/dev/null || true
    lsof -ti:3000 | xargs kill -9 2>/dev/null || true
    lsof -ti:8000 | xargs kill -9 2>/dev/null || true
    sleep 1
    success "既存のプロセスを停止しました"
fi

# ============================================================
# ステップ 1: バイナリダウンロード
# ============================================================
info "ステップ 1/6: バイナリをダウンロード中..."

info "バックエンドをダウンロード中..."
BACKEND_FILE="lmlight-api-linux-$ARCH"
curl -fSL "$BASE_URL/$BACKEND_FILE" -o "$INSTALL_DIR/bin/lmlight-api"
chmod +x "$INSTALL_DIR/bin/lmlight-api"
success "バックエンドをダウンロードしました"

info "フロントエンドをダウンロード中..."
curl -fSL "$BASE_URL/lmlight-web.tar.gz" -o "/tmp/lmlight-web.tar.gz"
tar -xzf "/tmp/lmlight-web.tar.gz" -C "$INSTALL_DIR/frontend"
rm /tmp/lmlight-web.tar.gz
success "フロントエンドをダウンロードしました"

# ============================================================
# ステップ 2: システム依存関係インストール
# ============================================================
info "ステップ 2/6: システム依存関係をインストール中..."

$NEED_SUDO apt update -qq

# Node.js
if ! command -v node &>/dev/null; then
    info "Node.js をインストール中..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | $NEED_SUDO bash -
    $NEED_SUDO apt install -y nodejs > /dev/null 2>&1
fi
success "Node.js: $(node -v)"

# ============================================================
# ステップ 3: PostgreSQL セットアップ
# ============================================================
info "ステップ 3/6: PostgreSQL をセットアップ中..."

if ! command -v psql &>/dev/null; then
    info "PostgreSQL 16 をインストール中..."
    $NEED_SUDO sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | $NEED_SUDO apt-key add -
    $NEED_SUDO apt update -qq
    $NEED_SUDO apt install -y postgresql-16 postgresql-contrib-16 postgresql-16-pgvector > /dev/null 2>&1
    $NEED_SUDO systemctl start postgresql
    $NEED_SUDO systemctl enable postgresql > /dev/null 2>&1
fi
success "PostgreSQL をインストールしました"

# データベースとユーザー作成
info "データベースを作成中..."
$NEED_SUDO -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';" > /dev/null 2>&1 || true
$NEED_SUDO -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" > /dev/null 2>&1 || true
$NEED_SUDO -u postgres psql -c "ALTER USER $DB_USER CREATEDB;" > /dev/null 2>&1 || true
$NEED_SUDO -u postgres psql -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS vector;" > /dev/null 2>&1
success "データベースを作成しました: $DB_NAME"

# マイグレーション実行
info "データベースマイグレーションを実行中..."
$NEED_SUDO -u postgres psql -d "$DB_NAME" << 'SQLEOF'
-- 列挙型
DO $$ BEGIN
    CREATE TYPE "UserRole" AS ENUM ('ADMIN', 'USER');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE "UserStatus" AS ENUM ('ACTIVE', 'INACTIVE');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE "MessageRole" AS ENUM ('USER', 'ASSISTANT', 'SYSTEM');
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- テーブル
CREATE TABLE IF NOT EXISTS "User" (
    "id" TEXT NOT NULL,
    "name" TEXT,
    "email" TEXT NOT NULL,
    "emailVerified" TIMESTAMP(3),
    "image" TEXT,
    "password" TEXT,
    "role" "UserRole" NOT NULL DEFAULT 'USER',
    "status" "UserStatus" NOT NULL DEFAULT 'ACTIVE',
    "lastLoginAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
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
    CONSTRAINT "Account_pkey" PRIMARY KEY ("provider","providerAccountId")
);

CREATE TABLE IF NOT EXISTS "Session" (
    "sessionToken" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "expires" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS "VerificationToken" (
    "identifier" TEXT NOT NULL,
    "token" TEXT NOT NULL,
    "expires" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "VerificationToken_pkey" PRIMARY KEY ("identifier","token")
);

CREATE TABLE IF NOT EXISTS "Authenticator" (
    "credentialID" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "providerAccountId" TEXT NOT NULL,
    "credentialPublicKey" TEXT NOT NULL,
    "counter" INTEGER NOT NULL,
    "credentialDeviceType" TEXT NOT NULL,
    "credentialBackedUp" BOOLEAN NOT NULL,
    "transports" TEXT,
    CONSTRAINT "Authenticator_pkey" PRIMARY KEY ("userId","credentialID")
);

CREATE TABLE IF NOT EXISTS "Bot" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "Bot_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "Chat" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "model" TEXT NOT NULL,
    "sessionId" TEXT NOT NULL,
    "botId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "Chat_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "Message" (
    "id" TEXT NOT NULL,
    "chatId" TEXT NOT NULL,
    "role" "MessageRole" NOT NULL,
    "content" TEXT NOT NULL,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "Message_pkey" PRIMARY KEY ("id")
);

-- インデックス
CREATE UNIQUE INDEX IF NOT EXISTS "User_email_key" ON "User"("email");
CREATE UNIQUE INDEX IF NOT EXISTS "Session_sessionToken_key" ON "Session"("sessionToken");
CREATE UNIQUE INDEX IF NOT EXISTS "Authenticator_credentialID_key" ON "Authenticator"("credentialID");
CREATE INDEX IF NOT EXISTS "Bot_userId_idx" ON "Bot"("userId");
CREATE INDEX IF NOT EXISTS "Chat_sessionId_idx" ON "Chat"("sessionId");
CREATE INDEX IF NOT EXISTS "Chat_userId_model_idx" ON "Chat"("userId", "model");
CREATE INDEX IF NOT EXISTS "Chat_userId_idx" ON "Chat"("userId");
CREATE INDEX IF NOT EXISTS "Chat_botId_idx" ON "Chat"("botId");
CREATE INDEX IF NOT EXISTS "Message_chatId_createdAt_idx" ON "Message"("chatId", "createdAt");

-- 外部キー（存在する場合は無視）
DO $$ BEGIN
    ALTER TABLE "Account" ADD CONSTRAINT "Account_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE "Session" ADD CONSTRAINT "Session_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE "Authenticator" ADD CONSTRAINT "Authenticator_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE "Bot" ADD CONSTRAINT "Bot_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE "Chat" ADD CONSTRAINT "Chat_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE "Chat" ADD CONSTRAINT "Chat_botId_fkey" FOREIGN KEY ("botId") REFERENCES "Bot"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE "Message" ADD CONSTRAINT "Message_chatId_fkey" FOREIGN KEY ("chatId") REFERENCES "Chat"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- 管理者ユーザー (admin123)
INSERT INTO "User" ("id", "email", "name", "password", "role", "status", "updatedAt")
VALUES (
    'admin-user-id',
    'admin@localhost.local',
    'Admin',
    '$2b$12$km3AGocYrvN44g4bE6F1.ujXVXrLhSg0BIH1ccvjTHD5cEPATJGXi',
    'ADMIN',
    'ACTIVE',
    CURRENT_TIMESTAMP
) ON CONFLICT ("id") DO NOTHING;

-- 権限付与
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO lmlight;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO lmlight;
SQLEOF
success "データベースマイグレーションが完了しました"

# ============================================================
# ステップ 4: Ollama インストール
# ============================================================
info "ステップ 4/6: Ollama をインストール中..."

if ! command -v ollama &>/dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh > /dev/null 2>&1
fi
success "Ollama をインストールしました"

# Ollama が起動していない場合は起動
if ! pgrep -x "ollama" > /dev/null; then
    info "Ollama を起動中..."
    nohup ollama serve > /tmp/ollama.log 2>&1 &
    sleep 3
fi

# ============================================================
# ステップ 5: LLMモデルダウンロード
# ============================================================
info "ステップ 5/6: LLMモデルをダウンロード中..."

MODELS=("gemma3:4b" "nomic-embed-text")
for model in "${MODELS[@]}"; do
    if ollama list 2>/dev/null | grep -q "$model"; then
        success "$model はインストール済みです"
    else
        info "$model をダウンロード中..."
        ollama pull "$model"
        success "$model をダウンロードしました"
    fi
done

# ============================================================
# ステップ 6: 設定とスクリプト作成
# ============================================================
info "ステップ 6/6: 設定を作成中..."

# .env ファイル作成（プロジェクトルート）
cat > "$INSTALL_DIR/.env" << ENVEOF
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@localhost:5432/$DB_NAME
OLLAMA_BASE_URL=http://localhost:11434
NEXTAUTH_SECRET=$(openssl rand -base64 32)
NEXTAUTH_URL=http://localhost:3000
NEXT_PUBLIC_API_URL=http://localhost:8000
ENVEOF

# frontend/.env にもコピー
cp "$INSTALL_DIR/.env" "$INSTALL_DIR/frontend/.env"
success ".env ファイルを作成しました"

# 起動スクリプト作成
cat > "$INSTALL_DIR/scripts/start.sh" << 'EOF'
#!/bin/bash
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# .env 読み込み
if [ -f "$PROJECT_ROOT/.env" ]; then
    export $(cat "$PROJECT_ROOT/.env" | grep -v '^#' | xargs)
fi

echo -e "${BLUE}LM Light を起動中...${NC}"

# PostgreSQL チェック
if ! sudo systemctl is-active --quiet postgresql; then
    echo "PostgreSQL を起動中..."
    sudo systemctl start postgresql
fi

# Ollama チェック
if ! pgrep -x "ollama" > /dev/null; then
    echo "Ollama を起動中..."
    nohup ollama serve > /tmp/ollama.log 2>&1 &
    sleep 3
fi

# 既存プロセス終了
lsof -ti:8000 | xargs kill -9 2>/dev/null || true
lsof -ti:3000 | xargs kill -9 2>/dev/null || true
sleep 1

# API 起動
echo "API を起動中..."
cd "$PROJECT_ROOT"
nohup "$PROJECT_ROOT/bin/lmlight-api" > "$PROJECT_ROOT/logs/api.log" 2>&1 &
echo $! > "$PROJECT_ROOT/logs/api.pid"
sleep 3

# Web 起動
echo "Web を起動中..."
cd "$PROJECT_ROOT/frontend"
nohup node server.js > "$PROJECT_ROOT/logs/web.log" 2>&1 &
echo $! > "$PROJECT_ROOT/logs/web.pid"
sleep 3

echo ""
echo -e "${GREEN}LM Light が起動しました！${NC}"
echo ""
echo "  Web UI: http://localhost:3000"
echo "  API:    http://localhost:8000"
echo ""
echo "  ログイン: admin@localhost.local / admin123"
echo ""
echo "  ログ: tail -f $PROJECT_ROOT/logs/api.log"
echo "  停止: $PROJECT_ROOT/scripts/stop.sh"
echo ""
EOF
chmod +x "$INSTALL_DIR/scripts/start.sh"

# 停止スクリプト作成
cat > "$INSTALL_DIR/scripts/stop.sh" << 'EOF'
#!/bin/bash
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "LM Light を停止中..."

# PID で停止
[ -f "$PROJECT_ROOT/logs/web.pid" ] && kill $(cat "$PROJECT_ROOT/logs/web.pid") 2>/dev/null
[ -f "$PROJECT_ROOT/logs/api.pid" ] && kill $(cat "$PROJECT_ROOT/logs/api.pid") 2>/dev/null

rm -f "$PROJECT_ROOT/logs/"*.pid

# ポートから強制終了
lsof -ti:3000 | xargs kill -9 2>/dev/null || true
lsof -ti:8000 | xargs kill -9 2>/dev/null || true

echo -e "${GREEN}LM Light を停止しました${NC}"
EOF
chmod +x "$INSTALL_DIR/scripts/stop.sh"

# シンボリックリンク作成
ln -sf "$INSTALL_DIR/scripts/start.sh" "$INSTALL_DIR/start.sh"
ln -sf "$INSTALL_DIR/scripts/stop.sh" "$INSTALL_DIR/stop.sh"

# ============================================================
# デスクトップエントリ作成
# ============================================================
info "デスクトップショートカットを作成中..."

DESKTOP_DIR="$HOME/.local/share/applications"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/lmlight.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=LM Light
Comment=Lightweight LLM Management Tool
Exec=$INSTALL_DIR/start.sh
Icon=utilities-terminal
Terminal=false
Categories=Development;Utility;
StartupNotify=true
EOF

chmod +x "$DESKTOP_DIR/lmlight.desktop"
success "デスクトップショートカットを作成しました: ~/.local/share/applications/lmlight.desktop"

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     LM Light のインストールが完了しました！          ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}起動:${NC} $INSTALL_DIR/start.sh"
echo -e "${BLUE}停止:${NC} $INSTALL_DIR/stop.sh"
echo ""
echo -e "${BLUE}Web UI:${NC}   http://localhost:3000"
echo -e "${BLUE}ログイン:${NC} admin@localhost.local / admin123"
echo ""
echo "============================================================"
echo "  ライセンス設定"
echo "============================================================"
echo ""
echo "  ライセンスファイルを以下に配置してください:"
echo "    $INSTALL_DIR/license.lic"
echo ""
echo "  ライセンス購入: https://lmlight.app/buy"
echo ""
