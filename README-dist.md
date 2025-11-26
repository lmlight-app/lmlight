# LM Light

LLM管理ツール - ローカルLLMを簡単に管理・利用できるWebアプリケーション

## インストール

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/lmlight-app/lmlight/main/scripts/install-macos.sh | bash
```

### Linux

```bash
curl -fsSL https://raw.githubusercontent.com/lmlight-app/lmlight/main/scripts/install-linux.sh | bash
```

### Docker

```bash
curl -fsSL https://raw.githubusercontent.com/lmlight-app/lmlight/main/scripts/install-docker.sh | bash
```

## 必要条件

- Node.js 18+
- PostgreSQL 16+ (with pgvector)
- Ollama

## 起動

インストール後:

```bash
~/.local/lmlight/start.sh
```

- Web UI: http://localhost:3000
- API: http://localhost:8000

## ライセンス

MIT License
