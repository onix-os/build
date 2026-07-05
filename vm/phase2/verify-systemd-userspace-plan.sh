#!/usr/bin/env bash
# vm/phase2/verify-systemd-userspace-plan.sh — verify the Phase 208 contract.
#
# Host-only safety check. This does not build systemd, copy host systemd,
# mount the image, or boot QEMU.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
README="$SCRIPT_DIR/README.md"
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

echo "==> Phase 208 systemd userspace contract"

need_file "$README"
need_file "$IMAGE_SCRIPT"

for text in \
  "### Phase 208" \
  "PID 1" \
  "/usr/lib/systemd/systemd" \
  "systemd.unit=multi-user.target" \
  "/usr/lib/systemd/system/multi-user.target" \
  "onix-systemd" \
  "musl" \
  "do not copy host systemd" \
  "do not copy Nix systemd" \
  "systemd-udevd" \
  "/etc/machine-id" \
  "/run" \
  "/dev" \
  "/proc" \
  "/sys" \
  "tmpfiles" \
  "sysusers" \
  "Phase 208 does not build systemd" \
  "### Phase 209"
do
  need_text "$README" "$text"
done

echo "contract : OK (documented in ${README#$ONIX_ROOT/})"

echo
echo "==> Phase 206 boot-entry compatibility"
for text in \
  "init=/usr/lib/systemd/systemd" \
  "systemd.unit=multi-user.target"
do
  need_text "$IMAGE_SCRIPT" "$text"
done

echo "boot path: OK (${IMAGE_SCRIPT#$ONIX_ROOT/} still points at the contracted init)"

echo
echo "==> success"
echo "Phase 208 is only a systemd userspace contract gate; no image was mounted."
