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

OLLAMA_ENABLED="${OLLAMA_ENABLED:-false}"
UNSLOTH_ENABLED="${UNSLOTH_ENABLED:-true}"
GPU_SERVICE="${GPU_SERVICE:-unsloth}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --disable-ollama|--ollama-disabled)
      OLLAMA_ENABLED="false"
      ;;
    --enable-ollama)
      OLLAMA_ENABLED="true"
      ;;
    --disable-unsloth|--unsloth-disabled)
      UNSLOTH_ENABLED="false"
      ;;
    --enable-unsloth)
      UNSLOTH_ENABLED="true"
      ;;
    --gpu-service)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --gpu-service. Use ollama, unsloth, none, or auto."
        exit 1
      fi
      GPU_SERVICE="$2"
      shift
      ;;
    --gpu-service=*)
      GPU_SERVICE="${1#*=}"
      ;;
    --help|-h)
      echo "Usage: ./scripts/deploy.sh [--disable-ollama|--enable-ollama] [--disable-unsloth|--enable-unsloth] [--gpu-service ollama|unsloth|none|auto]"
      echo "       or: OLLAMA_ENABLED=false UNSLOTH_ENABLED=false GPU_SERVICE=unsloth ./scripts/deploy.sh"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Use --help for usage."
      exit 1
      ;;
  esac
  shift
done

GPU_SERVICE="${GPU_SERVICE,,}"
case "$GPU_SERVICE" in
  ollama|unsloth|none|auto) ;;
  *)
    echo "Unsupported GPU service: $GPU_SERVICE"
    echo "Use one of: ollama, unsloth, none, auto"
    exit 1
    ;;
esac

export OLLAMA_ENABLED UNSLOTH_ENABLED GPU_SERVICE

NAMESPACE="${NAMESPACE:-homelab}"
STOCK_EZ_IMAGE="${STOCK_EZ_IMAGE:-ghcr.io/sushritpasupuleti/stock-ez:latest}"
OLLAMA_IMAGE="${OLLAMA_IMAGE:-ollama/ollama:latest}"
DASHBOARD_IMAGE="${DASHBOARD_IMAGE:-glanceapp/glance:latest}"
PORTAINER_IMAGE="${PORTAINER_IMAGE:-portainer/portainer-ce:latest}"
HOME_ASSISTANT_IMAGE="${HOME_ASSISTANT_IMAGE:-ghcr.io/home-assistant/home-assistant:stable}"
OPEN_WEBUI_IMAGE="${OPEN_WEBUI_IMAGE:-ghcr.io/open-webui/open-webui:main}"
UNSLOTH_IMAGE="${UNSLOTH_IMAGE:-unsloth/unsloth:latest}"
OPENSERP_IMAGE="${OPENSERP_IMAGE:-karust/openserp:latest}"
HERMES_IMAGE="${HERMES_IMAGE:-nousresearch/hermes-agent:latest}"
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
OPENSERP_HOST="${OPENSERP_HOST:-openserp.homelab.home.arpa}"
HERMES_HOST="${HERMES_HOST:-hermes.homelab.home.arpa}"
HERMES_DASHBOARD_HOST="${HERMES_DASHBOARD_HOST:-hermes-dashboard.homelab.home.arpa}"
UNSLOTH_HOST="${UNSLOTH_HOST:-unsloth.homelab.home.arpa}"
UNSLOTH_STUDIO_HOST="${UNSLOTH_STUDIO_HOST:-unsloth-studio.homelab.home.arpa}"
UNSLOTH_API_KEY="${UNSLOTH_API_KEY:-unsloth}"
UNSLOTH_MODEL="${UNSLOTH_MODEL:-qwen3:27b}"
UNSLOTH_STUDIO_USERNAME="${UNSLOTH_STUDIO_USERNAME:-unsloth}"
UNSLOTH_STUDIO_PASSWORD="${UNSLOTH_STUDIO_PASSWORD:-CozyEvergladeMomHuman}"
GRAFANA_HOST="${GRAFANA_HOST:-grafana.homelab.home.arpa}"
PROMETHEUS_HOST="${PROMETHEUS_HOST:-prometheus.homelab.home.arpa}"
QBITTORRENT_HOST="${QBITTORRENT_HOST:-torrent.homelab.home.arpa}"
FILEBROWSER_HOST="${FILEBROWSER_HOST:-files.homelab.home.arpa}"
JELLYFIN_HOST="${JELLYFIN_HOST:-media.homelab.home.arpa}"
PLEX_HOST="${PLEX_HOST:-plex.homelab.home.arpa}"
DOMAIN="${DOMAIN:-homelab.home.arpa}"
METALLB_ENABLED="${METALLB_ENABLED:-true}"
# Reserve one static LAN IP for MetalLB so the ingress stays stable across
# Kubernetes restarts and node reboots. Keep this address outside the router
# DHCP pool.
METALLB_IP_POOL="${METALLB_IP_POOL:-192.168.0.6-192.168.0.6}"
HOMEPAGE_ALLOWED_HOSTS="${HOMEPAGE_ALLOWED_HOSTS:-dashboard.homelab.home.arpa,stock-ez.homelab.home.arpa,portainer.homelab.home.arpa,homeassistant.homelab.home.arpa,open-webui.homelab.home.arpa,openserp.homelab.home.arpa,hermes.homelab.home.arpa,hermes-dashboard.homelab.home.arpa,unsloth.homelab.home.arpa,unsloth-studio.homelab.home.arpa,grafana.homelab.home.arpa,prometheus.homelab.home.arpa,torrent.homelab.home.arpa,files.homelab.home.arpa,media.homelab.home.arpa,plex.homelab.home.arpa,localhost,127.0.0.1,192.168.0.2,192.168.0.6,192.168.0.79,192.168.0.207,192.168.0.208,192.168.0.209,192.168.0.210,::1}"
HOMELAB_SECRET_FILE="${HOMELAB_SECRET_FILE:-$ROOT_DIR/.homelab-secrets.env}"
if [ -f "$HOMELAB_SECRET_FILE" ]; then
  set -a
  . "$HOMELAB_SECRET_FILE"
  set +a
fi
UNSLOTH_STUDIO_USERNAME="${UNSLOTH_STUDIO_USERNAME:-unsloth}"
UNSLOTH_STUDIO_PASSWORD="${UNSLOTH_STUDIO_PASSWORD:-CozyEvergladeMomHuman}"
GPU_DETECTED="$(if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then echo true; elif [ -e /dev/nvidiactl ] || ls /dev/nvidia* >/dev/null 2>&1 2>/dev/null; then echo true; else echo false; fi)"
NODE_GPU_ALLOCATABLE="0"
if kubectl get nodes -o jsonpath='{range .items[*]}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' >/dev/null 2>&1; then
  NODE_GPU_ALLOCATABLE="$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' 2>/dev/null | awk 'NF {print $1; exit}' || echo 0)"
fi
if [ -z "${NODE_GPU_ALLOCATABLE}" ]; then
  NODE_GPU_ALLOCATABLE="0"
fi
NVIDIA_ENABLE_REASON="Node GPU capacity is not yet available to Kubernetes."
KUBE_CONTAINER_RUNTIME="unknown"
if kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.containerRuntimeVersion}' >/dev/null 2>&1; then
  KUBE_CONTAINER_RUNTIME="$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.containerRuntimeVersion}' 2>/dev/null || true)"
fi
case "${KUBE_CONTAINER_RUNTIME}" in
  *docker*|*cri-dockerd*) KUBE_CONTAINER_RUNTIME="docker" ;;
  *containerd*) KUBE_CONTAINER_RUNTIME="containerd" ;;
  *cri-o*) KUBE_CONTAINER_RUNTIME="cri-o" ;;
  *) KUBE_CONTAINER_RUNTIME="unknown" ;;
esac

DOCKER_NVIDIA_RUNTIME_AVAILABLE="false"
CONTAINERD_NVIDIA_RUNTIME_AVAILABLE="false"
if command -v docker >/dev/null 2>&1; then
  if docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -Eq 'nvidia|nvidia-cdi'; then
    DOCKER_NVIDIA_RUNTIME_AVAILABLE="true"
  fi
fi
if command -v nvidia-container-runtime >/dev/null 2>&1 || [ -x /usr/bin/nvidia-container-runtime ]; then
  CONTAINERD_NVIDIA_RUNTIME_AVAILABLE="true"
fi

OLLAMA_USE_NVIDIA="${OLLAMA_USE_NVIDIA:-$GPU_DETECTED}"
UNSLOTH_USE_NVIDIA="${UNSLOTH_USE_NVIDIA:-false}"
OLLAMA_GPU_COUNT="${OLLAMA_GPU_COUNT:-1}"
OLLAMA_BACKEND_MODE="cpu"
OLLAMA_NUM_GPU="0"

case "$GPU_SERVICE" in
  ollama)
    OLLAMA_USE_NVIDIA="${OLLAMA_USE_NVIDIA:-true}"
    UNSLOTH_USE_NVIDIA="false"
    ;;
  unsloth)
    UNSLOTH_USE_NVIDIA="${UNSLOTH_USE_NVIDIA:-true}"
    OLLAMA_USE_NVIDIA="false"
    ;;
  none)
    OLLAMA_USE_NVIDIA="false"
    UNSLOTH_USE_NVIDIA="false"
    ;;
  auto)
    if [ "${OLLAMA_USE_NVIDIA:-false}" = "true" ] && [ "${UNSLOTH_USE_NVIDIA:-false}" = "true" ]; then
      UNSLOTH_USE_NVIDIA="false"
    fi
    ;;
esac

if [ "${OLLAMA_USE_NVIDIA}" = "true" ] && [ "${GPU_DETECTED}" != "true" ]; then
  echo "No NVIDIA GPU detected on the host; forcing Ollama to CPU mode."
  OLLAMA_USE_NVIDIA="false"
fi

if [ "${UNSLOTH_USE_NVIDIA}" = "true" ] && [ "${GPU_DETECTED}" != "true" ]; then
  echo "No NVIDIA GPU detected on the host; forcing Unsloth to CPU mode."
  UNSLOTH_USE_NVIDIA="false"
fi

if [ "${OLLAMA_USE_NVIDIA}" = "true" ] && [ "${NODE_GPU_ALLOCATABLE:-0}" = "0" ]; then
  echo "Kubernetes is not advertising any allocatable nvidia.com/gpu on the node; host GPU is present, but the cluster is not exposing GPU capacity to pods. Ollama remains in CPU mode until nvidia.com/gpu is available."
  NVIDIA_ENABLE_REASON="Kubernetes is not advertising any allocatable nvidia.com/gpu on the node."
  OLLAMA_USE_NVIDIA="false"
fi

if [ "${UNSLOTH_USE_NVIDIA}" = "true" ] && [ "${NODE_GPU_ALLOCATABLE:-0}" = "0" ]; then
  echo "Kubernetes is not advertising any allocatable nvidia.com/gpu on the node; forcing Unsloth to CPU mode."
  UNSLOTH_USE_NVIDIA="false"
fi

if [ "${OLLAMA_USE_NVIDIA}" = "true" ] && [ "${KUBE_CONTAINER_RUNTIME}" = "docker" ] && [ "${DOCKER_NVIDIA_RUNTIME_AVAILABLE}" != "true" ]; then
  echo "Docker is the node runtime, but the NVIDIA Container Toolkit is not configured for Docker; forcing Ollama to CPU mode."
  NVIDIA_ENABLE_REASON="Docker is configured as the node runtime, but the NVIDIA Docker runtime is not available."
  OLLAMA_USE_NVIDIA="false"
fi

if [ "${UNSLOTH_USE_NVIDIA}" = "true" ] && [ "${KUBE_CONTAINER_RUNTIME}" = "docker" ] && [ "${DOCKER_NVIDIA_RUNTIME_AVAILABLE}" != "true" ]; then
  echo "Docker is the node runtime, but the NVIDIA Container Toolkit is not configured for Docker; forcing Unsloth to CPU mode."
  UNSLOTH_USE_NVIDIA="false"
fi

if [ "${OLLAMA_USE_NVIDIA}" = "true" ] && [ "${KUBE_CONTAINER_RUNTIME}" = "containerd" ] && [ "${CONTAINERD_NVIDIA_RUNTIME_AVAILABLE}" != "true" ]; then
  echo "containerd is the node runtime, but the NVIDIA runtime is not configured; forcing Ollama to CPU mode."
  NVIDIA_ENABLE_REASON="containerd is configured as the node runtime, but the NVIDIA runtime is not available."
  OLLAMA_USE_NVIDIA="false"
fi

if [ "${UNSLOTH_USE_NVIDIA}" = "true" ] && [ "${KUBE_CONTAINER_RUNTIME}" = "containerd" ] && [ "${CONTAINERD_NVIDIA_RUNTIME_AVAILABLE}" != "true" ]; then
  echo "containerd is the node runtime, but the NVIDIA runtime is not configured; forcing Unsloth to CPU mode."
  UNSLOTH_USE_NVIDIA="false"
fi

if [ "${OLLAMA_USE_NVIDIA}" = "true" ] && [ "${KUBE_CONTAINER_RUNTIME}" = "containerd" ] && ! kubectl get runtimeclass nvidia >/dev/null 2>&1; then
  echo "The nvidia RuntimeClass is missing for the containerd node runtime; forcing Ollama to CPU mode."
  NVIDIA_ENABLE_REASON="The required nvidia RuntimeClass is missing for the containerd runtime."
  OLLAMA_USE_NVIDIA="false"
fi

if [ "${UNSLOTH_USE_NVIDIA}" = "true" ] && [ "${KUBE_CONTAINER_RUNTIME}" = "containerd" ] && ! kubectl get runtimeclass nvidia >/dev/null 2>&1; then
  echo "The nvidia RuntimeClass is missing for the containerd node runtime; forcing Unsloth to CPU mode."
  UNSLOTH_USE_NVIDIA="false"
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
  if [ "${KUBE_CONTAINER_RUNTIME}" = "containerd" ]; then
    OLLAMA_RUNTIME_CLASS="nvidia"
  else
    OLLAMA_RUNTIME_CLASS=""
  fi
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

UNSLOTH_GPU_COUNT="${UNSLOTH_GPU_COUNT:-${OLLAMA_GPU_COUNT:-1}}"
UNSLOTH_RUNTIME_CLASS=""
UNSLOTH_NVIDIA_VISIBLE_DEVICES=""
UNSLOTH_NVIDIA_DRIVER_CAPABILITIES=""
UNSLOTH_GPU_REQUEST_KEY="nvidia.com/gpu: \"0\""
UNSLOTH_GPU_LIMIT_KEY="nvidia.com/gpu: \"0\""

if [ "${UNSLOTH_USE_NVIDIA}" = "true" ] && [ "${NODE_GPU_ALLOCATABLE:-0}" = "0" ]; then
  echo "Kubernetes is not advertising any allocatable nvidia.com/gpu; forcing Unsloth to CPU mode."
  UNSLOTH_USE_NVIDIA="false"
fi

if [ "${UNSLOTH_USE_NVIDIA}" = "true" ] && [ "${KUBE_CONTAINER_RUNTIME}" = "containerd" ]; then
  UNSLOTH_RUNTIME_CLASS="nvidia"
  UNSLOTH_NVIDIA_VISIBLE_DEVICES="all"
  UNSLOTH_NVIDIA_DRIVER_CAPABILITIES="compute,utility"
  UNSLOTH_GPU_REQUEST_KEY="nvidia.com/gpu: \"${UNSLOTH_GPU_COUNT}\""
  UNSLOTH_GPU_LIMIT_KEY="nvidia.com/gpu: \"${UNSLOTH_GPU_COUNT}\""
elif [ "${UNSLOTH_USE_NVIDIA}" = "true" ] && [ "${KUBE_CONTAINER_RUNTIME}" = "docker" ]; then
  UNSLOTH_NVIDIA_VISIBLE_DEVICES="all"
  UNSLOTH_NVIDIA_DRIVER_CAPABILITIES="compute,utility"
  UNSLOTH_GPU_REQUEST_KEY="nvidia.com/gpu: \"${UNSLOTH_GPU_COUNT}\""
  UNSLOTH_GPU_LIMIT_KEY="nvidia.com/gpu: \"${UNSLOTH_GPU_COUNT}\""
fi

OLLAMA_COMPUTE_MODE="GPU"
UNSLOTH_COMPUTE_MODE="GPU"
if [ "${OLLAMA_USE_NVIDIA}" = "true" ]; then OLLAMA_COMPUTE_MODE="GPU"; else OLLAMA_COMPUTE_MODE="CPU"; fi
if [ "${UNSLOTH_USE_NVIDIA}" = "true" ]; then UNSLOTH_COMPUTE_MODE="GPU"; else UNSLOTH_COMPUTE_MODE="CPU"; fi

export NAMESPACE STOCK_EZ_IMAGE OLLAMA_IMAGE DASHBOARD_IMAGE PORTAINER_IMAGE HOME_ASSISTANT_IMAGE OPEN_WEBUI_IMAGE UNSLOTH_IMAGE OPENSERP_IMAGE HERMES_IMAGE PROMETHEUS_IMAGE GRAFANA_IMAGE GRAFANA_ADMIN_USER GRAFANA_ADMIN_PASSWORD QBITTORRENT_IMAGE FILEBROWSER_IMAGE PORTAINER_ADMIN_USER PORTAINER_ADMIN_PASSWORD QBITTORRENT_USERNAME QBITTORRENT_PASSWORD FILEBROWSER_USERNAME FILEBROWSER_PASSWORD STOCK_EZ_HOST DASHBOARD_HOST PORTAINER_HOST HOMEASSISTANT_HOST OPEN_WEBUI_HOST OPENSERP_HOST HERMES_HOST HERMES_DASHBOARD_HOST UNSLOTH_HOST UNSLOTH_STUDIO_HOST UNSLOTH_API_KEY UNSLOTH_MODEL UNSLOTH_STUDIO_USERNAME UNSLOTH_STUDIO_PASSWORD GRAFANA_HOST PROMETHEUS_HOST QBITTORRENT_HOST FILEBROWSER_HOST JELLYFIN_HOST PLEX_HOST DOMAIN METALLB_ENABLED METALLB_IP_POOL HOMEPAGE_ALLOWED_HOSTS HOMELAB_SECRET_FILE OLLAMA_USE_NVIDIA OLLAMA_GPU_COUNT OLLAMA_NUM_GPU OLLAMA_BACKEND_MODE OLLAMA_RUNTIME_CLASS OLLAMA_NVIDIA_VISIBLE_DEVICES OLLAMA_NVIDIA_DRIVER_CAPABILITIES OLLAMA_GPU_REQUEST_KEY OLLAMA_GPU_LIMIT_KEY UNSLOTH_USE_NVIDIA UNSLOTH_GPU_COUNT UNSLOTH_RUNTIME_CLASS UNSLOTH_NVIDIA_VISIBLE_DEVICES UNSLOTH_NVIDIA_DRIVER_CAPABILITIES UNSLOTH_GPU_REQUEST_KEY UNSLOTH_GPU_LIMIT_KEY DCGM_EXPORTER_SCRAPE KUBE_CONTAINER_RUNTIME DOCKER_NVIDIA_RUNTIME_AVAILABLE CONTAINERD_NVIDIA_RUNTIME_AVAILABLE OLLAMA_ENABLED UNSLOTH_ENABLED GPU_SERVICE OLLAMA_COMPUTE_MODE UNSLOTH_COMPUTE_MODE

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
UNSLOTH_STUDIO_USERNAME=${UNSLOTH_STUDIO_USERNAME}
UNSLOTH_STUDIO_PASSWORD=${UNSLOTH_STUDIO_PASSWORD}
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
  echo "OpenSERP: http://$OPENSERP_HOST"
  echo "  API docs: http://$OPENSERP_HOST/docs"
  echo "Hermes: http://$HERMES_HOST"
  echo "  Dashboard: http://$HERMES_DASHBOARD_HOST"
  echo "qBittorrent: http://$QBITTORRENT_HOST or http://<node-ip>:8080"
  echo "  Username: $QBITTORRENT_USERNAME"
  echo "  Password: $QBITTORRENT_PASSWORD"
  echo "File Browser: http://$FILEBROWSER_HOST or http://<node-ip>:80"
  echo "  Username: $FILEBROWSER_USERNAME"
  echo "  Password: $FILEBROWSER_PASSWORD"
  echo "Unsloth Studio: http://$UNSLOTH_STUDIO_HOST"
  echo "  Username: $UNSLOTH_STUDIO_USERNAME"
  echo "  Password: $UNSLOTH_STUDIO_PASSWORD"
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

set_service_enabled() {
  local deployment_name="$1"
  local enabled_value="${2:-true}"
  if [ "${enabled_value}" = "true" ]; then
    kubectl scale -n "$NAMESPACE" deployment/"$deployment_name" --replicas=1 >/dev/null 2>&1 || true
  else
    kubectl scale -n "$NAMESPACE" deployment/"$deployment_name" --replicas=0 >/dev/null 2>&1 || true
  fi
}

reload_runtime_config() {
  kubectl rollout restart -n "$NAMESPACE" deployment/prometheus deployment/grafana deployment/homelab-dashboard >/dev/null 2>&1 || true
  kubectl rollout status -n "$NAMESPACE" deployment/prometheus --timeout=180s || true
  kubectl rollout status -n "$NAMESPACE" deployment/grafana --timeout=180s || true
  kubectl rollout status -n "$NAMESPACE" deployment/homelab-dashboard --timeout=180s || true
}

report_nvidia_runtime_status() {
  local runtime_class_state="missing"
  if kubectl get runtimeclass nvidia >/dev/null 2>&1; then
    runtime_class_state="present"
  fi

  echo
  echo "=== NVIDIA runtime status ==="
  echo "Host GPU detected: ${GPU_DETECTED}"
  echo "Kubernetes allocatable nvidia.com/gpu: ${NODE_GPU_ALLOCATABLE:-0}"
  echo "Detected container runtime: ${KUBE_CONTAINER_RUNTIME}"
  echo "Docker NVIDIA runtime configured: ${DOCKER_NVIDIA_RUNTIME_AVAILABLE}"
  echo "containerd NVIDIA runtime configured: ${CONTAINERD_NVIDIA_RUNTIME_AVAILABLE}"
  echo "RuntimeClass 'nvidia': ${runtime_class_state}"
  echo "Ollama GPU mode enabled: ${OLLAMA_USE_NVIDIA}"
  echo "Unsloth GPU mode enabled: ${UNSLOTH_USE_NVIDIA}"
  echo "GPU service selected: ${GPU_SERVICE}"
  if [ "${UNSLOTH_USE_NVIDIA}" = "false" ]; then
    echo "Unsloth reason: ${NVIDIA_ENABLE_REASON}"
  fi
  if [ "${OLLAMA_USE_NVIDIA}" = "false" ]; then
    echo "Reason: ${NVIDIA_ENABLE_REASON}"
  fi

  case "${KUBE_CONTAINER_RUNTIME}" in
    docker)
      if [ "${DOCKER_NVIDIA_RUNTIME_AVAILABLE}" = "true" ]; then
        echo "Docker runtime config: valid for NVIDIA, but still not enough if Kubernetes is not advertising nvidia.com/gpu."
      else
        echo "Docker runtime config: invalid for NVIDIA. Run: sudo nvidia-ctk runtime configure --runtime=docker --set-as-default && sudo systemctl restart docker"
      fi
      ;;
    containerd)
      if [ "${CONTAINERD_NVIDIA_RUNTIME_AVAILABLE}" = "true" ]; then
        echo "containerd runtime config: valid for NVIDIA, but Kubernetes still needs allocatable GPU capacity and the 'nvidia' RuntimeClass."
      else
        echo "containerd runtime config: invalid for NVIDIA. Run: sudo env PATH=\"/run/current-system/sw/bin:$PATH\" nvidia-ctk runtime configure --runtime=containerd --set-as-default && sudo systemctl restart containerd && sudo systemctl restart k3s"
      fi
      if [ "${runtime_class_state}" = "present" ]; then
        echo "RuntimeClass config: valid. 'nvidia' RuntimeClass is available for Kubernetes pods."
      else
        echo "RuntimeClass config: missing. Create or restore the 'nvidia' RuntimeClass before enabling GPU workloads."
      fi
      ;;
    *)
      echo "Runtime config: unknown. NVIDIA GPU workloads will remain disabled until the node runtime is confirmed and configured."
      ;;
  esac
  echo "============================="
  echo
}

if [ "${OLLAMA_USE_NVIDIA}" = "true" ]; then
  echo "NVIDIA GPU detected and the node runtime is ${KUBE_CONTAINER_RUNTIME}; enabling GPU access for Ollama."

  if [ "${KUBE_CONTAINER_RUNTIME}" = "containerd" ]; then
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
  elif [ "${KUBE_CONTAINER_RUNTIME}" = "docker" ]; then
    echo "Docker runtime detected. Ensure the NVIDIA Container Toolkit is configured for Docker and that the node advertises nvidia.com/gpu."
    if command -v docker >/dev/null 2>&1 && ! docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -Eq 'nvidia|nvidia-cdi'; then
      echo "WARNING: Docker is not configured to use the NVIDIA runtime. Re-run the host-side Docker setup before redeploying Ollama in GPU mode."
    fi
  else
    echo "WARNING: Unknown container runtime (${KUBE_CONTAINER_RUNTIME}); waiting for a valid NVIDIA runtime before enabling GPU mode."
  fi
fi

report_nvidia_runtime_status

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
if [ "${OLLAMA_ENABLED}" = "true" ]; then
  render_and_apply "$ROOT_DIR/k8s/ollama/ollama.yaml"
else
  echo "Ollama disabled via OLLAMA_ENABLED=false; scaling deployment/ollama to 0."
  set_service_enabled "ollama" "false"
fi
if [ "${UNSLOTH_ENABLED}" = "true" ]; then
  render_and_apply "$ROOT_DIR/k8s/unsloth/unsloth.yaml"
else
  echo "Unsloth disabled via UNSLOTH_ENABLED=false; scaling deployment/unsloth to 0."
  set_service_enabled "unsloth" "false"
fi
render_and_apply "$ROOT_DIR/k8s/open-webui/open-webui.yaml"
render_and_apply "$ROOT_DIR/k8s/openserp/openserp.yaml"
render_and_apply "$ROOT_DIR/k8s/hermes/hermes.yaml"
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
if [ "${OLLAMA_ENABLED}" = "true" ]; then
  kubectl rollout status -n "$NAMESPACE" deployment/ollama --timeout=180s || true
else
  kubectl scale -n "$NAMESPACE" deployment/ollama --replicas=0 >/dev/null 2>&1 || true
fi
if [ "${UNSLOTH_ENABLED}" = "true" ]; then
  kubectl rollout status -n "$NAMESPACE" deployment/unsloth --timeout=180s || true
else
  kubectl scale -n "$NAMESPACE" deployment/unsloth --replicas=0 >/dev/null 2>&1 || true
fi
kubectl rollout status -n "$NAMESPACE" deployment/open-webui --timeout=180s || true
kubectl rollout status -n "$NAMESPACE" deployment/openserp --timeout=180s || true
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
echo "  http://$OPENSERP_HOST"
echo "  http://$OPENSERP_HOST/docs"
echo "  http://$HERMES_HOST"
echo "  http://$HERMES_DASHBOARD_HOST"
echo "  http://$PORTAINER_HOST"
echo "  http://$HOMEASSISTANT_HOST"
echo "  http://$QBITTORRENT_HOST"
echo "  http://$FILEBROWSER_HOST"
echo "  http://$JELLYFIN_HOST"
echo "  http://$PLEX_HOST"
