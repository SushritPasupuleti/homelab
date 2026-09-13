#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${VLLM_VENV_DIR:-$ROOT_DIR/.venvs/vllm}"
MODEL_PATH="${VLLM_MODEL_PATH:-${HOME}/.cache/huggingface/hub}"
PORT="${VLLM_PORT:-8000}"
HOST="${VLLM_HOST:-0.0.0.0}"
EXTRA_ARGS="${VLLM_EXTRA_ARGS:-}"

ensure_nixos_ldconfig() {
  if [ -x /run/current-system/sw/bin/ldconfig ] && [ ! -e /sbin/ldconfig ]; then
    if [ "$(id -u)" -ne 0 ]; then
      echo "NixOS detection: Triton expects /sbin/ldconfig, but this host stores it in /run/current-system/sw/bin/ldconfig."
      echo "Run the following once as root and then restart vLLM:"
      echo "  sudo mkdir -p /sbin && sudo ln -sf /run/current-system/sw/bin/ldconfig /sbin/ldconfig"
      exit 1
    fi

    mkdir -p /sbin
    ln -sf /run/current-system/sw/bin/ldconfig /sbin/ldconfig
  fi
}

if [ -d /run/current-system/sw/bin ]; then
  export PATH="/run/current-system/sw/bin:$PATH"
  export LD_LIBRARY_PATH="/run/current-system/sw/lib:/run/current-system/sw/lib64:${LD_LIBRARY_PATH:-}"
  export LIBRARY_PATH="/run/current-system/sw/lib:/run/current-system/sw/lib64:${LIBRARY_PATH:-}"
  ensure_nixos_ldconfig
fi

if [ ! -x "$VENV_DIR/bin/python" ]; then
  echo "vLLM venv not found at $VENV_DIR. Run ./scripts/setup-native-vllm.sh first."
  exit 1
fi

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
  echo "Using native NVIDIA GPU-backed vLLM."
else
  echo "GPU not detected; starting vLLM in CPU fallback mode."
fi

exec "$VENV_DIR/bin/python" -m vllm.entrypoints.openai.api_server \
  --host "$HOST" \
  --port "$PORT" \
  --model "$MODEL_PATH" \
  $EXTRA_ARGS
