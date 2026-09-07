#!/usr/bin/env bash
set -euo pipefail

NAS_HOST="${NAS_HOST:-192.168.1.11}"
REMOTE_PATH="${REMOTE_PATH:-/General/Media}"
MOUNT_POINT="${MOUNT_POINT:-/mnt/wdex4100/General/Media}"
USER="${USER:-admin}"
PASSWORD="${PASSWORD:-}"

sudo mkdir -p "$MOUNT_POINT"

if [ -z "$PASSWORD" ]; then
  echo "PASSWORD is required for the WDEX4100 share."
  echo "Example: PASSWORD='your-password' REMOTE_PATH='/General/Media' MOUNT_POINT='/mnt/wdex4100/General/Media' ./scripts/mount-wdex4100.sh"
  exit 1
fi

sudo mount -t cifs "//${NAS_HOST}${REMOTE_PATH}" "$MOUNT_POINT" \
  -o username="$USER",password="$PASSWORD",uid=$(id -u),gid=$(id -g),vers=3.0,iocharset=utf8,dir_mode=0775,file_mode=0664

echo "Mounted WDEX4100 share at $MOUNT_POINT from ${NAS_HOST}${REMOTE_PATH}"

echo

echo "Common WDEX4100 share paths:"
echo "  General:    //192.168.1.11/General/Media"
echo "  Extension2: //192.168.1.11/Extension2/Media"
echo "  General2:   //192.168.1.11/General2/Media"
