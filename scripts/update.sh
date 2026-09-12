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

OLLAMA_ENABLED="${OLLAMA_ENABLED:-true}"
UNSLOTH_ENABLED="${UNSLOTH_ENABLED:-true}"
GPU_SERVICE="${GPU_SERVICE:-ollama}"

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
        echo "Missing value for --gpu-service. Use ollama, unsloth, vllm, none, or auto."
        exit 1
      fi
      GPU_SERVICE="$2"
      shift
      ;;
    --gpu-service=*)
      GPU_SERVICE="${1#*=}"
      ;;
    --help|-h)
      echo "Usage: ./scripts/update.sh [--disable-ollama|--enable-ollama] [--disable-unsloth|--enable-unsloth] [--gpu-service ollama|unsloth|vllm|none|auto]"
      echo "       or: OLLAMA_ENABLED=false UNSLOTH_ENABLED=false GPU_SERVICE=vllm ./scripts/update.sh"
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
  ollama|unsloth|vllm|none|auto) ;;
  *)
    echo "Unsupported GPU service: $GPU_SERVICE"
    echo "Use one of: ollama, unsloth, vllm, none, auto"
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
PORTAINER_ADMIN_PASSWORD="${PORTAINER_ADMIN_PASSWORD:-$(openssl rand -base64 24 | tr -d '\n' | tr '+/' '-_')}"
QBITTORRENT_USERNAME="${QBITTORRENT_USERNAME:-admin}"
QBITTORRENT_PASSWORD="${QBITTORRENT_PASSWORD:-$(openssl rand -base64 24 | tr -d '\n' | tr '+/' '-_')}"
FILEBROWSER_USERNAME="${FILEBROWSER_USERNAME:-admin}"
FILEBROWSER_PASSWORD="${FILEBROWSER_PASSWORD:-$(openssl rand -base64 24 | tr -d '\n' | tr '+/' '-_')}"
OPENSERP_HOST="${OPENSERP_HOST:-openserp.homelab.home.arpa}"
HERMES_HOST="${HERMES_HOST:-hermes.homelab.home.arpa}"
HERMES_DASHBOARD_HOST="${HERMES_DASHBOARD_HOST:-hermes-dashboard.homelab.home.arpa}"
UNSLOTH_HOST="${UNSLOTH_HOST:-unsloth.homelab.home.arpa}"
UNSLOTH_STUDIO_HOST="${UNSLOTH_STUDIO_HOST:-unsloth-studio.homelab.home.arpa}"
UNSLOTH_API_KEY="${UNSLOTH_API_KEY:-unsloth}"
VLLM_API_KEY="${VLLM_API_KEY:-${UNSLOTH_API_KEY:-vllm}}"
UNSLOTH_MODEL="${UNSLOTH_MODEL:-qwen3:27b}"
UNSLOTH_KV_CACHE_HOST="${UNSLOTH_KV_CACHE_HOST:-valkey.homelab.svc.cluster.local}"
UNSLOTH_KV_CACHE_PORT="${UNSLOTH_KV_CACHE_PORT:-6379}"
UNSLOTH_KV_CACHE_PASSWORD="${UNSLOTH_KV_CACHE_PASSWORD:-$(openssl rand -base64 24 | tr -d '\n' | tr '+/' '-_')}"
VLLM_IMAGE="${VLLM_IMAGE:-vllm/vllm-openai:latest}"
VLLM_MODEL_NAME="${VLLM_MODEL_NAME:-unsloth/gemma-4-E4B-it-qat-GGUF}"
VLLM_MODEL_PATH="${VLLM_MODEL_PATH:-/workspace/.cache/huggingface/hub/models--unsloth--gemma-4-E4B-it-qat-GGUF/snapshots/8c5a9e4fd5482e2be20fe0bf013b4c262a8f4265/gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf}"
VLLM_EXTRA_ARGS="${VLLM_EXTRA_ARGS:---tensor-parallel-size 1 --gpu-memory-utilization 0.9 --max-model-len 16384}"
VLLM_NVIDIA_VISIBLE_DEVICES="${VLLM_NVIDIA_VISIBLE_DEVICES:-all}"
VLLM_NVIDIA_DRIVER_CAPABILITIES="${VLLM_NVIDIA_DRIVER_CAPABILITIES:-compute,utility}"
VLLM_RUNTIME_CLASS="${VLLM_RUNTIME_CLASS:-nvidia}"
UNSLOTH_STUDIO_USERNAME="${UNSLOTH_STUDIO_USERNAME:-unsloth}"
UNSLOTH_STUDIO_PASSWORD="${UNSLOTH_STUDIO_PASSWORD:-CozyEvergladeMomHuman}"
VALKEY_PASSWORD="${VALKEY_PASSWORD:-${UNSLOTH_KV_CACHE_PASSWORD}}"
HOMELAB_SECRET_FILE="${HOMELAB_SECRET_FILE:-$ROOT_DIR/.homelab-secrets.env}"

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

OLLAMA_USE_NVIDIA="${OLLAMA_USE_NVIDIA:-true}"
UNSLOTH_USE_NVIDIA="${UNSLOTH_USE_NVIDIA:-false}"
OLLAMA_GPU_COUNT="${OLLAMA_GPU_COUNT:-1}"
VLLM_USE_NVIDIA="${VLLM_USE_NVIDIA:-false}"
VLLM_GPU_COUNT="${VLLM_GPU_COUNT:-1}"
VLLM_GPU_REQUEST_KEY="nvidia.com/gpu: \"0\""
VLLM_GPU_LIMIT_KEY="nvidia.com/gpu: \"0\""
OLLAMA_BACKEND_MODE="cpu"
OLLAMA_NUM_GPU="0"

case "$GPU_SERVICE" in
  ollama)
    OLLAMA_USE_NVIDIA="${OLLAMA_USE_NVIDIA:-true}"
    UNSLOTH_USE_NVIDIA="false"
    VLLM_USE_NVIDIA="false"
    ;;
  unsloth)
    UNSLOTH_USE_NVIDIA="${UNSLOTH_USE_NVIDIA:-true}"
    OLLAMA_USE_NVIDIA="false"
    VLLM_USE_NVIDIA="false"
    ;;
  vllm)
    VLLM_USE_NVIDIA="${VLLM_USE_NVIDIA:-true}"
    OLLAMA_USE_NVIDIA="false"
    UNSLOTH_USE_NVIDIA="false"
    ;;
  none)
    OLLAMA_USE_NVIDIA="false"
    UNSLOTH_USE_NVIDIA="false"
    VLLM_USE_NVIDIA="false"
    ;;
  auto)
    if [ "${VLLM_USE_NVIDIA:-false}" = "true" ]; then
      OLLAMA_USE_NVIDIA="false"
      UNSLOTH_USE_NVIDIA="false"
    elif [ "${OLLAMA_USE_NVIDIA:-false}" = "true" ] && [ "${UNSLOTH_USE_NVIDIA:-false}" = "true" ]; then
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

if [ "${VLLM_USE_NVIDIA}" = "true" ] && [ "${GPU_DETECTED}" != "true" ]; then
  echo "No NVIDIA GPU detected on the host; forcing vLLM to CPU mode."
  VLLM_USE_NVIDIA="false"
fi

if [ "${VLLM_USE_NVIDIA}" = "true" ] && [ "${NODE_GPU_ALLOCATABLE:-0}" = "0" ]; then
  echo "Kubernetes is not advertising any allocatable nvidia.com/gpu; vLLM remains in CPU mode until nvidia.com/gpu is available."
  VLLM_USE_NVIDIA="false"
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

if [ "${VLLM_USE_NVIDIA}" = "true" ] && [ "${KUBE_CONTAINER_RUNTIME}" = "containerd" ] && [ "${CONTAINERD_NVIDIA_RUNTIME_AVAILABLE}" != "true" ]; then
  echo "containerd is the node runtime, but the NVIDIA runtime is not configured; forcing vLLM to CPU mode."
  VLLM_USE_NVIDIA="false"
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

if [ "${VLLM_USE_NVIDIA}" = "true" ] && [ "${KUBE_CONTAINER_RUNTIME}" = "containerd" ] && ! kubectl get runtimeclass nvidia >/dev/null 2>&1; then
  echo "The nvidia RuntimeClass is missing for the containerd node runtime; forcing vLLM to CPU mode."
  VLLM_USE_NVIDIA="false"
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

UNSLOTH_GPU_COUNT="${UNSLOTH_GPU_COUNT:-${OLLAMA_GPU_COUNT:-1}}"
UNSLOTH_RUNTIME_CLASS=""
UNSLOTH_NVIDIA_VISIBLE_DEVICES=""
UNSLOTH_NVIDIA_DRIVER_CAPABILITIES=""
UNSLOTH_GPU_REQUEST_KEY="nvidia.com/gpu: \"0\""
UNSLOTH_GPU_LIMIT_KEY="nvidia.com/gpu: \"0\""

if [ "${VLLM_USE_NVIDIA}" = "true" ] && [ "${NODE_GPU_ALLOCATABLE:-0}" = "0" ]; then
  VLLM_USE_NVIDIA="false"
fi

if [ "${VLLM_USE_NVIDIA}" = "true" ] && [ "${KUBE_CONTAINER_RUNTIME:-unknown}" = "containerd" ]; then
  VLLM_RUNTIME_CLASS="nvidia"
  VLLM_NVIDIA_VISIBLE_DEVICES="all"
  VLLM_NVIDIA_DRIVER_CAPABILITIES="compute,utility"
  VLLM_GPU_REQUEST_KEY="nvidia.com/gpu: \"${VLLM_GPU_COUNT}\""
  VLLM_GPU_LIMIT_KEY="nvidia.com/gpu: \"${VLLM_GPU_COUNT}\""
elif [ "${VLLM_USE_NVIDIA}" = "true" ] && [ "${KUBE_CONTAINER_RUNTIME:-unknown}" = "docker" ]; then
  VLLM_NVIDIA_VISIBLE_DEVICES="all"
  VLLM_NVIDIA_DRIVER_CAPABILITIES="compute,utility"
  VLLM_GPU_REQUEST_KEY="nvidia.com/gpu: \"${VLLM_GPU_COUNT}\""
  VLLM_GPU_LIMIT_KEY="nvidia.com/gpu: \"${VLLM_GPU_COUNT}\""
fi

if [ "${UNSLOTH_USE_NVIDIA}" = "true" ] && [ "${NODE_GPU_ALLOCATABLE:-0}" = "0" ]; then
  echo "Kubernetes is not advertising any allocatable nvidia.com/gpu; forcing Unsloth to CPU mode."
  UNSLOTH_USE_NVIDIA="false"
fi

if [ "${UNSLOTH_USE_NVIDIA}" = "true" ] && [ "${KUBE_CONTAINER_RUNTIME:-unknown}" = "containerd" ]; then
  UNSLOTH_RUNTIME_CLASS="nvidia"
  UNSLOTH_NVIDIA_VISIBLE_DEVICES="all"
  UNSLOTH_NVIDIA_DRIVER_CAPABILITIES="compute,utility"
  UNSLOTH_GPU_REQUEST_KEY="nvidia.com/gpu: \"${UNSLOTH_GPU_COUNT}\""
  UNSLOTH_GPU_LIMIT_KEY="nvidia.com/gpu: \"${UNSLOTH_GPU_COUNT}\""
elif [ "${UNSLOTH_USE_NVIDIA}" = "true" ] && [ "${KUBE_CONTAINER_RUNTIME:-unknown}" = "docker" ]; then
  UNSLOTH_NVIDIA_VISIBLE_DEVICES="all"
  UNSLOTH_NVIDIA_DRIVER_CAPABILITIES="compute,utility"
  UNSLOTH_GPU_REQUEST_KEY="nvidia.com/gpu: \"${UNSLOTH_GPU_COUNT}\""
  UNSLOTH_GPU_LIMIT_KEY="nvidia.com/gpu: \"${UNSLOTH_GPU_COUNT}\""
fi

OLLAMA_COMPUTE_MODE="GPU"
UNSLOTH_COMPUTE_MODE="GPU"
if [ "${OLLAMA_USE_NVIDIA}" = "true" ]; then OLLAMA_COMPUTE_MODE="GPU"; else OLLAMA_COMPUTE_MODE="CPU"; fi
if [ "${UNSLOTH_USE_NVIDIA}" = "true" ]; then UNSLOTH_COMPUTE_MODE="GPU"; else UNSLOTH_COMPUTE_MODE="CPU"; fi

export NAMESPACE STOCK_EZ_IMAGE OLLAMA_IMAGE DASHBOARD_IMAGE PORTAINER_IMAGE HOME_ASSISTANT_IMAGE OPEN_WEBUI_IMAGE UNSLOTH_IMAGE OPENSERP_IMAGE HERMES_IMAGE PROMETHEUS_IMAGE GRAFANA_IMAGE GRAFANA_ADMIN_USER GRAFANA_ADMIN_PASSWORD QBITTORRENT_IMAGE FILEBROWSER_IMAGE PORTAINER_ADMIN_USER PORTAINER_ADMIN_PASSWORD QBITTORRENT_USERNAME QBITTORRENT_PASSWORD FILEBROWSER_USERNAME FILEBROWSER_PASSWORD OPENSERP_HOST HERMES_HOST HERMES_DASHBOARD_HOST UNSLOTH_HOST UNSLOTH_STUDIO_HOST UNSLOTH_API_KEY VLLM_API_KEY UNSLOTH_MODEL UNSLOTH_KV_CACHE_HOST UNSLOTH_KV_CACHE_PORT UNSLOTH_KV_CACHE_PASSWORD UNSLOTH_STUDIO_USERNAME UNSLOTH_STUDIO_PASSWORD VALKEY_PASSWORD HOMELAB_SECRET_FILE OLLAMA_USE_NVIDIA OLLAMA_GPU_COUNT OLLAMA_NUM_GPU OLLAMA_BACKEND_MODE OLLAMA_RUNTIME_CLASS OLLAMA_NVIDIA_VISIBLE_DEVICES OLLAMA_NVIDIA_DRIVER_CAPABILITIES OLLAMA_GPU_REQUEST_KEY OLLAMA_GPU_LIMIT_KEY UNSLOTH_USE_NVIDIA UNSLOTH_GPU_COUNT UNSLOTH_RUNTIME_CLASS UNSLOTH_NVIDIA_VISIBLE_DEVICES UNSLOTH_NVIDIA_DRIVER_CAPABILITIES UNSLOTH_GPU_REQUEST_KEY UNSLOTH_GPU_LIMIT_KEY VLLM_IMAGE VLLM_MODEL_NAME VLLM_MODEL_PATH VLLM_EXTRA_ARGS VLLM_RUNTIME_CLASS VLLM_NVIDIA_VISIBLE_DEVICES VLLM_NVIDIA_DRIVER_CAPABILITIES VLLM_GPU_COUNT VLLM_USE_NVIDIA VLLM_GPU_REQUEST_KEY VLLM_GPU_LIMIT_KEY OLLAMA_ENABLED UNSLOTH_ENABLED GPU_SERVICE OLLAMA_COMPUTE_MODE UNSLOTH_COMPUTE_MODE KUBE_CONTAINER_RUNTIME NODE_GPU_ALLOCATABLE GPU_DETECTED DOCKER_NVIDIA_RUNTIME_AVAILABLE CONTAINERD_NVIDIA_RUNTIME_AVAILABLE NVIDIA_ENABLE_REASON

print_gpu_debug_context() {
  echo
  echo "=== GPU debug context ==="
  echo "GPU service selected: ${GPU_SERVICE}"
  echo "Host GPU detected: ${GPU_DETECTED}"
  echo "Kubernetes allocatable nvidia.com/gpu: ${NODE_GPU_ALLOCATABLE:-0}"
  echo "Detected container runtime: ${KUBE_CONTAINER_RUNTIME}"
  echo "Docker NVIDIA runtime configured: ${DOCKER_NVIDIA_RUNTIME_AVAILABLE}"
  echo "containerd NVIDIA runtime configured: ${CONTAINERD_NVIDIA_RUNTIME_AVAILABLE}"
  echo "Ollama GPU mode: ${OLLAMA_USE_NVIDIA}"
  echo "Unsloth GPU mode: ${UNSLOTH_USE_NVIDIA}"
  echo "Unsloth GPU request key: ${UNSLOTH_GPU_REQUEST_KEY}"
  echo "Unsloth GPU limit key: ${UNSLOTH_GPU_LIMIT_KEY}"
  echo "Unsloth runtime class: ${UNSLOTH_RUNTIME_CLASS:-none}"
  if [ "${UNSLOTH_USE_NVIDIA}" = "false" ]; then
    echo "Unsloth GPU reason: ${NVIDIA_ENABLE_REASON}"
  fi
  echo "========================="
  echo
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
    if key.endswith("GPU_REQUEST_KEY") and value == "":
        value = 'nvidia.com/gpu: "0"'
    if key.endswith("GPU_LIMIT_KEY") and value == "":
        value = 'nvidia.com/gpu: "0"'
    if key in {"OLLAMA_RUNTIME_CLASS", "UNSLOTH_RUNTIME_CLASS"} and value == "":
        value = ""
    text = text.replace(f"${{{key}}}", value)
text = text.replace("      runtimeClassName: \n", "")
text = text.replace("      runtimeClassName:  \n", "")
if not os.environ.get('VLLM_RUNTIME_CLASS', '').strip():
    text = text.replace('      runtimeClassName: ', '')
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
VALKEY_PASSWORD=${VALKEY_PASSWORD}
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
  echo "Unsloth Studio: http://$UNSLOTH_STUDIO_HOST"
  echo "  Username: $UNSLOTH_STUDIO_USERNAME"
  echo "  Password: $UNSLOTH_STUDIO_PASSWORD"
  echo "KV cache (Valkey): redis://$UNSLOTH_KV_CACHE_HOST:$UNSLOTH_KV_CACHE_PORT"
  echo "  Password: $UNSLOTH_KV_CACHE_PASSWORD"
  echo "  Secret file: $HOMELAB_SECRET_FILE"
  echo "==========================="
  echo
}

print_gpu_debug_context

kubectl set image -n "$NAMESPACE" deployment/stock-ez stock-ez="$STOCK_EZ_IMAGE" || true
if [ "${OLLAMA_ENABLED}" = "true" ]; then
  kubectl set image -n "$NAMESPACE" deployment/ollama ollama="$OLLAMA_IMAGE" || true
else
  echo "Ollama disabled via OLLAMA_ENABLED=false; scaling deployment/ollama to 0."
  set_service_enabled "ollama" "false"
fi
if [ "${UNSLOTH_ENABLED}" = "true" ]; then
  kubectl set image -n "$NAMESPACE" deployment/unsloth unsloth="$UNSLOTH_IMAGE" || true
else
  echo "Unsloth disabled via UNSLOTH_ENABLED=false; scaling deployment/unsloth to 0."
  set_service_enabled "unsloth" "false"
fi
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
render_and_apply "$ROOT_DIR/k8s/valkey/valkey.yaml"
render_and_apply "$ROOT_DIR/k8s/vllm/vllm.yaml"
if [ "${OLLAMA_ENABLED}" = "true" ]; then
  render_and_apply "$ROOT_DIR/k8s/ollama/ollama.yaml"
else
  set_service_enabled "ollama" "false"
fi
if [ "${UNSLOTH_ENABLED}" = "true" ]; then
  render_and_apply "$ROOT_DIR/k8s/unsloth/unsloth.yaml"
else
  set_service_enabled "unsloth" "false"
fi
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
