#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

NAMESPACE="${NAMESPACE:-homelab}"
STOCK_EZ_IMAGE="${STOCK_EZ_IMAGE:-ghcr.io/sushritpasupuleti/stock-ez:latest}"
DASHBOARD_IMAGE="${DASHBOARD_IMAGE:-nginx:alpine}"
PORTAINER_IMAGE="${PORTAINER_IMAGE:-portainer/portainer-ce:latest}"

export NAMESPACE STOCK_EZ_IMAGE DASHBOARD_IMAGE PORTAINER_IMAGE

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

kubectl set image -n "$NAMESPACE" deployment/stock-ez stock-ez="$STOCK_EZ_IMAGE"
kubectl set image -n "$NAMESPACE" deployment/homelab-dashboard homelab-dashboard="$DASHBOARD_IMAGE"
kubectl set image -n "$NAMESPACE" deployment/portainer portainer="$PORTAINER_IMAGE"

render_and_apply "$ROOT_DIR/k8s/stock-ez/configmap.yaml"
render_and_apply "$ROOT_DIR/k8s/dashboard/dashboard.yaml"

kubectl rollout status -n "$NAMESPACE" deployment/stock-ez --timeout=180s
kubectl rollout status -n "$NAMESPACE" deployment/homelab-dashboard --timeout=180s
kubectl rollout status -n "$NAMESPACE" deployment/portainer --timeout=180s

kubectl get pods -n "$NAMESPACE"

echo "Services were updated successfully."
