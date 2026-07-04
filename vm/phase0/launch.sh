#!/usr/bin/env bash
# vm/phase0/launch.sh — boot the Onix forge (quarry) under QEMU/KVM.
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
if [[ -n "${DISPLAY_MODE:-}" ]]; then :
elif [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]]; then DISPLAY_MODE=gtk
else DISPLAY_MODE=vnc; fi

usage() {
  cat >&2 <<EOF
usage: launch.sh [options]

  --direct         boot with QEMU -kernel/-initrd instead of grub/OVMF
  --snapshot       discard all disk writes on exit (throwaway experiments)
  --display MODE   gtk | sdl | vnc | none      (default: $DISPLAY_MODE)
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
    --cpus)     VM_CPUS="${2:?}"; shift ;;
    --ram)      VM_RAM="${2:?}"; shift ;;
    --dry-run)  DRY_RUN=1 ;;
    -h|--help)  usage; exit 0 ;;
    *) usage; die "unknown argument: $1" ;;
  esac
  shift
done

if [[ "$DRY_RUN" -ne 1 ]]; then
  need_cmd qemu-system-x86_64
  [[ -f "$DISK_IMG" ]] || die "no disk at ${DISK_IMG#$ONIX_ROOT/} — run ./build-disk.sh first"
fi

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
  gtk)  args+=(-vga virtio -display gtk) ;;
  sdl)  args+=(-vga virtio -display sdl) ;;
  vnc)  args+=(-vga virtio -vnc 127.0.0.1:0 -serial mon:stdio) ;;
  none) args+=(-vga none -nographic) ;;
  *)    die "unknown display mode: $DISPLAY_MODE (gtk|sdl|vnc|none)" ;;
esac

log "launching '$VM_NAME'  [$ACCEL/$CPU_MODEL, ${VM_CPUS} vCPU, ${VM_RAM} RAM, boot=$([[ $DIRECT -eq 1 ]] && echo direct-kernel || echo grub/OVMF), display=$DISPLAY_MODE]"
[[ "$SNAPSHOT" -eq 1 ]] && warn "snapshot mode: disk writes discarded on exit"
[[ "$DISPLAY_MODE" == vnc ]] && log "VNC: connect a viewer to 127.0.0.1:5900"
log "ssh: ssh -p $SSH_PORT $BUILD_USER@127.0.0.1   (login mason/onix, or ./ssh.sh)"

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf 'qemu-system-x86_64'; printf ' %q' "${args[@]}"; printf '\n'
  exit 0
fi
exec qemu-system-x86_64 "${args[@]}"
