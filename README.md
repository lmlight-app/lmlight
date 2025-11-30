# LM Light 利用マニュアル

## インストール

**macOS:**
```bash
curl -fsSL https://raw.githubusercontent.com/lmlight-app/dist/main/scripts/install-macos.sh | bash
```

**Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/lmlight-app/dist/main/scripts/install-linux.sh | bash
```

**Windows:**
```powershell
irm https://raw.githubusercontent.com/lmlight-app/dist/main/scripts/install-windows.ps1 | iex
```

インストール先: `~/.local/lmlight` (Windows: `%LOCALAPPDATA%\lmlight`)

**Docker:**
```bash
curl -fsSL https://raw.githubusercontent.com/lmlight-app/dist/main/scripts/install-docker.sh | bash
```

または手動で:
```bash
# イメージ取得
curl -fSL https://github.com/lmlight-app/dist/releases/latest/download/lmlight-api-docker.tar.gz | docker load
curl -fSL https://github.com/lmlight-app/dist/releases/latest/download/lmlight-web-docker.tar.gz | docker load

# 起動
docker run -d --name lmlight-api -p 8000:8000 --env-file .env lmlight-api
docker run -d --name lmlight-web -p 3000:3000 --env-file .env lmlight-web
```

## 環境構築

### 必要な依存関係

| 依存関係 | macOS | Linux (Ubuntu/Debian) |
|---------|-------|----------------------|
| Node.js 18+ | `brew install node` | `sudo apt install nodejs` |
| PostgreSQL 16+ | `brew install postgresql@16` | `sudo apt install postgresql` |
| Ollama | `brew install ollama` | `curl -fsSL https://ollama.com/install.sh \| sh` |

### データベース起動

```bash
brew services start postgresql@16  # macOS
sudo systemctl start postgresql    # Linux
```

※ DB/ユーザー作成は初回起動時にPrismaが自動実行

### Ollamaモデル

```bash
ollama pull gemma3:4b           # チャット用
ollama pull embeddinggemma      # RAG用 (推奨)
```

### 設定ファイル (.env)

インストール後、`~/.local/lmlight/.env` を編集:

```env
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
```

### ライセンス

`license.lic` を `~/.local/lmlight/` に配置

## 起動・停止

```bash
# 起動
~/.local/lmlight/start.sh

# 停止
~/.local/lmlight/stop.sh
```

**Windows:**
```powershell
& "$env:LOCALAPPDATA\lmlight\start.ps1"
& "$env:LOCALAPPDATA\lmlight\stop.ps1"
```

## アクセス

- Web: http://localhost:3000
- API: http://localhost:8000

デフォルトログイン: `admin@local` / `admin123`

## アップデート

同じインストールコマンドを再実行 (データは保持)

## アンインストール

```bash
rm -rf ~/.local/lmlight  # macOS/Linux
```

```powershell
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\lmlight"  # Windows
```

## ディレクトリ構造

```
~/.local/lmlight/
├── api             # APIバイナリ
├── web/            # Webフロントエンド
├── .env            # 設定ファイル
├── license.lic     # ライセンス
├── start.sh        # 起動
├── stop.sh         # 停止
└── logs/           # ログ
```
