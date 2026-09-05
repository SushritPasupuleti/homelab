#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

NAMESPACE="${NAMESPACE:-homelab}"
STOCK_EZ_IMAGE="${STOCK_EZ_IMAGE:-ghcr.io/sushritpasupuleti/stock-ez:latest}"
OLLAMA_IMAGE="${OLLAMA_IMAGE:-ollama/ollama:latest}"
DASHBOARD_IMAGE="${DASHBOARD_IMAGE:-nginx:alpine}"
PORTAINER_IMAGE="${PORTAINER_IMAGE:-portainer/portainer-ce:latest}"
STOCK_EZ_HOST="${STOCK_EZ_HOST:-stock-ez.homelab.local}"
DASHBOARD_HOST="${DASHBOARD_HOST:-dashboard.homelab.local}"
PORTAINER_HOST="${PORTAINER_HOST:-portainer.homelab.local}"
DOMAIN="${DOMAIN:-homelab.local}"

export NAMESPACE STOCK_EZ_IMAGE OLLAMA_IMAGE DASHBOARD_IMAGE PORTAINER_IMAGE STOCK_EZ_HOST DASHBOARD_HOST PORTAINER_HOST DOMAIN

render_and_apply() {
  local file="$1"
  python3 - "$file" <<'PY' | kubectl apply -f -
import os
import sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text()
for key, value in os.environ.items():
    text = text.replace(f"${{{key}}}", value)
print(text)
PY
}

kubectl apply -f "$ROOT_DIR/k8s/namespace.yaml"
render_and_apply "$ROOT_DIR/k8s/stock-ez/configmap.yaml"
render_and_apply "$ROOT_DIR/k8s/stock-ez/deployment.yaml"
render_and_apply "$ROOT_DIR/k8s/ollama/ollama.yaml"
render_and_apply "$ROOT_DIR/k8s/dashboard/dashboard.yaml"
render_and_apply "$ROOT_DIR/k8s/ingress/ingress.yaml"
render_and_apply "$ROOT_DIR/k8s/portainer/portainer.yaml"

kubectl rollout status -n "$NAMESPACE" deployment/stock-ez --timeout=180s || true
kubectl rollout status -n "$NAMESPACE" deployment/ollama --timeout=180s || true
kubectl rollout status -n "$NAMESPACE" deployment/homelab-dashboard --timeout=180s || true
kubectl rollout status -n "$NAMESPACE" deployment/portainer --timeout=180s || true

kubectl get svc,ingress,pvc -n "$NAMESPACE"

echo "Deployment complete. Accessible URLs will be similar to:"
echo "  http://$STOCK_EZ_HOST"
echo "  http://$DASHBOARD_HOST"
echo "  http://$PORTAINER_HOST"
