#!/usr/bin/env bash
# vm/phase0/fetch-rootfs.sh — download + verify the pinned Alpine minirootfs tarball.
# Idempotent: skips the download if the file is present and matches ROOTFS_SHA256.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

need_cmd curl
need_cmd sha256sum

mkdir -p "$DOWNLOAD_DIR"
verify() { echo "${ROOTFS_SHA256}  ${ROOTFS_PATH}" | sha256sum -c --status; }

if [[ -f "$ROOTFS_PATH" ]] && verify; then
  log "rootfs already present and verified: ${ROOTFS_PATH#$ONIX_ROOT/}"
  exit 0
fi

log "downloading $ROOTFS_NAME (~3.7 MiB) from $ROOTFS_URL"
curl -fL --retry 3 --retry-delay 2 -o "$ROOTFS_PATH" "$ROOTFS_URL"

if verify; then
  log "checksum OK — ${ROOTFS_PATH#$ONIX_ROOT/}"
else
  actual="$(sha256sum "$ROOTFS_PATH" | awk '{print $1}')"
  die "checksum MISMATCH for $ROOTFS_NAME
       expected: $ROOTFS_SHA256
       actual:   $actual
     (if Alpine bumped the point release, update ALPINE_VERSION/ROOTFS_SHA256 in config.sh)"
fi
