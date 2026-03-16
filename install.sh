#!/usr/bin/env bash
#
# Membrain Installer
# Usage: curl -fsSL https://membrn.ai/install.sh | bash
#
set -euo pipefail

VERSION="0.5.0"
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

# ─── Detect platform ────────────────────────────────────────
OS="$(uname -s)"
is_macos=false
is_linux=false

case "$OS" in
  Darwin) is_macos=true ;;
  Linux)  is_linux=true ;;
  *)      fail "Unsupported platform: ${OS}. Membrain supports macOS and Linux." ;;
esac

# Cleanup on failure — only cleans up artifacts that were actually created
cleanup_on_failure() {
  echo ""
  warn "Installation failed. Cleaning up..."
  # Only touch /etc/hosts if we got far enough to modify it
  if grep -q "# membrain" /etc/hosts 2>/dev/null; then
    if $is_macos; then
      sudo sed -i '' '/# membrain/d' /etc/hosts 2>/dev/null || true
    else
      sudo sed -i '/# membrain/d' /etc/hosts 2>/dev/null || true
    fi
  fi
  # Remove CA cert from trust store
  if $is_macos && [ -f "${MEMBRAIN_HOME}/certs/membrain-ca.pem" ]; then
    sudo security remove-trusted-cert -d "${MEMBRAIN_HOME}/certs/membrain-ca.pem" 2>/dev/null || true
  fi
  if $is_linux && [ -f /usr/local/share/ca-certificates/membrain-ca.crt ]; then
    sudo rm -f /usr/local/share/ca-certificates/membrain-ca.crt
    sudo update-ca-certificates 2>/dev/null || true
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

if $is_macos; then
  # macOS version
  macos_version=$(sw_vers -productVersion 2>/dev/null || echo "0")
  macos_major=$(echo "$macos_version" | cut -d. -f1)
  if [ "$macos_major" -lt 13 ] 2>/dev/null; then
    fail "macOS 13 (Ventura) or later required. You have ${macos_version}."
  fi
  info "macOS ${macos_version}"

  # Homebrew
  if command -v brew &>/dev/null; then
    brew_prefix=$(brew --prefix 2>/dev/null || echo "/usr/local")
    if [ -d "${brew_prefix}/Homebrew" ] && [ ! -w "${brew_prefix}/Homebrew" ]; then
      step "Fixing Homebrew permissions..."
      sudo chown -R "$(whoami)" "${brew_prefix}/Homebrew"
    fi
    step "Updating Homebrew..."
    brew update --quiet 2>/dev/null || true
    info "Homebrew"
  else
    step "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"
    info "Homebrew installed"
  fi
fi

if $is_linux; then
  # Linux distro info
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    info "Linux (${PRETTY_NAME:-$ID})"
  else
    info "Linux"
  fi
fi

# Git
if ! command -v git &>/dev/null; then
  step "Installing git..."
  if $is_macos; then
    brew install git
  else
    sudo apt-get update -qq && sudo apt-get install -y -qq git curl
  fi
fi

# Docker
if command -v docker &>/dev/null; then
  info "Docker"
elif $is_macos && [ -d "/Applications/Docker.app" ]; then
  info "Docker Desktop"
  step "Linking Docker CLI..."
  open -a Docker --args --accept-license 2>/dev/null || true
  for i in $(seq 1 20); do
    command -v docker &>/dev/null && break
    sleep 2
  done
else
  step "Installing Docker..."
  if $is_macos; then
    brew install --cask docker
    info "Docker Desktop installed"
  else
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$USER" 2>/dev/null || true
    sudo systemctl enable docker 2>/dev/null || true
    sudo systemctl start docker 2>/dev/null || true
    info "Docker installed"
  fi
fi

# Docker Compose v2 check
if ! docker compose version &>/dev/null; then
  if $is_linux; then
    step "Installing Docker Compose plugin..."
    sudo apt-get update -qq && sudo apt-get install -y -qq docker-compose-plugin
  else
    fail "Docker Compose plugin not found. Please install Docker Desktop."
  fi
fi

# Start Docker if not running
if ! docker info &>/dev/null 2>&1; then
  step "Starting Docker..."
  if $is_macos; then
    open -a Docker
  else
    sudo systemctl start docker 2>/dev/null || true
  fi
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
    fail "Docker failed to start after 90 seconds. Please start Docker manually and re-run."
  fi
fi

# Check ports
check_port() {
  local port=$1
  if $is_macos; then
    lsof -i ":${port}" -sTCP:LISTEN &>/dev/null 2>&1
  else
    ss -tlnp "sport = :${port}" 2>/dev/null | grep -q LISTEN
  fi
}

if check_port 443; then
  if $is_macos; then
    port_user=$(lsof -i :443 -sTCP:LISTEN 2>/dev/null | tail -1 | awk '{print $1}')
  else
    port_user=$(ss -tlnp 'sport = :443' 2>/dev/null | awk 'NR>1{print $6}' | head -1)
  fi
  if echo "$port_user" | grep -qiE "docker|vpnkit|com.docke"; then
    warn "Docker is using port 443 — will be released when we start our stack."
  else
    fail "Port 443 is in use by '${port_user}'. Please stop it and re-run."
  fi
fi
if check_port 8001; then
  if $is_macos; then
    port_user=$(lsof -i :8001 -sTCP:LISTEN 2>/dev/null | tail -1 | awk '{print $1}')
  else
    port_user=$(ss -tlnp 'sport = :8001' 2>/dev/null | awk 'NR>1{print $6}' | head -1)
  fi
  fail "Port 8001 is in use by '${port_user}'. Please stop it and re-run."
fi

# ─── API Key (optional) ──────────────────────────────────

echo ""
echo -e "  Enter your Anthropic API key (or press Enter to skip):"
echo -n "  > "
read -r api_key </dev/tty || api_key=""

if [ -n "$api_key" ]; then
  step "Verifying API key..."
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "x-api-key: ${api_key}" \
    -H "content-type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
    "https://api.anthropic.com/v1/messages" 2>/dev/null || echo "000")

  if [ "$http_code" = "000" ]; then
    warn "Could not reach api.anthropic.com. Continuing without verification."
  elif [ "$http_code" = "401" ]; then
    warn "API key appears invalid. You can update it later in ~/.membrain/.env"
  elif [ "$http_code" = "200" ]; then
    info "API key verified"
  else
    warn "API returned HTTP ${http_code} — continuing anyway."
  fi
else
  warn "No API key provided. You can add one later in ~/.membrain/.env"
  warn "Session-based auth (Claude Code login) will still work."
fi

# ─── Clone & Configure ───────────────────────────────────

echo ""
echo "  Setting up Membrain..."

mkdir -p "$MEMBRAIN_HOME"

step "Downloading Membrain..."
git clone --depth 1 --quiet "$REPO_URL" "${MEMBRAIN_HOME}/src"

# Validate clone
if [ ! -f "${MEMBRAIN_HOME}/src/deploy/docker-compose.yml" ]; then
  fail "docker-compose.yml not found in cloned repo. Clone may be corrupted."
fi
info "Downloaded Membrain"

# Copy deploy configs
cp "${MEMBRAIN_HOME}/src/deploy/docker-compose.yml" "${MEMBRAIN_HOME}/docker-compose.yml"
cp "${MEMBRAIN_HOME}/src/deploy/Caddyfile" "${MEMBRAIN_HOME}/Caddyfile"

# Copy embedder sidecar
cp -r "${MEMBRAIN_HOME}/src/deploy/embedder" "${MEMBRAIN_HOME}/embedder"

# Write .env
cat > "${MEMBRAIN_HOME}/.env" <<ENVEOF
ANTHROPIC_API_KEY=${api_key}
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

# ─── Start Services ──────────────────────────────────────

step "Pulling and starting services..."
docker compose -f "${MEMBRAIN_HOME}/docker-compose.yml" pull gateway 2>/dev/null || true
docker compose -f "${MEMBRAIN_HOME}/docker-compose.yml" up -d
info "Started services (gateway, caddy, postgres, redis)"

# ─── TLS Proxy Setup (sudo) ──────────────────────────────

echo ""
echo -e "  ${BOLD}Membrain needs admin access to install a trusted${NC}"
echo -e "  ${BOLD}certificate and configure DNS routing.${NC}"
echo ""

# Install CA to trust store
if $is_macos; then
  sudo security add-trusted-cert -d -r trustRoot \
    -k /Library/Keychains/System.keychain \
    "${MEMBRAIN_HOME}/certs/membrain-ca.pem"
else
  sudo cp "${MEMBRAIN_HOME}/certs/membrain-ca.pem" \
    /usr/local/share/ca-certificates/membrain-ca.crt
  sudo update-ca-certificates
fi
info "CA certificate trusted"

# Add /etc/hosts entry
if ! grep -q "# membrain" /etc/hosts 2>/dev/null; then
  echo "127.0.0.1 api.anthropic.com  # membrain" | sudo tee -a /etc/hosts >/dev/null
fi
info "DNS routing configured"

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

sudo cp "${MEMBRAIN_HOME}/src/deploy/membrain-wrapper.sh" /usr/local/bin/membrain
sudo chmod +x /usr/local/bin/membrain
info "Installed 'membrain' command"

# ─── Auto-Start ──────────────────────────────────────────

if $is_macos; then
  mkdir -p "${HOME}/Library/LaunchAgents"
  cp "${MEMBRAIN_HOME}/src/deploy/com.membrain.docker.plist" \
     "${HOME}/Library/LaunchAgents/com.membrain.docker.plist"
  launchctl load "${HOME}/Library/LaunchAgents/com.membrain.docker.plist" 2>/dev/null || true
  info "Auto-start configured (launchd)"
else
  # Linux: systemd user service
  mkdir -p "${HOME}/.config/systemd/user"
  cat > "${HOME}/.config/systemd/user/membrain.service" <<SYSDEOF
[Unit]
Description=Membrain AI Gateway
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${MEMBRAIN_HOME}
ExecStart=/usr/bin/docker compose -f ${MEMBRAIN_HOME}/docker-compose.yml up -d
ExecStop=/usr/bin/docker compose -f ${MEMBRAIN_HOME}/docker-compose.yml stop

[Install]
WantedBy=default.target
SYSDEOF
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable membrain.service 2>/dev/null || true
  info "Auto-start configured (systemd)"
fi

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
echo "    membrain addons    - list optional add-ons"
echo "    membrain uninstall - clean removal"
echo ""
echo "  Optional add-ons (enable anytime):"
echo "    membrain enable ml-search   - semantic knowledge search"
echo "    membrain enable litellm     - 100+ LLM backends"
echo ""
