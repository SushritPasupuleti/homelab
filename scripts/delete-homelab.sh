#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-homelab}"

kubectl delete namespace "$NAMESPACE" --ignore-not-found=true

echo "Deleted namespace: $NAMESPACE"
echo "Ingress is host-bound, so no MetalLB cleanup is required for this stack."

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