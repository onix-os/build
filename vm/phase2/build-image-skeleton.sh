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
#
# Phase 213 reuses this script with --systemd-payload to stage the first
# musl-targeted systemd userspace payload. This is a bootstrap/probe payload
# from pinned pkgsMusl.systemd, not the final systemd stone.
#
# Phase 214 reuses this script with --module-payload to stage the first
# matching kmod/modprobe + kernel modules payload from the same initramfs that
# Phase 211 already booted. This lets the switched-root systemd userspace load
# modules such as vfat after PID 1 starts.
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
SYSTEMD_PAYLOAD_OUT="${ONIX_SYSTEMD_PAYLOAD_OUT:-}"
SYSTEMD_CLOSURE_LIST="${ONIX_SYSTEMD_CLOSURE_LIST:-}"

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
  --systemd-payload) MODE="systemd-payload"; SUDO_MODE_ARGS=(--systemd-payload); shift ;;
  --module-payload) MODE="module-payload"; SUDO_MODE_ARGS=(--module-payload); shift ;;
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
      ONIX_SYSTEMD_PAYLOAD_OUT ONIX_SYSTEMD_CLOSURE_LIST \
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

prepare_systemd_payload() {
  local expr out closure

  log "Phase 213 input check: systemd userspace contract"
  "$SCRIPT_DIR/verify-systemd-userspace-plan.sh"

  need_cmd nix
  need_cmd readelf
  need_cmd strings
  mkdir -p "$IMAGE_DIR"

  if [[ -n "$SYSTEMD_PAYLOAD_OUT" ]]; then
    out="$SYSTEMD_PAYLOAD_OUT"
  else
    read -r -d '' expr <<EOF_NIX || true
let
  lock = builtins.fromJSON (builtins.readFile "$ONIX_ROOT/flake.lock");
  node = lock.nodes.nixpkgs_2.locked;
  src = builtins.fetchTree {
    type = node.type;
    owner = node.owner;
    repo = node.repo;
    rev = node.rev;
    narHash = node.narHash;
  };
  pkgs = import src {
    system = builtins.currentSystem;
    config.allowUnfree = true;
  };
  slimSystemd = pkgs.pkgsMusl.systemd.override {
    withDocumentation = false;
    withLibBPF = false;
    withTpm2Tss = false;
    withBootloader = false;
    withEfi = false;
    withUkify = false;
    withRemote = false;
    withImportd = false;
    withHomed = false;
    withCryptsetup = false;
    withRepart = false;
    withSysupdate = false;
    withCoredump = false;
    withVmspawn = false;
    withNspawn = false;
    withPolkit = false;
    withPam = false;
    withFido2 = false;
    withQrencode = false;
    withPasswordQuality = false;
    withLibarchive = false;
    withKexectools = false;
    withAnalyze = false;
    withApparmor = false;
    withAudit = false;
    withFirstboot = false;
    withGcrypt = false;
    withHostnamed = false;
    withHwdb = false;
    withLibidn2 = false;
    withLocaled = false;
    withLogind = false;
    withMachined = false;
    withNetworkd = false;
    withOpenSSL = false;
    withPCRE2 = false;
    withPortabled = false;
    withResolved = false;
    withShellCompletions = false;
    withTimedated = false;
    withTimesyncd = false;
    withUserDb = false;
    withVConsole = false;
    withCompression = false;
    withLibseccomp = false;
  };
in slimSystemd.overrideAttrs (old: {
  doInstallCheck = false;
  mesonFlags = (old.mesonFlags or []) ++ [
    "-Dlibmount=enabled"
  ];
})
EOF_NIX

    log "checking slim pkgsMusl.systemd bootstrap build graph"
    nix build --dry-run --impure --expr "$expr" >/dev/null

    log "building/fetching slim pinned pkgsMusl.systemd bootstrap payload"
    out="$(
      nix build --impure --no-link --print-out-paths --expr "$expr" |
        while IFS= read -r candidate; do
          if [[ -x "$candidate/lib/systemd/systemd" ]]; then
            printf '%s\n' "$candidate"
            break
          fi
        done
    )"
    [[ -n "$out" ]] || die "could not identify systemd runtime output from nix build"
  fi

  verify_systemd_payload_output "$out"

  if [[ -n "$SYSTEMD_CLOSURE_LIST" ]]; then
    closure="$SYSTEMD_CLOSURE_LIST"
  else
    closure="$IMAGE_DIR/systemd-payload.closure"
    nix path-info -r "$out" | sort > "$closure"
  fi
  [[ -s "$closure" ]] || die "systemd closure list is empty: $closure"
  grep -qx "$out" "$closure" || die "systemd closure list does not contain payload output: $out"

  printf '%s\n' "$out" > "$IMAGE_DIR/systemd-payload.out"

  SYSTEMD_PAYLOAD_OUT="$out"
  SYSTEMD_CLOSURE_LIST="$closure"
  export ONIX_SYSTEMD_PAYLOAD_OUT="$SYSTEMD_PAYLOAD_OUT"
  export ONIX_SYSTEMD_CLOSURE_LIST="$SYSTEMD_CLOSURE_LIST"

  log "systemd payload ready"
  echo "output : ${SYSTEMD_PAYLOAD_OUT}"
  echo "closure: ${SYSTEMD_CLOSURE_LIST#$ONIX_ROOT/}"
}

verify_systemd_payload_output() {
  local out="$1"
  local shared_strings

  [[ -d "$out" ]] || die "systemd payload output is missing: $out"
  [[ -x "$out/lib/systemd/systemd" ]] || die "systemd payload lacks executable lib/systemd/systemd: $out"
  [[ -x "$out/lib/systemd/systemd-udevd" ]] || die "systemd payload lacks executable lib/systemd/systemd-udevd: $out"
  [[ -f "$out/example/systemd/system/multi-user.target" ]] || die "systemd payload lacks example/systemd/system/multi-user.target: $out"

  shared_strings="$(mktemp "${TMPDIR:-/tmp}/systemd-strings.XXXXXX")"
  strings "$out"/lib/systemd/libsystemd-shared-*.so > "$shared_strings"
  grep -q 'libmount[.]so[.]1' "$shared_strings" \
    || { rm -f "$shared_strings"; die "systemd payload was not built with libmount dlopen support: $out"; }
  if grep -q 'libmount support not compiled in' "$shared_strings"; then
    rm -f "$shared_strings"
    die "systemd payload still says libmount support was not compiled in: $out"
  fi
  rm -f "$shared_strings"
}

systemd_musl_prefix() {
  local out="$1"
  local interpreter

  interpreter="$(
    readelf -l "$out/lib/systemd/systemd" |
      sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p'
  )"

  [[ "$interpreter" == /nix/store/*/lib/ld-musl-x86_64.so.1 ]] \
    || die "systemd payload is not using the expected musl interpreter: ${interpreter:-<missing>}"

  printf '%s\n' "${interpreter%/lib/ld-musl-x86_64.so.1}"
}

write_musl_loader_path() {
  local dest_root="$1"
  local out="$2"
  local closure="$3"
  local musl_prefix path_file dirs_file store_path

  musl_prefix="$(systemd_musl_prefix "$out")"
  path_file="$dest_root$musl_prefix/etc/ld-musl-x86_64.path"
  dirs_file="$(mktemp "${TMPDIR:-/tmp}/onix-musl-libdirs.XXXXXX")"

  while IFS= read -r store_path; do
    [[ -d "$dest_root$store_path" ]] || continue
    find "$dest_root$store_path" -type f -name '*.so*' -printf '%h\n'
  done < "$closure" | sed "s#^$dest_root##" | sort -u > "$dirs_file"

  grep -Fxq "$out/lib/systemd" "$dirs_file" \
    || echo "$out/lib/systemd" >> "$dirs_file"
  grep -Fxq "$musl_prefix/lib" "$dirs_file" \
    || echo "$musl_prefix/lib" >> "$dirs_file"

  sort -u "$dirs_file" > "$dirs_file.sorted"
  install -dm0755 "$(dirname "$path_file")"
  install -m0644 "$dirs_file.sorted" "$path_file"
  rm -f "$dirs_file" "$dirs_file.sorted"

  grep -Eq '^/nix/store/.+-util-linux-minimal-.+-lib/lib$' "$path_file" \
    || die "musl loader path does not include util-linux libmount directory: ${path_file#$dest_root}"
}

link_systemd_compiled_unit_dirs() {
  local dest_root="$1"
  local out="$2"

  [[ -d "$dest_root$out/lib/systemd" ]] || die "systemd lib directory is missing in image copy: $out/lib/systemd"
  [[ -d "$dest_root$out/example/systemd/system" ]] || die "systemd example system units are missing in image copy: $out/example/systemd/system"
  [[ -d "$dest_root$out/example/systemd/user" ]] || die "systemd example user units are missing in image copy: $out/example/systemd/user"

  ln -sfn "$out/example/systemd/system" "$dest_root$out/lib/systemd/system"
  ln -sfn "$out/example/systemd/user" "$dest_root$out/lib/systemd/user"

  test -f "$dest_root$out/lib/systemd/system/multi-user.target"
  test -f "$dest_root$out/lib/systemd/system/rescue.target"
}

if [[ $EUID -ne 0 ]]; then
  if [[ "$MODE" == "systemd-payload" ]]; then
    prepare_systemd_payload
  else
    "$SCRIPT_DIR/verify-image-contract.sh"
  fi
  need_root "${SUDO_MODE_ARGS[@]}"
fi

need_cmd awk
need_cmd blkid
need_cmd cmp
need_cmd cpio
need_cmd depmod
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
need_cmd readelf
need_cmd readlink
need_cmd rm
need_cmd sed
need_cmd sgdisk
need_cmd sort
need_cmd stat
need_cmd strings
need_cmd sync
need_cmd tar
need_cmd touch
need_cmd truncate
need_cmd umount
need_cmd chroot

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

mount_persist_partition() {
  mkdir -p "$MNT/persist"
  mount "$(part_path 4)" "$MNT/persist"
}

copy_nix_closure_into() {
  local dest="$1"
  local list="$2"
  local rel_list

  [[ -d "$dest" ]] || die "closure destination is missing: $dest"
  [[ -s "$list" ]] || die "closure list is missing/empty: ${list#$ONIX_ROOT/}"

  rel_list="$(mktemp "${TMPDIR:-/tmp}/systemd-closure.XXXXXX")"
  sed 's#^/##' "$list" > "$rel_list"

  mkdir -p "$dest/nix/store"
  tar --numeric-owner -C / -cpf - -T "$rel_list" | tar --numeric-owner -C "$dest" -xpf -
  rm -f "$rel_list"
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

install_systemd_payload() {
  local out="$SYSTEMD_PAYLOAD_OUT"
  local closure="$SYSTEMD_CLOSURE_LIST"
  local bin
  local musl_prefix

  log "Phase 213 input check: systemd userspace contract"
  "$SCRIPT_DIR/verify-systemd-userspace-plan.sh"

  [[ -n "$out" ]] || die "ONIX_SYSTEMD_PAYLOAD_OUT is missing"
  [[ -n "$closure" ]] || die "ONIX_SYSTEMD_CLOSURE_LIST is missing"
  [[ -s "$closure" ]] || die "systemd closure list is missing/empty: ${closure#$ONIX_ROOT/}"
  verify_systemd_payload_output "$out"

  if have_stale_mounts || have_stale_loops; then
    die "stale Phase 2 image mounts/loops exist; run make cleanup"
  fi

  rm -rf "$WORK_DIR"
  mkdir -p "$WORK_DIR"

  attach_existing_image
  verify_partition_contract
  mount_root_esp_boot
  mount_persist_partition

  log "verifying Phase 211 kernel/initramfs payload exists first"
  test -s "$MNT/boot/ONIX/vmlinuz"
  test -s "$MNT/boot/ONIX/initramfs.img"
  test -f "$MNT/boot/loader/entries/onix-phase-211.conf"
  grep -q 'init=/usr/lib/systemd/systemd' "$MNT/boot/loader/entries/onix-phase-211.conf"

  log "copying systemd runtime closure into root /nix/store"
  copy_nix_closure_into "$MNT" "$closure"

  log "copying systemd runtime closure into ONIX-PERSIST /nix/store"
  mkdir -p "$MNT/persist/nix"
  copy_nix_closure_into "$MNT/persist" "$closure"

  log "writing musl loader path for lazy dlopen libraries"
  write_musl_loader_path "$MNT" "$out" "$closure"
  write_musl_loader_path "$MNT/persist" "$out" "$closure"
  musl_prefix="$(systemd_musl_prefix "$out")"

  log "linking systemd compiled unit directories"
  link_systemd_compiled_unit_dirs "$MNT" "$out"
  link_systemd_compiled_unit_dirs "$MNT/persist" "$out"

  log "linking systemd userspace into ONIX /usr"
  mkdir -p "$MNT/usr/lib" "$MNT/usr/bin" "$MNT/etc/systemd/system" "$MNT/var/lib/systemd" "$MNT/var/log"
  rm -rf "$MNT/usr/lib/systemd"
  mkdir -p "$MNT/usr/lib/systemd"
  find "$out/lib/systemd" -maxdepth 1 -mindepth 1 | while IFS= read -r entry; do
    ln -s "$entry" "$MNT/usr/lib/systemd/$(basename "$entry")"
  done
  ln -sfn "$out/example/systemd/system" "$MNT/usr/lib/systemd/system"
  ln -sfn "$out/example/systemd/user" "$MNT/usr/lib/systemd/user"

  for bin in systemctl journalctl loginctl machinectl networkctl systemd-analyze systemd-tmpfiles systemd-sysusers udevadm; do
    if [[ -e "$out/bin/$bin" ]]; then
      ln -sfn "$out/bin/$bin" "$MNT/usr/bin/$bin"
    fi
  done

  log "materializing first-boot machine identity placeholder"
  : > "$MNT/etc/machine-id"
  chmod 0644 "$MNT/etc/machine-id"

  log "recording Phase 213 bootstrap payload metadata"
  install -dm0755 "$MNT/usr/share/onix/bootstrap" "$MNT/boot/ONIX"
  {
    echo "ONIX Phase 213 systemd userspace bootstrap payload"
    echo
    echo "This is the first musl-targeted systemd userspace payload staged into"
    echo "the ONIX image so the kernel can execute /usr/lib/systemd/systemd."
    echo
    echo "It is a slim bootstrap/probe payload from pinned pkgsMusl.systemd."
    echo "It is not the final systemd .stone package."
    echo
    echo "systemd output:"
    echo "$out"
    echo
    echo "closure paths:"
    sed 's/^/- /' "$closure"
  } > "$MNT/usr/share/onix/bootstrap/systemd-payload.txt"
  chmod 0644 "$MNT/usr/share/onix/bootstrap/systemd-payload.txt"

  cat > "$MNT/boot/ONIX/README.phase213" <<EOF
ONIX Phase 213 systemd userspace payload

This image now has a first musl-targeted systemd userspace payload:

- /usr/lib/systemd/systemd
- /usr/lib/systemd/systemd-udevd
- /usr/lib/systemd/system/multi-user.target
- $out/lib/systemd/system/multi-user.target
- ${musl_prefix}/etc/ld-musl-x86_64.path

The payload source is:

$out

This is a slim bootstrap/probe payload copied from pinned pkgsMusl.systemd so
the next boot probe can test the userspace handoff. The musl loader path file
lets lazy dlopen libraries such as libmount.so.1 resolve during early PID 1
startup. This is not the final systemd stone.

The compiled Nix store unit directory is linked to the packaged example unit
directory so multi-user.target and rescue.target resolve during the probe.
EOF
  chmod 0644 "$MNT/boot/ONIX/README.phase213"

  log "writing Phase 213 BLS entry"
  cat > "$MNT/efi/loader/loader.conf" <<'EOF'
default onix-phase-213.conf
timeout 3
console-mode max
editor no
EOF
  chmod 0644 "$MNT/efi/loader/loader.conf"

  cat > "$MNT/boot/loader/entries/onix-phase-213.conf" <<'EOF'
title ONIX
sort-key onix
version phase-213
linux /ONIX/vmlinuz
initrd /ONIX/initramfs.img
options root=LABEL=onix-root rootfstype=xfs rw init=/usr/lib/systemd/systemd systemd.unit=multi-user.target console=tty0 console=ttyS0,115200
EOF
  chmod 0644 "$MNT/boot/loader/entries/onix-phase-213.conf"

  log "verifying Phase 213 systemd userspace payload"
  test -x "$MNT$out/lib/systemd/systemd"
  test -x "$MNT$out/lib/systemd/systemd-udevd"
  test -f "$MNT$out/lib/systemd/system/multi-user.target"
  test -x "$MNT/persist$out/lib/systemd/systemd"
  test -f "$MNT/persist$out/lib/systemd/system/multi-user.target"
  test -f "$MNT$musl_prefix/etc/ld-musl-x86_64.path"
  test -f "$MNT/persist$musl_prefix/etc/ld-musl-x86_64.path"
  grep -Eq '^/nix/store/.+-util-linux-minimal-.+-lib/lib$' "$MNT$musl_prefix/etc/ld-musl-x86_64.path"
  test "$(readlink "$MNT/usr/lib/systemd/system")" = "$out/example/systemd/system"
  test -x "$MNT/usr/lib/systemd/systemd"
  test -f "$MNT/usr/lib/systemd/system/multi-user.target"
  test -f "$MNT/etc/machine-id"
  test -f "$MNT/usr/share/onix/bootstrap/systemd-payload.txt"
  test -f "$MNT/boot/ONIX/README.phase213"
  grep -q '^default onix-phase-213\.conf$' "$MNT/efi/loader/loader.conf"
  grep -q '^version phase-213$' "$MNT/boot/loader/entries/onix-phase-213.conf"
  grep -q 'init=/usr/lib/systemd/systemd' "$MNT/boot/loader/entries/onix-phase-213.conf"

  log "systemd payload preview"
  find "$MNT$out/lib/systemd" "$MNT/usr/bin" -maxdepth 2 -mindepth 1 | sort | sed "s#^$MNT##" | sed -n '1,120p'

  sync

  log "success"
  echo "image  : $IMAGE_RAW"
  echo "systemd: $out"
  echo "closure: ${closure#$ONIX_ROOT/}"
  echo "status : systemd userspace staged; next run make phase 212 to boot-probe the handoff"
}

extract_initramfs_payload() {
  local extract_dir="$1"

  need_file "$INITRAMFS_SOURCE"
  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  (
    cd "$extract_dir"
    gzip -dc "$INITRAMFS_SOURCE" | cpio -idmu >/dev/null 2>&1
  )
}

kernel_release_from_initramfs_extract() {
  local extract_dir="$1"
  local releases=()

  [[ -d "$extract_dir/usr/lib/modules" ]] \
    || die "initramfs extract has no usr/lib/modules directory"

  while IFS= read -r release; do
    releases+=("$release")
  done < <(find "$extract_dir/usr/lib/modules" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

  [[ "${#releases[@]}" -eq 1 ]] \
    || die "expected exactly one kernel module release in initramfs, found ${#releases[@]}"

  printf '%s\n' "${releases[0]}"
}

copy_initramfs_lib_with_target() {
  local extract_dir="$1"
  local dest_root="$2"
  local name="$3"
  local src=""
  local target

  if [[ -e "$extract_dir/usr/lib/$name" ]]; then
    src="$extract_dir/usr/lib/$name"
  elif [[ -e "$extract_dir/lib/$name" ]]; then
    src="$extract_dir/lib/$name"
  else
    die "initramfs lacks required kmod runtime library: $name"
  fi

  install -dm0755 "$dest_root/usr/lib"
  cp -a "$src" "$dest_root/usr/lib/"

  if [[ -L "$src" ]]; then
    target="$(readlink -f "$src")"
    [[ -f "$target" ]] || die "required library symlink target is missing for $name"
    cp -a "$target" "$dest_root/usr/lib/"
  fi
}

install_module_payload() {
  local extract_dir="$WORK_DIR/initramfs-extract"
  local kernel_release
  local lib
  local module
  local nix_kmod

  log "Phase 214 input check: kernel/initramfs payload"
  verify_kernel_payload_sources

  if have_stale_mounts || have_stale_loops; then
    die "stale Phase 2 image mounts/loops exist; run make cleanup"
  fi

  rm -rf "$WORK_DIR"
  mkdir -p "$WORK_DIR"

  attach_existing_image
  verify_partition_contract
  mount_root_esp_boot

  log "verifying Phase 213 systemd userspace payload exists first"
  test -s "$MNT/boot/ONIX/vmlinuz"
  test -s "$MNT/boot/ONIX/initramfs.img"
  test -f "$MNT/boot/loader/entries/onix-phase-213.conf"
  test -x "$MNT/usr/lib/systemd/systemd"
  grep -q 'init=/usr/lib/systemd/systemd' "$MNT/boot/loader/entries/onix-phase-213.conf"

  log "extracting matching kmod/modules payload from initramfs"
  extract_initramfs_payload "$extract_dir"
  kernel_release="$(kernel_release_from_initramfs_extract "$extract_dir")"

  test -x "$extract_dir/usr/bin/kmod"
  test "$(readlink "$extract_dir/usr/sbin/modprobe")" = "../bin/kmod"
  test -f "$extract_dir/usr/lib/modules/$kernel_release/modules.dep"
  test -f "$extract_dir/usr/lib/modules/$kernel_release/kernel/fs/fat/vfat.ko.gz"
  test -f "$extract_dir/usr/lib/modules/$kernel_release/kernel/fs/fat/fat.ko.gz"
  test -f "$extract_dir/usr/lib/modules/$kernel_release/kernel/fs/nls/nls_cp437.ko.gz"
  test -f "$extract_dir/usr/lib/modules/$kernel_release/kernel/fs/nls/nls_iso8859-1.ko.gz"

  log "installing kmod/modprobe runtime"
  install -Dm0755 "$extract_dir/usr/bin/kmod" "$MNT/usr/bin/kmod"
  ln -sfn kmod "$MNT/usr/bin/modprobe"
  install -dm0755 "$MNT/usr/sbin"
  ln -sfn ../bin/kmod "$MNT/usr/sbin/modprobe"

  log "pinning systemd modprobe unit to ONIX modprobe path"
  install -dm0755 "$MNT/etc/systemd/system/modprobe@.service.d"
  cat > "$MNT/etc/systemd/system/modprobe@.service.d/10-onix-modprobe.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=-/usr/sbin/modprobe -abq %i
EOF
  chmod 0644 "$MNT/etc/systemd/system/modprobe@.service.d/10-onix-modprobe.conf"

  for lib in \
    ld-musl-x86_64.so.1 \
    libc.musl-x86_64.so.1 \
    libzstd.so.1 \
    liblzma.so.5 \
    libz.so.1 \
    libcrypto.so.3
  do
    copy_initramfs_lib_with_target "$extract_dir" "$MNT" "$lib"
  done

  log "installing matching kernel module tree"
  rm -rf "$MNT/usr/lib/modules/$kernel_release"
  install -dm0755 "$MNT/usr/lib/modules"
  tar -C "$extract_dir/usr/lib/modules" -cpf - "$kernel_release" |
    tar --numeric-owner -C "$MNT/usr/lib/modules" -xpf -

  log "normalizing modules from gzip .ko.gz to plain ELF .ko"
  find "$MNT/usr/lib/modules/$kernel_release" -type f -name '*.ko.gz' -print0 |
    while IFS= read -r -d '' module; do
      gzip -df "$module"
    done

  log "regenerating module dependency indexes"
  depmod -b "$MNT" "$kernel_release"

  log "recording Phase 214 bootstrap payload metadata"
  install -dm0755 "$MNT/usr/share/onix/bootstrap" "$MNT/boot/ONIX"
  {
    echo "ONIX Phase 214 kernel module/kmod bootstrap payload"
    echo
    echo "This payload is extracted from the same initramfs staged in Phase 211:"
    echo
    echo "${INITRAMFS_SOURCE#$ONIX_ROOT/}"
    echo
    echo "It makes module loading available after switch-root, when systemd"
    echo "runs as PID 1 from the real ONIX root filesystem."
    echo
    echo "Installed kernel release:"
    echo "$kernel_release"
    echo
    echo "Important installed paths:"
    echo "- /usr/bin/kmod"
    echo "- /usr/bin/modprobe -> kmod"
    echo "- /usr/sbin/modprobe -> ../bin/kmod"
    echo "- /etc/systemd/system/modprobe@.service.d/10-onix-modprobe.conf"
    echo "- /usr/lib/modules/$kernel_release"
    echo "- /usr/lib/ld-musl-x86_64.so.1"
    echo
    echo "This is a bootstrap/probe payload. Later ONIX should package kernel,"
    echo "initramfs, kmod, and modules as ONIX-owned stones."
  } > "$MNT/usr/share/onix/bootstrap/kernel-modules-payload.txt"
  chmod 0644 "$MNT/usr/share/onix/bootstrap/kernel-modules-payload.txt"

  cat > "$MNT/boot/ONIX/README.phase214" <<EOF
ONIX Phase 214 kernel module/kmod payload

This image now has a first matching module-loading payload in the real root:

- /usr/bin/kmod
- /usr/bin/modprobe
- /usr/sbin/modprobe
- /etc/systemd/system/modprobe@.service.d/10-onix-modprobe.conf
- /usr/lib/modules/$kernel_release

The payload is extracted from:

${INITRAMFS_SOURCE#$ONIX_ROOT/}

The reason this exists is that Phase 212 proved systemd could reach
multi-user.target, but early mounts such as /boot and /efi could still fail or
time out because the switched-root userspace lacked modprobe and matching
modules. In particular, vfat filesystems may need these source modules:

- fat.ko.gz
- vfat.ko.gz
- nls_cp437.ko.gz
- nls_iso8859-1.ko.gz

Phase 214 decompresses those imported modules to plain .ko files before
regenerating modules.dep. This avoids a bootstrap mismatch where systemd's
Nix-provided libkmod can read xz/zstd modules but not gzip-compressed modules.

This is still a bootstrap/probe payload. Later ONIX should stop importing this
from the initramfs and instead package it as ONIX-owned kernel/kmod stones.
EOF
  chmod 0644 "$MNT/boot/ONIX/README.phase214"

  log "writing Phase 214 BLS entry"
  cat > "$MNT/efi/loader/loader.conf" <<'EOF'
default onix-phase-214.conf
timeout 3
console-mode max
editor no
EOF
  chmod 0644 "$MNT/efi/loader/loader.conf"

  cat > "$MNT/boot/loader/entries/onix-phase-214.conf" <<'EOF'
title ONIX
sort-key onix
version phase-214
linux /ONIX/vmlinuz
initrd /ONIX/initramfs.img
options root=LABEL=onix-root rootfstype=xfs rw init=/usr/lib/systemd/systemd systemd.unit=multi-user.target console=tty0 console=ttyS0,115200
EOF
  chmod 0644 "$MNT/boot/loader/entries/onix-phase-214.conf"

  log "verifying Phase 214 module/kmod payload"
  test -x "$MNT/usr/bin/kmod"
  test "$(readlink "$MNT/bin")" = "usr/bin"
  test "$(readlink "$MNT/sbin")" = "usr/sbin"
  test "$(readlink "$MNT/lib")" = "usr/lib"
  test "$(readlink "$MNT/usr/bin/modprobe")" = "kmod"
  test "$(readlink "$MNT/usr/sbin/modprobe")" = "../bin/kmod"
  test -f "$MNT/etc/systemd/system/modprobe@.service.d/10-onix-modprobe.conf"
  grep -q '^ExecStart=-/usr/sbin/modprobe -abq %i$' "$MNT/etc/systemd/system/modprobe@.service.d/10-onix-modprobe.conf"
  test -f "$MNT/usr/lib/ld-musl-x86_64.so.1"
  test -f "$MNT/usr/lib/libc.musl-x86_64.so.1"
  test -f "$MNT/usr/lib/libcrypto.so.3"
  test -d "$MNT/usr/lib/modules/$kernel_release"
  test -f "$MNT/usr/lib/modules/$kernel_release/modules.dep"
  test -f "$MNT/lib/modules/$kernel_release/modules.dep"
  test -f "$MNT/usr/lib/modules/$kernel_release/kernel/fs/fat/vfat.ko"
  test -f "$MNT/usr/lib/modules/$kernel_release/kernel/fs/fat/fat.ko"
  test ! -e "$MNT/usr/lib/modules/$kernel_release/kernel/fs/fat/vfat.ko.gz"
  ! grep -q '[.]ko[.]gz' "$MNT/usr/lib/modules/$kernel_release/modules.dep"
  grep -q 'kernel/fs/fat/vfat.ko' "$MNT/usr/lib/modules/$kernel_release/modules.dep"
  grep -q '^default onix-phase-214\.conf$' "$MNT/efi/loader/loader.conf"
  grep -q '^version phase-214$' "$MNT/boot/loader/entries/onix-phase-214.conf"
  test -f "$MNT/usr/share/onix/bootstrap/kernel-modules-payload.txt"
  test -f "$MNT/boot/ONIX/README.phase214"
  chroot "$MNT" /usr/bin/kmod --version >/dev/null
  chroot "$MNT" /usr/bin/modprobe -S "$kernel_release" --show-depends vfat >/dev/null
  chroot "$MNT" /usr/sbin/modprobe -S "$kernel_release" --show-depends vfat >/dev/null
  chroot "$MNT" /sbin/modprobe -S "$kernel_release" --show-depends vfat >/dev/null
  if [[ -n "$SYSTEMD_CLOSURE_LIST" && -s "$SYSTEMD_CLOSURE_LIST" ]]; then
    nix_kmod="$({ grep -E -- '-kmod-[0-9][^/]*$' "$SYSTEMD_CLOSURE_LIST" | grep -v -- '-lib' | head -1; } || true)"
    if [[ -n "$nix_kmod" && -x "$nix_kmod/bin/modprobe" ]]; then
      "$nix_kmod/bin/modprobe" -d "$MNT" -S "$kernel_release" --show-depends vfat >/dev/null
    fi
  fi

  log "module payload preview"
  find "$MNT/usr/bin/kmod" "$MNT/usr/bin/modprobe" "$MNT/usr/sbin/modprobe" "$MNT/etc/systemd/system/modprobe@.service.d" "$MNT/usr/lib/modules/$kernel_release" \
    -maxdepth 4 -mindepth 0 | sort | sed "s#^$MNT##" | sed -n '1,120p'

  sync

  log "success"
  echo "image  : $IMAGE_RAW"
  echo "kernel : $kernel_release"
  echo "status : module/kmod payload staged; next run make phase 212 to boot-probe clean mounts"
}

if [[ "$MODE" == "boot-skeleton" ]]; then
  install_boot_skeleton
  exit 0
fi

if [[ "$MODE" == "kernel-payload" ]]; then
  install_kernel_payload
  exit 0
fi

if [[ "$MODE" == "systemd-payload" ]]; then
  install_systemd_payload
  exit 0
fi

if [[ "$MODE" == "module-payload" ]]; then
  install_module_payload
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
