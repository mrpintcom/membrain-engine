#!/usr/bin/env bash
set -euo pipefail

MEMBRAIN_HOME="${HOME}/.membrain"
COMPOSE_FILE="${MEMBRAIN_HOME}/docker-compose.yml"
HOSTS_TAG="# membrain"
HOSTS_ENTRY="127.0.0.1 api.anthropic.com  ${HOSTS_TAG}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_installed() {
  if [ ! -d "$MEMBRAIN_HOME" ]; then
    echo -e "${RED}Membrain is not installed. Run the installer first.${NC}"
    exit 1
  fi
}

add_hosts_entry() {
  if ! grep -q "$HOSTS_TAG" /etc/hosts 2>/dev/null; then
    echo "$HOSTS_ENTRY" | sudo tee -a /etc/hosts >/dev/null
    echo -e "${GREEN}DNS routing enabled${NC}"
  fi
}

remove_hosts_entry() {
  if grep -q "$HOSTS_TAG" /etc/hosts 2>/dev/null; then
    sudo sed -i '' "/${HOSTS_TAG}/d" /etc/hosts
    echo -e "${YELLOW}DNS routing disabled${NC}"
  fi
}

# ─── .env helpers ────────────────────────────────────────

ENV_FILE="${MEMBRAIN_HOME}/.env"

env_get() {
  # Get value of a key from .env (empty string if not found)
  grep -E "^${1}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-
}

env_set() {
  # Set key=value in .env (creates or updates)
  if grep -qE "^${1}=" "$ENV_FILE" 2>/dev/null; then
    sed -i '' "s|^${1}=.*|${1}=${2}|" "$ENV_FILE"
  else
    echo "${1}=${2}" >> "$ENV_FILE"
  fi
}

env_remove() {
  # Remove a key from .env
  sed -i '' "/^${1}=/d" "$ENV_FILE" 2>/dev/null || true
}

profiles_add() {
  # Add a profile to COMPOSE_PROFILES (comma-separated)
  local current
  current=$(env_get "COMPOSE_PROFILES")
  if [ -z "$current" ]; then
    env_set "COMPOSE_PROFILES" "$1"
  elif ! echo ",$current," | grep -q ",$1,"; then
    env_set "COMPOSE_PROFILES" "${current},${1}"
  fi
}

profiles_remove() {
  # Remove a profile from COMPOSE_PROFILES
  local current
  current=$(env_get "COMPOSE_PROFILES")
  # Remove the profile, clean up commas
  local updated
  updated=$(echo "$current" | sed "s/${1}//" | sed 's/,,/,/g' | sed 's/^,//' | sed 's/,$//')
  if [ -z "$updated" ]; then
    env_remove "COMPOSE_PROFILES"
  else
    env_set "COMPOSE_PROFILES" "$updated"
  fi
}

profiles_has() {
  # Check if a profile is in COMPOSE_PROFILES
  local current
  current=$(env_get "COMPOSE_PROFILES")
  echo ",$current," | grep -q ",$1,"
}

step() { echo -e "  $1"; }
info() { echo -e "  ${GREEN}$1${NC}"; }

cmd_status() {
  check_installed
  echo "Membrain Status"
  echo "==============="
  echo ""

  # Health check
  if curl -sf http://localhost:8001/health >/dev/null 2>&1; then
    echo -e "  Gateway:  ${GREEN}healthy${NC}"
  else
    echo -e "  Gateway:  ${RED}not responding${NC}"
  fi

  # DNS routing
  if grep -q "$HOSTS_TAG" /etc/hosts 2>/dev/null; then
    echo -e "  DNS:      ${GREEN}routing through Membrain${NC}"
  else
    echo -e "  DNS:      ${YELLOW}direct (Membrain bypassed)${NC}"
  fi

  echo ""

  # Docker services
  docker compose -f "$COMPOSE_FILE" ps 2>/dev/null || echo -e "  ${RED}Docker services not running${NC}"
}

cmd_logs() {
  check_installed
  docker compose -f "$COMPOSE_FILE" logs -f gateway "$@"
}

cmd_stop() {
  check_installed
  echo "Stopping Membrain..."
  remove_hosts_entry
  docker compose -f "$COMPOSE_FILE" stop
  echo -e "${YELLOW}Membrain stopped. AI traffic goes directly to providers.${NC}"
}

cmd_start() {
  check_installed
  echo "Starting Membrain..."
  docker compose -f "$COMPOSE_FILE" start
  add_hosts_entry

  # Wait for health
  echo -n "Waiting for gateway"
  for i in $(seq 1 30); do
    if curl -sf http://localhost:8001/health >/dev/null 2>&1; then
      echo -e " ${GREEN}ready${NC}"
      return
    fi
    echo -n "."
    sleep 2
  done
  echo -e " ${RED}timeout — check 'membrain logs'${NC}"
}

cmd_update() {
  check_installed
  echo "Updating Membrain..."
  git -C "${MEMBRAIN_HOME}/src" pull --ff-only
  cp "${MEMBRAIN_HOME}/src/deploy/docker-compose.yml" "${MEMBRAIN_HOME}/docker-compose.yml"
  docker compose -f "$COMPOSE_FILE" pull gateway
  docker compose -f "$COMPOSE_FILE" up -d gateway
  echo -e "${GREEN}Updated and restarted.${NC}"
}

cmd_uninstall() {
  check_installed
  echo ""
  echo -e "${RED}This will remove Membrain and all its data.${NC}"
  echo -n "Type 'uninstall' to confirm: "
  read -r confirm
  if [ "$confirm" != "uninstall" ]; then
    echo "Cancelled."
    exit 0
  fi

  echo ""
  echo "Removing Membrain..."

  # 1. Remove CA cert from keychain (before deleting files)
  if [ -f "${MEMBRAIN_HOME}/certs/membrain-ca.pem" ]; then
    sudo security remove-trusted-cert -d "${MEMBRAIN_HOME}/certs/membrain-ca.pem" 2>/dev/null || true
    echo "  Removed CA certificate from keychain"
  fi

  # 2. Stop and remove containers + volumes + images
  docker compose -f "$COMPOSE_FILE" down -v --rmi all 2>/dev/null || true
  echo "  Stopped and removed containers"

  # 3. Remove /etc/hosts entry
  remove_hosts_entry

  # 4. Unload launchd plist
  local plist_path="${HOME}/Library/LaunchAgents/com.membrain.docker.plist"
  if [ -f "$plist_path" ]; then
    launchctl unload "$plist_path" 2>/dev/null || true
    rm -f "$plist_path"
    echo "  Removed auto-start configuration"
  fi

  # 5. Remove installation directory
  rm -rf "$MEMBRAIN_HOME"
  echo "  Removed ~/.membrain"

  # 6. Remove CLI wrapper (this script — must be last)
  sudo rm -f /usr/local/bin/membrain
  echo "  Removed membrain command"

  echo ""
  echo -e "${GREEN}Membrain uninstalled. Your system is restored.${NC}"
}

cmd_enable() {
  check_installed
  local addon="${1:-}"
  case "$addon" in
    ml-search)
      step "Enabling ML Search (semantic embeddings)..."
      profiles_add "ml-search"
      env_set "EMBEDDING_BACKEND" "remote"
      docker compose -f "$COMPOSE_FILE" up -d embedder
      echo -n "  Waiting for embedder"
      for i in $(seq 1 30); do
        if docker compose -f "$COMPOSE_FILE" exec -T embedder python -c "import urllib.request; urllib.request.urlopen('http://localhost:8002/health')" >/dev/null 2>&1; then
          echo -e " ${GREEN}ready${NC}"
          docker compose -f "$COMPOSE_FILE" restart gateway
          info "ML Search enabled. Gateway restarted."
          return
        fi
        echo -n "."
        sleep 3
      done
      echo -e " ${YELLOW}still starting (model download may take a few minutes)${NC}"
      info "ML Search enabled. Run 'membrain logs embedder' to check progress."
      ;;
    litellm)
      step "Enabling LiteLLM (100+ model backends)..."
      env_set "LITELLM" "true"
      docker compose -f "$COMPOSE_FILE" up -d --build gateway
      info "LiteLLM enabled. Gateway rebuilt and restarted."
      ;;
    *)
      echo "Unknown add-on: ${addon}"
      echo ""
      echo "Available add-ons:"
      echo "  ml-search   Semantic knowledge search (sentence-transformers)"
      echo "  litellm     100+ LLM backends via LiteLLM"
      exit 1
      ;;
  esac
}

cmd_disable() {
  check_installed
  local addon="${1:-}"
  case "$addon" in
    ml-search)
      step "Disabling ML Search..."
      profiles_remove "ml-search"
      env_set "EMBEDDING_BACKEND" "local"
      docker compose -f "$COMPOSE_FILE" stop embedder 2>/dev/null || true
      docker compose -f "$COMPOSE_FILE" restart gateway
      info "ML Search disabled. Falling back to text search."
      ;;
    litellm)
      step "Disabling LiteLLM..."
      env_remove "LITELLM"
      docker compose -f "$COMPOSE_FILE" up -d --build gateway
      info "LiteLLM disabled. Gateway rebuilt."
      ;;
    *)
      echo "Unknown add-on: ${addon}"
      echo "Run 'membrain addons' to see available add-ons."
      exit 1
      ;;
  esac
}

cmd_addons() {
  check_installed
  echo "Membrain Add-ons"
  echo "================"
  echo ""

  # ml-search
  if profiles_has "ml-search"; then
    echo -e "  ml-search   ${GREEN}enabled${NC}   Semantic knowledge search"
  else
    echo -e "  ml-search   ${YELLOW}disabled${NC}  Semantic knowledge search"
  fi

  # litellm
  if [ "$(env_get LITELLM)" = "true" ]; then
    echo -e "  litellm     ${GREEN}enabled${NC}   100+ LLM backends"
  else
    echo -e "  litellm     ${YELLOW}disabled${NC}  100+ LLM backends"
  fi

  echo ""
  echo "Enable:  membrain enable <addon>"
  echo "Disable: membrain disable <addon>"
}

cmd_help() {
  echo "Usage: membrain <command>"
  echo ""
  echo "Commands:"
  echo "  status      Check if Membrain is running"
  echo "  logs        Stream gateway logs (Ctrl+C to stop)"
  echo "  start       Start Membrain and enable DNS routing"
  echo "  stop        Stop Membrain and disable DNS routing"
  echo "  update      Pull latest version and restart"
  echo "  addons      List available add-ons and their status"
  echo "  enable      Enable an add-on (e.g. membrain enable ml-search)"
  echo "  disable     Disable an add-on"
  echo "  uninstall   Remove Membrain completely"
  echo "  help        Show this help message"
  echo ""
  echo "Dashboard: http://localhost:8001"
}

case "${1:-help}" in
  status)    cmd_status ;;
  logs)      shift; cmd_logs "$@" ;;
  stop)      cmd_stop ;;
  start)     cmd_start ;;
  update)    cmd_update ;;
  enable)    shift; cmd_enable "$@" ;;
  disable)   shift; cmd_disable "$@" ;;
  addons)    cmd_addons ;;
  uninstall) cmd_uninstall ;;
  help|*)    cmd_help ;;
esac
