#!/usr/bin/env bash
# vm/phase4/remote-inspection-probe.sh — prove Phase 405 remote inspection.
#
# This wraps the serial probe with QEMU host port forwarding enabled. The serial
# side waits until ONIX says the guest listener is ready; then the host side
# connects to 127.0.0.1:7665 and expects the remote inspection marker.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${ONIX_STATE_DIR:-$ONIX_ROOT/vm/state}"

HOST_PORT="${ONIX_REMOTE_INSPECTION_HOST_PORT:-7665}"
GUEST_PORT="${ONIX_REMOTE_INSPECTION_GUEST_PORT:-6649}"
MARKER="${ONIX_REMOTE_INSPECTION_MARKER:-ONIX_REMOTE_INSPECTION_OK name=ONIX phase=405}"

export ONIX_REMOTE_INSPECTION_HOST_PORT="$HOST_PORT"
export ONIX_REMOTE_INSPECTION_GUEST_PORT="$GUEST_PORT"
export ONIX_REMOTE_INSPECTION_MARKER="$MARKER"

export ONIX_SERIAL_CONSOLE_PROBE_NAME="${ONIX_REMOTE_INSPECTION_PROBE_NAME:-phase405}"
export ONIX_SERIAL_BOOT_LOG="${ONIX_REMOTE_INSPECTION_BOOT_LOG:-$STATE_DIR/phase405.boot.log}"
export ONIX_SERIAL_CONSOLE_LOG="${ONIX_REMOTE_INSPECTION_SERIAL_LOG:-$STATE_DIR/phase405.serial.log}"
export ONIX_SERIAL_CONSOLE_SOCKET="${ONIX_REMOTE_INSPECTION_SERIAL_SOCKET:-$STATE_DIR/phase405.serial.sock}"
export ONIX_SERIAL_PROBE_LABEL="${ONIX_REMOTE_INSPECTION_PROBE_LABEL:-Phase 405 remote inspection probe}"
export ONIX_QEMU_NETDEV="${ONIX_QEMU_NETDEV:-user,id=net0,hostfwd=tcp:127.0.0.1:${HOST_PORT}-:${GUEST_PORT}}"
export ONIX_SERIAL_PROOF_COMMAND="${ONIX_REMOTE_INSPECTION_SERIAL_COMMAND:-/usr/lib/onix/bootstrap-network-proof && /usr/lib/onix/bootstrap-remote-inspection-proof}"
export ONIX_SERIAL_COMMAND_MARKER="${ONIX_REMOTE_INSPECTION_READY_MARKER:-ONIX_REMOTE_INSPECTION_READY port=${GUEST_PORT}}"
export ONIX_SERIAL_HOST_PROOF_COMMAND="${ONIX_REMOTE_INSPECTION_HOST_COMMAND:-$SCRIPT_DIR/remote-inspection-host-check.sh}"
export ONIX_SERIAL_HOST_PROOF_MARKER="$MARKER"
export ONIX_SERIAL_SUCCESS_MESSAGE="${ONIX_REMOTE_INSPECTION_SUCCESS_MESSAGE:-Phase 405 proved host-to-guest TCP inspection through QEMU port forwarding.}"

exec "$SCRIPT_DIR/serial-console-probe.sh" "$@"
