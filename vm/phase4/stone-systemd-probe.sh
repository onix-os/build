#!/usr/bin/env bash
# vm/phase4/stone-systemd-probe.sh — Phase 417 live systemd proof.
#
# Phase 416 installed systemd into the image and materialized its bundled
# bootstrap store into the runtime /nix/store paths. Phase 417 boots the image
# and proves the kernel can still execute /usr/lib/systemd/systemd as PID 1,
# while the existing bootstrap network and SSH services still come up.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${ONIX_STATE_DIR:-$ONIX_ROOT/vm/state}"

WAIT_SECONDS="${ONIX_STONE_SYSTEMD_SECONDS:-120}"
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
usage: stone-systemd-probe.sh [options]

  --seconds N      seconds to wait for the boot proof (default: $WAIT_SECONDS)
  --kill           stop existing Phase 417 QEMU probe and exit
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

stone_systemd_serial_command() {
  cat <<'EOF'
/usr/bin/busybox sh -c 'set -eu; bb=/usr/bin/busybox; sys="$("$bb" readlink /usr/lib/systemd/systemd)"; case "$sys" in /nix/store/*-systemd-*/lib/systemd/systemd) ;; *) echo "bad-systemd-link=$sys"; exit 1 ;; esac; test -x "$sys"; test -x "/usr/lib/onix/bootstrap$sys"; test -f /usr/share/onix/bootstrap/systemd-stone.txt; test -f /usr/share/onix/packages/systemd.md; pid1="$("$bb" cat /proc/1/comm)"; test "$pid1" = systemd; printf "ONIX_STONE_SYSTEMD_SERIAL_OK pid1=%s systemd=%s bootstrap=present proof=present\n" "$pid1" "$sys"'
EOF
}

stone_systemd_remote_command() {
  cat <<'EOF'
/usr/bin/busybox sh -c 'set -eu; bb=/usr/bin/busybox; sys="$("$bb" readlink /usr/lib/systemd/systemd)"; case "$sys" in /nix/store/*-systemd-*/lib/systemd/systemd) ;; *) echo "bad-systemd-link=$sys"; exit 1 ;; esac; test -x "$sys"; test -x "/usr/lib/onix/bootstrap$sys"; test -x /usr/bin/systemctl; test -x /usr/bin/journalctl; test -x /usr/bin/udevadm; test -f /usr/share/onix/packages/systemd.closure; pid1="$("$bb" cat /proc/1/comm)"; test "$pid1" = systemd; version="$(/usr/bin/systemctl --version | "$bb" head -n1)"; printf "ONIX_STONE_SYSTEMD_SSH_OK user=%s uid=%s pid1=%s systemd=%s version=%s\n" "$("$bb" id -un)" "$("$bb" id -u)" "$pid1" "$sys" "$version"'
EOF
}

kill_probe() {
  ONIX_SSH_PROBE_NAME=p417ssh \
    "$SCRIPT_DIR/ssh-probe.sh" --kill || true
}

if [[ "$KILL_ONLY" -eq 1 ]]; then
  kill_probe
  exit 0
fi

[[ -f "$ONIX_ROOT/artifacts/onix-image/onix.raw" ]] \
  || die "missing ONIX image: artifacts/onix-image/onix.raw (run make phase 2 first)"
[[ -f "$ONIX_ROOT/artifacts/onix-local-repo/stone.index" ]] \
  || die "missing local Phase 4 repo index: artifacts/onix-local-repo/stone.index"
compgen -G "$ONIX_ROOT/artifacts/onix-local-repo/systemd-*.stone" >/dev/null \
  || die "missing systemd stone in artifacts/onix-local-repo (run make phase 415)"

log "Phase 417 stone systemd live proof"
log "goal      : boot with systemd materialized as PID 1 runtime payload"
log "window    : ${WAIT_SECONDS}s"

kill_probe >/dev/null 2>&1 || true

ONIX_SSH_PROBE_NAME=p417ssh \
ONIX_SSH_BOOT_LOG="$STATE_DIR/phase417.ssh-boot.log" \
ONIX_SSH_SERIAL_LOG="$STATE_DIR/phase417.ssh-serial.log" \
ONIX_SSH_SERIAL_SOCKET="$STATE_DIR/phase417.ssh.sock" \
ONIX_SSH_HOST_PORT="${ONIX_STONE_SYSTEMD_SSH_HOST_PORT:-7629}" \
ONIX_SSH_PROBE_LABEL="Phase 417 SSH stone systemd proof" \
ONIX_SSH_SERIAL_COMMAND="/usr/lib/onix/bootstrap-network-proof && /usr/lib/onix/bootstrap-ssh-proof && $(stone_systemd_serial_command)" \
ONIX_SSH_READY_MARKER='ONIX_STONE_SYSTEMD_SERIAL_OK pid1=systemd systemd=/nix/store/.*/lib/systemd/systemd bootstrap=present proof=present' \
ONIX_SSH_MARKER='ONIX_STONE_SYSTEMD_SSH_OK user=onix uid=1000 pid1=systemd systemd=/nix/store/.*/lib/systemd/systemd version=systemd' \
ONIX_SSH_REMOTE_COMMAND="$(stone_systemd_remote_command)" \
ONIX_SSH_SUCCESS_MESSAGE="Phase 417 proved the image boots with systemd materialized as the PID 1 runtime payload." \
  "$SCRIPT_DIR/ssh-probe.sh" "${probe_args[@]}"

cat <<EOF

==> success
Phase 417 proved the booted ONIX image can use systemd for the active
systemd runtime payload while authenticated SSH still works.

Evidence logs:
  ${STATE_DIR#$ONIX_ROOT/}/phase417.*.log

EOF
