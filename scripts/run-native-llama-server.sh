#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR/native-llama-server"
MODEL="${LLAMA_MODEL:-}"
HOST="${LLAMA_HOST:-0.0.0.0}"
PORT="${LLAMA_PORT:-8001}"
GPU_LAYERS="${LLAMA_GPU_LAYERS:-35}"
CTX_SIZE="${LLAMA_CTX_SIZE:-4096}"
BATCH_SIZE="${LLAMA_BATCH_SIZE:-512}"
THREADS="${LLAMA_THREADS:-8}"
SERVER_BIN="${LLAMA_SERVER_BIN:-$(command -v llama-server || echo llama-server)}"
EXTRA_ARGS="${LLAMA_EXTRA_ARGS:-}"

if [ -z "$MODEL" ]; then
  echo "LLAMA_MODEL is required. Set it to a GGUF path before starting the server."
  exit 1
fi

if [ ! -x "$(command -v python3 || true)" ]; then
  echo "python3 is required but not installed."
  exit 1
fi

if ! command -v "$SERVER_BIN" >/dev/null 2>&1 2>/dev/null; then
  echo "llama-server not found at '$SERVER_BIN'."
  echo "Either install the package or set LLAMA_SERVER_BIN to the actual binary path."
  exit 1
fi

exec python3 "$PROJECT_DIR/llama_server.py" \
  --model "$MODEL" \
  --host "$HOST" \
  --port "$PORT" \
  --server-bin "$SERVER_BIN" \
  --n-gpu-layers "$GPU_LAYERS" \
  --ctx-size "$CTX_SIZE" \
  --batch-size "$BATCH_SIZE" \
  --threads "$THREADS" \
  --extra-args "$EXTRA_ARGS"
