# MemBrain

**The cognitive layer for AI — open-source, self-hosted.**

LLMs generate language. MemBrain provides everything else a brain needs around them — memory, threat detection, judgment, routing, audit, isolation, and operator visibility — as one integrated system, not bolted-on plugins.

## Install (macOS)

```bash
curl -fsSL https://membrn.ai/install.sh | bash
```

**What it does:**
- Installs Docker Desktop (if needed)
- Pulls the MemBrain engine image from `ghcr.io/mrpintcom/membrain`
- Sets up a transparent TLS proxy so all AI traffic routes through MemBrain
- Starts the dashboard at <http://localhost:8001>

**Requirements:** macOS 13 (Ventura) or later. You'll need an Anthropic and/or OpenAI API key.

## What MemBrain does — the seven pillars

| Pillar | What it covers |
|---|---|
| **Detection** | 25+ PII patterns plus optional ML NER (BERT-based). Hybrid regex + NER mode, fail-closed under scanner errors. |
| **Enforcement** | Six policy modes (`pass` / `log` / `alert` / `redact` / `block` / `confirm`) with per-project rules and human-in-the-loop approval. Tool-policy fnmatch globs with `allow` / `deny` / `approve` actions. |
| **Memory** | Knowledge store on pgvector with semantic search, auto-extraction from responses, PII rescan on injection, federated cross-brain sharing under explicit policy. |
| **Visibility** | Audit logging with SHA-256 hash-chain (tamper-evident), encrypted PII mapping, GDPR export and right-to-erasure, alert engine with webhook + Slack, Prometheus `/metrics`. |
| **Routing** | Multi-provider (Anthropic, OpenAI, Claude CLI, Ollama, LiteLLM 100+ models), tier / cost / privacy-based routing, fallback chains, exact + semantic response caching. |
| **Coverage** | Three ingress modes — application proxy (`/v1/messages`, `/v1/chat/completions`), transparent network proxy (TLS termination + SNI inspection), and full MCP governance (`/mcp/v1/{server}`). |
| **Trust** | Multi-tenant isolation (per-project cache, MCP registry, audit, knowledge), RBAC, OIDC SSO + SCIM, peppered API-key hashing, atomic key rotation. Open-source under Apache 2.0. |

## Commands

```
membrain status    - deep liveness check (DB + Redis reachability)
membrain logs      - view logs
membrain stop      - pause MemBrain
membrain start     - resume
membrain update    - pull latest version
membrain uninstall - clean removal
```

## How it works

MemBrain intercepts API calls to common AI provider hosts via a local TLS proxy:

1. A trusted CA certificate is installed on your Mac
2. DNS is routed through `/etc/hosts` to localhost
3. Caddy terminates TLS and forwards to the MemBrain gateway
4. The gateway inspects, governs, logs, and forwards requests to the real upstream

Your API key never leaves your machine. All processing happens locally.

For server / Kubernetes deployments and the application-proxy and MCP-governance modes, see the deployment docs at <https://membrn.ai/docs/>.

## Reporting issues

This is a distribution-only repository. Issues are intentionally disabled here. For bug reports, feature requests, and questions:

- Email <membrn.ai@gmail.com>
- Discussions: <https://github.com/mrpintcom/membrain-engine/discussions>

## License

Apache 2.0. The full source for the gateway lives in the upstream MemBrain project; this repo distributes the deploy manifests and installer.
