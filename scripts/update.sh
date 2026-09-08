#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl is not installed or not on PATH."
  exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "ERROR: Kubernetes cluster is not reachable from this machine."
  echo "       Ensure your kubeconfig is loaded and the cluster is running before running ./scripts/update.sh"
  exit 1
fi

NAMESPACE="${NAMESPACE:-homelab}"
STOCK_EZ_IMAGE="${STOCK_EZ_IMAGE:-ghcr.io/sushritpasupuleti/stock-ez:latest}"
OLLAMA_IMAGE="${OLLAMA_IMAGE:-ollama/ollama:latest}"
DASHBOARD_IMAGE="${DASHBOARD_IMAGE:-glanceapp/glance:latest}"
PORTAINER_IMAGE="${PORTAINER_IMAGE:-portainer/portainer-ce:latest}"
HOME_ASSISTANT_IMAGE="${HOME_ASSISTANT_IMAGE:-ghcr.io/home-assistant/home-assistant:stable}"
OPEN_WEBUI_IMAGE="${OPEN_WEBUI_IMAGE:-ghcr.io/open-webui/open-webui:main}"
OPENSERP_IMAGE="${OPENSERP_IMAGE:-karust/openserp:latest}"
HERMES_IMAGE="${HERMES_IMAGE:-nousresearch/hermes-agent:latest}"
PROMETHEUS_IMAGE="${PROMETHEUS_IMAGE:-prom/prometheus:v2.53.2}"
GRAFANA_IMAGE="${GRAFANA_IMAGE:-grafana/grafana:11.1.5}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-$(openssl rand -base64 24 | tr -d '\n' | tr '+/' '-_')}"
QBITTORRENT_IMAGE="${QBITTORRENT_IMAGE:-lscr.io/linuxserver/qbittorrent:latest}"
FILEBROWSER_IMAGE="${FILEBROWSER_IMAGE:-filebrowser/filebrowser:latest}"
PORTAINER_ADMIN_USER="${PORTAINER_ADMIN_USER:-admin}"
PORTAINER_ADMIN_PASSWORD="${PORTAINER_ADMIN_PASSWORD:-$(openssl rand -base64 24 | tr -d '\n' | tr '+/' '-_')}"
QBITTORRENT_USERNAME="${QBITTORRENT_USERNAME:-admin}"
QBITTORRENT_PASSWORD="${QBITTORRENT_PASSWORD:-$(openssl rand -base64 24 | tr -d '\n' | tr '+/' '-_')}"
FILEBROWSER_USERNAME="${FILEBROWSER_USERNAME:-admin}"
FILEBROWSER_PASSWORD="${FILEBROWSER_PASSWORD:-$(openssl rand -base64 24 | tr -d '\n' | tr '+/' '-_')}"
OPENSERP_HOST="${OPENSERP_HOST:-openserp.homelab.home.arpa}"
HERMES_HOST="${HERMES_HOST:-hermes.homelab.home.arpa}"
HERMES_DASHBOARD_HOST="${HERMES_DASHBOARD_HOST:-hermes-dashboard.homelab.home.arpa}"
HOMELAB_SECRET_FILE="${HOMELAB_SECRET_FILE:-$ROOT_DIR/.homelab-secrets.env}"

GPU_DETECTED="$(if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then echo true; elif [ -e /dev/nvidiactl ] || ls /dev/nvidia* >/dev/null 2>&1 2>/dev/null; then echo true; else echo false; fi)"
NODE_GPU_ALLOCATABLE=""
if kubectl get nodes -o jsonpath='{range .items[*]}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' >/dev/null 2>&1; then
  NODE_GPU_ALLOCATABLE="$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' 2>/dev/null | awk 'BEGIN {found=0} $1 ~ /^[0-9]+$/ && $1 > 0 {print $1; found=1} END {if (!found) exit 0}' || true)"
fi
OLLAMA_USE_NVIDIA="${OLLAMA_USE_NVIDIA:-$GPU_DETECTED}"
OLLAMA_GPU_COUNT="${OLLAMA_GPU_COUNT:-1}"
OLLAMA_BACKEND_MODE="cpu"
OLLAMA_NUM_GPU="0"

if [ "${OLLAMA_USE_NVIDIA}" = "true" ] && [ "${GPU_DETECTED}" != "true" ]; then
  OLLAMA_USE_NVIDIA="false"
fi

if [ "${OLLAMA_USE_NVIDIA}" = "true" ] && [ -z "${NODE_GPU_ALLOCATABLE}" ]; then
  OLLAMA_USE_NVIDIA="false"
fi

if [ "${OLLAMA_USE_NVIDIA}" = "true" ]; then
  OLLAMA_RUNTIME_CLASS="nvidia"
  OLLAMA_NVIDIA_VISIBLE_DEVICES="all"
  OLLAMA_NVIDIA_DRIVER_CAPABILITIES="compute,utility"
  OLLAMA_GPU_COUNT="${OLLAMA_GPU_COUNT:-1}"
  OLLAMA_GPU_REQUEST_KEY="nvidia.com/gpu: \"${OLLAMA_GPU_COUNT}\""
  OLLAMA_GPU_LIMIT_KEY="nvidia.com/gpu: \"${OLLAMA_GPU_COUNT}\""
  OLLAMA_NUM_GPU="${OLLAMA_GPU_COUNT}"
  OLLAMA_BACKEND_MODE="gpu"
else
  OLLAMA_RUNTIME_CLASS=""
  OLLAMA_NVIDIA_VISIBLE_DEVICES=""
  OLLAMA_NVIDIA_DRIVER_CAPABILITIES=""
  OLLAMA_GPU_COUNT="0"
  OLLAMA_GPU_REQUEST_KEY="nvidia.com/gpu: \"0\""
  OLLAMA_GPU_LIMIT_KEY="nvidia.com/gpu: \"0\""
  OLLAMA_NUM_GPU="0"
  OLLAMA_BACKEND_MODE="cpu"
fi

export NAMESPACE STOCK_EZ_IMAGE OLLAMA_IMAGE DASHBOARD_IMAGE PORTAINER_IMAGE HOME_ASSISTANT_IMAGE OPEN_WEBUI_IMAGE OPENSERP_IMAGE HERMES_IMAGE PROMETHEUS_IMAGE GRAFANA_IMAGE GRAFANA_ADMIN_USER GRAFANA_ADMIN_PASSWORD QBITTORRENT_IMAGE FILEBROWSER_IMAGE PORTAINER_ADMIN_USER PORTAINER_ADMIN_PASSWORD QBITTORRENT_USERNAME QBITTORRENT_PASSWORD FILEBROWSER_USERNAME FILEBROWSER_PASSWORD OPENSERP_HOST HERMES_HOST HERMES_DASHBOARD_HOST HOMELAB_SECRET_FILE OLLAMA_USE_NVIDIA OLLAMA_GPU_COUNT OLLAMA_NUM_GPU OLLAMA_BACKEND_MODE OLLAMA_RUNTIME_CLASS OLLAMA_NVIDIA_VISIBLE_DEVICES OLLAMA_NVIDIA_DRIVER_CAPABILITIES OLLAMA_GPU_REQUEST_KEY OLLAMA_GPU_LIMIT_KEY

render_and_apply() {
  local file="$1"
  python3 - "$file" <<'PY' | kubectl apply -f -
import os
import sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text()
for key, value in sorted(os.environ.items()):
    text = text.replace(f"${{{key}}}", value)
print(text)
PY
}

write_homelab_secrets() {
  mkdir -p "$(dirname "$HOMELAB_SECRET_FILE")"
  cat > "$HOMELAB_SECRET_FILE" <<EOF
# Local-only credentials for the homelab stack. This file is gitignored.
PORTAINER_ADMIN_USER=${PORTAINER_ADMIN_USER}
PORTAINER_ADMIN_PASSWORD=${PORTAINER_ADMIN_PASSWORD}
GRAFANA_ADMIN_USER=${GRAFANA_ADMIN_USER}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
QBITTORRENT_USERNAME=${QBITTORRENT_USERNAME}
QBITTORRENT_PASSWORD=${QBITTORRENT_PASSWORD}
FILEBROWSER_USERNAME=${FILEBROWSER_USERNAME}
FILEBROWSER_PASSWORD=${FILEBROWSER_PASSWORD}
EOF
  chmod 600 "$HOMELAB_SECRET_FILE"
}

log_homelab_credentials() {
  echo
  echo "=== Homelab credentials ==="
  echo "Portainer: http://portainer.homelab.home.arpa"
  echo "  Username: $PORTAINER_ADMIN_USER"
  echo "  Password: $PORTAINER_ADMIN_PASSWORD"
  echo "Grafana: http://grafana.homelab.home.arpa"
  echo "  Username: $GRAFANA_ADMIN_USER"
  echo "  Password: $GRAFANA_ADMIN_PASSWORD"
  echo "Prometheus: http://prometheus.homelab.home.arpa"
  echo "OpenSERP: http://$OPENSERP_HOST"
  echo "  API docs: http://$OPENSERP_HOST/docs"
  echo "Hermes: http://$HERMES_HOST"
  echo "  Dashboard: http://$HERMES_DASHBOARD_HOST"
  echo "qBittorrent: http://torrent.homelab.home.arpa"
  echo "  Username: $QBITTORRENT_USERNAME"
  echo "  Password: $QBITTORRENT_PASSWORD"
  echo "File Browser: http://files.homelab.home.arpa"
  echo "  Username: $FILEBROWSER_USERNAME"
  echo "  Password: $FILEBROWSER_PASSWORD"
  echo "  Secret file: $HOMELAB_SECRET_FILE"
  echo "==========================="
  echo
}

kubectl set image -n "$NAMESPACE" deployment/stock-ez stock-ez="$STOCK_EZ_IMAGE" || true
kubectl set image -n "$NAMESPACE" deployment/ollama ollama="$OLLAMA_IMAGE" || true
kubectl set image -n "$NAMESPACE" deployment/homelab-dashboard homelab-dashboard="$DASHBOARD_IMAGE" || true
kubectl set image -n "$NAMESPACE" deployment/portainer portainer="$PORTAINER_IMAGE" || true
kubectl set image -n "$NAMESPACE" deployment/home-assistant home-assistant="$HOME_ASSISTANT_IMAGE" || true
kubectl set image -n "$NAMESPACE" deployment/open-webui open-webui="$OPEN_WEBUI_IMAGE" || true
kubectl set image -n "$NAMESPACE" deployment/openserp openserp="$OPENSERP_IMAGE" || true
kubectl set image -n "$NAMESPACE" deployment/hermes hermes="$HERMES_IMAGE" || true
kubectl set image -n "$NAMESPACE" deployment/prometheus prometheus="$PROMETHEUS_IMAGE" || true
kubectl set image -n "$NAMESPACE" deployment/grafana grafana="$GRAFANA_IMAGE" || true
kubectl set image -n "$NAMESPACE" deployment/qbittorrent qbittorrent="$QBITTORRENT_IMAGE" || true
kubectl set image -n "$NAMESPACE" deployment/filebrowser filebrowser="$FILEBROWSER_IMAGE" || true

render_and_apply "$ROOT_DIR/k8s/stock-ez/configmap.yaml"
render_and_apply "$ROOT_DIR/k8s/ollama/ollama.yaml"
render_and_apply "$ROOT_DIR/k8s/open-webui/open-webui.yaml"
render_and_apply "$ROOT_DIR/k8s/openserp/openserp.yaml"
render_and_apply "$ROOT_DIR/k8s/hermes/hermes.yaml"
render_and_apply "$ROOT_DIR/k8s/dashboard/configmap.yaml"
render_and_apply "$ROOT_DIR/k8s/dashboard/dashboard.yaml"
render_and_apply "$ROOT_DIR/k8s/monitoring/monitoring.yaml"
render_and_apply "$ROOT_DIR/k8s/home-assistant/home-assistant.yaml"
render_and_apply "$ROOT_DIR/k8s/media/qbittorrent.yaml"
render_and_apply "$ROOT_DIR/k8s/media/filebrowser.yaml"
render_and_apply "$ROOT_DIR/k8s/portainer/portainer.yaml"

kubectl rollout status -n "$NAMESPACE" deployment/stock-ez --timeout=180s || true
kubectl rollout status -n "$NAMESPACE" deployment/ollama --timeout=180s || true
kubectl rollout status -n "$NAMESPACE" deployment/open-webui --timeout=180s || true
kubectl rollout status -n "$NAMESPACE" deployment/openserp --timeout=180s || true
kubectl rollout status -n "$NAMESPACE" deployment/hermes --timeout=180s || true
kubectl rollout status -n "$NAMESPACE" deployment/homelab-dashboard --timeout=180s || true
kubectl rollout status -n "$NAMESPACE" deployment/prometheus --timeout=180s || true
kubectl rollout status -n "$NAMESPACE" deployment/grafana --timeout=180s || true
kubectl rollout status -n "$NAMESPACE" deployment/qbittorrent --timeout=180s || true
kubectl rollout status -n "$NAMESPACE" deployment/filebrowser --timeout=180s || true
kubectl rollout status -n "$NAMESPACE" deployment/portainer --timeout=180s || true
kubectl rollout status -n "$NAMESPACE" deployment/home-assistant --timeout=180s || true

write_homelab_secrets
log_homelab_credentials

kubectl get pods -n "$NAMESPACE"

echo "Services were updated successfully."
