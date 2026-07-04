#!/usr/bin/env bash
# vm/phase0/clean.sh — remove forge state so you can rebuild the disk from scratch.
#   ./clean.sh            remove disk, NVRAM, exported kernel/initrd (keeps SSH key + tarball)
#   ./clean.sh --keys     also remove the generated SSH keypair
#   ./clean.sh --all      also remove the downloaded minirootfs tarball
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

log "removing disk + NVRAM + exported kernel/initrd under ${STATE_DIR#$ONIX_ROOT/}/"
rm -f \
  "$DISK_IMG" \
  "$STATE_DIR/${VM_NAME}.raw" \
  "$STATE_DIR/${VM_NAME}.qcow2" \
  "$OVMF_VARS" "$KERNEL_IMG" "$INITRD_IMG"

case "${1:-}" in
  --keys) warn "removing SSH keypair"; rm -f "$SSH_KEY" "$SSH_KEY.pub" ;;
  --all)  warn "removing SSH keypair + minirootfs tarball"
          rm -f "$SSH_KEY" "$SSH_KEY.pub" "$ROOTFS_PATH" ;;
esac

log "clean. next: make disk && make run"
