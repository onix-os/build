#!/usr/bin/env bash
# vm/phase2/boot-probe.sh — Phase 212 first ONIX QEMU boot probe.
#
# This is a probe, not a permanent VM launcher.
# It boots the generated ONIX image long enough to prove whether systemd-boot
# can load the kernel/initramfs and how far early boot gets.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${ONIX_STATE_DIR:-$ONIX_ROOT/vm/state}"
IMAGE_RAW="${ONIX_IMAGE_RAW:-$ONIX_ROOT/artifacts/onix-image/onix.raw}"

PROBE_NAME="${ONIX_BOOT_PROBE_NAME:-phase212}"
QEMU_PROCESS_NAME="onix-$PROBE_NAME"
PIDFILE="$STATE_DIR/${PROBE_NAME}.pid"
SERIAL_LOG="${ONIX_BOOT_PROBE_SERIAL_LOG:-$STATE_DIR/${PROBE_NAME}.serial.log}"
OVMF_VARS="$STATE_DIR/${PROBE_NAME}_OVMF_VARS.fd"

VM_CPUS="${ONIX_BOOT_PROBE_CPUS:-2}"
VM_RAM="${ONIX_BOOT_PROBE_RAM:-2G}"
WAIT_SECONDS="${ONIX_BOOT_PROBE_SECONDS:-45}"
MAC_ADDR="${ONIX_BOOT_PROBE_MAC:-52:54:00:66:49:12}"
ATTACHED="${ATTACHED:-0}"
DISPLAY_MODE="${ONIX_BOOT_PROBE_DISPLAY:-serial}"

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
usage: boot-probe.sh [options]

  --seconds N      seconds to let QEMU run (default: $WAIT_SECONDS)
  --serial-log P   serial log path (default: ${SERIAL_LOG#$ONIX_ROOT/})
  --attached       run QEMU in the foreground so you can watch it
                   make form: ATTACHED=1 make phase 212
                   display: ONIX_BOOT_PROBE_DISPLAY=serial|gtk|sdl|vnc|none
  --kill           stop an existing Phase 212 QEMU probe and exit
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
    --attached) ATTACHED=1 ;;
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
    log "qemu      : no running Phase 212 probe ($QEMU_PROCESS_NAME)"
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

need_cmd qemu-system-x86_64
need_cmd grep
need_cmd install
need_cmd sed
need_cmd sort
need_cmd tail

[[ -f "$IMAGE_RAW" ]] || die "missing ONIX image: ${IMAGE_RAW#$ONIX_ROOT/}; run make phase 211"

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

case "$ATTACHED" in
  1|yes|true|on) ATTACHED=1 ;;
  0|no|false|off|"") ATTACHED=0 ;;
  *) die "ATTACHED must be 0/1, yes/no, true/false, or on/off" ;;
esac

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
  -netdev "user,id=net0"
  -device "virtio-net-pci,netdev=net0,mac=$MAC_ADDR"
  -drive "if=none,id=drive0,file=$IMAGE_RAW,format=raw,cache=writeback,discard=unmap,snapshot=on"
  -device virtio-blk-pci,drive=drive0,bootindex=1
  -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
  -drive "if=pflash,format=raw,file=$OVMF_VARS"
)

if [[ "$ATTACHED" -eq 1 ]]; then
  case "$DISPLAY_MODE" in
    serial)
      args+=(-vga none -display none -serial mon:stdio)
      ;;
    gtk)
      args+=(-vga virtio -display gtk -serial "file:$SERIAL_LOG" -monitor none)
      ;;
    sdl)
      args+=(-vga virtio -display sdl -serial "file:$SERIAL_LOG" -monitor none)
      ;;
    vnc)
      args+=(-vga virtio -vnc 127.0.0.1:0 -serial "file:$SERIAL_LOG" -monitor none)
      ;;
    none)
      args+=(-vga none -nographic)
      ;;
    *)
      die "unknown ONIX_BOOT_PROBE_DISPLAY=$DISPLAY_MODE (serial|gtk|sdl|vnc|none)"
      ;;
  esac
else
  args+=(
    -vga none
    -display none
    -serial "file:$SERIAL_LOG"
    -monitor none
    -daemonize
    -pidfile "$PIDFILE"
  )
fi

log "Phase 212 first ONIX boot probe"
log "image     : ${IMAGE_RAW#$ONIX_ROOT/}"
log "qemu      : $ACCEL/$CPU_MODEL, ${VM_CPUS} vCPU, ${VM_RAM} RAM"
if [[ "$ATTACHED" -eq 1 ]]; then
  log "mode      : attached foreground display=$DISPLAY_MODE"
  if [[ "$DISPLAY_MODE" == serial || "$DISPLAY_MODE" == none ]]; then
    log "serial    : connected to this terminal"
  else
    log "serial log: ${SERIAL_LOG#$ONIX_ROOT/}"
  fi
  [[ "$DISPLAY_MODE" == vnc ]] && log "VNC       : connect a viewer to 127.0.0.1:5900"
  if [[ "$DISPLAY_MODE" == serial || "$DISPLAY_MODE" == none ]]; then
    log "exit      : press Ctrl-a then x, or press Ctrl-C"
  else
    log "exit      : close the QEMU window or press Ctrl-C in this terminal"
  fi
else
  log "mode      : automatic headless probe"
  log "serial log: ${SERIAL_LOG#$ONIX_ROOT/}"
  log "window    : ${WAIT_SECONDS}s"
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf 'qemu-system-x86_64'
  printf ' %q' "${args[@]}"
  printf '\n'
  exit 0
fi

kill_probe >/dev/null 2>&1 || true
: > "$SERIAL_LOG"

log "launching QEMU"
if [[ "$ATTACHED" -eq 1 ]]; then
  exec qemu-system-x86_64 "${args[@]}"
fi

qemu-system-x86_64 "${args[@]}"

tail -n +1 -f "$SERIAL_LOG" &
tail_pid=$!
cleanup_tail() {
  kill "$tail_pid" >/dev/null 2>&1 || true
  wait "$tail_pid" >/dev/null 2>&1 || true
}
trap cleanup_tail EXIT

deadline=$((SECONDS + WAIT_SECONDS))
while [[ "$SECONDS" -lt "$deadline" ]]; do
  if grep -qa 'Kernel panic\|switch_root:.*systemd\|Run /usr/lib/systemd/systemd as init process' "$SERIAL_LOG"; then
    log "probe     : useful boot evidence observed; stopping early"
    break
  fi
  sleep 1
done
cleanup_tail
trap - EXIT

kill_probe

log "serial evidence"
if [[ ! -s "$SERIAL_LOG" ]]; then
  die "serial log is empty; OVMF/systemd-boot/kernel did not produce serial output"
fi

if ! grep -qa 'Linux version' "$SERIAL_LOG"; then
  sed -n '1,160p' "$SERIAL_LOG" >&2
  die "kernel did not appear to start"
fi

grep -qa 'root=LABEL=onix-root' "$SERIAL_LOG" \
  || die "kernel command line did not include root=LABEL=onix-root"
grep -qa 'init=/usr/lib/systemd/systemd' "$SERIAL_LOG" \
  || die "kernel command line did not include init=/usr/lib/systemd/systemd"

if grep -qa '/usr/lib/systemd/systemd' "$SERIAL_LOG"; then
  echo "handoff : observed systemd init path in boot log"
else
  warn "handoff : systemd init path not observed beyond kernel command line"
fi

if grep -qa 'Kernel panic' "$SERIAL_LOG"; then
  echo "result  : kernel reached a panic; this is useful Phase 212 evidence"
else
  echo "result  : kernel started; no kernel panic observed inside probe window"
fi

echo
echo "==> success"
echo "Phase 212 captured first ONIX boot evidence; systemd userspace is still pending."
