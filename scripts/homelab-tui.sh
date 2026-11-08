#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v go >/dev/null 2>&1; then
  echo "Go is required to run the Homelab Control TUI." >&2
  exit 1
fi

export CGO_ENABLED="${CGO_ENABLED:-0}"

cd "$ROOT_DIR"
exec go run ./cmd/homelab-tui "$@"
