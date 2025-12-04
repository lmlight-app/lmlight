# LM Light 利用マニュアル (Nuitka版)

> **Note**: Nuitkaビルドは一部環境で問題が発生する場合があります。
> 推奨: [PyInstaller版 (dist_v2)](https://github.com/lmlight-app/dist_v2) をご利用ください。

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

## 環境構築 (インストール前に実行)

### 必要な依存関係

| 依存関係 | macOS | Linux (Ubuntu/Debian) | Windows |
|---------|-------|----------------------|---------|
| Node.js 18+ | `brew install node` | `sudo apt install nodejs npm` | `winget install OpenJS.NodeJS.LTS` |
| PostgreSQL 16+ | `brew install postgresql@16` | `sudo apt install postgresql` | `winget install PostgreSQL.PostgreSQL` |
| pgvector | `brew install pgvector` | `sudo apt install postgresql-16-pgvector` | [手動インストール](https://github.com/pgvector/pgvector#windows) |
| Ollama | `brew install ollama` | `curl -fsSL https://ollama.com/install.sh \| sh` | `winget install Ollama.Ollama` |

### サービス起動

PostgreSQL と Ollama は `start.sh` / `stop.sh` で自動的に起動・停止されます。

※ データベース・ユーザー・テーブル作成はインストーラーが自動実行します

### 手動DBセットアップ (開発・トラブルシュート用)

```bash
cd web

# Prismaクライアント生成
npx prisma generate

# スキーマをDBに反映
npx prisma db push

# 初期データ投入 (admin@local / admin123)
npx prisma db seed
```

### Ollamaモデル

[Ollama モデル一覧](https://ollama.com/search) から好みのモデルを選択:

```bash
ollama pull <model_name>        # 例: gemma3:4b, llama3.2, qwen2.5 など
ollama pull nomic-embed-text    # RAG用埋め込みモデル (推奨)
```

### 設定ファイル (.env)

インストール後、`~/.local/lmlight/.env` を編集:

| 環境変数 | 説明 | デフォルト |
|---------|------|-----------|
| `DATABASE_URL` | PostgreSQL接続URL | `postgresql://<user>:<password>@localhost:5432/<database>` |
| `OLLAMA_BASE_URL` | OllamaサーバーURL | `http://localhost:11434` |
| `LICENSE_FILE_PATH` | ライセンスファイルのパス | `~/.local/lmlight/license.lic` |
| `NEXTAUTH_SECRET` | セッション暗号化キー (任意の文字列) | - |
| `NEXTAUTH_URL` | WebアプリのURL | `http://localhost:3000` |
| `NEXT_PUBLIC_API_URL` | APIサーバーURL | `http://localhost:8000` |
| `API_PORT` | APIポート | `8000` |
| `WEB_PORT` | Webポート | `3000` |

※ インストーラーが自動設定します。手動変更が必要な場合のみ編集してください。

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

※ 初回ログイン後、パスワードを変更してください

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
