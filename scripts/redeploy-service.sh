#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K8S_DIR="${ROOT_DIR}/k8s"
NAMESPACE="${NAMESPACE:-homelab}"
SERVICE_NAME="${1:-}"

usage() {
  cat <<'EOF'
Usage: ./scripts/redeploy-service.sh <service-name>

Example:
  ./scripts/redeploy-service.sh home-assistant
  ./scripts/redeploy-service.sh jellyfin
  ./scripts/redeploy-service.sh open-webui

This script will:
  1. Find the Kubernetes manifest(s) for the given service under k8s/
  2. Delete the matching deployment/service/PVC resources
  3. Re-apply the manifests so the service is fully recreated from scratch
EOF
}

if [[ -z "${SERVICE_NAME}" ]]; then
  usage
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl is not installed or not on PATH."
  exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "ERROR: Kubernetes cluster is not reachable from this machine."
  exit 1
fi

find_service_manifests() {
  python3 - "${SERVICE_NAME}" "${K8S_DIR}" <<'PY'
import re
import sys
from pathlib import Path

service = sys.argv[1].strip().lower()
root = Path(sys.argv[2])
seen = set()
matches = []

for path in sorted(root.rglob("*.y*ml")):
    try:
        text = path.read_text(encoding="utf-8")
    except Exception:
        continue

    lower_name = path.name.lower()
    if service in lower_name:
        matches.append(str(path))
        seen.add(str(path))
        continue

    for match in re.finditer(r"(?m)^\s*name\s*:\s*['\"]?([^\n'\"]+)['\"]?\s*$", text):
        value = match.group(1).strip().lower()
        if value == service:
            matches.append(str(path))
            seen.add(str(path))
            break

    if str(path) in seen:
        continue

    if service.replace("-", "") in path.name.lower().replace("-", ""):
        matches.append(str(path))
        seen.add(str(path))

for item in matches:
    print(item)
PY
}

mapfile -t MANIFESTS < <(find_service_manifests)

if [[ ${#MANIFESTS[@]} -eq 0 ]]; then
  echo "No Kubernetes manifests found for service '${SERVICE_NAME}' under ${K8S_DIR}."
  echo "Try one of the known service names such as home-assistant, jellyfin, open-webui, plex, or prometheus."
  exit 1
fi

for manifest in "${MANIFESTS[@]}"; do
  echo "Deleting resources from ${manifest}"
  kubectl delete -f "${manifest}" --namespace "${NAMESPACE}" --ignore-not-found=true --wait=true || true
done

# Delete any remaining matching app resources by label in case they were left behind.
kubectl delete deployment,service,pod,pvc,configmap,secret -n "${NAMESPACE}" -l app="${SERVICE_NAME}" --ignore-not-found=true --wait=true || true

render_and_apply() {
  local file="$1"
  python3 - "$file" <<'PY' | kubectl apply -f - --namespace "${NAMESPACE}"
import os
import sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text()
for key, value in sorted(os.environ.items()):
    text = text.replace(f"${{{key}}}", value)
print(text)
PY
}

for manifest in "${MANIFESTS[@]}"; do
  echo "Applying ${manifest}"
  render_and_apply "${manifest}"
done

echo
printf 'Redeploy complete for %s in namespace %s.\n' "${SERVICE_NAME}" "${NAMESPACE}"

echo "Current status:"
kubectl get pods -n "${NAMESPACE}" | grep -E "${SERVICE_NAME}|NAME" || true
