#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${PORTFOLIO_PUFFIN_SOURCE_DIR:-$ROOT_DIR/services/portfolio-zero}"
HOMELAB_PATCH="${PORTFOLIO_PUFFIN_PATCH:-$ROOT_DIR/patches/portfolio-zero/0001-homelab-ollama-api-proxy.patch}"
API_IMAGE="${PORTFOLIO_PUFFIN_API_IMAGE:-portfolio-puffin-api:local}"
WEB_IMAGE="${PORTFOLIO_PUFFIN_WEB_IMAGE:-portfolio-puffin-web:local}"
IMPORT_IMAGES="${PORTFOLIO_PUFFIN_IMPORT_IMAGES:-true}"

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "Docker is required and its daemon must be reachable to build Portfolio Puffin." >&2
  exit 1
fi
if [ ! -f "$SOURCE_DIR/backend/Dockerfile" ] || [ ! -f "$SOURCE_DIR/frontend/Dockerfile" ]; then
  echo "Portfolio Puffin source is missing under $SOURCE_DIR." >&2
  exit 1
fi

build_dir="$(mktemp -d /tmp/portfolio-puffin-build.XXXXXX)"
trap 'rm -rf "$build_dir"' EXIT
mkdir -p "$build_dir/source"
git -C "$SOURCE_DIR" archive HEAD | tar -x -C "$build_dir/source"
git -C "$build_dir/source" apply "$HOMELAB_PATCH"

docker build -t "$API_IMAGE" "$build_dir/source/backend"
docker build -t "$WEB_IMAGE" "$build_dir/source/frontend"

if [ "$IMPORT_IMAGES" = "true" ]; then
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl is required to detect the cluster container runtime." >&2
    exit 1
  fi
  cluster_runtime="$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.containerRuntimeVersion}' 2>/dev/null || true)"
  if [ -z "$cluster_runtime" ]; then
    echo "Could not detect the Kubernetes node container runtime; cannot import local images." >&2
    exit 1
  fi
  for image in "$API_IMAGE" "$WEB_IMAGE"; do
    image_tar="$(mktemp "/tmp/portfolio-puffin.XXXXXX.tar")"
    trap 'rm -f "$image_tar"; rm -rf "$build_dir"' EXIT
    docker save "$image" -o "$image_tar"
    if [[ "$cluster_runtime" == docker://* ]]; then
      target_docker_host="${PORTFOLIO_PUFFIN_K3S_DOCKER_HOST:-unix:///var/run/docker.sock}"
      docker --host "$target_docker_host" load --input "$image_tar"
    else
      if ! command -v k3s >/dev/null 2>&1; then
        echo "k3s is required to import images into the containerd runtime." >&2
        exit 1
      fi
      if ! sudo -n true >/dev/null 2>&1; then
        echo "Importing local images into the k3s containerd runtime needs sudo." >&2
        echo "Run 'sudo -v' and retry ./scripts/deploy-portfolio-puffin.sh." >&2
        exit 1
      fi
      sudo k3s ctr images import "$image_tar"
    fi
    rm -f "$image_tar"
    trap - EXIT
  done
fi

echo "Built Portfolio Puffin images: $API_IMAGE and $WEB_IMAGE"
