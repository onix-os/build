#!/usr/bin/env bash
# vm/phase2/build-image-skeleton.sh — create a non-booting ONIX disk skeleton.
#
# Phase 205 takes the host-built root tree:
#
#   artifacts/onix-root-tree/
#
# and copies it into a real root filesystem inside:
#
#   artifacts/onix-image/onix.raw
#
# Phase 205 is intentionally non-booting. It creates partitions/filesystems and
# proves the root payload lands correctly.
#
# Phase 206 reuses this script with --boot-skeleton to add the first
# systemd-boot/BLS skeleton to the existing image. That still does not install a
# kernel/initramfs/init system, so the image is not a complete bootable OS yet.
#
# Phase 211 reuses this script with --kernel-payload to install the first
# kernel/initramfs boot payload into /boot/ONIX. The default source is the
# exported forge payload under vm/state/, but the script verifies that the
# initramfs can handle ONIX's XFS root before copying it.
set -euo pipefail

SUDO_ENV_FILE=""
if [[ "${1:-}" == "--onix-env-file" ]]; then
  SUDO_ENV_FILE="${2:?missing env-file path}"
  shift 2
  # shellcheck source=/dev/null
  source "$SUDO_ENV_FILE"
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SELF="$SCRIPT_DIR/build-image-skeleton.sh"

IMAGE_DIR="${ONIX_IMAGE_DIR:-$ONIX_ROOT/artifacts/onix-image}"
IMAGE_RAW="${ONIX_IMAGE_RAW:-$IMAGE_DIR/onix.raw}"
WORK_DIR="${ONIX_IMAGE_WORK_DIR:-$ONIX_ROOT/artifacts/onix-image-work}"
ROOT_TREE_DIR="${ONIX_ROOT_TREE_DIR:-$ONIX_ROOT/artifacts/onix-root-tree}"
KERNEL_SOURCE="${ONIX_KERNEL_IMAGE:-$ONIX_ROOT/vm/state/vmlinuz-virt}"
INITRAMFS_SOURCE="${ONIX_INITRAMFS_IMAGE:-$ONIX_ROOT/vm/state/initramfs-virt}"

IMAGE_SIZE="${ONIX_IMAGE_SIZE:-12G}"
ESP_SIZE="${ONIX_IMAGE_ESP_SIZE:-512M}"
BOOT_SIZE="${ONIX_IMAGE_BOOT_SIZE:-1G}"
ROOT_SIZE="${ONIX_IMAGE_ROOT_SIZE:-8G}"

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

need_file() {
  [[ -f "$1" ]] || die "missing expected file: ${1#$ONIX_ROOT/}"
}

need_dir() {
  [[ -d "$1" ]] || die "missing expected directory: ${1#$ONIX_ROOT/}"
}

safe_generated_paths() {
  case "$IMAGE_RAW" in
    "$ONIX_ROOT"/artifacts/onix-image/*.raw) ;;
    *) die "refusing unsafe image path outside artifacts/onix-image/*.raw: $IMAGE_RAW" ;;
  esac
  case "$WORK_DIR" in
    "$ONIX_ROOT"/artifacts/onix-image-work) ;;
    "$ONIX_ROOT"/artifacts/onix-image-work/*) ;;
    *) die "refusing unsafe work path outside artifacts/onix-image-work: $WORK_DIR" ;;
  esac
}

if [[ "${1:-}" == "--sudoers-check" ]]; then
  [[ $EUID -eq 0 ]] || die "sudoers check must run through sudo"
  log "sudoers  : passwordless build-image-skeleton OK"
  exit 0
fi

MODE="build"
SUDO_MODE_ARGS=()
case "${1:-}" in
  --cleanup-stale) MODE="cleanup-stale"; SUDO_MODE_ARGS=(--cleanup-stale); shift ;;
  --clean) MODE="clean"; SUDO_MODE_ARGS=(--clean); shift ;;
  --boot-skeleton) MODE="boot-skeleton"; SUDO_MODE_ARGS=(--boot-skeleton); shift ;;
  --kernel-payload) MODE="kernel-payload"; SUDO_MODE_ARGS=(--kernel-payload); shift ;;
  "") ;;
  *) die "unknown option: $1" ;;
esac

safe_generated_paths

have_stale_mounts() {
  [[ -d "$WORK_DIR" ]] || return 1
  findmnt -R "$WORK_DIR" >/dev/null 2>&1
}

have_stale_loops() {
  [[ -f "$IMAGE_RAW" ]] || return 1
  losetup -j "$IMAGE_RAW" 2>/dev/null | grep -q .
}

need_root() {
  if [[ $EUID -eq 0 ]]; then
    return 0
  fi

  need_cmd sudo
  env_file="$(mktemp "${TMPDIR:-/tmp}/onix-image-env.XXXXXX")"
  chmod 600 "$env_file"
  {
    for name in \
      ONIX_IMAGE_DIR ONIX_IMAGE_RAW ONIX_IMAGE_WORK_DIR ONIX_ROOT_TREE_DIR \
      ONIX_IMAGE_SIZE ONIX_IMAGE_ESP_SIZE ONIX_IMAGE_BOOT_SIZE ONIX_IMAGE_ROOT_SIZE \
      ONIX_SYSTEMD_BOOT_EFI ONIX_KERNEL_IMAGE ONIX_INITRAMFS_IMAGE \
      PATH
    do
      value="${!name-}"
      printf 'export %s=%q\n' "$name" "$value"
    done
  } > "$env_file"
  trap 'rm -f "$env_file"' EXIT
  log "escalating to root via sudo (passwordless after make phase 001 / make doctor) …"
  sudo -- "$SELF" --onix-env-file "$env_file" "$@"
  exit $?
}

unmount_tree() {
  local root="$1"
  local targets=()
  local target
  [[ -n "$root" && -d "$root" ]] || return 0
  sync
  while IFS= read -r target; do
    targets+=("$target")
  done < <(findmnt -R -n -o TARGET "$root" 2>/dev/null | sort -r)
  for target in "${targets[@]}"; do
    umount "$target" 2>/dev/null || umount -l "$target" 2>/dev/null || true
  done
}

detach_image_loops() {
  local loopdev
  [[ -f "$IMAGE_RAW" ]] || return 0
  while IFS= read -r loopdev; do
    [[ -n "$loopdev" ]] || continue
    warn "detaching $loopdev"
    losetup -d "$loopdev" 2>/dev/null || true
  done < <(losetup -j "$IMAGE_RAW" 2>/dev/null | awk -F: '{ print $1 }')
}

cleanup_stale() {
  log "cleaning stale Phase 2 image mounts/loops"
  unmount_tree "$WORK_DIR"
  detach_image_loops
}

clean_generated() {
  cleanup_stale
  log "removing generated Phase 2 image artifacts"
  rm -rf "$IMAGE_DIR" "$WORK_DIR"
}

if [[ "$MODE" == "cleanup-stale" || "$MODE" == "clean" ]]; then
  need_cmd findmnt
  need_cmd losetup
  if [[ $EUID -ne 0 ]]; then
    if ! have_stale_mounts && ! have_stale_loops; then
      if [[ "$MODE" == "clean" ]]; then
        log "removing generated Phase 2 image artifacts"
        rm -rf "$IMAGE_DIR" "$WORK_DIR"
      else
        log "phase2    : no stale image mounts/loops"
      fi
      exit 0
    fi
  fi
  need_root "${SUDO_MODE_ARGS[@]}"
fi

if [[ "$MODE" == "clean" ]]; then
  clean_generated
  [[ -n "${SUDO_UID:-}" ]] && chown -R "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$ONIX_ROOT/artifacts" 2>/dev/null || true
  exit 0
fi

if [[ "$MODE" == "cleanup-stale" ]]; then
  cleanup_stale
  exit 0
fi

if [[ $EUID -ne 0 ]]; then
  "$SCRIPT_DIR/verify-image-contract.sh"
  need_root "${SUDO_MODE_ARGS[@]}"
fi

need_cmd awk
need_cmd blkid
need_cmd cmp
need_cmd cpio
need_cmd find
need_cmd findmnt
need_cmd grep
need_cmd gzip
need_cmd install
need_cmd losetup
need_cmd mkdir
need_cmd mkfs.fat
need_cmd mkfs.xfs
need_cmd mount
need_cmd partprobe
need_cmd readlink
need_cmd rm
need_cmd sed
need_cmd sgdisk
need_cmd sort
need_cmd stat
need_cmd sync
need_cmd tar
need_cmd truncate
need_cmd umount

if [[ "$MODE" == "build" ]]; then
  need_dir "$ROOT_TREE_DIR"
  need_file "$ROOT_TREE_DIR/usr/lib/os-release"
  need_file "$ROOT_TREE_DIR/etc/fstab"

  log "Phase 205 input check: image contract"
  "$SCRIPT_DIR/verify-image-contract.sh"
fi

if have_stale_mounts || have_stale_loops; then
  die "stale Phase 2 image mounts/loops exist; run make cleanup"
fi

MNT=""
DISK_DEV=""

cleanup() {
  set +e
  if [[ -n "$MNT" && -d "$MNT" ]]; then
    unmount_tree "$MNT"
  fi
  [[ -n "$DISK_DEV" ]] && losetup -d "$DISK_DEV" >/dev/null 2>&1
  rm -rf "$WORK_DIR"
  [[ -n "${SUDO_UID:-}" ]] && chown -R "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$IMAGE_DIR" "$WORK_DIR" 2>/dev/null
  [[ -n "$SUDO_ENV_FILE" ]] && rm -f "$SUDO_ENV_FILE"
}
trap cleanup EXIT

part_path() {
  printf '%sp%s' "$DISK_DEV" "$1"
}

wait_for_partitions() {
  local i
  for i in $(seq 1 80); do
    [[ -b "$(part_path 1)" && -b "$(part_path 2)" && -b "$(part_path 3)" && -b "$(part_path 4)" ]] && return 0
    partprobe "$DISK_DEV" 2>/dev/null || true
    sleep 0.25
  done
  die "loop partitions did not appear for $DISK_DEV"
}

expect_blkid() {
  local part="$1"
  local want_label="$2"
  local want_type="$3"
  local got_label got_type
  got_label="$(blkid -s LABEL -o value "$part")"
  got_type="$(blkid -s TYPE -o value "$part")"
  [[ "$got_label" == "$want_label" ]] || die "$part label is $got_label, expected $want_label"
  [[ "$got_type" == "$want_type" ]] || die "$part type is $got_type, expected $want_type"
}

expect_gpt_name() {
  local idx="$1"
  local want="$2"
  sgdisk -i "$idx" "$DISK_DEV" | grep -q "Partition name: '$want'" \
    || die "GPT partition $idx is not named $want"
}

find_systemd_boot_efi() {
  local bootctl_path bootctl_root candidate

  if [[ -n "${ONIX_SYSTEMD_BOOT_EFI:-}" ]]; then
    [[ -f "$ONIX_SYSTEMD_BOOT_EFI" ]] || die "ONIX_SYSTEMD_BOOT_EFI is set but missing: $ONIX_SYSTEMD_BOOT_EFI"
    printf '%s\n' "$ONIX_SYSTEMD_BOOT_EFI"
    return 0
  fi

  if command -v bootctl >/dev/null 2>&1; then
    bootctl_path="$(readlink -f "$(command -v bootctl)")"
    bootctl_root="${bootctl_path%/bin/bootctl}"
    candidate="$bootctl_root/lib/systemd/boot/efi/systemd-bootx64.efi"
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  for candidate in /nix/store/*-systemd-*/lib/systemd/boot/efi/systemd-bootx64.efi; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  die "missing systemd-bootx64.efi; run direnv reload so flake.nix exports ONIX_SYSTEMD_BOOT_EFI"
}

verify_kernel_payload_sources() {
  local initrd_list

  log "verifying kernel/initramfs source payload"
  need_file "$KERNEL_SOURCE"
  need_file "$INITRAMFS_SOURCE"
  [[ -s "$KERNEL_SOURCE" ]] || die "kernel source is empty: $KERNEL_SOURCE"
  [[ -s "$INITRAMFS_SOURCE" ]] || die "initramfs source is empty: $INITRAMFS_SOURCE"

  initrd_list="$(mktemp "${TMPDIR:-/tmp}/onix-initramfs-list.XXXXXX")"
  if ! gzip -dc "$INITRAMFS_SOURCE" | cpio -it >"$initrd_list" 2>/dev/null; then
    rm -f "$initrd_list"
    die "could not list initramfs contents: $INITRAMFS_SOURCE"
  fi

  grep -qx 'init' "$initrd_list" \
    || { rm -f "$initrd_list"; die "initramfs does not contain /init"; }
  grep -Eq '(^|/)usr/lib/modules/[^/]+/kernel/fs/xfs/xfs[.]ko([.]gz)?$' "$initrd_list" \
    || { rm -f "$initrd_list"; die "initramfs lacks xfs.ko; rebuild forge payload with XFS support"; }
  grep -Eq '(^|/)usr/lib/modules/[^/]+/kernel/fs/fat/vfat[.]ko([.]gz)?$' "$initrd_list" \
    || { rm -f "$initrd_list"; die "initramfs lacks vfat.ko; it must understand the /boot filesystem"; }
  grep -Eq '(^|/)usr/lib/modules/[^/]+/kernel/drivers/block/virtio_blk[.]ko([.]gz)?$' "$initrd_list" \
    || { rm -f "$initrd_list"; die "initramfs lacks virtio_blk.ko; it must see the QEMU disk"; }

  rm -f "$initrd_list"
  echo "payload : OK"
  echo "kernel  : ${KERNEL_SOURCE#$ONIX_ROOT/}"
  echo "initramfs: ${INITRAMFS_SOURCE#$ONIX_ROOT/}"
}

attach_existing_image() {
  need_file "$IMAGE_RAW"
  log "attaching existing raw image via loop"
  DISK_DEV="$(losetup --find --show --partscan "$IMAGE_RAW")"
  [[ -n "$DISK_DEV" ]] || die "no free loop device"
  partprobe "$DISK_DEV" 2>/dev/null || true
  wait_for_partitions
}

verify_partition_contract() {
  log "verifying GPT names and filesystem labels"
  expect_gpt_name 1 "ONIX-ESP"
  expect_gpt_name 2 "ONIX-BOOT"
  expect_gpt_name 3 "onix-root"
  expect_gpt_name 4 "ONIX-PERSIST"
  expect_blkid "$(part_path 1)" "ONIX-ESP" "vfat"
  expect_blkid "$(part_path 2)" "ONIX-BOOT" "vfat"
  expect_blkid "$(part_path 3)" "onix-root" "xfs"
  expect_blkid "$(part_path 4)" "ONIX-PERSIST" "xfs"
}

mount_root_esp_boot() {
  log "mounting root, ESP, and boot partitions"
  MNT="$WORK_DIR/mnt"
  mkdir -p "$MNT"
  mount "$(part_path 3)" "$MNT"
  mkdir -p "$MNT/efi" "$MNT/boot"
  mount "$(part_path 1)" "$MNT/efi"
  mount "$(part_path 2)" "$MNT/boot"
}

install_boot_skeleton() {
  local boot_efi
  boot_efi="$(find_systemd_boot_efi)"

  log "Phase 206 input check: image contract"
  "$SCRIPT_DIR/verify-image-contract.sh"

  if have_stale_mounts || have_stale_loops; then
    die "stale Phase 2 image mounts/loops exist; run make cleanup"
  fi

  rm -rf "$WORK_DIR"
  mkdir -p "$WORK_DIR"

  attach_existing_image
  verify_partition_contract
  mount_root_esp_boot

  log "installing systemd-boot EFI binaries"
  install -Dm0644 "$boot_efi" "$MNT/efi/EFI/systemd/systemd-bootx64.efi"
  install -Dm0644 "$boot_efi" "$MNT/efi/EFI/BOOT/BOOTX64.EFI"

  log "writing loader.conf on the ESP"
  install -dm0755 "$MNT/efi/loader"
  cat > "$MNT/efi/loader/loader.conf" <<'EOF'
default onix-phase-206.conf
timeout 3
console-mode max
editor no
EOF
  chmod 0644 "$MNT/efi/loader/loader.conf"

  log "writing future BLS entry on ONIX-BOOT"
  install -dm0755 "$MNT/boot/loader/entries" "$MNT/boot/ONIX"
  cat > "$MNT/boot/loader/entries/onix-phase-206.conf" <<'EOF'
title ONIX
sort-key onix
version phase-206
linux /ONIX/vmlinuz
initrd /ONIX/initramfs.img
options root=LABEL=onix-root rootfstype=xfs rw init=/usr/lib/systemd/systemd systemd.unit=multi-user.target
EOF
  chmod 0644 "$MNT/boot/loader/entries/onix-phase-206.conf"

  cat > "$MNT/boot/ONIX/README.phase206" <<'EOF'
ONIX Phase 206 boot skeleton

This partition now contains the future BLS entry path for systemd-boot.

The image is still intentionally not a full bootable OS:

- /boot/ONIX/vmlinuz is not installed yet
- /boot/ONIX/initramfs.img is not installed yet
- /usr/lib/systemd/systemd is not installed yet

Phase 206 proves the bootloader layout, not the kernel/init/userspace layer.
EOF
  chmod 0644 "$MNT/boot/ONIX/README.phase206"

  log "verifying Phase 206 boot skeleton"
  test -s "$MNT/efi/EFI/systemd/systemd-bootx64.efi"
  test -s "$MNT/efi/EFI/BOOT/BOOTX64.EFI"
  cmp -s "$MNT/efi/EFI/systemd/systemd-bootx64.efi" "$MNT/efi/EFI/BOOT/BOOTX64.EFI"
  grep -q '^default onix-phase-206\.conf$' "$MNT/efi/loader/loader.conf"
  test -f "$MNT/boot/loader/entries/onix-phase-206.conf"
  grep -q '^title ONIX$' "$MNT/boot/loader/entries/onix-phase-206.conf"
  grep -q '^linux /ONIX/vmlinuz$' "$MNT/boot/loader/entries/onix-phase-206.conf"
  grep -q 'root=LABEL=onix-root' "$MNT/boot/loader/entries/onix-phase-206.conf"
  grep -q 'init=/usr/lib/systemd/systemd' "$MNT/boot/loader/entries/onix-phase-206.conf"
  test -f "$MNT/boot/ONIX/README.phase206"
  test ! -e "$MNT/boot/ONIX/vmlinuz"
  test ! -e "$MNT/boot/ONIX/initramfs.img"
  test ! -e "$MNT/usr/lib/systemd/systemd"

  log "ESP preview"
  find "$MNT/efi" -maxdepth 4 -mindepth 1 | sort | sed "s#^$MNT/efi#/efi#" | sed -n '1,80p'

  log "BOOT preview"
  find "$MNT/boot" -maxdepth 4 -mindepth 1 | sort | sed "s#^$MNT/boot#/boot#" | sed -n '1,80p'

  sync

  log "success"
  echo "image : $IMAGE_RAW"
  echo "status: systemd-boot/BLS skeleton installed; kernel/initramfs/systemd still pending"
}

install_kernel_payload() {
  log "Phase 211 input check: kernel/initramfs contract"
  "$SCRIPT_DIR/verify-kernel-initramfs-plan.sh"
  verify_kernel_payload_sources

  if have_stale_mounts || have_stale_loops; then
    die "stale Phase 2 image mounts/loops exist; run make cleanup"
  fi

  rm -rf "$WORK_DIR"
  mkdir -p "$WORK_DIR"

  attach_existing_image
  verify_partition_contract
  mount_root_esp_boot

  log "verifying Phase 206 boot skeleton exists first"
  test -f "$MNT/efi/loader/loader.conf"
  test -f "$MNT/boot/loader/entries/onix-phase-206.conf"
  grep -q '^linux /ONIX/vmlinuz$' "$MNT/boot/loader/entries/onix-phase-206.conf"
  grep -q '^initrd /ONIX/initramfs.img$' "$MNT/boot/loader/entries/onix-phase-206.conf"

  log "installing first kernel + initramfs payload"
  install -Dm0644 "$KERNEL_SOURCE" "$MNT/boot/ONIX/vmlinuz"
  install -Dm0644 "$INITRAMFS_SOURCE" "$MNT/boot/ONIX/initramfs.img"

  log "writing Phase 211 BLS entry"
  cat > "$MNT/efi/loader/loader.conf" <<'EOF'
default onix-phase-211.conf
timeout 3
console-mode max
editor no
EOF
  chmod 0644 "$MNT/efi/loader/loader.conf"

  cat > "$MNT/boot/loader/entries/onix-phase-211.conf" <<'EOF'
title ONIX
sort-key onix
version phase-211
linux /ONIX/vmlinuz
initrd /ONIX/initramfs.img
options root=LABEL=onix-root rootfstype=xfs rw init=/usr/lib/systemd/systemd systemd.unit=multi-user.target console=tty0 console=ttyS0,115200
EOF
  chmod 0644 "$MNT/boot/loader/entries/onix-phase-211.conf"

  cat > "$MNT/boot/ONIX/README.phase211" <<EOF
ONIX Phase 211 kernel/initramfs payload

This partition now contains the first boot payload:

- /boot/ONIX/vmlinuz
- /boot/ONIX/initramfs.img

Source kernel:

${KERNEL_SOURCE#$ONIX_ROOT/}

Source initramfs:

${INITRAMFS_SOURCE#$ONIX_ROOT/}

This is the first imported boot payload so systemd-boot can load a real kernel
and initramfs. It is not yet the final ONIX onix-kernel/onix-initramfs package
story.

The image still needs a real /usr/lib/systemd/systemd payload before it can
complete the userspace handoff.
EOF
  chmod 0644 "$MNT/boot/ONIX/README.phase211"

  log "verifying Phase 211 kernel/initramfs payload"
  test -s "$MNT/boot/ONIX/vmlinuz"
  test -s "$MNT/boot/ONIX/initramfs.img"
  cmp -s "$KERNEL_SOURCE" "$MNT/boot/ONIX/vmlinuz"
  cmp -s "$INITRAMFS_SOURCE" "$MNT/boot/ONIX/initramfs.img"
  grep -q '^default onix-phase-211\.conf$' "$MNT/efi/loader/loader.conf"
  test -f "$MNT/boot/loader/entries/onix-phase-211.conf"
  grep -q '^version phase-211$' "$MNT/boot/loader/entries/onix-phase-211.conf"
  grep -q '^linux /ONIX/vmlinuz$' "$MNT/boot/loader/entries/onix-phase-211.conf"
  grep -q '^initrd /ONIX/initramfs.img$' "$MNT/boot/loader/entries/onix-phase-211.conf"
  grep -q 'root=LABEL=onix-root' "$MNT/boot/loader/entries/onix-phase-211.conf"
  grep -q 'rootfstype=xfs' "$MNT/boot/loader/entries/onix-phase-211.conf"
  grep -q 'init=/usr/lib/systemd/systemd' "$MNT/boot/loader/entries/onix-phase-211.conf"
  grep -q 'console=ttyS0,115200' "$MNT/boot/loader/entries/onix-phase-211.conf"
  test -f "$MNT/boot/ONIX/README.phase211"
  test ! -e "$MNT/usr/lib/systemd/systemd"

  log "BOOT preview"
  find "$MNT/boot" -maxdepth 4 -mindepth 1 | sort | sed "s#^$MNT/boot#/boot#" | sed -n '1,100p'

  sync

  log "success"
  echo "image : $IMAGE_RAW"
  echo "status: kernel/initramfs payload installed; systemd userspace still pending"
}

if [[ "$MODE" == "boot-skeleton" ]]; then
  install_boot_skeleton
  exit 0
fi

if [[ "$MODE" == "kernel-payload" ]]; then
  install_kernel_payload
  exit 0
fi

log "rebuilding generated raw image: ${IMAGE_RAW#$ONIX_ROOT/}"
rm -rf "$WORK_DIR"
mkdir -p "$IMAGE_DIR" "$WORK_DIR"
rm -f "$IMAGE_RAW"
truncate -s "$IMAGE_SIZE" "$IMAGE_RAW"

log "attaching raw disk via loop"
DISK_DEV="$(losetup --find --show --partscan "$IMAGE_RAW")"
[[ -n "$DISK_DEV" ]] || die "no free loop device"

log "partitioning GPT on $DISK_DEV"
sgdisk --zap-all "$DISK_DEV" >/dev/null
sgdisk -n1:0:+"$ESP_SIZE"  -t1:EF00 -c1:"ONIX-ESP"     "$DISK_DEV" >/dev/null
sgdisk -n2:0:+"$BOOT_SIZE" -t2:EA00 -c2:"ONIX-BOOT"    "$DISK_DEV" >/dev/null
sgdisk -n3:0:+"$ROOT_SIZE" -t3:8300 -c3:"onix-root"    "$DISK_DEV" >/dev/null
sgdisk -n4:0:0             -t4:8300 -c4:"ONIX-PERSIST" "$DISK_DEV" >/dev/null
partprobe "$DISK_DEV" 2>/dev/null || true
wait_for_partitions

log "formatting filesystems"
mkfs.fat -F32 -n ONIX-ESP "$(part_path 1)" >/dev/null
mkfs.fat -F32 -n ONIX-BOOT "$(part_path 2)" >/dev/null
mkfs.xfs -q -f -L onix-root "$(part_path 3)"
mkfs.xfs -q -f -L ONIX-PERSIST "$(part_path 4)"

verify_partition_contract

log "mounting root partition"
MNT="$WORK_DIR/mnt"
mkdir -p "$MNT"
mount "$(part_path 3)" "$MNT"

log "copying root tree into onix-root with root:root ownership"
tar -C "$ROOT_TREE_DIR" -cpf - . | tar -C "$MNT" --no-same-owner -xpf -

log "mounting child filesystems"
mkdir -p "$MNT/efi" "$MNT/boot" "$MNT/persist"
mount "$(part_path 1)" "$MNT/efi"
mount "$(part_path 2)" "$MNT/boot"
mount "$(part_path 4)" "$MNT/persist"

log "materializing persistent bind-source directories"
mkdir -p "$MNT/persist/home" "$MNT/persist/nix" "$MNT/nix"
chmod 0755 "$MNT/persist" "$MNT/persist/home" "$MNT/persist/nix" "$MNT/nix"

log "verifying non-booting disk skeleton"
test -f "$MNT/usr/lib/os-release"
test -f "$MNT/etc/fstab"
test -L "$MNT/etc/os-release"
test "$(stat -c '%u:%g' "$MNT/usr/lib/os-release")" = "0:0"
test "$(stat -c '%a' "$MNT/tmp")" = "1777"
test -d "$MNT/dev"
test -d "$MNT/proc"
test -d "$MNT/sys"
test -d "$MNT/run"
test -d "$MNT/efi"
test -d "$MNT/boot"
test -d "$MNT/persist/home"
test -d "$MNT/persist/nix"
test -d "$MNT/nix"
grep -q '^NAME="ONIX"$' "$MNT/usr/lib/os-release"
grep -q 'LABEL=ONIX-ESP' "$MNT/etc/fstab"
grep -q 'LABEL=ONIX-BOOT' "$MNT/etc/fstab"
grep -q 'LABEL=onix-root' "$MNT/etc/fstab"
grep -q 'LABEL=ONIX-PERSIST' "$MNT/etc/fstab"

if [[ -e "$MNT/efi/EFI/BOOT/BOOTX64.EFI" ]]; then
  die "Phase 205 must stay non-booting, but an EFI loader exists"
fi

log "partition table"
sgdisk -p "$DISK_DEV"

log "image content preview"
find "$MNT" -maxdepth 3 -mindepth 1 | sort | sed "s#^$MNT##" | sed -n '1,120p'

sync

log "success"
echo "image : $IMAGE_RAW"
echo "size  : $IMAGE_SIZE"
echo "status: non-booting root/disk skeleton"
