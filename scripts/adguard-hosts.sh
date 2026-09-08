#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${INGRESS_IP:-}" ]]; then
  RESOLVED_IP="${INGRESS_IP}"
else
  if kubectl get ingress -n homelab homelab-ingress >/dev/null 2>&1; then
    RESOLVED_IP="$(kubectl get ingress -n homelab homelab-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  fi

  if [[ -z "${RESOLVED_IP}" ]]; then
    RESOLVED_IP="$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  fi

  if [[ -z "${RESOLVED_IP}" ]]; then
    echo "Could not determine the ingress IP automatically. Set INGRESS_IP explicitly." >&2
    exit 1
  fi
fi

cat <<EOF
# Add these entries to AdGuard Home > Filters > Hosts or custom upstream config
# Ingress IP: ${RESOLVED_IP}

${RESOLVED_IP} dashboard.homelab.home.arpa
${RESOLVED_IP} stock-ez.homelab.home.arpa
${RESOLVED_IP} open-webui.homelab.home.arpa
${RESOLVED_IP} openserp.homelab.home.arpa
${RESOLVED_IP} hermes.homelab.home.arpa
${RESOLVED_IP} hermes-dashboard.homelab.home.arpa
${RESOLVED_IP} ollama.homelab.home.arpa
${RESOLVED_IP} portainer.homelab.home.arpa
${RESOLVED_IP} grafana.homelab.home.arpa
${RESOLVED_IP} prometheus.homelab.home.arpa
${RESOLVED_IP} torrent.homelab.home.arpa
${RESOLVED_IP} files.homelab.home.arpa
${RESOLVED_IP} homeassistant.homelab.home.arpa
${RESOLVED_IP} media.homelab.home.arpa
${RESOLVED_IP} plex.homelab.home.arpa

# Optional helper entries
${RESOLVED_IP} homelab.home.arpa
EOF
