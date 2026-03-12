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

enable_pf() {
  if [ -f /etc/pf.anchors/membrain ]; then
    sudo pfctl -f /etc/pf.conf 2>/dev/null || true
    sudo pfctl -e 2>/dev/null || true
  fi
}

disable_pf() {
  if [ -f /etc/pf.anchors/membrain ]; then
    sudo rm -f /etc/pf.anchors/membrain
    sudo sed -i '' '/membrain/d' /etc/pf.conf 2>/dev/null || true
    sudo pfctl -f /etc/pf.conf 2>/dev/null || true
    echo -e "${YELLOW}Port forwarding removed${NC}"
  fi
}

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
  enable_pf

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
  git -C "${MEMBRAIN_HOME}/engine" pull --ff-only
  cp "${MEMBRAIN_HOME}/engine/deploy/docker-compose.yml" "${MEMBRAIN_HOME}/docker-compose.yml"
  cp "${MEMBRAIN_HOME}/engine/deploy/Caddyfile" "${MEMBRAIN_HOME}/Caddyfile"
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

  # 3. Remove /etc/hosts entry and pf rules
  remove_hosts_entry
  disable_pf

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

cmd_help() {
  echo "Usage: membrain <command>"
  echo ""
  echo "Commands:"
  echo "  status      Check if Membrain is running"
  echo "  logs        Stream gateway logs (Ctrl+C to stop)"
  echo "  start       Start Membrain and enable DNS routing"
  echo "  stop        Stop Membrain and disable DNS routing"
  echo "  update      Pull latest version and restart"
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
  uninstall) cmd_uninstall ;;
  help|*)    cmd_help ;;
esac
