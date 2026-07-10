#!/usr/bin/env bash
# vm/phase2/verify-kernel-initramfs-plan.sh — verify the Phase 207 contract.
#
# Host-only safety check. This does not mount the image, copy kernels, build an
# initramfs, or boot QEMU.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOC="$ONIX_ROOT/vm/phase2/docs/207_kernel_initramfs_contract.md"
IMAGE_SCRIPT="$SCRIPT_DIR/build-image-skeleton.sh"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_file() {
  [[ -f "$1" ]] || die "missing expected file: ${1#$ONIX_ROOT/}"
}

need_text() {
  local file="$1"
  local text="$2"
  grep -Fq -- "$text" "$file" || die "missing required text in ${file#$ONIX_ROOT/}: $text"
}

echo "==> Phase 207 kernel + initramfs contract"

need_file "$DOC"
need_file "$IMAGE_SCRIPT"

for text in \
  "# Phase 207" \
  "/boot/ONIX/vmlinuz" \
  "/boot/ONIX/initramfs.img" \
  "/usr/lib/systemd/systemd" \
  "root=LABEL=onix-root" \
  "rootfstype=xfs" \
  "virtio_pci" \
  "virtio_blk" \
  "xfs" \
  "vfat" \
  "onix-kernel" \
  "onix-initramfs" \
  "do not use the host kernel as the final ONIX kernel" \
  "Phase 207 does not copy kernel files"
do
  need_text "$DOC" "$text"
done

echo "contract : OK (documented in ${DOC#$ONIX_ROOT/})"

echo
echo "==> Phase 206 boot-entry compatibility"
for text in \
  "linux /ONIX/vmlinuz" \
  "initrd /ONIX/initramfs.img" \
  "root=LABEL=onix-root" \
  "rootfstype=xfs" \
  "init=/usr/lib/systemd/systemd"
do
  need_text "$IMAGE_SCRIPT" "$text"
done

echo "boot path: OK (${IMAGE_SCRIPT#$ONIX_ROOT/} still points at the contracted paths)"

echo
echo "==> success"
echo "Phase 207 is only a kernel/initramfs contract gate; no image was mounted."
