#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-homelab}"
DEPLOYMENT="${UNSLOTH_DEPLOYMENT:-unsloth}"
USERNAME="${UNSLOTH_STUDIO_USERNAME:-unsloth}"
SECRET_FILE="${HOMELAB_SECRET_FILE:-$ROOT_DIR/.homelab-secrets.env}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required to reset Unsloth Studio credentials." >&2
  exit 1
fi

if ! kubectl -n "$NAMESPACE" get deployment "$DEPLOYMENT" >/dev/null 2>&1; then
  echo "Deployment/$DEPLOYMENT not found in namespace $NAMESPACE." >&2
  exit 1
fi

OUTPUT_FILE="$(mktemp)"
trap 'rm -f "$OUTPUT_FILE"' EXIT

if ! kubectl -n "$NAMESPACE" exec "deploy/$DEPLOYMENT" -- \
  /opt/unsloth-studio/unsloth_studio/bin/unsloth studio reset-password >"$OUTPUT_FILE" 2>&1; then
  cat "$OUTPUT_FILE" >&2
  echo "Failed to reset the Unsloth Studio password." >&2
  exit 1
fi

cat "$OUTPUT_FILE"

PASSWORD="$(sed -n "s/^New password for '.*': //p" "$OUTPUT_FILE" | tail -n 1)"

if [ -z "$PASSWORD" ]; then
  echo "Could not parse the generated password from the reset output." >&2
  exit 1
fi

if [ -f "$SECRET_FILE" ]; then
  if grep -q '^UNSLOTH_STUDIO_USERNAME=' "$SECRET_FILE"; then
    sed -i "/^UNSLOTH_STUDIO_USERNAME=/c\\UNSLOTH_STUDIO_USERNAME=$USERNAME" "$SECRET_FILE"
  else
    printf '\nUNSLOTH_STUDIO_USERNAME=%s\n' "$USERNAME" >> "$SECRET_FILE"
  fi

  if grep -q '^UNSLOTH_STUDIO_PASSWORD=' "$SECRET_FILE"; then
    sed -i "/^UNSLOTH_STUDIO_PASSWORD=/c\\UNSLOTH_STUDIO_PASSWORD=$PASSWORD" "$SECRET_FILE"
  else
    printf 'UNSLOTH_STUDIO_PASSWORD=%s\n' "$PASSWORD" >> "$SECRET_FILE"
  fi
else
  printf 'UNSLOTH_STUDIO_USERNAME=%s\nUNSLOTH_STUDIO_PASSWORD=%s\n' "$USERNAME" "$PASSWORD" > "$SECRET_FILE"
fi

echo
printf 'Updated %s with the current Unsloth password.\n' "$SECRET_FILE"
printf 'Username: %s\n' "$USERNAME"
printf 'Password: %s\n' "$PASSWORD"
