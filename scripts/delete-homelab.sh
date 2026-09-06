#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-homelab}"

kubectl delete namespace "$NAMESPACE" --ignore-not-found=true

echo "Deleted namespace: $NAMESPACE"
echo "If you also want to remove MetalLB, run: kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml"

# check and delete all PVCs in the namespace
echo "Checking for PVCs in namespace: $NAMESPACE"
PVCs=$(kubectl get pvc -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
echo "Found PVCs: $PVCs"
if [ -n "$PVCs" ]; then 
    echo "Deleting PVCs in namespace: $NAMESPACE"
    for pvc in $PVCs; do
        kubectl delete pvc "$pvc" -n "$NAMESPACE"
    done
fi