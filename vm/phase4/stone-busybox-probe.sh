#!/usr/bin/env bash
# vm/phase4/stone-busybox-probe.sh — Phase 411 live onix-busybox proof.
#
# Phase 410 proved the disk image points /usr/bin and /bin compatibility paths
# at the onix-busybox stone payload. Phase 411 boots the image and proves the
# existing serial, network, remote-inspection, and SSH behaviors still work with
# that command path.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${ONIX_STATE_DIR:-$ONIX_ROOT/vm/state}"

WAIT_SECONDS="${ONIX_STONE_BUSYBOX_SECONDS:-90}"
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
usage: stone-busybox-probe.sh [options]

  --seconds N      seconds to wait for each boot proof (default: $WAIT_SECONDS)
  --kill           stop existing Phase 411 QEMU probes and exit
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

stone_busybox_command() {
  local marker="$1"

  printf '/usr/bin/busybox sh -c '\''bb=/usr/bin/busybox; test -x "$bb"; "$bb" true; bin="$("$bb" readlink /bin 2>/dev/null || printf real-bin)"; shlink="$("$bb" readlink /usr/bin/sh 2>/dev/null || printf no-link)"; uid="$("$bb" id -u)"; printf "%s uid=%%s bin=%%s sh=%%s busybox=%%s\\n" "$uid" "$bin" "$shlink" "$bb"'\''\n' \
    "$marker"
}

stone_ssh_remote_command() {
  cat <<'EOF'
/usr/bin/busybox sh -c 'bb=/usr/bin/busybox; test -x "$bb"; "$bb" true; bin="$("$bb" readlink /bin 2>/dev/null || printf real-bin)"; shlink="$("$bb" readlink /usr/bin/sh 2>/dev/null || printf no-link)"; printf "ONIX_STONE_BUSYBOX_SSH_OK user=%s uid=%s bin=%s sh=%s busybox=%s\n" "$("$bb" id -un)" "$("$bb" id -u)" "$bin" "$shlink" "$bb"'
EOF
}

kill_all() {
  ONIX_SERIAL_CONSOLE_PROBE_NAME=p411ser \
    "$SCRIPT_DIR/serial-console-probe.sh" --kill || true
  ONIX_NETWORK_PROBE_NAME=p411net \
    "$SCRIPT_DIR/network-probe.sh" --kill || true
  ONIX_REMOTE_INSPECTION_PROBE_NAME=p411rem \
    "$SCRIPT_DIR/remote-inspection-probe.sh" --kill || true
  ONIX_SSH_PROBE_NAME=p411ssh \
    "$SCRIPT_DIR/ssh-probe.sh" --kill || true
}

if [[ "$KILL_ONLY" -eq 1 ]]; then
  kill_all
  exit 0
fi

[[ -f "$ONIX_ROOT/artifacts/onix-image/onix.raw" ]] \
  || die "missing ONIX image: artifacts/onix-image/onix.raw (run make phase 2 first)"

log "Phase 411 stone BusyBox live proof"
log "goal      : serial + network + remote inspection + SSH execute through /usr/bin/busybox"
log "window    : ${WAIT_SECONDS}s per probe"

kill_all >/dev/null 2>&1 || true

log "probe 1/4: serial shell uses onix-busybox"
ONIX_SERIAL_CONSOLE_PROBE_NAME=p411ser \
ONIX_SERIAL_BOOT_LOG="$STATE_DIR/phase411.serial-boot.log" \
ONIX_SERIAL_CONSOLE_LOG="$STATE_DIR/phase411.serial-shell.log" \
ONIX_SERIAL_CONSOLE_SOCKET="$STATE_DIR/phase411.serial.sock" \
ONIX_SERIAL_PROBE_LABEL="Phase 411 serial shell stone BusyBox proof" \
ONIX_SERIAL_PROOF_COMMAND="$(stone_busybox_command ONIX_STONE_BUSYBOX_SERIAL_OK)" \
ONIX_SERIAL_COMMAND_MARKER='ONIX_STONE_BUSYBOX_SERIAL_OK uid=0 .*busybox=/usr/bin/busybox' \
ONIX_SERIAL_SUCCESS_MESSAGE="Phase 411 proved the serial bootstrap shell can execute the stone BusyBox." \
  "$SCRIPT_DIR/serial-console-probe.sh" "${probe_args[@]}"

log "probe 2/4: network scripts use onix-busybox commands"
ONIX_NETWORK_PROBE_NAME=p411net \
ONIX_NETWORK_BOOT_LOG="$STATE_DIR/phase411.network-boot.log" \
ONIX_NETWORK_SERIAL_LOG="$STATE_DIR/phase411.network-serial.log" \
ONIX_NETWORK_SERIAL_SOCKET="$STATE_DIR/phase411.network.sock" \
ONIX_NETWORK_PROBE_LABEL="Phase 411 network stone BusyBox proof" \
ONIX_NETWORK_PROOF_COMMAND="/usr/lib/onix/bootstrap-network-proof && $(stone_busybox_command ONIX_STONE_BUSYBOX_NETWORK_OK)" \
ONIX_NETWORK_COMMAND_MARKER='ONIX_STONE_BUSYBOX_NETWORK_OK uid=0 .*busybox=/usr/bin/busybox' \
ONIX_NETWORK_SUCCESS_MESSAGE="Phase 411 proved bootstrap networking still works with stone BusyBox commands." \
  "$SCRIPT_DIR/network-probe.sh" "${probe_args[@]}"

log "probe 3/4: remote inspection listener uses onix-busybox nc/netstat"
ONIX_REMOTE_INSPECTION_PROBE_NAME=p411rem \
ONIX_REMOTE_INSPECTION_BOOT_LOG="$STATE_DIR/phase411.remote-boot.log" \
ONIX_REMOTE_INSPECTION_SERIAL_LOG="$STATE_DIR/phase411.remote-serial.log" \
ONIX_REMOTE_INSPECTION_SERIAL_SOCKET="$STATE_DIR/phase411.remote.sock" \
ONIX_REMOTE_INSPECTION_HOST_PORT="${ONIX_STONE_BUSYBOX_REMOTE_HOST_PORT:-7666}" \
ONIX_REMOTE_INSPECTION_PROBE_LABEL="Phase 411 remote inspection stone BusyBox proof" \
ONIX_REMOTE_INSPECTION_SERIAL_COMMAND="/usr/lib/onix/bootstrap-network-proof && /usr/lib/onix/bootstrap-remote-inspection-proof && $(stone_busybox_command ONIX_STONE_BUSYBOX_REMOTE_OK)" \
ONIX_REMOTE_INSPECTION_READY_MARKER='ONIX_STONE_BUSYBOX_REMOTE_OK uid=0 .*busybox=/usr/bin/busybox' \
ONIX_REMOTE_INSPECTION_SUCCESS_MESSAGE="Phase 411 proved remote inspection still works with stone BusyBox nc/netstat." \
  "$SCRIPT_DIR/remote-inspection-probe.sh" "${probe_args[@]}"

log "probe 4/4: SSH session uses onix-busybox commands"
ONIX_SSH_PROBE_NAME=p411ssh \
ONIX_SSH_BOOT_LOG="$STATE_DIR/phase411.ssh-boot.log" \
ONIX_SSH_SERIAL_LOG="$STATE_DIR/phase411.ssh-serial.log" \
ONIX_SSH_SERIAL_SOCKET="$STATE_DIR/phase411.ssh.sock" \
ONIX_SSH_HOST_PORT="${ONIX_STONE_BUSYBOX_SSH_HOST_PORT:-7627}" \
ONIX_SSH_PROBE_LABEL="Phase 411 SSH stone BusyBox proof" \
ONIX_SSH_SERIAL_COMMAND="/usr/lib/onix/bootstrap-network-proof && /usr/lib/onix/bootstrap-ssh-proof && $(stone_busybox_command ONIX_STONE_BUSYBOX_SSH_SERIAL_OK)" \
ONIX_SSH_READY_MARKER='ONIX_STONE_BUSYBOX_SSH_SERIAL_OK uid=0 .*busybox=/usr/bin/busybox' \
ONIX_SSH_MARKER='ONIX_STONE_BUSYBOX_SSH_OK user=onix uid=1000 .*busybox=/usr/bin/busybox' \
ONIX_SSH_REMOTE_COMMAND="$(stone_ssh_remote_command)" \
ONIX_SSH_SUCCESS_MESSAGE="Phase 411 proved authenticated SSH still works and executes stone BusyBox commands." \
  "$SCRIPT_DIR/ssh-probe.sh" "${probe_args[@]}"

cat <<EOF

==> success
Phase 411 proved the booted ONIX image can use onix-busybox for:

  - serial bootstrap shell
  - bootstrap QEMU user networking
  - host-to-guest TCP inspection
  - authenticated SSH command execution

Evidence logs:
  ${STATE_DIR#$ONIX_ROOT/}/phase411.*.log

EOF
