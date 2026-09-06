#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-stock-ez:local}"
TMP_TAR="${TMP_TAR:-/tmp/stock-ez-local.tar}"
BUILD_CONTEXT="${BUILD_CONTEXT:-${STOCK_EZ_SOURCE_DIR:-}}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not installed or not on PATH."
  echo "Build the image locally first, then import it into k3s with:"
  echo "  sudo k3s ctr images import /path/to/image.tar"
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker is installed but the daemon is unreachable."
  echo "Fix the daemon connection first, then rerun this script."
  echo "Common fixes:"
  echo "  1) Start the daemon: sudo systemctl start docker"
  echo "  2) Or on Docker Desktop: open Docker Desktop and ensure it is running"
  echo "  3) Reset the connection: unset DOCKER_HOST DOCKER_CONTEXT; docker context use default"
  echo "  4) If needed: export DOCKER_HOST=unix:///var/run/docker.sock"
  exit 1
fi

if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  if [ -n "$BUILD_CONTEXT" ]; then
    echo "Image '$IMAGE_NAME' was not found locally. Building it from: $BUILD_CONTEXT"
    docker build -t "$IMAGE_NAME" "$BUILD_CONTEXT"
  else
    echo "Image '$IMAGE_NAME' was not found locally."
    echo "Build it first, for example:"
    echo "  docker build -t $IMAGE_NAME /path/to/stock-ez"
    echo "or set BUILD_CONTEXT=/path/to/stock-ez and rerun this script."
    exit 1
  fi
fi

docker save "$IMAGE_NAME" -o "$TMP_TAR"
if command -v k3s >/dev/null 2>&1; then
  if ! sudo -n true >/dev/null 2>&1; then
    echo "Local image import requires sudo access."
    echo "Either run: sudo -v"
    echo "or set STOCK_EZ_IMAGE to a remote image and rerun ./scripts/deploy.sh"
    exit 1
  fi
  sudo k3s ctr images import "$TMP_TAR"
elif command -v nerdctl >/dev/null 2>&1; then
  if ! sudo -n true >/dev/null 2>&1; then
    echo "Local image import requires sudo access."
    echo "Either run: sudo -v"
    echo "or set STOCK_EZ_IMAGE to a remote image and rerun ./scripts/deploy.sh"
    exit 1
  fi
  sudo nerdctl --namespace k8s.io load -i "$TMP_TAR"
else
  echo "Neither k3s nor nerdctl was found on PATH."
  echo "Import the tarball into your cluster runtime manually."
  exit 1
fi

echo "Imported $IMAGE_NAME into the cluster runtime."
