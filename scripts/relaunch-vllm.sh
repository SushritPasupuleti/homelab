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
  exit 1
fi

VLLM_IMAGE="${VLLM_IMAGE:-vllm/vllm-openai:latest}"
VLLM_MODEL_NAME="${VLLM_MODEL_NAME:-unsloth/gemma-4-E4B-it-qat-GGUF}"
VLLM_MODEL_PATH="${VLLM_MODEL_PATH:-/workspace/.cache/huggingface/hub/models--unsloth--gemma-4-E4B-it-qat-GGUF/snapshots/8c5a9e4fd5482e2be20fe0bf013b4c262a8f4265/gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf}"
VLLM_EXTRA_ARGS="${VLLM_EXTRA_ARGS:---tensor-parallel-size 1 --gpu-memory-utilization 0.9 --max-model-len 16384}"
VLLM_NVIDIA_VISIBLE_DEVICES="${VLLM_NVIDIA_VISIBLE_DEVICES:-all}"
VLLM_NVIDIA_DRIVER_CAPABILITIES="${VLLM_NVIDIA_DRIVER_CAPABILITIES:-compute,utility}"
VLLM_RUNTIME_CLASS="${VLLM_RUNTIME_CLASS:-nvidia}"
VLLM_GPU_COUNT="${VLLM_GPU_COUNT:-1}"
VLLM_NAMESPACE="${VLLM_NAMESPACE:-homelab}"
TEMPLATE_FILE="${TEMPLATE_FILE:-$ROOT_DIR/k8s/vllm/vllm.yaml}"

if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "ERROR: vLLM manifest not found at $TEMPLATE_FILE"
  exit 1
fi

if kubectl get runtimeclass nvidia >/dev/null 2>&1; then
  VLLM_RUNTIME_CLASS="${VLLM_RUNTIME_CLASS:-nvidia}"
else
  VLLM_RUNTIME_CLASS=""
fi

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

if [ "${KUBE_CONTAINER_RUNTIME}" = "docker" ]; then
  echo "Docker runtime detected; using the Docker-backed NVIDIA path without a RuntimeClass."
  VLLM_RUNTIME_CLASS=""
fi

VLLM_GPU_REQUEST_KEY="nvidia.com/gpu: \"${VLLM_GPU_COUNT}\""
VLLM_GPU_LIMIT_KEY="nvidia.com/gpu: \"${VLLM_GPU_COUNT}\""

if kubectl get nodes -o jsonpath='{range .items[*]}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' 2>/dev/null | awk 'NF {print $1; exit}' | grep -q '^[0-9]'; then
  :
else
  echo "No allocatable nvidia.com/gpu capacity is available to Kubernetes right now; vLLM will be relaunching in CPU fallback mode."
  VLLM_GPU_REQUEST_KEY='nvidia.com/gpu: "0"'
  VLLM_GPU_LIMIT_KEY='nvidia.com/gpu: "0"'
  VLLM_RUNTIME_CLASS=""
  VLLM_NVIDIA_VISIBLE_DEVICES=""
  VLLM_NVIDIA_DRIVER_CAPABILITIES=""
fi

export VLLM_IMAGE VLLM_MODEL_NAME VLLM_MODEL_PATH VLLM_EXTRA_ARGS VLLM_NVIDIA_VISIBLE_DEVICES VLLM_NVIDIA_DRIVER_CAPABILITIES VLLM_RUNTIME_CLASS VLLM_GPU_COUNT VLLM_GPU_REQUEST_KEY VLLM_GPU_LIMIT_KEY VLLM_NAMESPACE

kubectl delete rs -n "$VLLM_NAMESPACE" -l app=vllm --ignore-not-found >/dev/null 2>&1 || true
kubectl delete pod -n "$VLLM_NAMESPACE" -l app=vllm --force --grace-period=0 >/dev/null 2>&1 || true

python3 - "$TEMPLATE_FILE" <<'PY' | kubectl apply -f -
import os
import sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text()
for key, value in sorted(os.environ.items()):
    if key.startswith('VLLM_'):
        text = text.replace(f"${{{key}}}", value)
text = text.replace('      runtimeClassName: \n', '')
text = text.replace('      runtimeClassName:  \n', '')
if not os.environ.get('VLLM_RUNTIME_CLASS', '').strip():
    text = text.replace('      runtimeClassName: ', '')
print(text)
PY

kubectl rollout restart deployment/vllm -n "$VLLM_NAMESPACE" >/dev/null 2>&1 || true
kubectl rollout status deployment/vllm -n "$VLLM_NAMESPACE" --timeout=180s || true

echo
printf 'vLLM relaunch requested.\n'
printf '  model path: %s\n' "$VLLM_MODEL_PATH"
printf '  extra args: %s\n' "$VLLM_EXTRA_ARGS"
printf '  image: %s\n' "$VLLM_IMAGE"
printf '  namespace: %s\n' "$VLLM_NAMESPACE"
printf '  endpoint: http://vllm.homelab.home.arpa\n'
