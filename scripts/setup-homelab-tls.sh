#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TLS_DIR="${HOMELAB_TLS_DIR:-$ROOT_DIR/.local/tls}"
NAMESPACE="${NAMESPACE:-homelab}"
SECRET_NAME="${HOMELAB_TLS_SECRET_NAME:-homelab-wildcard-tls}"
CA_KEY="$TLS_DIR/homelab-root-ca.key"
CA_CERT="$TLS_DIR/homelab-root-ca.crt"
LEAF_KEY="$TLS_DIR/wildcard.homelab.home.arpa.key"
LEAF_CSR="$TLS_DIR/wildcard.homelab.home.arpa.csr"
LEAF_CERT="$TLS_DIR/wildcard.homelab.home.arpa.crt"
CHAIN_CERT="$TLS_DIR/wildcard-fullchain.crt"
EXT_FILE="$TLS_DIR/wildcard.ext"

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required to create the local homelab certificate authority." >&2
  exit 1
fi
if ! command -v kubectl >/dev/null 2>&1 || ! kubectl cluster-info >/dev/null 2>&1; then
  echo "A reachable Kubernetes cluster is required to install the TLS secret." >&2
  exit 1
fi

mkdir -p "$TLS_DIR"
chmod 700 "$TLS_DIR"

kubectl apply -f "$ROOT_DIR/k8s/namespace.yaml"
if ! kubectl get ingressclass nginx >/dev/null 2>&1; then
  echo "The nginx IngressClass is missing. Install ingress-nginx before enabling TLS." >&2
  exit 1
fi

if [[ -e "$CA_KEY" || -e "$CA_CERT" ]]; then
  if [[ ! -s "$CA_KEY" || ! -s "$CA_CERT" ]]; then
    echo "Found an incomplete CA key pair under $TLS_DIR; restore both files or move them aside." >&2
    exit 1
  fi
else
  openssl genrsa -out "$CA_KEY" 4096
  chmod 600 "$CA_KEY"
  openssl req -x509 -new -sha256 -days 3650 \
    -key "$CA_KEY" \
    -out "$CA_CERT" \
    -subj "/CN=Homelab Home ARPA Root CA" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -addext "subjectKeyIdentifier=hash"
  chmod 644 "$CA_CERT"
fi

openssl genrsa -out "$LEAF_KEY" 3072
chmod 600 "$LEAF_KEY"
openssl req -new -sha256 \
  -key "$LEAF_KEY" \
  -out "$LEAF_CSR" \
  -subj "/CN=*.homelab.home.arpa"

cat > "$EXT_FILE" <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:*.homelab.home.arpa
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF

openssl x509 -req -sha256 -days 397 \
  -in "$LEAF_CSR" \
  -CA "$CA_CERT" \
  -CAkey "$CA_KEY" \
  -CAcreateserial \
  -out "$LEAF_CERT" \
  -extfile "$EXT_FILE"
chmod 644 "$LEAF_CERT"
cat "$LEAF_CERT" "$CA_CERT" > "$CHAIN_CERT"
chmod 644 "$CHAIN_CERT"
openssl verify -CAfile "$CA_CERT" "$LEAF_CERT"

kubectl create secret tls "$SECRET_NAME" \
  --namespace "$NAMESPACE" \
  --cert="$CHAIN_CERT" \
  --key="$LEAF_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$ROOT_DIR/k8s/ingress/ingress.yaml"

echo
echo "HTTPS is enabled for ingress hosts under *.homelab.home.arpa."
echo "Install this CA certificate on each client device to remove browser warnings:"
echo "  $CA_CERT"
echo "Keep the CA private key secret and backed up securely: $CA_KEY"
