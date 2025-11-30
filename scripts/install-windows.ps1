# LM Light インストーラー for Windows
# 使い方: irm https://raw.githubusercontent.com/lmlight-app/dist/main/scripts/install-windows.ps1 | iex

$ErrorActionPreference = "Stop"

# 設定
$BASE_URL = if ($env:LMLIGHT_BASE_URL) { $env:LMLIGHT_BASE_URL } else { "https://github.com/lmlight-app/dist/releases/latest/download" }
$INSTALL_DIR = if ($env:LMLIGHT_INSTALL_DIR) { $env:LMLIGHT_INSTALL_DIR } else { "$env:LOCALAPPDATA\lmlight" }
$ARCH = "amd64"  # Windows は x64 のみサポート

# データベース設定
$DB_USER = "lmlight"
$DB_PASSWORD = "lmlight"
$DB_NAME = "lmlight"

# カラー定義（PowerShell）
function Write-Info { param($msg) Write-Host "[情報] $msg" -ForegroundColor Blue }
function Write-Success { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Error { param($msg) Write-Host "[エラー] $msg" -ForegroundColor Red; exit 1 }
function Write-Warn { param($msg) Write-Host "[警告] $msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════╗" -ForegroundColor Blue
Write-Host "║      LM Light インストーラー for Windows             ║" -ForegroundColor Blue
Write-Host "╚═══════════════════════════════════════════════════════╝" -ForegroundColor Blue
Write-Host ""

Write-Info "アーキテクチャ: $ARCH"
Write-Info "インストール先: $INSTALL_DIR"

# 管理者権限チェック
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warn "管理者権限で実行していません。一部の機能が制限される場合があります。"
}

# ディレクトリ作成
New-Item -ItemType Directory -Force -Path "$INSTALL_DIR\bin" | Out-Null
New-Item -ItemType Directory -Force -Path "$INSTALL_DIR\frontend" | Out-Null
New-Item -ItemType Directory -Force -Path "$INSTALL_DIR\data" | Out-Null
New-Item -ItemType Directory -Force -Path "$INSTALL_DIR\logs" | Out-Null
New-Item -ItemType Directory -Force -Path "$INSTALL_DIR\scripts" | Out-Null

# 既存インストールチェック
if (Test-Path "$INSTALL_DIR\bin\lmlight-api.exe") {
    Write-Info "既存のインストールを検出しました。アップデート中..."

    # 既存プロセス停止
    Write-Info "既存のプロセスを停止中..."
    Get-Process -Name "lmlight-api" -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "*lmlight*" } | Stop-Process -Force
    Start-Sleep -Seconds 1
    Write-Success "既存のプロセスを停止しました"
}

# ============================================================
# ステップ 1: バイナリダウンロード
# ============================================================
Write-Info "ステップ 1/5: バイナリをダウンロード中..."

Write-Info "バックエンドをダウンロード中..."
$BACKEND_FILE = "lmlight-api-windows-$ARCH.exe"
Invoke-WebRequest -Uri "$BASE_URL/$BACKEND_FILE" -OutFile "$INSTALL_DIR\bin\lmlight-api.exe" -UseBasicParsing
Write-Success "バックエンドをダウンロードしました"

Write-Info "フロントエンドをダウンロード中..."
$TEMP_TAR = "$env:TEMP\lmlight-web.tar.gz"
Invoke-WebRequest -Uri "$BASE_URL/lmlight-web.tar.gz" -OutFile $TEMP_TAR -UseBasicParsing

# tar展開（Windows 10 1803+）
$WORK_DIR = "$env:TEMP\lmlight-web-$PID"
New-Item -ItemType Directory -Force -Path $WORK_DIR | Out-Null
tar -xzf $TEMP_TAR -C $WORK_DIR

# frontendディレクトリを置き換え
if (Test-Path "$INSTALL_DIR\frontend") {
    Remove-Item -Recurse -Force "$INSTALL_DIR\frontend"
}
Move-Item -Path $WORK_DIR -Destination "$INSTALL_DIR\frontend"
Remove-Item -Force $TEMP_TAR

Write-Success "フロントエンドをダウンロードしました"

# ============================================================
# ステップ 2: 依存関係チェック
# ============================================================
Write-Info "ステップ 2/5: 依存関係をチェック中..."

$MISSING_DEPS = @()

# Node.js チェック
if (Get-Command node -ErrorAction SilentlyContinue) {
    Write-Success "Node.js: $(node --version)"
} else {
    Write-Warn "Node.js が見つかりません"
    $MISSING_DEPS += "nodejs"
}

# PostgreSQL チェック
if (Get-Command psql -ErrorAction SilentlyContinue) {
    Write-Success "PostgreSQL が見つかりました"
} else {
    Write-Warn "PostgreSQL が見つかりません"
    $MISSING_DEPS += "postgresql"
}

# Ollama チェック
if (Get-Command ollama -ErrorAction SilentlyContinue) {
    Write-Success "Ollama が見つかりました"
} else {
    Write-Warn "Ollama が見つかりません"
    $MISSING_DEPS += "ollama"
}

# Tesseract OCR チェック (オプション: 画像OCR用)
if (Get-Command tesseract -ErrorAction SilentlyContinue) {
    Write-Success "Tesseract OCR が見つかりました (画像OCR用)"
} else {
    Write-Warn "Tesseract OCR が見つかりません (オプション: 画像OCR用)"
    $MISSING_DEPS += "tesseract"
}

# winget で依存関係をインストール（オプション）
if ($MISSING_DEPS.Count -gt 0 -and $isAdmin) {
    Write-Info "不足している依存関係を自動インストールしますか？ (Y/n)"
    $response = Read-Host
    if ($response -eq "" -or $response -eq "Y" -or $response -eq "y") {
        foreach ($dep in $MISSING_DEPS) {
            switch ($dep) {
                "nodejs" {
                    Write-Info "Node.js をインストール中..."
                    winget install -e --id OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements
                }
                "postgresql" {
                    Write-Info "PostgreSQL をインストール中..."
                    winget install -e --id PostgreSQL.PostgreSQL --silent --accept-package-agreements --accept-source-agreements
                }
                "ollama" {
                    Write-Info "Ollama をインストール中..."
                    winget install -e --id Ollama.Ollama --silent --accept-package-agreements --accept-source-agreements
                }
                "tesseract" {
                    Write-Info "Tesseract OCR をインストール中..."
                    Write-Warn "Tesseract は手動インストールが必要です: https://github.com/UB-Mannheim/tesseract/wiki"
                }
            }
        }
    }
}

# ============================================================
# ステップ 3: PostgreSQL セットアップ
# ============================================================
Write-Info "ステップ 3/5: PostgreSQL をセットアップ中..."

if (Get-Command psql -ErrorAction SilentlyContinue) {
    Write-Info "データベースを作成中..."

    # PostgreSQL サービス起動
    $pgService = Get-Service -Name "postgresql*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pgService -and $pgService.Status -ne "Running") {
        Start-Service $pgService.Name
        Start-Sleep -Seconds 3
    }

    # データベースとユーザー作成
    $env:PGPASSWORD = "postgres"
    psql -U postgres -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';" 2>$null
    psql -U postgres -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" 2>$null
    psql -U postgres -c "ALTER USER $DB_USER CREATEDB;" 2>$null

    # pgvector拡張
    psql -U postgres -d $DB_NAME -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>$null

    # マイグレーション実行
    Write-Info "データベースマイグレーションを実行中..."

    $SQL_MIGRATION = @"
-- 列挙型
DO `$`$ BEGIN
    CREATE TYPE "UserRole" AS ENUM ('ADMIN', 'USER');
EXCEPTION WHEN duplicate_object THEN null; END `$`$;

DO `$`$ BEGIN
    CREATE TYPE "UserStatus" AS ENUM ('ACTIVE', 'INACTIVE');
EXCEPTION WHEN duplicate_object THEN null; END `$`$;

DO `$`$ BEGIN
    CREATE TYPE "MessageRole" AS ENUM ('USER', 'ASSISTANT', 'SYSTEM');
EXCEPTION WHEN duplicate_object THEN null; END `$`$;

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
CREATE INDEX IF NOT EXISTS "Bot_userId_idx" ON "Bot"("userId");
CREATE INDEX IF NOT EXISTS "Chat_userId_idx" ON "Chat"("userId");
CREATE INDEX IF NOT EXISTS "Message_chatId_createdAt_idx" ON "Message"("chatId", "createdAt");

-- 外部キー
DO `$`$ BEGIN
    ALTER TABLE "Bot" ADD CONSTRAINT "Bot_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END `$`$;

DO `$`$ BEGIN
    ALTER TABLE "Chat" ADD CONSTRAINT "Chat_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END `$`$;

DO `$`$ BEGIN
    ALTER TABLE "Message" ADD CONSTRAINT "Message_chatId_fkey" FOREIGN KEY ("chatId") REFERENCES "Chat"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END `$`$;

-- 管理者ユーザー (admin123)
INSERT INTO "User" ("id", "email", "name", "password", "role", "status", "updatedAt")
VALUES (
    'admin-user-id',
    'admin@localhost.local',
    'Admin',
    '`$2b`$12`$km3AGocYrvN44g4bE6F1.ujXVXrLhSg0BIH1ccvjTHD5cEPATJGXi',
    'ADMIN',
    'ACTIVE',
    CURRENT_TIMESTAMP
) ON CONFLICT ("id") DO NOTHING;

-- 権限付与
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;
"@

    $SQL_MIGRATION | psql -U postgres -d $DB_NAME 2>$null
    Write-Success "データベースマイグレーションが完了しました"
} else {
    Write-Warn "PostgreSQL がインストールされていないため、データベースセットアップをスキップしました"
}

# ============================================================
# ステップ 4: Ollama セットアップ
# ============================================================
Write-Info "ステップ 4/5: Ollama をセットアップ中..."

if (Get-Command ollama -ErrorAction SilentlyContinue) {
    # Ollama が起動していない場合は起動
    $ollamaProcess = Get-Process -Name "ollama" -ErrorAction SilentlyContinue
    if (-not $ollamaProcess) {
        Write-Info "Ollama を起動中..."
        Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
        Start-Sleep -Seconds 3
    }

    # モデルダウンロード
    $MODELS = @("gemma3:4b", "nomic-embed-text")
    foreach ($model in $MODELS) {
        $hasModel = ollama list 2>$null | Select-String $model
        if ($hasModel) {
            Write-Success "$model はインストール済みです"
        } else {
            Write-Info "$model をダウンロード中..."
            ollama pull $model
        }
    }
} else {
    Write-Warn "Ollama がインストールされていないため、モデルダウンロードをスキップしました"
}

# ============================================================
# ステップ 5: 設定とスクリプト作成
# ============================================================
Write-Info "ステップ 5/5: 設定を作成中..."

# .env ファイル作成
$NEXTAUTH_SECRET = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 32 | ForEach-Object {[char]$_})
$ENV_CONTENT = @"
DATABASE_URL=postgresql://${DB_USER}:${DB_PASSWORD}@localhost:5432/${DB_NAME}
OLLAMA_BASE_URL=http://localhost:11434
NEXTAUTH_SECRET=$NEXTAUTH_SECRET
NEXTAUTH_URL=http://localhost:3000
NEXT_PUBLIC_API_URL=http://localhost:8000
"@

Set-Content -Path "$INSTALL_DIR\.env" -Value $ENV_CONTENT -Encoding UTF8
Copy-Item "$INSTALL_DIR\.env" "$INSTALL_DIR\frontend\.env"
Write-Success ".env ファイルを作成しました"

# 起動スクリプト作成
$START_SCRIPT = @'
# LM Light 起動スクリプト
$PROJECT_ROOT = Split-Path -Parent $PSScriptRoot
if (Test-Path "$PROJECT_ROOT\scripts") {
    $PROJECT_ROOT = $PROJECT_ROOT
} else {
    $PROJECT_ROOT = Split-Path -Parent $PROJECT_ROOT
}

# .env 読み込み
if (Test-Path "$PROJECT_ROOT\.env") {
    Get-Content "$PROJECT_ROOT\.env" | ForEach-Object {
        if ($_ -match "^([^=]+)=(.*)$") {
            [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2])
        }
    }
}

Write-Host "LM Light を起動中..." -ForegroundColor Blue

# PostgreSQL チェック
$pgService = Get-Service -Name "postgresql*" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pgService -and $pgService.Status -ne "Running") {
    Write-Host "PostgreSQL を起動中..."
    Start-Service $pgService.Name
    Start-Sleep -Seconds 2
}

# Ollama チェック
if (-not (Get-Process -Name "ollama" -ErrorAction SilentlyContinue)) {
    Write-Host "Ollama を起動中..."
    Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
    Start-Sleep -Seconds 3
}

# 既存プロセス終了
Get-Process -Name "lmlight-api" -ErrorAction SilentlyContinue | Stop-Process -Force
Get-NetTCPConnection -LocalPort 3000, 8000 -ErrorAction SilentlyContinue | ForEach-Object {
    Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 1

# API 起動
Write-Host "API を起動中..."
Start-Process -FilePath "$PROJECT_ROOT\bin\lmlight-api.exe" -WorkingDirectory $PROJECT_ROOT -WindowStyle Hidden -RedirectStandardOutput "$PROJECT_ROOT\logs\api.log" -RedirectStandardError "$PROJECT_ROOT\logs\api.err"
Start-Sleep -Seconds 3

# Web 起動
Write-Host "Web を起動中..."
Start-Process -FilePath "node" -ArgumentList "server.js" -WorkingDirectory "$PROJECT_ROOT\frontend" -WindowStyle Hidden -RedirectStandardOutput "$PROJECT_ROOT\logs\web.log" -RedirectStandardError "$PROJECT_ROOT\logs\web.err"
Start-Sleep -Seconds 3

Write-Host ""
Write-Host "LM Light が起動しました！" -ForegroundColor Green
Write-Host ""
Write-Host "  Web UI: http://localhost:3000"
Write-Host "  API:    http://localhost:8000"
Write-Host ""
Write-Host "  ログイン: admin@localhost.local / admin123"
Write-Host ""

# ブラウザを開く
Start-Process "http://localhost:3000"
'@

Set-Content -Path "$INSTALL_DIR\scripts\start.ps1" -Value $START_SCRIPT -Encoding UTF8

# 停止スクリプト作成
$STOP_SCRIPT = @'
Write-Host "LM Light を停止中..."

Get-Process -Name "lmlight-api" -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "*lmlight*" } | Stop-Process -Force

Write-Host "LM Light を停止しました" -ForegroundColor Green
'@

Set-Content -Path "$INSTALL_DIR\scripts\stop.ps1" -Value $STOP_SCRIPT -Encoding UTF8

# シンボリックリンク的な起動ファイル
Copy-Item "$INSTALL_DIR\scripts\start.ps1" "$INSTALL_DIR\start.ps1"
Copy-Item "$INSTALL_DIR\scripts\stop.ps1" "$INSTALL_DIR\stop.ps1"

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║     LM Light のインストールが完了しました！          ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

if ($MISSING_DEPS.Count -gt 0) {
    Write-Warn "不足している依存関係: $($MISSING_DEPS -join ', ')"
    Write-Host ""
    Write-Host "  winget でインストール:"
    if ($MISSING_DEPS -contains "nodejs") { Write-Host "    winget install OpenJS.NodeJS.LTS" }
    if ($MISSING_DEPS -contains "postgresql") { Write-Host "    winget install PostgreSQL.PostgreSQL" }
    if ($MISSING_DEPS -contains "ollama") { Write-Host "    winget install Ollama.Ollama" }
    if ($MISSING_DEPS -contains "tesseract") { Write-Host "    Tesseract: https://github.com/UB-Mannheim/tesseract/wiki  # オプション: 画像OCR用" }
    Write-Host ""
}

# Create Start Menu shortcuts (path is consistent across all locales)
$START_MENU = [Environment]::GetFolderPath("Programs")
$APP_FOLDER = "$START_MENU\LM Light"
New-Item -ItemType Directory -Force -Path $APP_FOLDER | Out-Null

$WshShell = New-Object -ComObject WScript.Shell

$StartShortcut = $WshShell.CreateShortcut("$APP_FOLDER\LM Light Start.lnk")
$StartShortcut.TargetPath = "powershell.exe"
$StartShortcut.Arguments = "-ExecutionPolicy Bypass -File `"$INSTALL_DIR\start.ps1`""
$StartShortcut.WorkingDirectory = $INSTALL_DIR
$StartShortcut.Description = "Start LM Light"
$StartShortcut.Save()

$StopShortcut = $WshShell.CreateShortcut("$APP_FOLDER\LM Light Stop.lnk")
$StopShortcut.TargetPath = "powershell.exe"
$StopShortcut.Arguments = "-ExecutionPolicy Bypass -File `"$INSTALL_DIR\stop.ps1`""
$StopShortcut.WorkingDirectory = $INSTALL_DIR
$StopShortcut.Description = "Stop LM Light"
$StopShortcut.Save()

Write-Success "スタートメニューにショートカットを作成しました"

Write-Host "起動: $INSTALL_DIR\start.ps1" -ForegroundColor Blue
Write-Host "停止: $INSTALL_DIR\stop.ps1" -ForegroundColor Blue
Write-Host ""
Write-Host "Web UI:   http://localhost:3000" -ForegroundColor Blue
Write-Host "ログイン: admin@localhost.local / admin123" -ForegroundColor Blue
Write-Host ""
Write-Host "============================================================"
Write-Host "  ライセンス設定"
Write-Host "============================================================"
Write-Host ""
Write-Host "  ライセンスファイルを以下に配置してください:"
Write-Host "    $INSTALL_DIR\license.lic"
Write-Host ""
Write-Host "  ライセンス購入: https://lmlight.app/buy"
Write-Host ""