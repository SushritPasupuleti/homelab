#!/usr/bin/env bash
set -euo pipefail

METALLB_IP_POOL="${METALLB_IP_POOL:-192.168.1.200-192.168.1.249}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml
kubectl wait --namespace metallb-system --for=condition=ready pod -l app=metallb --timeout=180s || true

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
