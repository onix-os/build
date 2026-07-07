#!/usr/bin/env bash
# vm/phase4/network-probe.sh — prove Phase 404 bootstrap networking.
#
# This is a thin wrapper over the Phase 403 serial probe. Phase 404 still uses
# the temporary ttyS1 bootstrap shell as the control channel, but the command it
# sends proves a different thing: the booted image has configured QEMU user-mode
# networking and can report its IPv4 address from inside ONIX.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${ONIX_STATE_DIR:-$ONIX_ROOT/vm/state}"

export ONIX_SERIAL_CONSOLE_PROBE_NAME="${ONIX_NETWORK_PROBE_NAME:-phase404}"
export ONIX_SERIAL_BOOT_LOG="${ONIX_NETWORK_BOOT_LOG:-$STATE_DIR/phase404.boot.log}"
export ONIX_SERIAL_CONSOLE_LOG="${ONIX_NETWORK_SERIAL_LOG:-$STATE_DIR/phase404.serial.log}"
export ONIX_SERIAL_CONSOLE_SOCKET="${ONIX_NETWORK_SERIAL_SOCKET:-$STATE_DIR/phase404.serial.sock}"
export ONIX_SERIAL_PROBE_LABEL="${ONIX_NETWORK_PROBE_LABEL:-Phase 404 bootstrap network probe}"
export ONIX_SERIAL_PROOF_COMMAND="${ONIX_NETWORK_PROOF_COMMAND:-/usr/lib/onix/bootstrap-network-proof}"
export ONIX_SERIAL_COMMAND_MARKER="${ONIX_NETWORK_COMMAND_MARKER:-ONIX_NETWORK_OK iface=[^[:space:]]+ ip=10\\.0\\.2\\.15 router=10\\.0\\.2\\.2}"
export ONIX_SERIAL_SUCCESS_MESSAGE="${ONIX_NETWORK_SUCCESS_MESSAGE:-Phase 404 proved minimal QEMU user networking inside the booted ONIX image.}"

exec "$SCRIPT_DIR/serial-console-probe.sh" "$@"
