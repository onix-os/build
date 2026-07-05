#!/usr/bin/env bash
# vm/phase0/launch.sh — boot the ONIX forge (quarry) under QEMU/KVM.
#
#   ./launch.sh            boot the disk via its own grub-efi + OVMF (UEFI)
#   ./launch.sh --direct   boot via QEMU direct-kernel (bypasses grub; safety net)
#
# The disk is built by build-disk.sh. First boot: log in (mason/onix or the
# generated key) and run ./provision.sh to build moss + boulder.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

DIRECT=0
SNAPSHOT=0
DRY_RUN=0
BACKGROUND=0
WAIT_FOR_SSH=0
WAIT_TIMEOUT="${BOOT_WAIT_TIMEOUT:-240}"
LOGIN_PROMPT_GRACE="${LOGIN_PROMPT_GRACE:-20}"
DISPLAY_MODE="${DISPLAY_MODE:-vnc}"
SERIAL_LOG="${SERIAL_LOG:-$STATE_DIR/${VM_NAME}.serial.log}"
PIDFILE="$STATE_DIR/${VM_NAME}.pid"

usage() {
  cat >&2 <<EOF
usage: launch.sh [options]

  --direct         boot with QEMU -kernel/-initrd instead of grub/OVMF
  --snapshot       discard all disk writes on exit (throwaway experiments)
  --display MODE   gtk | sdl | vnc | none      (default: $DISPLAY_MODE)
  --background     launch QEMU in the background and return
  --wait           with --background: tail serial log until SSH is ready
  --wait-timeout N seconds to wait for SSH with --wait (default: $WAIT_TIMEOUT)
  --serial-log P   serial log path for --background (default: ${SERIAL_LOG#$ONIX_ROOT/})
  --cpus N         vCPUs                        (default: $VM_CPUS)
  --ram SIZE       memory, e.g. 8G              (default: $VM_RAM)
  --dry-run        print the QEMU command and exit
  -h, --help

ssh in:  ssh -p $SSH_PORT $BUILD_USER@127.0.0.1   (or ./ssh.sh)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --direct)   DIRECT=1 ;;
    --snapshot) SNAPSHOT=1 ;;
    --display)  DISPLAY_MODE="${2:?}"; shift ;;
    --background) BACKGROUND=1 ;;
    --wait)     WAIT_FOR_SSH=1 ;;
    --wait-timeout) WAIT_TIMEOUT="${2:?}"; shift ;;
    --serial-log) SERIAL_LOG="${2:?}"; shift ;;
    --cpus)     VM_CPUS="${2:?}"; shift ;;
    --ram)      VM_RAM="${2:?}"; shift ;;
    --dry-run)  DRY_RUN=1 ;;
    -h|--help)  usage; exit 0 ;;
    *) usage; die "unknown argument: $1" ;;
  esac
  shift
done

[[ "$WAIT_FOR_SSH" -eq 1 && "$BACKGROUND" -ne 1 ]] && die "--wait requires --background"

if [[ "$DRY_RUN" -ne 1 ]]; then
  need_cmd qemu-system-x86_64
  [[ -f "$DISK_IMG" ]] || die "no disk at ${DISK_IMG#$ONIX_ROOT/} — run ./build-disk.sh first"
fi

collect_qemu_pids() {
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -x "$QEMU_PROCESS_NAME" || true
  else
    ps -eo pid=,comm= | awk -v name="$QEMU_PROCESS_NAME" '$2 == name { print $1 }'
  fi
}

qemu_is_running() {
  [[ -n "$(collect_qemu_pids)" ]]
}

wait_for_ssh() {
  local deadline=$((SECONDS + WAIT_TIMEOUT))
  local first=1
  while :; do
    if "$ONIX_PHASE0_DIR/ssh.sh" "$BUILD_USER" true >/dev/null 2>&1; then
      log "boot       : SSH is ready"
      return 0
    fi
    if [[ "$first" -eq 0 ]] && ! qemu_is_running; then
      die "QEMU exited before SSH became ready"
    fi
    first=0
    [[ "$SECONDS" -lt "$deadline" ]] || die "timed out waiting ${WAIT_TIMEOUT}s for SSH on 127.0.0.1:$SSH_PORT"
    sleep 2
  done
}

serial_login_prompt_seen() {
  grep -qa "${VM_NAME} login:" "$SERIAL_LOG" 2>/dev/null
}

wait_for_batch_boot_ready() {
  local marker_deadline
  wait_for_ssh
  marker_deadline=$((SECONDS + LOGIN_PROMPT_GRACE))
  while ! serial_login_prompt_seen; do
    [[ "$SECONDS" -lt "$marker_deadline" ]] || {
      warn "boot       : SSH ready, but serial login prompt was not seen within ${LOGIN_PROMPT_GRACE}s; continuing"
      return 0
    }
    sleep 1
  done
  log "boot       : serial login prompt reached; continuing"
}

if [[ -w /dev/kvm ]]; then ACCEL=kvm; CPU_MODEL=host
else ACCEL=tcg; CPU_MODEL=max; warn "/dev/kvm not writable — slow TCG emulation"; fi

args=(
  -name "$VM_NAME,process=onix-$VM_NAME"
  -machine "q35,accel=$ACCEL"
  -cpu "$CPU_MODEL"
  -smp "$VM_CPUS"
  -m "$VM_RAM"
  -object "rng-random,filename=/dev/urandom,id=rng0"
  -device virtio-rng-pci,rng=rng0
  -device virtio-balloon-pci
  -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22"
  -device "virtio-net-pci,netdev=net0,mac=$MAC_ADDR"
  -drive "if=none,id=drive0,file=$DISK_IMG,format=$DISK_FORMAT,cache=writeback,discard=unmap"
)

if [[ "$DIRECT" -eq 1 ]]; then
  if [[ "$DRY_RUN" -ne 1 ]]; then
    [[ -f "$KERNEL_IMG" && -f "$INITRD_IMG" ]] || die "no exported kernel/initrd — rebuild with build-disk.sh"
  fi
  args+=(
    -device virtio-blk-pci,drive=drive0,bootindex=1
    -kernel "$KERNEL_IMG"
    -initrd "$INITRD_IMG"
    -append "root=LABEL=onix-root rootfstype=ext4 rw console=tty0 console=ttyS0,115200"
  )
else
  if [[ "$DRY_RUN" -eq 1 ]]; then
    if ! find_ovmf 2>/dev/null; then
      warn "no OVMF firmware detected; dry-run uses configured placeholder paths"
      OVMF_CODE="${ONIX_OVMF_CODE:-/path/to/OVMF_CODE.fd}"
    fi
  else
    ensure_ovmf_vars
  fi
  args+=(
    -device ich9-ahci,id=ahci
    -device ide-hd,drive=drive0,bus=ahci.0,bootindex=1
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
    -drive "if=pflash,format=raw,file=$OVMF_VARS"
  )
fi

[[ "$SNAPSHOT" -eq 1 ]] && args+=(-snapshot)

case "$DISPLAY_MODE" in
  gtk)
    [[ "$BACKGROUND" -eq 0 ]] || die "--background does not support display=gtk; use display=vnc or display=none"
    args+=(-vga virtio -display gtk)
    ;;
  sdl)
    [[ "$BACKGROUND" -eq 0 ]] || die "--background does not support display=sdl; use display=vnc or display=none"
    args+=(-vga virtio -display sdl)
    ;;
  vnc)
    args+=(-vga virtio -vnc 127.0.0.1:0)
    if [[ "$BACKGROUND" -eq 1 ]]; then
      args+=(-serial "file:$SERIAL_LOG")
    else
      args+=(-serial mon:stdio)
    fi
    ;;
  none)
    if [[ "$BACKGROUND" -eq 1 ]]; then
      args+=(-vga none -display none -serial "file:$SERIAL_LOG" -monitor none)
    else
      args+=(-vga none -nographic)
    fi
    ;;
  *)    die "unknown display mode: $DISPLAY_MODE (gtk|sdl|vnc|none)" ;;
esac

if [[ "$BACKGROUND" -eq 1 ]]; then
  mkdir -p "$STATE_DIR"
  args+=(-daemonize -pidfile "$PIDFILE")
fi

log "launching '$VM_NAME'  [$ACCEL/$CPU_MODEL, ${VM_CPUS} vCPU, ${VM_RAM} RAM, boot=$([[ $DIRECT -eq 1 ]] && echo direct-kernel || echo grub/OVMF), display=$DISPLAY_MODE]"
[[ "$SNAPSHOT" -eq 1 ]] && warn "snapshot mode: disk writes discarded on exit"
[[ "$DISPLAY_MODE" == vnc ]] && log "VNC: connect a viewer to 127.0.0.1:5900"
[[ "$BACKGROUND" -eq 1 ]] && log "serial log: ${SERIAL_LOG#$ONIX_ROOT/}"
log "ssh: ssh -p $SSH_PORT $BUILD_USER@127.0.0.1   (login mason/onix, or ./ssh.sh)"

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf 'qemu-system-x86_64'; printf ' %q' "${args[@]}"; printf '\n'
  exit 0
fi

if [[ "$BACKGROUND" -eq 1 ]]; then
  if qemu_is_running; then
    warn "QEMU already running for $QEMU_PROCESS_NAME; not launching another copy"
  else
    : > "$SERIAL_LOG"
    qemu-system-x86_64 "${args[@]}"
  fi

  if [[ "$WAIT_FOR_SSH" -eq 1 ]]; then
    log "boot       : tailing serial log until SSH is ready"
    touch "$SERIAL_LOG"
    tail -n +1 -f "$SERIAL_LOG" &
    tail_pid=$!
    cleanup_tail() {
      kill "$tail_pid" >/dev/null 2>&1 || true
      wait "$tail_pid" >/dev/null 2>&1 || true
    }
    trap cleanup_tail EXIT
    wait_for_batch_boot_ready
    cleanup_tail
    trap - EXIT
  fi
  exit 0
fi

exec qemu-system-x86_64 "${args[@]}"
