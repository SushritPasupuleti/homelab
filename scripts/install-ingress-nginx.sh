#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

HOST_IP="${HOST_IP:-$(hostname -I 2>/dev/null | awk '{print $1}' || true)}"
if [[ -z "${HOST_IP}" ]]; then
  HOST_IP="$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || true)"
fi
if [[ -z "${HOST_IP}" ]]; then
  echo "ERROR: Unable to detect the host IP. Set HOST_IP to your LAN IP and rerun this script."
  exit 1
fi

if kubectl get namespace ingress-nginx >/dev/null 2>&1; then
  echo "ingress-nginx already installed."
else
  echo "Installing ingress-nginx controller in bare-metal mode for host IP ${HOST_IP}..."
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/baremetal/deploy.yaml
fi

# Use the host IP as an external service IP without binding the ingress pod to the
# node's host ports. This avoids conflicts with any existing ingress controller on
# 80/443 (for example Traefik), which fails scheduling when both try to claim the
# same ports via hostNetwork.
kubectl -n ingress-nginx patch svc ingress-nginx-controller --type='merge' \
  -p "{\"spec\":{\"externalIPs\":[\"${HOST_IP}\"]}}" 2>/dev/null || true

kubectl wait --namespace ingress-nginx \
  --for=condition=Available deployment/ingress-nginx-controller \
  --timeout=180s || true

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod -l app.kubernetes.io/component=controller \
  --timeout=180s || true

echo "Ingress-nginx is ready and is configured to use host IP ${HOST_IP}."
