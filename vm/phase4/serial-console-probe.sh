#!/usr/bin/env bash
# vm/phase4/serial-console-probe.sh — prove the Phase 403 serial console.
#
# This is intentionally separate from Phase 212's passive boot probe. Phase 403
# must prove two-way serial I/O: ONIX prints a console-ready marker, then the
# host sends a command and sees root-shell output come back.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${ONIX_STATE_DIR:-$ONIX_ROOT/vm/state}"
IMAGE_RAW="${ONIX_IMAGE_RAW:-$ONIX_ROOT/artifacts/onix-image/onix.raw}"

PROBE_NAME="${ONIX_SERIAL_CONSOLE_PROBE_NAME:-phase403}"
QEMU_PROCESS_NAME="onix-$PROBE_NAME"
SERIAL_LOG="${ONIX_SERIAL_CONSOLE_LOG:-$STATE_DIR/${PROBE_NAME}.serial.log}"
BOOT_LOG="${ONIX_SERIAL_BOOT_LOG:-$STATE_DIR/${PROBE_NAME}.boot.log}"
SERIAL_SOCKET="${ONIX_SERIAL_CONSOLE_SOCKET:-$STATE_DIR/${PROBE_NAME}.serial.sock}"
OVMF_VARS="$STATE_DIR/${PROBE_NAME}_OVMF_VARS.fd"

VM_CPUS="${ONIX_SERIAL_CONSOLE_CPUS:-2}"
VM_RAM="${ONIX_SERIAL_CONSOLE_RAM:-2G}"
WAIT_SECONDS="${ONIX_SERIAL_CONSOLE_SECONDS:-75}"
MAC_ADDR="${ONIX_SERIAL_CONSOLE_MAC:-52:54:00:66:49:13}"
NETDEV_ARG="${ONIX_QEMU_NETDEV:-user,id=net0}"

READY_MARKER="${ONIX_SERIAL_READY_MARKER:-ONIX_BOOTSTRAP_SERIAL_CONSOLE_READY}"
COMMAND_MARKER="${ONIX_SERIAL_COMMAND_MARKER:-ONIX_SERIAL_COMMAND_OK uid=0}"
PROBE_LABEL="${ONIX_SERIAL_PROBE_LABEL:-Phase 403 serial console probe}"
PROOF_COMMAND="${ONIX_SERIAL_PROOF_COMMAND:-echo ONIX_SERIAL_COMMAND_OK uid=\$(/bin/id -u) kernel=\$(/bin/uname -s) pwd=\$(pwd)}"
SUCCESS_MESSAGE="${ONIX_SERIAL_SUCCESS_MESSAGE:-Phase 403 proved two-way bootstrap serial root console access.}"
HOST_PROOF_COMMAND="${ONIX_SERIAL_HOST_PROOF_COMMAND:-}"
HOST_PROOF_MARKER="${ONIX_SERIAL_HOST_PROOF_MARKER:-}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*"
}

warn() {
  printf 'warn: %s\n' "$*" >&2
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

usage() {
  cat >&2 <<EOF
usage: serial-console-probe.sh [options]

  --seconds N      seconds to wait for serial proof (default: $WAIT_SECONDS)
  --serial-log P   serial log path (default: ${SERIAL_LOG#$ONIX_ROOT/})
  --boot-log P     boot-console log path (default: ${BOOT_LOG#$ONIX_ROOT/})
  --kill           stop an existing Phase 403 QEMU probe and exit
  --dry-run        print the QEMU command and exit
  -h, --help
EOF
}

DRY_RUN=0
KILL_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --seconds) WAIT_SECONDS="${2:?missing seconds}"; shift ;;
    --serial-log) SERIAL_LOG="${2:?missing path}"; shift ;;
    --boot-log) BOOT_LOG="${2:?missing path}"; shift ;;
    --kill) KILL_ONLY=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "unknown argument: $1" ;;
  esac
  shift
done

collect_pids() {
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -x "$QEMU_PROCESS_NAME" || true
  else
    ps -eo pid=,comm= | awk -v name="$QEMU_PROCESS_NAME" '$2 == name { print $1 }'
  fi
}

kill_probe() {
  local pids=()
  local alive=()
  mapfile -t pids < <(collect_pids)
  if [[ "${#pids[@]}" -eq 0 ]]; then
    log "qemu      : no running Phase 403 probe ($QEMU_PROCESS_NAME)"
    return 0
  fi

  log "qemu      : stopping $QEMU_PROCESS_NAME pid(s): ${pids[*]}"
  kill -TERM "${pids[@]}" 2>/dev/null || true

  local deadline=$((SECONDS + 8))
  while :; do
    mapfile -t alive < <(collect_pids)
    [[ "${#alive[@]}" -eq 0 ]] && { log "qemu      : stopped"; return 0; }
    [[ "$SECONDS" -ge "$deadline" ]] && break
    sleep 1
  done

  warn "qemu      : still running after TERM; forcing pid(s): ${alive[*]}"
  kill -KILL "${alive[@]}" 2>/dev/null || true
  log "qemu      : killed"
}

if [[ "$KILL_ONLY" -eq 1 ]]; then
  kill_probe
  exit 0
fi

need_cmd awk
if [[ -n "$HOST_PROOF_COMMAND" ]]; then
  need_cmd bash
fi
need_cmd grep
need_cmd install
need_cmd nc
need_cmd qemu-system-x86_64
need_cmd sed
need_cmd sort
need_cmd tail

[[ -f "$IMAGE_RAW" ]] || die "missing ONIX image: ${IMAGE_RAW#$ONIX_ROOT/}; run make phase 2 first"

find_ovmf() {
  local c
  local -a code_candidates=(
    "${ONIX_OVMF_CODE:-}"
    /usr/share/edk2/x64/OVMF_CODE.4m.fd
    /usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd
    /usr/share/OVMF/OVMF_CODE.4m.fd
    /usr/share/edk2-ovmf/x64/OVMF_CODE.fd
    /usr/share/OVMF/OVMF_CODE.fd
    /usr/share/qemu/OVMF_CODE.fd
  )
  OVMF_CODE=""
  for c in "${code_candidates[@]}"; do
    [[ -n "$c" && -f "$c" ]] && { OVMF_CODE="$c"; break; }
  done
  [[ -n "$OVMF_CODE" ]] || return 1
  OVMF_VARS_TEMPLATE="${ONIX_OVMF_VARS_TEMPLATE:-${OVMF_CODE/OVMF_CODE/OVMF_VARS}}"
  [[ -f "$OVMF_VARS_TEMPLATE" ]] || return 1
}

find_ovmf || die "no OVMF firmware; run direnv reload so ONIX_OVMF_CODE and ONIX_OVMF_VARS_TEMPLATE exist"

if [[ -w /dev/kvm ]]; then
  ACCEL=kvm
  CPU_MODEL=host
else
  ACCEL=tcg
  CPU_MODEL=max
  warn "/dev/kvm not writable — slow TCG emulation"
fi

mkdir -p "$STATE_DIR"
install -m 0644 "$OVMF_VARS_TEMPLATE" "$OVMF_VARS"
chmod u+rw "$OVMF_VARS"

args=(
  -name "$PROBE_NAME,process=$QEMU_PROCESS_NAME"
  -machine "q35,accel=$ACCEL"
  -cpu "$CPU_MODEL"
  -smp "$VM_CPUS"
  -m "$VM_RAM"
  -object "rng-random,filename=/dev/urandom,id=rng0"
  -device virtio-rng-pci,rng=rng0
  -device virtio-balloon-pci
  -netdev "$NETDEV_ARG"
  -device "virtio-net-pci,netdev=net0,mac=$MAC_ADDR"
  -drive "if=none,id=drive0,file=$IMAGE_RAW,format=raw,cache=writeback,discard=unmap,snapshot=on"
  -device virtio-blk-pci,drive=drive0,bootindex=1
  -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
  -drive "if=pflash,format=raw,file=$OVMF_VARS"
  -vga none
  -display none
  -serial "file:$BOOT_LOG"
  -chardev "socket,id=onixserial,path=$SERIAL_SOCKET,server=on,wait=off,signal=off"
  -serial chardev:onixserial
  -monitor none
  -daemonize
)

log "$PROBE_LABEL"
log "image     : ${IMAGE_RAW#$ONIX_ROOT/}"
log "qemu      : $ACCEL/$CPU_MODEL, ${VM_CPUS} vCPU, ${VM_RAM} RAM"
log "netdev    : $NETDEV_ARG"
log "boot log : ${BOOT_LOG#$ONIX_ROOT/} (ttyS0)"
log "shell log: ${SERIAL_LOG#$ONIX_ROOT/} (ttyS1)"
log "shell io : ${SERIAL_SOCKET#$ONIX_ROOT/}"
log "window    : ${WAIT_SECONDS}s"

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf 'qemu-system-x86_64'
  printf ' %q' "${args[@]}"
  printf '\n'
  exit 0
fi

kill_probe >/dev/null 2>&1 || true
: > "$SERIAL_LOG"
: > "$BOOT_LOG"
rm -f "$SERIAL_SOCKET"

maybe_print_line() {
  local line="$1"
  if printf '%s\n' "$line" |
    grep -aE 'Linux version|Welcome to|Multi-User System|ONIX_BOOTSTRAP|ONIX_SERIAL|Kernel panic|switch_root|Failed|error:' >/dev/null 2>&1; then
    printf '%s\n' "$line"
  fi
}

read_serial_until() {
  local pattern="$1"
  local seconds="$2"
  local poke="${3:-0}"
  local line
  local deadline=$((SECONDS + seconds))
  local next_poke=$((SECONDS + 3))

  while [[ "$SECONDS" -lt "$deadline" ]]; do
      if IFS= read -r -t 1 line <&"${SERIAL_RUN[0]}"; then
      printf '%s\n' "$line" >> "$SERIAL_LOG"
      maybe_print_line "$line"
      if printf '%s\n' "$line" | grep -qaE "$pattern"; then
        return 0
      fi
      if printf '%s\n' "$line" | grep -qa 'Kernel panic'; then
        return 2
      fi
    else
      if [[ -n "${QEMU_PID:-}" ]] && ! kill -0 "$QEMU_PID" >/dev/null 2>&1; then
        return 3
      fi
      if [[ "$poke" -eq 1 && "$SECONDS" -ge "$next_poke" && -n "${SERIAL_RUN[1]-}" ]]; then
        printf '\n' >&"${SERIAL_RUN[1]}" || true
        next_poke=$((SECONDS + 3))
      fi
    fi
  done

  return 1
}

cleanup_qemu() {
  set +e
  if [[ -n "${SERIAL_RUN[1]-}" ]]; then
    printf 'poweroff -f\n' >&"${SERIAL_RUN[1]}" || true
  fi
  sleep 1
  kill_probe >/dev/null 2>&1 || true
  rm -f "$SERIAL_SOCKET"
}

log "launching QEMU"
qemu-system-x86_64 "${args[@]}"
QEMU_PID="$(collect_pids | head -n1)"
[[ -n "$QEMU_PID" ]] || die "QEMU did not start"
trap cleanup_qemu EXIT

log "connecting to serial socket"
deadline=$((SECONDS + 10))
while [[ ! -S "$SERIAL_SOCKET" ]]; do
  [[ "$SECONDS" -lt "$deadline" ]] || die "serial socket did not appear: ${SERIAL_SOCKET#$ONIX_ROOT/}"
  sleep 0.2
done
coproc SERIAL_RUN { nc -U "$SERIAL_SOCKET"; }

log "waiting for bootstrap serial console service"
if ! read_serial_until "$READY_MARKER" "$WAIT_SECONDS" 1; then
  printf '%s\n' '--- ttyS1 shell log ---' >&2
  sed -n '1,220p' "$SERIAL_LOG" >&2
  printf '%s\n' '--- ttyS0 boot log tail ---' >&2
  tail -n 160 "$BOOT_LOG" >&2 || true
  die "serial console ready marker was not observed: $READY_MARKER"
fi

log "serial console ready marker observed; sending command"
sleep 2
printf '\n' >&"${SERIAL_RUN[1]}"
printf '%s\n' "$PROOF_COMMAND" >&"${SERIAL_RUN[1]}"

if ! read_serial_until "$COMMAND_MARKER" 20; then
  printf '%s\n' '--- ttyS1 shell log ---' >&2
  sed -n '1,260p' "$SERIAL_LOG" >&2
  printf '%s\n' '--- ttyS0 boot log tail ---' >&2
  tail -n 160 "$BOOT_LOG" >&2 || true
  die "serial command proof was not observed: $COMMAND_MARKER"
fi

if [[ -n "$HOST_PROOF_COMMAND" ]]; then
  log "running host-side proof"
  if ! host_output="$(bash -c "$HOST_PROOF_COMMAND" 2>&1)"; then
    printf '%s\n' '--- host proof output ---' >&2
    printf '%s\n' "$host_output" >&2
    die "host-side proof command failed"
  fi

  printf '%s\n' "$host_output"
  if [[ -n "$HOST_PROOF_MARKER" ]] &&
     ! printf '%s\n' "$host_output" | grep -qaE "$HOST_PROOF_MARKER"; then
    die "host-side proof marker was not observed: $HOST_PROOF_MARKER"
  fi
fi

cleanup_qemu
trap - EXIT

log "serial evidence"
if grep -qa "$READY_MARKER" "$SERIAL_LOG"; then
  echo "console : observed $READY_MARKER"
else
  die "serial log does not contain console ready marker"
fi
grep -qaE "$COMMAND_MARKER" "$SERIAL_LOG" \
  || die "serial log does not contain expected command marker"
grep -qa 'Reached target .*Multi-User System' "$BOOT_LOG" \
  || warn "multi-user.target marker was not observed before serial proof"

echo "command : observed $COMMAND_MARKER"
if [[ -n "$HOST_PROOF_MARKER" ]]; then
  echo "host    : observed $HOST_PROOF_MARKER"
fi
echo
echo "==> success"
echo "$SUCCESS_MESSAGE"
