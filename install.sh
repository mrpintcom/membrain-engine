#!/usr/bin/env bash
#
# Membrain Installer
# Usage: curl -fsSL https://membrn.ai/install.sh | bash
#
set -euo pipefail

VERSION="0.1.0"
MEMBRAIN_HOME="${HOME}/.membrain"
REPO_URL="https://github.com/mrpintcom/membrain-engine.git"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${YELLOW}!${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; exit 1; }
step()  { echo -e "  ${BLUE}→${NC} $1"; }

# Cleanup on failure — only cleans up artifacts that were actually created
cleanup_on_failure() {
  echo ""
  warn "Installation failed. Cleaning up..."
  # Only touch /etc/hosts and keychain if we got far enough to modify them
  if grep -q "# membrain" /etc/hosts 2>/dev/null; then
    sudo sed -i '' '/# membrain/d' /etc/hosts 2>/dev/null || true
  fi
  if [ -f /etc/pf.anchors/membrain ]; then
    sudo rm -f /etc/pf.anchors/membrain 2>/dev/null || true
    sudo sed -i '' '/membrain/d' /etc/pf.conf 2>/dev/null || true
    sudo pfctl -f /etc/pf.conf 2>/dev/null || true
  fi
  if [ -f "${MEMBRAIN_HOME}/certs/membrain-ca.pem" ]; then
    sudo security remove-trusted-cert -d "${MEMBRAIN_HOME}/certs/membrain-ca.pem" 2>/dev/null || true
  fi
  if [ -d "$MEMBRAIN_HOME" ]; then
    rm -rf "$MEMBRAIN_HOME"
  fi
}
trap cleanup_on_failure ERR

# ─── Banner ───────────────────────────────────────────────

echo ""
echo -e "  ${BOLD}Membrain Installer v${VERSION}${NC}"
echo ""

# ─── Check: already installed? ────────────────────────────

if [ -d "$MEMBRAIN_HOME" ]; then
  echo -e "  ${YELLOW}Membrain is already installed at ${MEMBRAIN_HOME}${NC}"
  echo -e "  Run ${BOLD}membrain update${NC} to update, or ${BOLD}membrain uninstall${NC} first."
  exit 1
fi

# ─── Preflight ────────────────────────────────────────────

echo "  Checking prerequisites..."

# macOS version
macos_version=$(sw_vers -productVersion 2>/dev/null || echo "0")
macos_major=$(echo "$macos_version" | cut -d. -f1)
if [ "$macos_major" -lt 13 ] 2>/dev/null; then
  fail "macOS 13 (Ventura) or later required. You have ${macos_version}."
fi
info "macOS ${macos_version}"

# Homebrew
if command -v brew &>/dev/null; then
  # Fix permissions if needed (common on Intel Macs)
  brew_prefix=$(brew --prefix 2>/dev/null || echo "/usr/local")
  if [ ! -w "${brew_prefix}/Homebrew" ] 2>/dev/null; then
    step "Fixing Homebrew permissions..."
    sudo chown -R "$(whoami)" "${brew_prefix}/Homebrew"
  fi
  # Update Homebrew to support latest macOS versions
  step "Updating Homebrew..."
  brew update --quiet 2>/dev/null || true
  info "Homebrew"
else
  step "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add Homebrew to PATH for this session
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"
  info "Homebrew installed"
fi

# Git
if ! command -v git &>/dev/null; then
  step "Installing git..."
  brew install git
fi

# Docker
if command -v docker &>/dev/null || [ -d "/Applications/Docker.app" ]; then
  info "Docker Desktop"
  # Ensure docker CLI is on PATH (app may exist but CLI not linked)
  if ! command -v docker &>/dev/null; then
    step "Linking Docker CLI..."
    open -a Docker --args --accept-license 2>/dev/null || true
    # Wait for Docker to create CLI symlinks
    for i in $(seq 1 20); do
      command -v docker &>/dev/null && break
      sleep 2
    done
  fi
else
  step "Installing Docker Desktop via Homebrew..."
  brew install --cask docker
  info "Docker Desktop installed"
fi

# Docker Compose v2 check
if ! docker compose version &>/dev/null; then
  fail "Docker Compose plugin not found. Please install Docker Desktop."
fi

# Start Docker if not running
if ! docker info &>/dev/null 2>&1; then
  step "Starting Docker Desktop..."
  open -a Docker
  echo -n "  Waiting for Docker"
  for i in $(seq 1 30); do
    if docker info &>/dev/null 2>&1; then
      echo -e " ${GREEN}ready${NC}"
      break
    fi
    echo -n "."
    sleep 3
  done
  if ! docker info &>/dev/null 2>&1; then
    fail "Docker failed to start after 90 seconds. Please start Docker Desktop manually and re-run."
  fi
fi

# Check ports (8443 for Caddy TLS, 8001 for dashboard)
for check_port in 8443 8001; do
  if lsof -i ":${check_port}" -sTCP:LISTEN &>/dev/null 2>&1; then
    port_user=$(lsof -i ":${check_port}" -sTCP:LISTEN 2>/dev/null | tail -1 | awk '{print $1}')
    fail "Port ${check_port} is in use by '${port_user}'. Please stop it and re-run."
  fi
done

# ─── API Key (optional) ───────────────────────────────────

echo ""
echo -n "  Enter your Anthropic API key (or press Enter to skip): "
read -r api_key </dev/tty

if [ -n "$api_key" ]; then
  step "Verifying API key..."
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "x-api-key: ${api_key}" \
    -H "content-type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
    "https://api.anthropic.com/v1/messages" 2>/dev/null || echo "000")

  if [ "$http_code" = "000" ]; then
    warn "Could not reach api.anthropic.com. Saving key anyway."
  elif [ "$http_code" = "401" ]; then
    warn "API key may be invalid. Saving anyway — you can update it later in ~/.membrain/.env"
  elif [ "$http_code" = "200" ]; then
    info "API key verified"
  else
    warn "API returned HTTP ${http_code} — continuing anyway."
  fi
else
  warn "No API key provided. Add one later to ~/.membrain/.env"
fi

# ─── Clone & Configure ───────────────────────────────────

echo ""
echo "  Setting up Membrain..."

mkdir -p "$MEMBRAIN_HOME"

step "Downloading Membrain..."
git clone --depth 1 --quiet "$REPO_URL" "${MEMBRAIN_HOME}/engine"

# Validate clone
if [ ! -f "${MEMBRAIN_HOME}/engine/deploy/docker-compose.yml" ]; then
  fail "docker-compose.yml not found in cloned repo. Clone may be corrupted."
fi
info "Downloaded Membrain"

# Copy configs
cp "${MEMBRAIN_HOME}/engine/deploy/docker-compose.yml" "${MEMBRAIN_HOME}/docker-compose.yml"
cp "${MEMBRAIN_HOME}/engine/deploy/Caddyfile" "${MEMBRAIN_HOME}/Caddyfile"

# Write .env
cat > "${MEMBRAIN_HOME}/.env" <<ENVEOF
ANTHROPIC_API_KEY=${api_key:-}
DATABASE_URL=postgresql+asyncpg://membrain:membrain@postgres:5432/membrain
REDIS_URL=redis://redis:6379
ENVEOF
chmod 600 "${MEMBRAIN_HOME}/.env"

# ─── Certificate Generation ──────────────────────────────

step "Generating TLS certificates..."
mkdir -p "${MEMBRAIN_HOME}/certs"

# Generate CA
openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
  -keyout "${MEMBRAIN_HOME}/certs/membrain-ca-key.pem" \
  -out "${MEMBRAIN_HOME}/certs/membrain-ca.pem" \
  -subj "/CN=Membrain Gateway CA/O=Membrain" \
  2>/dev/null

# Generate leaf cert for api.anthropic.com
openssl req -newkey rsa:2048 -nodes \
  -keyout "${MEMBRAIN_HOME}/certs/api.anthropic.com-key.pem" \
  -out "${MEMBRAIN_HOME}/certs/api.anthropic.com.csr" \
  -subj "/CN=api.anthropic.com" \
  2>/dev/null

# Create SAN config
cat > "${MEMBRAIN_HOME}/certs/san.cnf" <<SANEOF
[req]
distinguished_name = req_dn
[req_dn]
[v3_leaf]
basicConstraints = CA:FALSE
subjectAltName = DNS:api.anthropic.com
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
SANEOF

# Sign leaf cert with CA
openssl x509 -req \
  -in "${MEMBRAIN_HOME}/certs/api.anthropic.com.csr" \
  -CA "${MEMBRAIN_HOME}/certs/membrain-ca.pem" \
  -CAkey "${MEMBRAIN_HOME}/certs/membrain-ca-key.pem" \
  -CAcreateserial \
  -out "${MEMBRAIN_HOME}/certs/api.anthropic.com.pem" \
  -days 825 \
  -extfile "${MEMBRAIN_HOME}/certs/san.cnf" \
  -extensions v3_leaf \
  2>/dev/null

# Clean up temp files
rm -f "${MEMBRAIN_HOME}/certs/api.anthropic.com.csr" \
      "${MEMBRAIN_HOME}/certs/san.cnf" \
      "${MEMBRAIN_HOME}/certs/membrain-ca.srl"

# Set permissions
chmod 700 "${MEMBRAIN_HOME}/certs"
chmod 600 "${MEMBRAIN_HOME}/certs/membrain-ca-key.pem"
chmod 600 "${MEMBRAIN_HOME}/certs/api.anthropic.com-key.pem"

info "Generated TLS certificates"

# ─── Pull & Start Services ───────────────────────────────

step "Pulling Membrain image..."
docker compose -f "${MEMBRAIN_HOME}/docker-compose.yml" pull gateway
info "Image downloaded"

step "Starting services..."
docker compose -f "${MEMBRAIN_HOME}/docker-compose.yml" up -d
info "Started services (gateway, caddy, postgres, redis)"

# ─── TLS Proxy Setup (sudo) ──────────────────────────────

echo ""
echo -e "  ${BOLD}Membrain needs admin access to install a trusted${NC}"
echo -e "  ${BOLD}certificate and configure DNS routing.${NC}"
echo ""

# Install CA to system keychain
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  "${MEMBRAIN_HOME}/certs/membrain-ca.pem"
info "CA certificate trusted"

# Add /etc/hosts entries (IPv4 + IPv6 to prevent bypass)
if ! grep -q "# membrain" /etc/hosts 2>/dev/null; then
  echo "127.0.0.1 api.anthropic.com  # membrain" | sudo tee -a /etc/hosts >/dev/null
  echo "::1 api.anthropic.com  # membrain" | sudo tee -a /etc/hosts >/dev/null
fi
sudo dscacheutil -flushcache 2>/dev/null || true
sudo killall -HUP mDNSResponder 2>/dev/null || true
info "DNS routing configured"

# Set up pf to redirect 443 → 8443 on loopback
# (port 443 is reserved by macOS system services)
echo "rdr pass on lo0 proto tcp from any to 127.0.0.1 port 443 -> 127.0.0.1 port 8443" \
  | sudo tee /etc/pf.anchors/membrain >/dev/null
if ! grep -q "membrain" /etc/pf.conf 2>/dev/null; then
  # rdr-anchor must be placed with other rdr-anchors (before filter rules)
  sudo sed -i '' '/rdr-anchor "com.apple\/\*"/a\
rdr-anchor "membrain"' /etc/pf.conf
  echo "load anchor \"membrain\" from \"/etc/pf.anchors/membrain\"" | sudo tee -a /etc/pf.conf >/dev/null
fi
sudo pfctl -f /etc/pf.conf 2>/dev/null || true
sudo pfctl -e 2>/dev/null || true
info "Port forwarding configured (443 → 8443)"

# ─── Health Check ─────────────────────────────────────────

echo -n "  Waiting for gateway"
health_ok=false
for i in $(seq 1 30); do
  if curl -sf http://localhost:8001/health >/dev/null 2>&1; then
    echo -e " ${GREEN}ready${NC}"
    health_ok=true
    break
  fi
  echo -n "."
  sleep 2
done

if [ "$health_ok" = true ]; then
  info "Health check passed"
else
  warn "Gateway not responding yet. It may still be starting."
  warn "Check: docker compose -f ${MEMBRAIN_HOME}/docker-compose.yml logs gateway"
fi

# ─── Install CLI Wrapper ─────────────────────────────────

sudo cp "${MEMBRAIN_HOME}/engine/deploy/membrain-wrapper.sh" /usr/local/bin/membrain
sudo chmod +x /usr/local/bin/membrain
info "Installed 'membrain' command"

# ─── Auto-Start ──────────────────────────────────────────

mkdir -p "${HOME}/Library/LaunchAgents"
cp "${MEMBRAIN_HOME}/engine/deploy/com.membrain.docker.plist" \
   "${HOME}/Library/LaunchAgents/com.membrain.docker.plist"
launchctl load "${HOME}/Library/LaunchAgents/com.membrain.docker.plist" 2>/dev/null || true
info "Auto-start configured"

# ─── Disable cleanup trap (install succeeded) ────────────

trap - ERR

# ─── Done ─────────────────────────────────────────────────

echo ""
echo -e "  ${GREEN}${BOLD}Membrain is running!${NC}"
echo ""
echo "  Dashboard:  http://localhost:8001"
echo "  All traffic to api.anthropic.com now routes through Membrain."
echo "  Works with: Claude Desktop, Claude Code, browsers, any app."
echo ""
echo "  Commands:"
echo "    membrain status    - check health"
echo "    membrain logs      - view logs"
echo "    membrain stop      - pause Membrain"
echo "    membrain start     - resume"
echo "    membrain update    - pull latest version"
echo "    membrain uninstall - clean removal"
echo ""