# LM Light

🚀 **超軽量・高速なLLM管理ツール** - ローカルLLMを簡単に管理・利用できるWebアプリケーション

## 特徴

✅ **軽量** - わずか60MBのダウンロード、110MBのインストールサイズ
⚡ **高速** - 3秒で起動、200MBのメモリ使用量
🎯 **シンプル** - ワンコマンドでインストール、デスクトップアプリとして起動
🔒 **プライバシー** - 完全ローカル実行、データは外部送信なし

## インストール

### ネイティブ版（推奨）

**macOS:**
```bash
curl -fsSL https://raw.githubusercontent.com/lmlight-app/lmlight/main/scripts/install-macos.sh | bash
```

**Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/lmlight-app/lmlight/main/scripts/install-linux.sh | bash
```

### Docker版

```bash
curl -fsSL https://raw.githubusercontent.com/lmlight-app/lmlight/main/scripts/install-docker.sh | bash
```

## 必要条件

### ネイティブ版
- PostgreSQL 16+ (pgvector対応)
- Ollama

*Node.jsは不要です - フロントエンドに同梱されています*

### Docker版
- Docker & Docker Compose

## 起動方法

### ネイティブ版

**コマンドライン:**
```bash
~/.local/lmlight/start.sh
```

**デスクトップアプリ:**
- **macOS:** `~/Applications/LM Light.app`
- **Linux:** アプリケーションメニューから「LM Light」を検索

### アクセス

- Web UI: http://localhost:3000
- API: http://localhost:8000
- ログイン: `admin@localhost.local` / `admin123`

## アップデート

同じインストールコマンドを再実行するだけでOK:

```bash
# macOS
curl -fsSL https://raw.githubusercontent.com/lmlight-app/lmlight/main/scripts/install-macos.sh | bash

# Linux
curl -fsSL https://raw.githubusercontent.com/lmlight-app/lmlight/main/scripts/install-linux.sh | bash
```

既存のデータは保持されます。

## アンインストール

```bash
rm -rf ~/.local/lmlight
# macOS: rm -rf ~/Applications/LM\ Light.app
# Linux: rm -f ~/.local/share/applications/lmlight.desktop
```

## 比較

| 項目 | LM Light | Docker版 | Open WebUI |
|------|----------|----------|------------|
| ダウンロードサイズ | 60MB | 500MB+ | 2GB+ |
| メモリ使用量 | 200MB | 500MB+ | 1GB+ |
| 起動時間 | 3秒 | 10-20秒 | 30秒+ |

## ライセンス

MIT License
