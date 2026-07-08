#!/usr/bin/env bash
# vm/phase4/stone-dropbear-probe.sh — Phase 413 live onix-dropbear proof.
#
# Phase 412 built onix-dropbear as a real .stone. Phase 413 installs that
# package into the image and proves that authenticated SSH still works with the
# service started from /usr/sbin/dropbear instead of a copied Nix payload.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${ONIX_STATE_DIR:-$ONIX_ROOT/vm/state}"

WAIT_SECONDS="${ONIX_STONE_DROPBEAR_SECONDS:-90}"
DRY_RUN=0
KILL_ONLY=0

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*"
}

usage() {
  cat >&2 <<EOF
usage: stone-dropbear-probe.sh [options]

  --seconds N      seconds to wait for the boot proof (default: $WAIT_SECONDS)
  --kill           stop existing Phase 413 QEMU probe and exit
  --dry-run        print underlying QEMU commands and exit
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --seconds) WAIT_SECONDS="${2:?missing seconds}"; shift ;;
    --kill) KILL_ONLY=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "unknown argument: $1" ;;
  esac
  shift
done

probe_args=(--seconds "$WAIT_SECONDS")
if [[ "$DRY_RUN" -eq 1 ]]; then
  probe_args+=(--dry-run)
fi

stone_dropbear_serial_command() {
  cat <<'EOF'
/usr/bin/busybox sh -c 'set -eu; test -x /usr/sbin/dropbear; test -x /usr/bin/dropbearkey; /usr/bin/busybox ps | /usr/bin/busybox grep -F /usr/sbin/dropbear >/dev/null; printf "ONIX_STONE_DROPBEAR_SERIAL_OK dropbear=/usr/sbin/dropbear key=/usr/bin/dropbearkey\n"'
EOF
}

stone_dropbear_remote_command() {
  cat <<'EOF'
/usr/bin/busybox sh -c 'set -eu; test -x /usr/sbin/dropbear; test -x /usr/bin/dropbearkey; test -f /usr/share/onix/packages/onix-dropbear.md; printf "ONIX_STONE_DROPBEAR_SSH_OK user=%s uid=%s dropbear=/usr/sbin/dropbear key=/usr/bin/dropbearkey package=present\n" "$(/usr/bin/busybox id -un)" "$(/usr/bin/busybox id -u)"'
EOF
}

kill_probe() {
  ONIX_SSH_PROBE_NAME=p413ssh \
    "$SCRIPT_DIR/ssh-probe.sh" --kill || true
}

if [[ "$KILL_ONLY" -eq 1 ]]; then
  kill_probe
  exit 0
fi

[[ -f "$ONIX_ROOT/artifacts/onix-image/onix.raw" ]] \
  || die "missing ONIX image: artifacts/onix-image/onix.raw (run make phase 2 first)"

log "Phase 413 stone Dropbear live proof"
log "goal      : authenticated SSH starts from /usr/sbin/dropbear"
log "window    : ${WAIT_SECONDS}s"

kill_probe >/dev/null 2>&1 || true

ONIX_SSH_PROBE_NAME=p413ssh \
ONIX_SSH_BOOT_LOG="$STATE_DIR/phase413.ssh-boot.log" \
ONIX_SSH_SERIAL_LOG="$STATE_DIR/phase413.ssh-serial.log" \
ONIX_SSH_SERIAL_SOCKET="$STATE_DIR/phase413.ssh.sock" \
ONIX_SSH_HOST_PORT="${ONIX_STONE_DROPBEAR_SSH_HOST_PORT:-7628}" \
ONIX_SSH_PROBE_LABEL="Phase 413 SSH stone Dropbear proof" \
ONIX_SSH_SERIAL_COMMAND="/usr/lib/onix/bootstrap-network-proof && /usr/lib/onix/bootstrap-ssh-proof && $(stone_dropbear_serial_command)" \
ONIX_SSH_READY_MARKER='ONIX_STONE_DROPBEAR_SERIAL_OK dropbear=/usr/sbin/dropbear key=/usr/bin/dropbearkey' \
ONIX_SSH_MARKER='ONIX_STONE_DROPBEAR_SSH_OK user=onix uid=1000 dropbear=/usr/sbin/dropbear key=/usr/bin/dropbearkey package=present' \
ONIX_SSH_REMOTE_COMMAND="$(stone_dropbear_remote_command)" \
ONIX_SSH_SUCCESS_MESSAGE="Phase 413 proved authenticated SSH starts from onix-dropbear." \
  "$SCRIPT_DIR/ssh-probe.sh" "${probe_args[@]}"

cat <<EOF

==> success
Phase 413 proved the booted ONIX image can use onix-dropbear for
authenticated SSH.

Evidence logs:
  ${STATE_DIR#$ONIX_ROOT/}/phase413.*.log

EOF
