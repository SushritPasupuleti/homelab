#!/usr/bin/env bash
set -euo pipefail

METALLB_IP_POOL="${METALLB_IP_POOL:-192.168.0.2-192.168.0.253}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

# MetalLB's speaker DaemonSet mounts a secret named "memberlist". The upstream
# install instructions require creating it explicitly; otherwise the pod crashes
# with "secret \"memberlist\" not found" during startup.
kubectl --namespace metallb-system create secret generic memberlist \
  --from-literal=secretkey="$(openssl rand -base64 128)" \
  --dry-run=client -o yaml | kubectl apply -f -

# Wait for the controller and speaker resources to be available before creating
# MetalLB IPAddressPool resources. The validating webhook is created as part of
# the install and must have endpoints or CRD validation fails with a no-endpoints
# error.
kubectl --namespace metallb-system rollout status deployment/controller --timeout=180s
kubectl --namespace metallb-system rollout status daemonset/speaker --timeout=180s
kubectl --namespace metallb-system wait --for=jsonpath='{.subsets[0].addresses[0].ip}' endpoints/metallb-webhook-service --timeout=180s

METALLB_IP_POOL="$METALLB_IP_POOL" python3 -c '
import os, sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text()
text = text.replace("${METALLB_IP_POOL}", os.environ["METALLB_IP_POOL"])
print(text)
' "$ROOT_DIR/k8s/metallb/ip-address-pool.yaml" | kubectl apply -f -

echo "MetalLB installed and the pool is configured with ${METALLB_IP_POOL}"
echo "Now your ingress should receive a LAN IP and the URLs can be used without editing /etc/hosts in many setups."
