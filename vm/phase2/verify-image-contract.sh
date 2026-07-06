#!/usr/bin/env bash
# vm/phase2/verify-image-contract.sh — verify the Phase 204 image contract.
#
# Host-only safety check. This script does not create disks, partition,
# format, mount, unmount, SSH, boot QEMU, or use sudo.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOC="$ONIX_ROOT/book/src/phases/204.md"
ROOT_TREE_DIR="${ONIX_ROOT_TREE_DIR:-$ONIX_ROOT/artifacts/onix-root-tree}"
FSTAB="$ROOT_TREE_DIR/etc/fstab"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_file() {
  [[ -f "$1" ]] || die "missing expected file: ${1#$ONIX_ROOT/}"
}

need_dir() {
  [[ -d "$1" ]] || die "missing expected directory: ${1#$ONIX_ROOT/}"
}

need_text() {
  local file="$1"
  local text="$2"
  grep -Fq -- "$text" "$file" || die "missing required contract text in ${file#$ONIX_ROOT/}: $text"
}

echo "==> Phase 204 image/disk assembly contract"

need_file "$DOC"

for text in \
  "# Phase 204" \
  "artifacts/onix-image/onix.raw" \
  "artifacts/onix-image-work/" \
  "artifacts/onix-root-tree/" \
  "ONIX-ESP" \
  "ONIX-BOOT" \
  "onix-root" \
  "ONIX-PERSIST" \
  "/efi" \
  "/boot" \
  "/persist" \
  "vfat" \
  "xfs" \
  "Phase 205" \
  "Phase 206"
do
  need_text "$DOC" "$text"
done

echo "contract : OK (documented in ${DOC#$ONIX_ROOT/})"

echo
echo "==> Phase 204 current root tree compatibility"
need_dir "$ROOT_TREE_DIR"
need_file "$ROOT_TREE_DIR/usr/lib/os-release"
need_file "$ROOT_TREE_DIR/etc/os-release"
need_file "$FSTAB"

for text in \
  "LABEL=ONIX-ESP" \
  "LABEL=ONIX-BOOT" \
  "LABEL=onix-root" \
  "LABEL=ONIX-PERSIST" \
  "/efi" \
  "/boot" \
  "/persist" \
  "vfat" \
  "xfs"
do
  need_text "$FSTAB" "$text"
done

echo "root tree: OK (${ROOT_TREE_DIR#$ONIX_ROOT/})"
echo "fstab    : OK (${FSTAB#$ONIX_ROOT/})"

echo
echo "==> success"
echo "Phase 204 is only a contract gate; no disk was created or mounted."
