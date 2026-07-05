#!/usr/bin/env bash
# vm/phase0/build-disk.sh — build a bootable musl forge disk from the Alpine minirootfs.
#
#   minirootfs.tar.gz  ->  raw disk (GPT: ONIX-ESP + ext4 onix-root)
#                          -> extract rootfs -> chroot-setup.sh -> grub-efi
#
# Needs root (loop device / mkfs / mount / chroot). Re-execs itself via sudo, so
# with the passwordless rule installed by ./install-sudoers.sh it runs without a
# prompt (and an agent can run it unattended). All produced artifacts are
# chowned back to the invoking user. Re-run with --force to rebuild.
set -euo pipefail

SUDO_ENV_FILE=""
if [[ "${1:-}" == "--onix-env-file" ]]; then
  SUDO_ENV_FILE="${2:?missing env-file path}"
  shift 2
  # shellcheck source=/dev/null
  source "$SUDO_ENV_FILE"
fi
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

SELF="$ONIX_PHASE0_DIR/build-disk.sh"

if [[ "${1:-}" == "--sudoers-check" ]]; then
  [[ $EUID -eq 0 ]] || die "sudoers check must run through sudo"
  log "sudoers  : passwordless build-disk OK"
  exit 0
fi

if [[ $EUID -ne 0 ]]; then
  need_cmd sudo
  env_file="$(mktemp "${TMPDIR:-/tmp}/onix-build-env.XXXXXX")"
  chmod 600 "$env_file"
  {
    for name in \
      ONIX_DOWNLOAD_DIR ONIX_STATE_DIR ONIX_OVMF_CODE ONIX_OVMF_VARS_TEMPLATE \
      VM_NAME BUILD_USER ALPINE_VERSION ALPINE_BRANCH ALPINE_ARCH ALPINE_MIRROR \
      KERNEL_FLAVOR OS_TOOLS_REPO OS_TOOLS_REF VM_CPUS VM_RAM DISK_SIZE DISK_FORMAT ONIX_DISK_IMG SSH_PORT MAC_ADDR ROOT_PW \
      PATH
    do
      value="${!name-}"
      printf 'export %s=%q\n' "$name" "$value"
    done
  } > "$env_file"
  trap 'rm -f "$env_file"' EXIT
  log "escalating to root via sudo (passwordless once ./install-sudoers.sh has run) …"
  sudo -- "$SELF" --onix-env-file "$env_file" "$@"
  exit $?
fi

need_cmd truncate; need_cmd losetup; need_cmd findmnt; need_cmd sgdisk; need_cmd partprobe
need_cmd mkfs.fat; need_cmd mkfs.ext4; need_cmd mount; need_cmd umount
need_cmd tar; need_cmd modprobe; need_cmd chroot

CLEANUP_STALE=0
[[ "${1:-}" == "--cleanup-stale" ]] && { CLEANUP_STALE=1; shift; }
INSPECT=0
[[ "${1:-}" == "--inspect" ]] && { INSPECT=1; shift; }
FORCE=0
[[ "${1:-}" == "--force" || "${1:-}" == "-f" ]] && FORCE=1

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

have_stale_mounts() {
  findmnt -rn -o TARGET,SOURCE \
    | awk '$1 ~ "^/tmp/tmp\\.[^/]+$" && $2 ~ "^/dev/(loop|nbd)[0-9]+p[0-9]+$" { found=1 } END { exit found ? 0 : 1 }'
}

cleanup_stale() {
  local root loopdev
  log "cleaning stale ONIX loop/NBD mount trees"
  while IFS= read -r root; do
    [[ -n "$root" ]] || continue
    warn "unmounting stale tree: $root"
    unmount_tree "$root"
    rmdir "$root" 2>/dev/null || true
  done < <(findmnt -rn -o TARGET,SOURCE \
    | awk '$1 ~ "^/tmp/tmp\\.[^/]+$" && $2 ~ "^/dev/(loop|nbd)[0-9]+p[0-9]+$" { print $1 }' \
    | sort -r -u)

  log "detaching stale loop devices for ${DISK_IMG#$ONIX_ROOT/}"
  while IFS= read -r loopdev; do
    [[ -n "$loopdev" ]] || continue
    warn "detaching $loopdev"
    losetup -d "$loopdev" 2>/dev/null || true
  done < <(losetup -a | awk -F: -v img="$DISK_IMG" -v imgbase="$(basename "$DISK_IMG")" \
    '$0 ~ img || $0 ~ imgbase { print $1 }')
}

if [[ "$CLEANUP_STALE" -eq 1 ]]; then
  cleanup_stale
  exit 0
fi

if have_stale_mounts; then
  die "stale ONIX disk mounts exist under /tmp; run 'make cleanup' before building"
fi

if [[ "$INSPECT" -ne 1 ]]; then
  find_ovmf >/dev/null 2>&1 || die "no OVMF_CODE/OVMF_VARS firmware — run 'direnv reload' so flake.nix exports ONIX_OVMF_CODE, or set ONIX_OVMF_CODE + ONIX_OVMF_VARS_TEMPLATE"
fi

mount_chroot_api() {
  log "mounting isolated /proc /sys /dev for chroot"
  mkdir -p "$MNT/proc" "$MNT/sys" "$MNT/dev"
  mount -t proc proc "$MNT/proc"
  mount -t sysfs sysfs "$MNT/sys"
  mount -t tmpfs -o mode=755,nosuid,strictatime tmpfs "$MNT/dev"

  mknod -m 666 "$MNT/dev/null" c 1 3
  mknod -m 666 "$MNT/dev/zero" c 1 5
  mknod -m 666 "$MNT/dev/full" c 1 7
  mknod -m 666 "$MNT/dev/random" c 1 8
  mknod -m 666 "$MNT/dev/urandom" c 1 9
  mknod -m 666 "$MNT/dev/tty" c 5 0
  ln -s /proc/self/fd "$MNT/dev/fd"
  ln -s /proc/self/fd/0 "$MNT/dev/stdin"
  ln -s /proc/self/fd/1 "$MNT/dev/stdout"
  ln -s /proc/self/fd/2 "$MNT/dev/stderr"

  # GRUB probes the mounted root/ESP devices. Expose only this build's loop
  # disk nodes, not the host's full /dev or /dev/pts.
  create_chroot_block_node "$DISK_DEV"
  create_chroot_block_node "${DISK_DEV}p1"
  create_chroot_block_node "${DISK_DEV}p2"
}

create_chroot_block_node() {
  local dev="$1"
  local name major_minor major minor
  [[ -b "$dev" ]] || die "expected block device does not exist: $dev"
  name="$(basename "$dev")"
  major_minor="$(stat -c '%t:%T' "$dev")"
  major="$((16#${major_minor%:*}))"
  minor="$((16#${major_minor#*:}))"
  mknod -m 660 "$MNT/dev/$name" b "$major" "$minor"
}

attach_disk() {
  local mode="$1"
  log "attaching raw disk via loop ($mode)"
  modprobe loop 2>/dev/null || true
  if [[ "$mode" == ro ]]; then
    DISK_DEV="$(losetup --find --show --partscan --read-only "$DISK_IMG")"
  else
    DISK_DEV="$(losetup --find --show --partscan "$DISK_IMG")"
  fi
  [[ -n "$DISK_DEV" ]] || die "no free loop device"
  partprobe "$DISK_DEV" 2>/dev/null || true; sleep 0.5
}

wait_for_partitions() {
  local i
  for i in $(seq 1 40); do
    [[ -b "${DISK_DEV}p1" && -b "${DISK_DEV}p2" ]] && return 0
    partprobe "$DISK_DEV" 2>/dev/null || true
    sleep 0.25
  done
  die "loop partitions did not appear for $DISK_DEV"
}

if [[ "$INSPECT" -eq 1 ]]; then
  [[ -f "$DISK_IMG" ]] || die "no disk at ${DISK_IMG#$ONIX_ROOT/} — run ./build-disk.sh first"
  MNT=""; DISK_DEV=""
  cleanup() {
    set +e
    if [[ -n "$MNT" && -d "$MNT" ]]; then
      unmount_tree "$MNT"
      rmdir "$MNT" 2>/dev/null
    fi
    [[ -n "$DISK_DEV" ]] && losetup -d "$DISK_DEV" >/dev/null 2>&1
    [[ -n "$SUDO_ENV_FILE" ]] && rm -f "$SUDO_ENV_FILE"
  }
  trap cleanup EXIT

  attach_disk ro
  wait_for_partitions
  log "partition table"
  sgdisk -p "$DISK_DEV"

  MNT="$(mktemp -d)"
  mount -o ro,noload "${DISK_DEV}p2" "$MNT"
  mkdir -p "$MNT/efi"
  mount -o ro "${DISK_DEV}p1" "$MNT/efi"

  log "EFI partition files"
  find "$MNT/efi" -maxdepth 5 -print | sed "s#^$MNT/efi#/efi#"

  log "root /boot files"
  find "$MNT/boot" -maxdepth 4 -print | sed "s#^$MNT#/root#"

  if [[ -f "$MNT/efi/EFI/BOOT/BOOTX64.EFI" ]]; then
    log "found removable EFI loader: /efi/EFI/BOOT/BOOTX64.EFI"
  else
    die "missing /efi/EFI/BOOT/BOOTX64.EFI"
  fi
  exit 0
fi

[[ -f "$ROOTFS_PATH" ]] || die "no rootfs tarball — run ./fetch-rootfs.sh first"
if [[ -f "$DISK_IMG" && "$FORCE" -ne 1 ]]; then
  die "disk already exists: ${DISK_IMG#$ONIX_ROOT/} (pass --force to rebuild, or ./clean.sh)"
fi

ensure_ssh_key                       # created root-owned here; chowned back in cleanup
SSH_PUBKEY="$(cat "$SSH_KEY.pub")"
ROOT_PW="${ROOT_PW:-onix}"           # throwaway forge; SSH is key-based anyway

mkdir -p "$STATE_DIR"
MNT=""; DISK_DEV=""

cleanup() {
  set +e
  if [[ -n "$MNT" && -d "$MNT" ]]; then
    unmount_tree "$MNT"
    rmdir "$MNT" 2>/dev/null
  fi
  [[ -n "$DISK_DEV" ]] && losetup -d "$DISK_DEV" >/dev/null 2>&1
  # hand all build outputs back to the human who invoked sudo
  [[ -n "${SUDO_UID:-}" ]] && chown -R "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$STATE_DIR" 2>/dev/null
  [[ -n "$SUDO_ENV_FILE" ]] && rm -f "$SUDO_ENV_FILE"
}
trap cleanup EXIT

log "creating ${DISK_SIZE} sparse raw disk: ${DISK_IMG#$ONIX_ROOT/}"
rm -f "$DISK_IMG"
truncate -s "$DISK_SIZE" "$DISK_IMG"

attach_disk rw

log "partitioning GPT (ESP 512M + ext4 root) on $DISK_DEV"
sgdisk --zap-all "$DISK_DEV" >/dev/null
sgdisk -n1:0:+512M -t1:EF00 -c1:"ONIX-ESP"  "$DISK_DEV" >/dev/null
sgdisk -n2:0:0     -t2:8300 -c2:"onix-root" "$DISK_DEV" >/dev/null
partprobe "$DISK_DEV"; sleep 0.5
wait_for_partitions

log "formatting filesystems"
mkfs.fat -F32 -n ONIX-ESP "${DISK_DEV}p1" >/dev/null
mkfs.ext4 -q -L onix-root "${DISK_DEV}p2"

log "mounting target"
MNT="$(mktemp -d)"
mount "${DISK_DEV}p2" "$MNT"
mkdir -p "$MNT/efi"
mount "${DISK_DEV}p1" "$MNT/efi"

log "extracting minirootfs"
tar -xpf "$ROOTFS_PATH" -C "$MNT"

log "seeding apk repositories + DNS"
printf '%s\n%s\n' "$APK_REPO_MAIN" "$APK_REPO_COMMUNITY" > "$MNT/etc/apk/repositories"
echo "nameserver 1.1.1.1" > "$MNT/etc/resolv.conf"

mount_chroot_api

log "injecting build env + scripts into the image"
cp "$ONIX_PHASE0_DIR/chroot-setup.sh" "$MNT/root/chroot-setup.sh"
[[ -f "$ONIX_PHASE0_DIR/provision.sh" ]] && cp "$ONIX_PHASE0_DIR/provision.sh" "$MNT/root/provision.sh"
cat > "$MNT/root/onix.env" <<EOF
HOSTNAME_="$VM_NAME"
BUILD_USER="$BUILD_USER"
KERNEL_FLAVOR="$KERNEL_FLAVOR"
ROOT_PW="$ROOT_PW"
SSH_PUBKEY="$SSH_PUBKEY"
OS_TOOLS_REPO="$OS_TOOLS_REPO"
OS_TOOLS_REF="$OS_TOOLS_REF"
EOF

log "running chroot setup (apk install + bootloader + users) …"
chroot "$MNT" /bin/sh -e /root/chroot-setup.sh

log "verifying removable EFI loader on ESP"
if [[ ! -s "$MNT/efi/EFI/BOOT/BOOTX64.EFI" ]]; then
  warn "ESP is missing /EFI/BOOT/BOOTX64.EFI after chroot setup"
  tmp_loader="$(mktemp)"
  rm -f "$tmp_loader"

  log "checking whether GRUB wrote the loader to root /efi instead"
  umount "$MNT/efi"
  if [[ -s "$MNT/efi/EFI/BOOT/BOOTX64.EFI" ]]; then
    cp "$MNT/efi/EFI/BOOT/BOOTX64.EFI" "$tmp_loader"
    log "found loader under root /efi; copying it to the ESP"
  fi
  mount "${DISK_DEV}p1" "$MNT/efi"
  mkdir -p "$MNT/efi/EFI/BOOT"
  if [[ -s "$tmp_loader" ]]; then
    cp "$tmp_loader" "$MNT/efi/EFI/BOOT/BOOTX64.EFI"
    rm -f "$tmp_loader"
  fi
  if [[ ! -s "$MNT/efi/EFI/BOOT/BOOTX64.EFI" ]]; then
    log "building standalone GRUB loader directly onto the mounted ESP"
    chroot "$MNT" /bin/sh -e -c \
      'mkdir -p /efi/EFI/BOOT && grub-mkstandalone -O x86_64-efi -o /efi/EFI/BOOT/BOOTX64.EFI "boot/grub/grub.cfg=/boot/grub/grub.cfg"'
  fi
fi
[[ -s "$MNT/efi/EFI/BOOT/BOOTX64.EFI" ]] || die "missing /efi/EFI/BOOT/BOOTX64.EFI after chroot setup"

log "exporting kernel + initramfs for 'launch.sh --direct'"
cp "$MNT/boot/vmlinuz-$KERNEL_FLAVOR"   "$KERNEL_IMG"
cp "$MNT/boot/initramfs-$KERNEL_FLAVOR" "$INITRD_IMG"

log "cleaning injected build files"
rm -f "$MNT/root/onix.env" "$MNT/root/chroot-setup.sh"

ensure_ovmf_vars   # per-VM UEFI NVRAM for the OVMF boot path

log "done. boot it:  ./launch.sh   (or ./launch.sh --direct if grub misbehaves)"
