#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v kubectl >/dev/null 2>&1 || ! kubectl cluster-info >/dev/null 2>&1; then
  echo "A reachable Kubernetes cluster is required to deploy Portfolio Puffin." >&2
  exit 1
fi
if ! kubectl get secret -n homelab homelab-wildcard-tls >/dev/null 2>&1; then
  echo "The HTTPS certificate is not installed. Run ./scripts/setup-homelab-tls.sh first." >&2
  exit 1
fi

PORTFOLIO_PUFFIN_API_IMAGE="${PORTFOLIO_PUFFIN_API_IMAGE:-portfolio-puffin-api:local}"
PORTFOLIO_PUFFIN_WEB_IMAGE="${PORTFOLIO_PUFFIN_WEB_IMAGE:-portfolio-puffin-web:local}"
PORTFOLIO_PUFFIN_LLM_BASE_URL="${PORTFOLIO_PUFFIN_LLM_BASE_URL:-http://ollama.homelab.svc.cluster.local:11434}"
PORTFOLIO_PUFFIN_LLM_MODEL="${PORTFOLIO_PUFFIN_LLM_MODEL:-gemma4:e2b}"
export PORTFOLIO_PUFFIN_API_IMAGE PORTFOLIO_PUFFIN_WEB_IMAGE
export PORTFOLIO_PUFFIN_LLM_BASE_URL PORTFOLIO_PUFFIN_LLM_MODEL

"$ROOT_DIR/scripts/build-portfolio-puffin.sh"
kubectl apply -f "$ROOT_DIR/k8s/namespace.yaml"

python3 - "$ROOT_DIR/k8s/portfolio/portfolio.yaml" <<'PY' | kubectl apply -f -
import os
import sys
from pathlib import Path

manifest = Path(sys.argv[1]).read_text()
for key in (
    "PORTFOLIO_PUFFIN_API_IMAGE",
    "PORTFOLIO_PUFFIN_WEB_IMAGE",
    "PORTFOLIO_PUFFIN_LLM_BASE_URL",
    "PORTFOLIO_PUFFIN_LLM_MODEL",
):
    manifest = manifest.replace(f"${{{key}}}", os.environ[key])
print(manifest)
PY

kubectl apply -f "$ROOT_DIR/k8s/ingress/ingress.yaml"
kubectl rollout restart -n homelab deployment/portfolio-puffin-api deployment/portfolio-puffin-web
kubectl rollout status -n homelab deployment/portfolio-puffin-api --timeout=180s
kubectl rollout status -n homelab deployment/portfolio-puffin-web --timeout=180s
kubectl get pods,svc -n homelab -l 'app in (portfolio-puffin-api,portfolio-puffin-web)'
kubectl get ingress -n homelab homelab-ingress
