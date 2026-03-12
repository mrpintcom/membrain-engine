# MemBrain

**The cognitive layer for AI.**

GPT and Claude are just the creative cortex. A real brain needs memory, judgment, threat detection, routing, and recall. MemBrain provides the cognitive functions LLMs lack — as one integrated system, not bolted-on plugins.

## Install (macOS)

```bash
curl -fsSL https://membrn.ai/install.sh | bash
```

**What it does:**
- Installs Docker Desktop (if needed)
- Pulls the MemBrain engine image
- Sets up transparent TLS proxy so all AI traffic routes through MemBrain
- Starts the dashboard at http://localhost:8001

**Requirements:** macOS 13 (Ventura) or later. You'll need an Anthropic API key.

## Commands

```
membrain status    - check health
membrain logs      - view logs
membrain stop      - pause MemBrain
membrain start     - resume
membrain update    - pull latest version
membrain uninstall - clean removal
```

## How It Works

MemBrain intercepts API calls to `api.anthropic.com` via a local TLS proxy:
1. A trusted CA certificate is installed on your Mac
2. DNS is routed through `/etc/hosts` to localhost
3. Caddy terminates TLS and forwards to the MemBrain gateway
4. The gateway inspects, logs, and forwards requests to the real API

Your API key never leaves your machine. All processing happens locally.