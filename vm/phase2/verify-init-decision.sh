#!/usr/bin/env bash
# vm/phase2/verify-init-decision.sh — verify the Phase 210 init-path decision.
#
# Host-only check. This does not build init systems, mount the image, use sudo,
# or boot QEMU.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
README="$SCRIPT_DIR/README.md"
BOOT_SCRIPT="$SCRIPT_DIR/build-image-skeleton.sh"

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

echo "==> Phase 210 init path decision contract"

need_file "$README"
need_file "$BOOT_SCRIPT"

for text in \
  "### Phase 210" \
  "init path: systemd-on-musl" \
  "bootloader: systemd-boot" \
  "keep systemd if we can" \
  "ONIX uses systemd as PID 1" \
  "systemd-boot loads the kernel" \
  "systemd runs as PID 1" \
  "init=/usr/lib/systemd/systemd systemd.unit=multi-user.target" \
  "systemd starts as PID 1" \
  "udev/device setup works" \
  "basic services work" \
  "Phase 210 does not build the init system" \
  "### Phase 211"
do
  need_text "$README" "$text"
done

echo "contract : OK (documented in ${README#$ONIX_ROOT/})"

echo
echo "==> bootloader/init compatibility"
need_text "$BOOT_SCRIPT" "init=/usr/lib/systemd/systemd"
need_text "$BOOT_SCRIPT" "systemd-boot/BLS skeleton"
echo "boot path: OK (${BOOT_SCRIPT#$ONIX_ROOT/} follows the systemd init path)"

echo
echo "==> success"
echo "Phase 210 records a decision only; no image was mounted."
