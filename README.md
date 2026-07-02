# MemBrain

**The cognitive layer for AI — self-hosted, open-core.**

LLMs generate language. MemBrain provides everything else a brain needs around them — memory, threat detection, judgment, routing, audit, isolation, and operator visibility — as one integrated system, not bolted-on plugins.

## Install (macOS)

```bash
curl -fsSL https://membrn.ai/install.sh | bash
```

**What it does:**
- Installs Docker Desktop (if needed)
- Pulls the pinned MemBrain engine image from `ghcr.io/mrpintcom/membrain`
- Starts the gateway, database, and cache
- Points your AI clients at MemBrain as an explicit proxy (`ANTHROPIC_BASE_URL=http://localhost:8001`)
- Opens the dashboard at <http://localhost:8001>

Prefer zero-config, system-wide interception instead of setting a base URL? Turn on the optional transparent proxy after install (see [How it works](#how-it-works)):

```bash
membrain enable transparent-proxy
```

**Requirements:** macOS 13 (Ventura) or later, and an Anthropic and/or OpenAI API key. (Linux is also supported by the installer; for servers and Kubernetes see the deployment docs.)

## What MemBrain does — the seven pillars

The community build is licensed under Apache 2.0. Features marked **★ Enterprise** require a licensed add-on.

| Pillar | What it covers |
|---|---|
| **Detection** | 25+ PII patterns, fail-closed under scanner errors. Optional ML NER (BERT-based) with hybrid regex + NER mode — **★ Enterprise**. |
| **Enforcement** | Six policy modes (`pass` / `log` / `alert` / `redact` / `block` / `confirm`) with per-project rules and human-in-the-loop approval. Tool-policy fnmatch globs with `allow` / `deny` / `approve` actions. |
| **Memory** | Knowledge store on pgvector with semantic search, auto-extraction from responses, PII rescan on injection, federated cross-brain sharing under explicit policy. |
| **Visibility** | Audit logging with a tamper-evident HMAC-SHA256 hash-chain, encrypted PII mapping, GDPR export and right-to-erasure, alert engine with webhook + Slack, Prometheus `/metrics`. |
| **Routing** | Multi-provider (Anthropic, OpenAI, Claude CLI, Ollama, LiteLLM 100+ models), tier / cost / privacy-based routing, fallback chains, exact + semantic response caching. |
| **Coverage** | Three ingress modes — application proxy (`/v1/messages`, `/v1/chat/completions`), transparent network proxy (TLS termination + SNI inspection), and MCP governance (`/mcp/v1/{server}`). |
| **Trust** | Multi-tenant isolation (per-project cache, MCP registry, audit, knowledge), RBAC, peppered API-key hashing, atomic key rotation. OIDC SSO + SCIM provisioning — **★ Enterprise**. |

## Commands

```
membrain status    - health check + container status
membrain logs      - view logs
membrain stop      - pause MemBrain
membrain start     - resume
membrain enable    - turn on an add-on (e.g. transparent-proxy)
membrain disable   - turn off an add-on
membrain addons    - list available add-ons and their state
membrain update    - pull the latest version
membrain uninstall - clean removal
```

## How it works

By default, MemBrain runs as an **explicit proxy**. The installer sets `ANTHROPIC_BASE_URL=http://localhost:8001`, so your AI clients send requests to MemBrain, which inspects, governs, logs, and forwards them to the real upstream. Your API key never leaves your machine.

For zero-config, system-wide coverage, enable the optional **transparent proxy**:

```bash
membrain enable transparent-proxy
```

It then:

1. Installs a **name-constrained** trusted CA on your Mac (scoped to `api.anthropic.com`; the CA private key is deleted right after it signs the leaf certificate)
2. Routes `api.anthropic.com` to localhost via `/etc/hosts`
3. Runs Caddy to terminate TLS and forward to the MemBrain gateway
4. Governs that traffic with no per-client configuration

Either way, all processing happens locally.

For server / Kubernetes deployments and the application-proxy and MCP-governance modes, see the deployment docs at <https://membrn.ai/docs/>.

## Editions

MemBrain is **open-core**. The community gateway — everything above except the **★ Enterprise** items — is licensed under Apache 2.0 and is what this installer pulls and runs. Enterprise add-ons (ML NER, OIDC SSO + SCIM, and other licensed capabilities) are packaged separately and activated with a license. This repository distributes the installer and deploy manifests; it is not the gateway source tree.

## Reporting issues

This is a distribution-only repository. Issues are intentionally disabled here. For bug reports, feature requests, and questions:

- Discussions: <https://github.com/mrpintcom/membrain-engine/discussions>
- Email <membrn.ai@gmail.com>

## License

Apache 2.0 for the community gateway and this distribution repository. Enterprise add-ons are separately licensed.
