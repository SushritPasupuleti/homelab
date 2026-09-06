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
  echo "       Ensure your kubeconfig is loaded and the cluster is running before running ./scripts/deploy.sh"
  exit 1
fi

NAMESPACE="${NAMESPACE:-homelab}"
STOCK_EZ_IMAGE="${STOCK_EZ_IMAGE:-ghcr.io/sushritpasupuleti/stock-ez:latest}"
OLLAMA_IMAGE="${OLLAMA_IMAGE:-ollama/ollama:latest}"
DASHBOARD_IMAGE="${DASHBOARD_IMAGE:-glanceapp/glance:latest}"
PORTAINER_IMAGE="${PORTAINER_IMAGE:-portainer/portainer-ce:latest}"
HOME_ASSISTANT_IMAGE="${HOME_ASSISTANT_IMAGE:-ghcr.io/home-assistant/home-assistant:stable}"
OPEN_WEBUI_IMAGE="${OPEN_WEBUI_IMAGE:-ghcr.io/open-webui/open-webui:main}"
PROMETHEUS_IMAGE="${PROMETHEUS_IMAGE:-prom/prometheus:v2.53.2}"
GRAFANA_IMAGE="${GRAFANA_IMAGE:-grafana/grafana:11.1.5}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-$(openssl rand -base64 24 | tr -d '\n' | tr '+/' '-_')}"
QBITTORRENT_IMAGE="${QBITTORRENT_IMAGE:-lscr.io/linuxserver/qbittorrent:latest}"
FILEBROWSER_IMAGE="${FILEBROWSER_IMAGE:-filebrowser/filebrowser:latest}"
PORTAINER_ADMIN_USER="${PORTAINER_ADMIN_USER:-admin}"
DCGM_EXPORTER_SCRAPE=""
PORTAINER_ADMIN_PASSWORD="${PORTAINER_ADMIN_PASSWORD:-$(openssl rand -base64 24 | tr -d '\n' | tr '+/' '-_')}"
QBITTORRENT_USERNAME="${QBITTORRENT_USERNAME:-admin}"
QBITTORRENT_PASSWORD="${QBITTORRENT_PASSWORD:-$(openssl rand -base64 24 | tr -d '\n' | tr '+/' '-_')}"
FILEBROWSER_USERNAME="${FILEBROWSER_USERNAME:-admin}"
FILEBROWSER_PASSWORD="${FILEBROWSER_PASSWORD:-$(openssl rand -base64 24 | tr -d '\n' | tr '+/' '-_')}"
STOCK_EZ_HOST="${STOCK_EZ_HOST:-stock-ez.homelab.home.arpa}"
DASHBOARD_HOST="${DASHBOARD_HOST:-dashboard.homelab.home.arpa}"
PORTAINER_HOST="${PORTAINER_HOST:-portainer.homelab.home.arpa}"
HOMEASSISTANT_HOST="${HOMEASSISTANT_HOST:-homeassistant.homelab.home.arpa}"
OPEN_WEBUI_HOST="${OPEN_WEBUI_HOST:-open-webui.homelab.home.arpa}"
GRAFANA_HOST="${GRAFANA_HOST:-grafana.homelab.home.arpa}"
PROMETHEUS_HOST="${PROMETHEUS_HOST:-prometheus.homelab.home.arpa}"
QBITTORRENT_HOST="${QBITTORRENT_HOST:-torrent.homelab.home.arpa}"
FILEBROWSER_HOST="${FILEBROWSER_HOST:-files.homelab.home.arpa}"
JELLYFIN_HOST="${JELLYFIN_HOST:-media.homelab.home.arpa}"
PLEX_HOST="${PLEX_HOST:-plex.homelab.home.arpa}"
DOMAIN="${DOMAIN:-homelab.home.arpa}"
METALLB_ENABLED="${METALLB_ENABLED:-true}"
METALLB_IP_POOL="${METALLB_IP_POOL:-192.168.1.200-192.168.1.249}"
HOMEPAGE_ALLOWED_HOSTS="${HOMEPAGE_ALLOWED_HOSTS:-dashboard.homelab.home.arpa,stock-ez.homelab.home.arpa,portainer.homelab.home.arpa,homeassistant.homelab.home.arpa,open-webui.homelab.home.arpa,grafana.homelab.home.arpa,prometheus.homelab.home.arpa,torrent.homelab.home.arpa,files.homelab.home.arpa,ollama.homelab.home.arpa,media.homelab.home.arpa,plex.homelab.home.arpa,localhost,127.0.0.1,192.168.1.201,192.168.1.202,192.168.1.203,192.168.1.205,192.168.1.207,192.168.1.208,192.168.1.209,192.168.1.210,192.168.1.213,192.168.1.214,192.168.1.6,::1}"
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
  echo "No NVIDIA GPU detected on the host; forcing Ollama to CPU mode."
  OLLAMA_USE_NVIDIA="false"
fi

if [ "${OLLAMA_USE_NVIDIA}" = "true" ] && [ -z "${NODE_GPU_ALLOCATABLE}" ]; then
  echo "Kubernetes node reports no allocatable nvidia.com/gpu; forcing Ollama to CPU mode."
  OLLAMA_USE_NVIDIA="false"
fi

if [ "${OLLAMA_USE_NVIDIA}" = "true" ]; then
  DCGM_EXPORTER_SCRAPE='
      - job_name: "dcgm-exporter"
        static_configs:
          - targets: ["dcgm-exporter:9400"]'
else
  DCGM_EXPORTER_SCRAPE=""
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

export NAMESPACE STOCK_EZ_IMAGE OLLAMA_IMAGE DASHBOARD_IMAGE PORTAINER_IMAGE HOME_ASSISTANT_IMAGE OPEN_WEBUI_IMAGE PROMETHEUS_IMAGE GRAFANA_IMAGE GRAFANA_ADMIN_USER GRAFANA_ADMIN_PASSWORD QBITTORRENT_IMAGE FILEBROWSER_IMAGE PORTAINER_ADMIN_USER PORTAINER_ADMIN_PASSWORD QBITTORRENT_USERNAME QBITTORRENT_PASSWORD FILEBROWSER_USERNAME FILEBROWSER_PASSWORD STOCK_EZ_HOST DASHBOARD_HOST PORTAINER_HOST HOMEASSISTANT_HOST OPEN_WEBUI_HOST GRAFANA_HOST PROMETHEUS_HOST QBITTORRENT_HOST FILEBROWSER_HOST JELLYFIN_HOST PLEX_HOST DOMAIN METALLB_ENABLED METALLB_IP_POOL HOMEPAGE_ALLOWED_HOSTS HOMELAB_SECRET_FILE OLLAMA_USE_NVIDIA OLLAMA_GPU_COUNT OLLAMA_NUM_GPU OLLAMA_BACKEND_MODE OLLAMA_RUNTIME_CLASS OLLAMA_NVIDIA_VISIBLE_DEVICES OLLAMA_NVIDIA_DRIVER_CAPABILITIES OLLAMA_GPU_REQUEST_KEY OLLAMA_GPU_LIMIT_KEY DCGM_EXPORTER_SCRAPE

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
  echo "Portainer: http://$PORTAINER_HOST or http://<node-ip>:30900"
  echo "  Username: $PORTAINER_ADMIN_USER"
  echo "  Password: $PORTAINER_ADMIN_PASSWORD"
  echo "Grafana: http://$GRAFANA_HOST"
  echo "  Username: $GRAFANA_ADMIN_USER"
  echo "  Password: $GRAFANA_ADMIN_PASSWORD"
  echo "Prometheus: http://$PROMETHEUS_HOST"
  echo "qBittorrent: http://$QBITTORRENT_HOST or http://<node-ip>:8080"
  echo "  Username: $QBITTORRENT_USERNAME"
  echo "  Password: $QBITTORRENT_PASSWORD"
  echo "File Browser: http://$FILEBROWSER_HOST or http://<node-ip>:80"
  echo "  Username: $FILEBROWSER_USERNAME"
  echo "  Password: $FILEBROWSER_PASSWORD"
  echo "  Secret file: $HOMELAB_SECRET_FILE"
  echo "==========================="
  echo
}

initialize_portainer_admin() {
  local node_ip
  node_ip="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null | awk '{print $1}' || true)"
  if [ -z "$node_ip" ]; then
    echo "Unable to determine the cluster node IP; Portainer admin init will need to be completed via the web UI."
    return 0
  fi

  local portainer_node_port
  portainer_node_port="$(kubectl get svc -n "$NAMESPACE" portainer -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "30900")"

  if ! curl -fsS "http://${node_ip}:${portainer_node_port}/api/health" >/dev/null 2>&1; then
    echo "Portainer is not ready yet; skipping admin initialization until the service is reachable."
    return 0
  fi

  if curl -fsS -X POST "http://${node_ip}:${portainer_node_port}/api/users/admin/init" \
      -H 'Content-Type: application/json' \
      --data "{\"Username\":\"${PORTAINER_ADMIN_USER}\",\"Password\":\"${PORTAINER_ADMIN_PASSWORD}\"}" >/dev/null 2>&1; then
    echo "Portainer admin initialized successfully."
  else
    echo "Portainer admin was already initialized or is not accepting the bootstrap request yet."
  fi
}

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
marker = "      # DCGM_EXPORTER_SCRAPE"
value = os.environ.get("DCGM_EXPORTER_SCRAPE", "")
if value:
    text = text.replace(marker, value.rstrip())
else:
    text = text.replace(marker + "\n", "")
print(text)
PY
}

reload_runtime_config() {
  kubectl rollout restart -n "$NAMESPACE" deployment/prometheus deployment/grafana deployment/homelab-dashboard >/dev/null 2>&1 || true
  kubectl rollout status -n "$NAMESPACE" deployment/prometheus --timeout=180s || true
  kubectl rollout status -n "$NAMESPACE" deployment/grafana --timeout=180s || true
  kubectl rollout status -n "$NAMESPACE" deployment/homelab-dashboard --timeout=180s || true
}

if [ "${OLLAMA_USE_NVIDIA}" = "true" ]; then
  echo "NVIDIA GPU detected on the host; enabling GPU access for Ollama."
  if ! command -v nvidia-container-runtime >/dev/null 2>&1 && [ ! -x /usr/bin/nvidia-container-runtime ]; then
    echo "WARNING: NVIDIA GPU is present, but the containerd runtime is not configured for Kubernetes."
    echo "         Run the host-side fix from docs/nvidia-gpu-troubleshooting.md before expecting GPU metrics or Ollama GPU mode to work."
    echo "         Required commands:"
    echo "           sudo env PATH=\"/run/current-system/sw/bin:$PATH\" nvidia-ctk runtime configure --runtime=containerd --set-as-default"
    echo "           sudo systemctl restart containerd && sudo systemctl restart k3s"
  fi

  if ! kubectl get runtimeclass nvidia >/dev/null 2>&1; then
    kubectl create runtimeclass nvidia --handler=nvidia --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  fi

  if ! kubectl get daemonset -n kube-system nvidia-device-plugin-daemonset >/dev/null 2>&1; then
    kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.2/nvidia-device-plugin.yml >/dev/null
  fi
fi

kubectl apply -f "$ROOT_DIR/k8s/namespace.yaml"

if [ "${METALLB_ENABLED}" = "true" ]; then
  METALLB_IP_POOL="$METALLB_IP_POOL" "$ROOT_DIR/scripts/install-metallb.sh"
fi

if ! kubectl get deployment -n ingress-nginx ingress-nginx-controller >/dev/null 2>&1; then
  "$ROOT_DIR/scripts/install-ingress-nginx.sh"
fi

if [[ "${STOCK_EZ_IMAGE:-}" == *":local" ]] || [[ "${STOCK_EZ_IMAGE:-}" == "stock-ez" ]]; then
  echo "Importing local Stock-EZ image into the cluster runtime before deployment..."
  "$ROOT_DIR/scripts/load-local-image.sh"
fi

render_and_apply "$ROOT_DIR/k8s/stock-ez/configmap.yaml"
render_and_apply "$ROOT_DIR/k8s/stock-ez/deployment.yaml"
render_and_apply "$ROOT_DIR/k8s/ollama/ollama.yaml"
render_and_apply "$ROOT_DIR/k8s/open-webui/open-webui.yaml"
render_and_apply "$ROOT_DIR/k8s/home-assistant/home-assistant.yaml"
render_and_apply "$ROOT_DIR/k8s/dashboard/configmap.yaml"
render_and_apply "$ROOT_DIR/k8s/dashboard/dashboard.yaml"
render_and_apply "$ROOT_DIR/k8s/monitoring/monitoring.yaml"
if [ "${OLLAMA_USE_NVIDIA}" = "true" ]; then
  render_and_apply "$ROOT_DIR/k8s/monitoring/dcgm-exporter.yaml"
else
  kubectl delete -f "$ROOT_DIR/k8s/monitoring/dcgm-exporter.yaml" --ignore-not-found=true >/dev/null 2>&1 || true
fi
render_and_apply "$ROOT_DIR/k8s/media/jellyfin.yaml"
render_and_apply "$ROOT_DIR/k8s/media/minidlna.yaml"
render_and_apply "$ROOT_DIR/k8s/media/qbittorrent.yaml"
render_and_apply "$ROOT_DIR/k8s/media/plex.yaml"
render_and_apply "$ROOT_DIR/k8s/ingress/ingress.yaml"
render_and_apply "$ROOT_DIR/k8s/portainer/portainer.yaml"

kubectl rollout status -n "$NAMESPACE" deployment/stock-ez --timeout=180s || true
kubectl rollout status -n "$NAMESPACE" deployment/ollama --timeout=180s || true
kubectl rollout status -n "$NAMESPACE" deployment/open-webui --timeout=180s || true
kubectl rollout status -n "$NAMESPACE" deployment/home-assistant --timeout=180s || true
kubectl rollout status -n "$NAMESPACE" deployment/jellyfin --timeout=180s || true
kubectl rollout status -n "$NAMESPACE" deployment/minidlna --timeout=180s || true
kubectl rollout status -n "$NAMESPACE" deployment/qbittorrent --timeout=180s || true
kubectl rollout status -n "$NAMESPACE" deployment/plex --timeout=180s || true
kubectl rollout status -n "$NAMESPACE" deployment/portainer --timeout=180s || true

reload_runtime_config

kubectl get svc,ingress,pvc -n "$NAMESPACE"

write_homelab_secrets
initialize_portainer_admin
log_homelab_credentials

echo "Deployment complete. Accessible URLs will be similar to:"
echo "  http://$STOCK_EZ_HOST"
echo "  http://$DASHBOARD_HOST"
echo "  http://$OPEN_WEBUI_HOST"
echo "  http://$PORTAINER_HOST"
echo "  http://$HOMEASSISTANT_HOST"
echo "  http://$QBITTORRENT_HOST"
echo "  http://$FILEBROWSER_HOST"
echo "  http://$JELLYFIN_HOST"
echo "  http://$PLEX_HOST"
