#!/usr/bin/env bash
set -euo pipefail

if [ -n "${NODE_IP:-}" ]; then
  NODE_IP="$(printf '%s\n' "${NODE_IP}" | tr ' ' '\n' | grep -E '^[0-9]+(\.[0-9]+){3}$' | head -n 1 || printf '%s\n' "${NODE_IP}" | awk '{print $1}')"
elif command -v kubectl >/dev/null 2>&1; then
  INGRESS_IP="$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  if [ -n "${INGRESS_IP}" ]; then
    NODE_IP="${INGRESS_IP}"
  else
    NODE_IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "127.0.0.1")"
    NODE_IP="$(printf '%s\n' "${NODE_IP}" | tr ' ' '\n' | grep -E '^[0-9]+(\.[0-9]+){3}$' | head -n 1 || printf '%s\n' "${NODE_IP}" | awk '{print $1}')"
  fi
else
  NODE_IP="127.0.0.1"
fi

HOST_ALIASES=(
  dashboard.homelab.home.arpa
  portainer.homelab.home.arpa
  stock-ez.homelab.home.arpa
  homeassistant.homelab.home.arpa
  open-webui.homelab.home.arpa
  ollama.homelab.home.arpa
  media.homelab.home.arpa
  plex.homelab.home.arpa
  grafana.homelab.home.arpa
  prometheus.homelab.home.arpa
  torrent.homelab.home.arpa
  files.homelab.home.arpa
)
HOSTS_ENTRY="${NODE_IP} ${HOST_ALIASES[*]}"

if [ "${1:-}" = "--nixos" ] || { [ -f /etc/os-release ] && grep -Eq '^ID=nixos|^ID_LIKE=.*nixos' /etc/os-release; }; then
  if [ "$(id -u)" -ne 0 ]; then
    echo "On NixOS, this script should run as root."
    echo "Use: sudo env NODE_IP=${NODE_IP} ./scripts/update-hosts.sh --nixos"
    exit 1
  fi

  NIXOS_CONF_DIR="/etc/nixos"
  NIX_SNIPPET="{ networking.extraHosts = ''
    ${HOSTS_ENTRY}
  ''; }"

  echo "Copy this into a file like /etc/nixos/homelab-hosts.nix:"
  echo "----------------------------------------------------"
  printf '%s\n' "$NIX_SNIPPET"
  echo "----------------------------------------------------"

  mkdir -p "$NIXOS_CONF_DIR"
  cat > "$NIXOS_CONF_DIR/homelab-hosts.nix" <<EOF
{ networking.extraHosts = ''
  ${HOSTS_ENTRY}
''; }
EOF

  if [ -f "$NIXOS_CONF_DIR/configuration.nix" ] && ! grep -q "homelab-hosts.nix" "$NIXOS_CONF_DIR/configuration.nix"; then
    echo "Add this to /etc/nixos/configuration.nix:"
    echo "  imports = [ ./homelab-hosts.nix ];"
  fi

  echo "Wrote $NIXOS_CONF_DIR/homelab-hosts.nix"
  echo "Then run: sudo nixos-rebuild switch"
  exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must run as root."
  echo "Use: sudo ./scripts/update-hosts.sh"
  exit 1
fi

HOSTS_FILE="/etc/hosts"

if ! touch "$HOSTS_FILE" 2>/dev/null; then
  echo "Unable to write to $HOSTS_FILE. In some environments, /etc/hosts is mounted read-only."
  echo "On NixOS, use: sudo env NODE_IP=${NODE_IP} ./scripts/update-hosts.sh --nixos"
  echo "Run this from the host OS, not a container or VM, or update the file manually."
  exit 1
fi

if grep -qE "dashboard\.homelab\.home\.arpa|portainer\.homelab\.home\.arpa|stock-ez\.homelab\.home\.arpa|homeassistant\.homelab\.home\.arpa|open-webui\.homelab\.home\.arpa|ollama\.homelab\.home\.arpa|media\.homelab\.home\.arpa|plex\.homelab\.home\.arpa|grafana\.homelab\.home\.arpa|prometheus\.homelab\.home\.arpa|torrent\.homelab\.home\.arpa|files\.homelab\.home\.arpa" "$HOSTS_FILE"; then
  tmp_file="$(mktemp)"
  grep -vE "dashboard\.homelab\.home\.arpa|portainer\.homelab\.home\.arpa|stock-ez\.homelab\.home\.arpa|homeassistant\.homelab\.home\.arpa|open-webui\.homelab\.home\.arpa|ollama\.homelab\.home\.arpa|media\.homelab\.home\.arpa|plex\.homelab\.home\.arpa|grafana\.homelab\.home\.arpa|prometheus\.homelab\.home\.arpa|torrent\.homelab\.home\.arpa|files\.homelab\.home\.arpa" "$HOSTS_FILE" > "$tmp_file" || true
  cat "$tmp_file" > "$HOSTS_FILE"
  rm -f "$tmp_file"
fi

printf '\n%s\n' "$HOSTS_ENTRY" >> "$HOSTS_FILE"

echo "Updated /etc/hosts with the homelab entries for $NODE_IP"
