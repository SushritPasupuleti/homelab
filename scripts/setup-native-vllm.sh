#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${VLLM_VENV_DIR:-$ROOT_DIR/.venvs/vllm}"
MODEL_PATH="${VLLM_MODEL_PATH:-${HOME}/.cache/huggingface/hub}"
PORT="${VLLM_PORT:-8000}"
HOST="${VLLM_HOST:-0.0.0.0}"
EXTRA_ARGS="${VLLM_EXTRA_ARGS:-}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required but not installed."
  exit 1
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "uv is not installed; installing it to the user environment first."
  python3 -m pip install --user uv
  export PATH="$HOME/.local/bin:$PATH"
fi

mkdir -p "$ROOT_DIR/.venvs"
uv venv "$VENV_DIR" --python "$(command -v python3)"

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
  echo "NVIDIA GPU detected. Installing vLLM with GPU support."
  uv pip install --python "$VENV_DIR/bin/python" "vllm>=0.7.0" --extra-index-url https://download.pytorch.org/whl/cu121
else
  echo "No NVIDIA GPU detected; vLLM will run in CPU fallback mode when launched."
  uv pip install --python "$VENV_DIR/bin/python" "vllm>=0.7.0"
fi

cat > "$ROOT_DIR/scripts/run-native-vllm.sh" <<'EOF'
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
EOF
chmod +x "$ROOT_DIR/scripts/run-native-vllm.sh"

cat > "$ROOT_DIR/scripts/vllm-native.service" <<EOF
[Unit]
Description=vLLM Native Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$ROOT_DIR
Environment=VLLM_VENV_DIR=$VENV_DIR
Environment=VLLM_MODEL_PATH=$MODEL_PATH
Environment=VLLM_PORT=$PORT
Environment=VLLM_HOST=$HOST
Environment=VLLM_EXTRA_ARGS=$EXTRA_ARGS
ExecStart=$ROOT_DIR/scripts/run-native-vllm.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo
echo "vLLM native environment created at: $VENV_DIR"
echo "Launcher script: $ROOT_DIR/scripts/run-native-vllm.sh"
echo "Systemd unit file: $ROOT_DIR/scripts/vllm-native.service"
echo
echo "To install as a system service:"
echo "  sudo cp $ROOT_DIR/scripts/vllm-native.service /etc/systemd/system/vllm-native.service"
echo "  sudo systemctl daemon-reload"
echo "  sudo systemctl enable --now vllm-native.service"
echo
echo "To run manually:"
echo "  VLLM_MODEL_PATH=/path/to/model VLLM_PORT=8000 $ROOT_DIR/scripts/run-native-vllm.sh"
echo
