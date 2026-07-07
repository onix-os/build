#!/usr/bin/env bash
# vm/phase4/ssh-probe.sh — prove Phase 406 authenticated SSH.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${ONIX_STATE_DIR:-$ONIX_ROOT/vm/state}"

HOST_PORT="${ONIX_SSH_HOST_PORT:-7626}"
GUEST_PORT="${ONIX_SSH_GUEST_PORT:-22}"
SSH_USER="${ONIX_SSH_USER:-onix}"
SSH_UID="${ONIX_SSH_UID:-1000}"
MARKER="${ONIX_SSH_MARKER:-ONIX_SSH_OK user=${SSH_USER} uid=${SSH_UID}}"
KEY="${ONIX_SSH_CLIENT_KEY:-$STATE_DIR/id_ed25519}"

export ONIX_SSH_HOST_PORT="$HOST_PORT"
export ONIX_SSH_GUEST_PORT="$GUEST_PORT"
export ONIX_SSH_USER="$SSH_USER"
export ONIX_SSH_UID="$SSH_UID"
export ONIX_SSH_CLIENT_KEY="$KEY"
export ONIX_SSH_MARKER="$MARKER"

export ONIX_SERIAL_CONSOLE_PROBE_NAME="${ONIX_SSH_PROBE_NAME:-phase406}"
export ONIX_SERIAL_BOOT_LOG="${ONIX_SSH_BOOT_LOG:-$STATE_DIR/phase406.boot.log}"
export ONIX_SERIAL_CONSOLE_LOG="${ONIX_SSH_SERIAL_LOG:-$STATE_DIR/phase406.serial.log}"
export ONIX_SERIAL_CONSOLE_SOCKET="${ONIX_SSH_SERIAL_SOCKET:-$STATE_DIR/phase406.serial.sock}"
export ONIX_SERIAL_PROBE_LABEL="${ONIX_SSH_PROBE_LABEL:-Phase 406 SSH proof}"
export ONIX_QEMU_NETDEV="${ONIX_QEMU_NETDEV:-user,id=net0,hostfwd=tcp:127.0.0.1:${HOST_PORT}-:${GUEST_PORT}}"
export ONIX_SERIAL_PROOF_COMMAND="${ONIX_SSH_SERIAL_COMMAND:-/usr/lib/onix/bootstrap-network-proof && /usr/lib/onix/bootstrap-ssh-proof}"
export ONIX_SERIAL_COMMAND_MARKER="${ONIX_SSH_READY_MARKER:-ONIX_SSH_READY user=${SSH_USER} port=${GUEST_PORT}}"
export ONIX_SERIAL_HOST_PROOF_COMMAND="${ONIX_SSH_HOST_COMMAND:-$SCRIPT_DIR/ssh-host-check.sh}"
export ONIX_SERIAL_HOST_PROOF_MARKER="$MARKER"
export ONIX_SERIAL_SUCCESS_MESSAGE="${ONIX_SSH_SUCCESS_MESSAGE:-Phase 406 proved authenticated SSH access through QEMU port forwarding.}"

exec "$SCRIPT_DIR/serial-console-probe.sh" "$@"
