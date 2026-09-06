#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if kubectl get namespace ingress-nginx >/dev/null 2>&1; then
  echo "ingress-nginx already installed."
else
  echo "Installing ingress-nginx controller and admission webhook..."
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/cloud/deploy.yaml
fi

kubectl wait --namespace ingress-nginx \
  --for=condition=Available deployment/ingress-nginx-controller \
  --timeout=180s || true

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod -l app.kubernetes.io/component=controller \
  --timeout=180s || true

echo "Ingress-nginx is ready. The admission webhook should now be serving endpoints."
