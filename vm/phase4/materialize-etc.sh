#!/usr/bin/env bash
# vm/phase4/materialize-etc.sh — materialize live ONIX base-system state.
#
# Phase 401 starts making the booted ONIX image usable. It codifies the rule:
#
#   /usr/share/defaults owns packaged defaults
#   /etc owns live machine configuration
#
# Phase 402 adds the first account database policy. It deliberately reuses this
# already-allowed rootful Phase 4 script so adding a new subphase does not mean
# teaching sudoers about another writable script every time.
#
# Phase 403 adds a deliberately temporary bootstrap serial root console. This is
# not a real authenticated login design. It proves that ONIX can put a shell on
# a dedicated bootstrap serial line and receive commands from the host.
#
# Phase 404 adds the first minimal networking proof. It is still bootstrap
# glue: BusyBox brings up QEMU's virtio NIC with the deterministic user-mode
# networking address so the booted image can prove that it has IPv4 and a
# default route without expanding kernel-module ownership in Phase 4.
#
# Phase 405 adds the first host-to-guest remote inspection proof. It is not SSH.
# It is a tiny BusyBox nc listener behind QEMU host port forwarding, proving
# that the host can reach a process inside the booted ONIX image.
#
# Phase 406 adds the first authenticated remote access proof with Dropbear SSH.
# It creates a non-root bootstrap user, installs an authorized key, disables
# password auth, and proves host-to-guest SSH over QEMU port forwarding.
#
# Phase 410 consumes the locally built busybox stone from the Phase 4 local
# moss repo. It makes /usr/bin/busybox package-owned and leaves /bin as an image
# compatibility layer for the bootstrap scripts that still call /bin/sh, /bin/nc,
# /bin/ifconfig, and friends.
#
# Phase 413 consumes the locally built dropbear stone from the same repo.
# It makes /usr/sbin/dropbear and /usr/bin/dropbearkey package-owned, then
# rewrites the bootstrap SSH service away from the temporary Nix Dropbear path.
#
# Phase 414 audits the remaining systemd ownership boundary before we try to
# build systemd. It should not mutate the image; it only proves the current
# active paths and remaining Nix payload debt are understood.
#
# Phase 416 consumes the locally built systemd stone. Because this first
# systemd stone is a bootstrap ownership package, the Nix-built runtime closure
# is package-owned under /usr/lib/onix/bootstrap/nix/store first. Image assembly
# then materializes that package-owned bootstrap copy into /nix/store and
# /persist/nix/store so the absolute musl loader and runtime paths resolve when
# the kernel starts PID 1.
#
# Phase 418 consumes bootstrap-policy. That package owns the bootstrap
# helper scripts, proof notes, and source copies of temporary bootstrap systemd
# units. The active unit tree is still the current bootstrap systemd tree, so
# this script activates package-owned unit sources into that tree as a temporary
# image-assembly step.
#
# Phase 420 prunes the old bootstrap-only Nix BusyBox/Dropbear payloads after
# their active runtime paths have moved to busybox and dropbear. It
# deliberately keeps any shared paths that still belong to the active systemd
# closure, because systemd still needs /nix/store compatibility in this phase.
#
# Phase 422 consumes the native source-built systemd stone. It replaces the
# bootstrap systemd symlink farm with real files under /usr/lib/systemd, activates
# package-owned bootstrap unit sources into that native unit tree, and removes the
# old bootstrap systemd runtime compatibility copy.
#
# This script is intentionally conservative. It creates missing live files, but
# it preserves existing local overrides so later ONIX can report drift instead
# of silently erasing admin choices.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SELF="$SCRIPT_DIR/materialize-etc.sh"

SUDO_ENV_FILE=""
if [[ "${1:-}" == "--onix-env-file" ]]; then
  SUDO_ENV_FILE="${2:?missing env-file path}"
  shift 2
  # shellcheck source=/dev/null
  source "$SUDO_ENV_FILE"
fi

IMAGE_RAW="${ONIX_IMAGE_RAW:-$ONIX_ROOT/artifacts/onix-image/onix.raw}"
WORK_DIR="${ONIX_PHASE4_WORK_DIR:-$ONIX_ROOT/artifacts/onix-phase4-work}"
STATE_DIR="${ONIX_STATE_DIR:-$ONIX_ROOT/vm/state}"
CLOSURE_LIST="${ONIX_SYSTEMD_CLOSURE_LIST:-$ONIX_ROOT/artifacts/onix-image/systemd-payload.closure}"
SYSTEMD_PAYLOAD_OUT="${ONIX_SYSTEMD_PAYLOAD_OUT:-}"
SYSTEMD_PAYLOAD_OUT_FILE="$ONIX_ROOT/artifacts/onix-image/systemd-payload.out"
SERIAL_CONSOLE_PAYLOAD_OUT="${ONIX_SERIAL_CONSOLE_PAYLOAD_OUT:-}"
SERIAL_CONSOLE_PAYLOAD_OUT_FILE="$ONIX_ROOT/artifacts/onix-image/serial-console-payload.out"
SERIAL_CONSOLE_CLOSURE_LIST="${ONIX_SERIAL_CONSOLE_CLOSURE_LIST:-$ONIX_ROOT/artifacts/onix-image/serial-console-payload.closure}"
SERIAL_CONSOLE_APPLETS="${ONIX_SERIAL_CONSOLE_APPLETS:-$ONIX_ROOT/artifacts/onix-image/serial-console-payload.applets}"
SERIAL_CONSOLE_TTY="${ONIX_SERIAL_CONSOLE_TTY:-ttyS1}"
DROPBEAR_PAYLOAD_OUT="${ONIX_DROPBEAR_PAYLOAD_OUT:-}"
DROPBEAR_PAYLOAD_OUT_FILE="$ONIX_ROOT/artifacts/onix-image/dropbear-payload.out"
DROPBEAR_CLOSURE_LIST="${ONIX_DROPBEAR_CLOSURE_LIST:-$ONIX_ROOT/artifacts/onix-image/dropbear-payload.closure}"
SSH_USER="${ONIX_SSH_USER:-onix}"
SSH_UID="${ONIX_SSH_UID:-1000}"
SSH_GID="${ONIX_SSH_GID:-100}"
SSH_CLIENT_KEY="${ONIX_SSH_CLIENT_KEY:-$STATE_DIR/id_ed25519}"
SSH_CLIENT_PUB="${ONIX_SSH_CLIENT_PUB:-$SSH_CLIENT_KEY.pub}"
LOCAL_REPO_DIR="${ONIX_LOCAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-local-repo}"
IMAGE_REPO_DIR="${ONIX_IMAGE_REPO_DIR:-$LOCAL_REPO_DIR}"
HOST_MOSS="${ONIX_HOST_MOSS:-$ONIX_ROOT/artifacts/host-tools/bin/moss}"
BUSYBOX_MOSS_ROOT="$WORK_DIR/busybox-moss-root"
BUSYBOX_MOSS_CACHE="$WORK_DIR/busybox-moss-cache"
BUSYBOX_INSTALL_TARGET="$WORK_DIR/busybox-install-target"
DROPBEAR_MOSS_ROOT="$WORK_DIR/dropbear-moss-root"
DROPBEAR_MOSS_CACHE="$WORK_DIR/dropbear-moss-cache"
DROPBEAR_INSTALL_TARGET="$WORK_DIR/dropbear-install-target"
SYSTEMD_MOSS_ROOT="$WORK_DIR/systemd-moss-root"
SYSTEMD_MOSS_CACHE="$WORK_DIR/systemd-moss-cache"
SYSTEMD_INSTALL_TARGET="$WORK_DIR/systemd-install-target"
BOOTSTRAP_POLICY_MOSS_ROOT="$WORK_DIR/bootstrap-policy-moss-root"
BOOTSTRAP_POLICY_MOSS_CACHE="$WORK_DIR/bootstrap-policy-moss-cache"
BOOTSTRAP_POLICY_INSTALL_TARGET="$WORK_DIR/bootstrap-policy-install-target"
PHASE5_RUNTIME_MOSS_ROOT="$WORK_DIR/phase5-runtime-moss-root"
PHASE5_RUNTIME_MOSS_CACHE="$WORK_DIR/phase5-runtime-moss-cache"
PHASE5_RUNTIME_INSTALL_TARGET="$WORK_DIR/phase5-runtime-install-target"
PHASE5_LIVE_MOSS_ROOT="$WORK_DIR/phase5-live-moss-root"
PHASE5_LIVE_MOSS_CACHE="$WORK_DIR/phase5-live-moss-cache"
MNT="$WORK_DIR/mnt"
DISK_DEV=""
ACTION="etc"
READ_ONLY_MOUNTS=0

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

safe_generated_paths() {
  case "$IMAGE_RAW" in
    "$ONIX_ROOT"/artifacts/onix-image/*.raw) ;;
    *) die "refusing unsafe image path outside artifacts/onix-image/*.raw: $IMAGE_RAW" ;;
  esac
  case "$WORK_DIR" in
    "$ONIX_ROOT"/artifacts/onix-phase4-work) ;;
    "$ONIX_ROOT"/artifacts/onix-phase4-work/*) ;;
    *) die "refusing unsafe work path outside artifacts/onix-phase4-work: $WORK_DIR" ;;
  esac
  case "$IMAGE_REPO_DIR" in
    "$ONIX_ROOT"/artifacts/onix-local-repo) ;;
    "$ONIX_ROOT"/artifacts/onix-local-repo/*) ;;
    "$ONIX_ROOT"/artifacts/onix-repo) ;;
    "$ONIX_ROOT"/artifacts/onix-repo/*) ;;
    *) die "refusing unsafe image repo path outside artifacts/onix-local-repo or artifacts/onix-repo: $IMAGE_REPO_DIR" ;;
  esac
}

validate_serial_tty() {
  case "$SERIAL_CONSOLE_TTY" in
    ttyS[0-9]*) ;;
    *) die "refusing unsafe serial console tty name: $SERIAL_CONSOLE_TTY" ;;
  esac
}

have_stale_mounts() {
  [[ -d "$WORK_DIR" ]] || return 1
  findmnt -R "$WORK_DIR" >/dev/null 2>&1
}

have_stale_loops() {
  [[ -f "$IMAGE_RAW" ]] || return 1
  losetup -j "$IMAGE_RAW" 2>/dev/null | grep -q .
}

unmount_tree() {
  local target="$1"
  if [[ ! -d "$target" ]]; then
    return 0
  fi

  while findmnt -R "$target" >/dev/null 2>&1; do
    findmnt -Rno TARGET "$target" |
      sort -r |
      while IFS= read -r mountpoint; do
        umount "$mountpoint" 2>/dev/null || umount -l "$mountpoint" 2>/dev/null || true
      done
  done
}

cleanup_stale() {
  log "cleaning stale Phase 4 image mounts/loops"
  unmount_tree "$WORK_DIR"
  if [[ -f "$IMAGE_RAW" ]]; then
    while IFS= read -r loopdev; do
      [[ -n "$loopdev" ]] || continue
      losetup -d "$loopdev" 2>/dev/null || true
    done < <(losetup -j "$IMAGE_RAW" 2>/dev/null | awk -F: '{ print $1 }')
  fi
  rm -rf "$WORK_DIR"
}

need_root() {
  if [[ $EUID -eq 0 ]]; then
    return 0
  fi

  need_cmd sudo
  env_file="$(mktemp "${TMPDIR:-/tmp}/onix-phase4-env.XXXXXX")"
  chmod 600 "$env_file"
  {
    for name in \
      ONIX_IMAGE_RAW ONIX_PHASE4_WORK_DIR ONIX_SYSTEMD_CLOSURE_LIST \
      ONIX_SYSTEMD_PAYLOAD_OUT \
      ONIX_SERIAL_CONSOLE_PAYLOAD_OUT ONIX_SERIAL_CONSOLE_CLOSURE_LIST \
      ONIX_SERIAL_CONSOLE_APPLETS ONIX_SERIAL_CONSOLE_TTY \
      ONIX_DROPBEAR_PAYLOAD_OUT ONIX_DROPBEAR_CLOSURE_LIST \
      ONIX_SSH_USER ONIX_SSH_UID ONIX_SSH_GID ONIX_SSH_CLIENT_KEY \
      ONIX_SSH_CLIENT_PUB ONIX_STATE_DIR ONIX_LOCAL_REPO_DIR ONIX_IMAGE_REPO_DIR ONIX_HOST_MOSS \
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

part_path() {
  local num="$1"
  if [[ -e "${DISK_DEV}p${num}" ]]; then
    printf '%s\n' "${DISK_DEV}p${num}"
  else
    printf '%s\n' "${DISK_DEV}${num}"
  fi
}

wait_for_partitions() {
  local i
  for i in $(seq 1 50); do
    if [[ -b "$(part_path 3)" ]]; then
      return 0
    fi
    sleep 0.1
  done
  die "loop partitions did not appear for $DISK_DEV"
}

mount_persist_partition() {
  local persist_dev

  persist_dev="$(part_path 4)"
  expect_blkid "$persist_dev" "ONIX-PERSIST" "xfs"
  ensure_image_mount_dir "$MNT/persist"

  if findmnt "$MNT/persist" >/dev/null 2>&1; then
    return 0
  fi

  mount_image_partition "$persist_dev" "$MNT/persist" "xfs"
  printf 'mount    : ONIX-PERSIST -> /persist\n'
}

mount_boot_partition() {
  local boot_dev

  boot_dev="$(part_path 2)"
  expect_blkid "$boot_dev" "ONIX-BOOT" "vfat"
  ensure_image_mount_dir "$MNT/boot"

  if findmnt "$MNT/boot" >/dev/null 2>&1; then
    return 0
  fi

  mount_image_partition "$boot_dev" "$MNT/boot" "vfat"
  printf 'mount    : ONIX-BOOT -> /boot\n'
}

ensure_image_mount_dir() {
  local target="$1"

  if [[ "$READ_ONLY_MOUNTS" -eq 1 ]]; then
    [[ -d "$target" ]] || die "read-only audit expected mount directory to exist: ${target#$MNT}"
    return 0
  fi

  install -dm0755 "$target"
}

mount_image_partition() {
  local dev="$1"
  local target="$2"
  local type="$3"

  if [[ "$READ_ONLY_MOUNTS" -eq 1 ]]; then
    case "$type" in
      xfs) mount -o ro,norecovery "$dev" "$target" ;;
      *) mount -o ro "$dev" "$target" ;;
    esac
    return 0
  fi

  mount "$dev" "$target"
}

detach() {
  set +e
  sync
  unmount_tree "$MNT"
  if [[ -n "$DISK_DEV" ]]; then
    losetup -d "$DISK_DEV" >/dev/null 2>&1 || true
  fi
}

expect_blkid() {
  local dev="$1"
  local label="$2"
  local type="$3"

  [[ "$(blkid -s LABEL -o value "$dev")" == "$label" ]] \
    || die "partition $dev label mismatch; expected $label"
  [[ "$(blkid -s TYPE -o value "$dev")" == "$type" ]] \
    || die "partition $dev type mismatch; expected $type"
}

copy_default_if_missing() {
  local rel="$1"
  local src="$MNT/usr/share/defaults/$rel"
  local dst="$MNT/$rel"
  local dst_dir

  [[ -f "$src" ]] || die "missing packaged default: /usr/share/defaults/$rel"
  dst_dir="$(dirname "$dst")"
  install -dm0755 "$dst_dir"

  if [[ ! -e "$dst" ]]; then
    install -m0644 "$src" "$dst"
    printf 'created  : /%s from /usr/share/defaults/%s\n' "$rel" "$rel"
    return 0
  fi

  if cmp -s "$src" "$dst"; then
    printf 'default  : /%s already matches packaged default\n' "$rel"
    return 0
  fi

  printf 'override : /%s exists and differs; preserved\n' "$rel"
}

refresh_if_onix_generated() {
  local rel="$1"
  local marker="$2"
  local src="$MNT/usr/share/defaults/$rel"
  local dst="$MNT/$rel"
  local dst_dir

  [[ -f "$src" ]] || die "missing packaged default: /usr/share/defaults/$rel"
  dst_dir="$(dirname "$dst")"
  install -dm0755 "$dst_dir"

  if [[ ! -e "$dst" ]]; then
    install -m0644 "$src" "$dst"
    printf 'created  : /%s from refreshed ONIX default\n' "$rel"
    return 0
  fi

  if cmp -s "$src" "$dst"; then
    printf 'default  : /%s already matches refreshed ONIX default\n' "$rel"
    return 0
  fi

  if grep -q "$marker" "$dst"; then
    install -m0644 "$src" "$dst"
    printf 'refresh  : /%s replaced old generated ONIX default\n' "$rel"
    return 0
  fi

  printf 'override : /%s exists and differs; preserved\n' "$rel"
}

refresh_login_defaults() {
  local motd_bytes

  install -dm0755 \
    "$MNT/usr/share/onix/branding" \
    "$MNT/usr/share/defaults/etc/profile.d" \
    "$MNT/etc/profile.d"

  [[ -f "$MNT/usr/share/onix/branding/logo.txt" ]] \
    || die "missing ONIX logo asset: /usr/share/onix/branding/logo.txt"

  if [[ ! "$MNT/usr/share/onix/branding/logo.txt" -ef "$MNT/usr/share/onix/branding/logo.motd" ]]; then
    cp "$MNT/usr/share/onix/branding/logo.txt" \
      "$MNT/usr/share/onix/branding/logo.motd"
  fi

  cat "$MNT/usr/share/onix/branding/logo.motd" > "$MNT/usr/share/defaults/etc/motd"
  cat >> "$MNT/usr/share/defaults/etc/motd" <<'EOF_MOTD'

Welcome to ONIX.
moss controls the machine. Nix controls the toolbox.
EOF_MOTD

  cat > "$MNT/usr/share/defaults/etc/profile" <<'EOF_PROFILE'
# ONIX default login shell profile.
#
# BusyBox ash reads /etc/profile for login shells. Keep this file small and
# source package-provided policy from /etc/profile.d.

for script in /etc/profile.d/*.sh; do
    [ -r "$script" ] && . "$script"
done

unset script
EOF_PROFILE

  cat > "$MNT/usr/share/defaults/etc/profile.d/onix-path.sh" <<'EOF_PATH'
# ONIX default PATH policy.
# This is a default template; image/boot glue may install it into /etc/profile.d.

case ":${PATH:-}:" in
    *:/usr/bin:*) ;;
    *) PATH="/usr/bin${PATH:+:$PATH}" ;;
esac

case ":$PATH:" in
    *:/usr/sbin:*) ;;
    *) PATH="/usr/sbin:$PATH" ;;
esac

export PATH

if [ -n "${PS1:-}" ]; then
    alias ll='ls -laF'
    alias la='ls -A'
    alias l='ls -CF'
fi
EOF_PATH

  cat > "$MNT/usr/share/defaults/etc/profile.d/onix-login.sh" <<'EOF_LOGIN'
# ONIX interactive login banner.
#
# Dropbear is started with -m so it does not print /etc/motd. That avoids
# Dropbear's MOTD byte limit. Interactive shells print the colored logo here
# instead.

[ -n "${PS1:-}" ] || return 0
[ -t 1 ] || return 0
[ "${TERM:-}" != "dumb" ] || return 0
[ "${ONIX_LOGIN_BANNER:-1}" != "0" ] || return 0

if [ -z "${ONIX_LOGIN_BANNER_SHOWN:-}" ]; then
    export ONIX_LOGIN_BANNER_SHOWN=1

    if [ -r /usr/share/onix/branding/logo.ansi ]; then
        cat /usr/share/onix/branding/logo.ansi
    elif [ -r /etc/motd ]; then
        cat /etc/motd
    fi

    printf '\nWelcome to ONIX.\n'
    printf 'moss controls the machine. Nix controls the toolbox.\n'
fi
EOF_LOGIN

  chmod 0644 \
    "$MNT/usr/share/onix/branding/logo.motd" \
    "$MNT/usr/share/defaults/etc/motd" \
    "$MNT/usr/share/defaults/etc/profile" \
    "$MNT/usr/share/defaults/etc/profile.d/onix-path.sh" \
    "$MNT/usr/share/defaults/etc/profile.d/onix-login.sh"

  motd_bytes="$(wc -c < "$MNT/usr/share/defaults/etc/motd")"
  [[ "$motd_bytes" -lt 2048 ]] \
    || die "generated login MOTD is too large for bootstrap Dropbear banner: ${motd_bytes} bytes"

  refresh_if_onix_generated etc/motd 'Welcome to ONIX'
  refresh_if_onix_generated etc/profile 'ONIX default login shell profile'
  refresh_if_onix_generated etc/profile.d/onix-path.sh 'ONIX default PATH policy'
  refresh_if_onix_generated etc/profile.d/onix-login.sh 'ONIX interactive login banner'

  printf 'login   : MOTD/profile/color-login defaults refreshed (%s MOTD bytes)\n' "$motd_bytes"
}

copy_nix_closure_into() {
  local dest="$1"
  local list="$2"
  local rel_list

  [[ -d "$dest" ]] || die "closure destination is missing: $dest"
  [[ -s "$list" ]] || die "closure list is missing/empty: ${list#$ONIX_ROOT/}"

  need_cmd tar
  rel_list="$(mktemp "${TMPDIR:-/tmp}/onix-phase4-closure.XXXXXX")"
  sed 's#^/##' "$list" > "$rel_list"

  mkdir -p "$dest/nix/store"
  tar --numeric-owner -C / -cpf - -T "$rel_list" | tar --numeric-owner -C "$dest" -xpf -
  rm -f "$rel_list"
}

verify_busybox_payload() {
  local out="$1"
  local interp

  [[ -n "$out" ]] || die "empty BusyBox payload path"
  [[ -x "$out/bin/busybox" ]] || die "BusyBox payload is missing bin/busybox: $out"

  interp="$(readelf -l "$out/bin/busybox" 2>/dev/null |
    sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p' |
    head -n1)"
  if [[ -n "$interp" ]]; then
    [[ "$interp" == /nix/store/*/lib/ld-musl-x86_64.so.1 ]] \
      || die "BusyBox payload is not musl-linked; interpreter=$interp"
  fi

  "$out/bin/busybox" --list | grep -qx sh \
    || die "BusyBox payload does not provide the sh applet"
}

prepare_serial_console_payload() {
  local expr out

  need_cmd nix
  need_cmd readelf
  mkdir -p "$ONIX_ROOT/artifacts/onix-image"

  if [[ -n "$SERIAL_CONSOLE_PAYLOAD_OUT" &&
        -s "$SERIAL_CONSOLE_CLOSURE_LIST" &&
        -s "$SERIAL_CONSOLE_APPLETS" ]]; then
    verify_busybox_payload "$SERIAL_CONSOLE_PAYLOAD_OUT"
    return 0
  fi

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
in pkgs.pkgsMusl.busybox
EOF_NIX

  log "checking musl BusyBox bootstrap shell build graph"
  nix build --dry-run --impure --expr "$expr" >/dev/null

  log "building/fetching musl BusyBox bootstrap shell payload"
  out="$(nix build --impure --no-link --print-out-paths --expr "$expr")"
  verify_busybox_payload "$out"

  nix path-info -r "$out" | sort > "$SERIAL_CONSOLE_CLOSURE_LIST"
  "$out/bin/busybox" --list | sort -u > "$SERIAL_CONSOLE_APPLETS"
  printf '%s\n' "$out" > "$SERIAL_CONSOLE_PAYLOAD_OUT_FILE"

  SERIAL_CONSOLE_PAYLOAD_OUT="$out"
  export ONIX_SERIAL_CONSOLE_PAYLOAD_OUT="$SERIAL_CONSOLE_PAYLOAD_OUT"
  export ONIX_SERIAL_CONSOLE_CLOSURE_LIST="$SERIAL_CONSOLE_CLOSURE_LIST"
  export ONIX_SERIAL_CONSOLE_APPLETS="$SERIAL_CONSOLE_APPLETS"

  log "serial console payload ready"
  echo "busybox: $SERIAL_CONSOLE_PAYLOAD_OUT"
  echo "closure: ${SERIAL_CONSOLE_CLOSURE_LIST#$ONIX_ROOT/}"
}

load_serial_console_payload_metadata() {
  if [[ -z "$SERIAL_CONSOLE_PAYLOAD_OUT" && -f "$SERIAL_CONSOLE_PAYLOAD_OUT_FILE" ]]; then
    SERIAL_CONSOLE_PAYLOAD_OUT="$(< "$SERIAL_CONSOLE_PAYLOAD_OUT_FILE")"
  fi

  [[ -n "$SERIAL_CONSOLE_PAYLOAD_OUT" ]] \
    || die "missing serial console payload; run make phase 403 from a non-root dev shell"
  [[ -s "$SERIAL_CONSOLE_CLOSURE_LIST" ]] \
    || die "missing serial console closure list: ${SERIAL_CONSOLE_CLOSURE_LIST#$ONIX_ROOT/}"
  [[ -s "$SERIAL_CONSOLE_APPLETS" ]] \
    || die "missing serial console applet list: ${SERIAL_CONSOLE_APPLETS#$ONIX_ROOT/}"
}

verify_dropbear_payload() {
  local out="$1"
  local interp

  [[ -n "$out" ]] || die "empty Dropbear payload path"
  [[ -x "$out/bin/dropbear" ]] || die "Dropbear payload is missing bin/dropbear: $out"
  [[ -x "$out/bin/dropbearkey" ]] || die "Dropbear payload is missing bin/dropbearkey: $out"

  interp="$(readelf -l "$out/bin/dropbear" 2>/dev/null |
    sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p' |
    head -n1)"
  if [[ -n "$interp" ]]; then
    [[ "$interp" == /nix/store/*/lib/ld-musl-x86_64.so.1 ]] \
      || die "Dropbear payload is not musl-linked; interpreter=$interp"
  fi
}

prepare_dropbear_payload() {
  local expr out

  need_cmd nix
  need_cmd readelf
  mkdir -p "$ONIX_ROOT/artifacts/onix-image"

  if [[ -n "$DROPBEAR_PAYLOAD_OUT" && -s "$DROPBEAR_CLOSURE_LIST" ]]; then
    verify_dropbear_payload "$DROPBEAR_PAYLOAD_OUT"
    return 0
  fi

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
in pkgs.pkgsMusl.dropbear
EOF_NIX

  log "checking musl Dropbear bootstrap SSH build graph"
  nix build --dry-run --impure --expr "$expr" >/dev/null

  log "building/fetching musl Dropbear bootstrap SSH payload"
  out="$(nix build --impure --no-link --print-out-paths --expr "$expr")"
  verify_dropbear_payload "$out"

  nix path-info -r "$out" | sort > "$DROPBEAR_CLOSURE_LIST"
  printf '%s\n' "$out" > "$DROPBEAR_PAYLOAD_OUT_FILE"

  DROPBEAR_PAYLOAD_OUT="$out"
  export ONIX_DROPBEAR_PAYLOAD_OUT="$DROPBEAR_PAYLOAD_OUT"
  export ONIX_DROPBEAR_CLOSURE_LIST="$DROPBEAR_CLOSURE_LIST"

  log "Dropbear payload ready"
  echo "dropbear: $DROPBEAR_PAYLOAD_OUT"
  echo "closure : ${DROPBEAR_CLOSURE_LIST#$ONIX_ROOT/}"
}

load_dropbear_payload_metadata() {
  if [[ -z "$DROPBEAR_PAYLOAD_OUT" && -f "$DROPBEAR_PAYLOAD_OUT_FILE" ]]; then
    DROPBEAR_PAYLOAD_OUT="$(< "$DROPBEAR_PAYLOAD_OUT_FILE")"
  fi

  [[ -n "$DROPBEAR_PAYLOAD_OUT" ]] \
    || die "missing Dropbear payload; run make phase 406 from a non-root dev shell"
  [[ -s "$DROPBEAR_CLOSURE_LIST" ]] \
    || die "missing Dropbear closure list: ${DROPBEAR_CLOSURE_LIST#$ONIX_ROOT/}"
}

ensure_ssh_client_key() {
  need_cmd ssh-keygen
  install -dm0700 "$(dirname "$SSH_CLIENT_KEY")"

  if [[ ! -f "$SSH_CLIENT_KEY" ]]; then
    ssh-keygen -t ed25519 -N '' -f "$SSH_CLIENT_KEY" -C "onix-phase406" >/dev/null
    chmod 0600 "$SSH_CLIENT_KEY"
    printf 'ssh-key  : generated %s\n' "${SSH_CLIENT_KEY#$ONIX_ROOT/}"
  fi

  if [[ ! -f "$SSH_CLIENT_PUB" ]]; then
    ssh-keygen -y -f "$SSH_CLIENT_KEY" > "$SSH_CLIENT_PUB"
    chmod 0644 "$SSH_CLIENT_PUB"
    printf 'ssh-key  : generated %s\n' "${SSH_CLIENT_PUB#$ONIX_ROOT/}"
  fi

  [[ -s "$SSH_CLIENT_KEY" ]] || die "SSH client key is empty: $SSH_CLIENT_KEY"
  [[ -s "$SSH_CLIENT_PUB" ]] || die "SSH client public key is empty: $SSH_CLIENT_PUB"
}

load_systemd_payload_metadata() {
  if [[ -z "$SYSTEMD_PAYLOAD_OUT" && -f "$SYSTEMD_PAYLOAD_OUT_FILE" ]]; then
    SYSTEMD_PAYLOAD_OUT="$(< "$SYSTEMD_PAYLOAD_OUT_FILE")"
  fi

  [[ -n "$SYSTEMD_PAYLOAD_OUT" ]] \
    || die "missing systemd payload path; run make phase 213 first"
  [[ "$SYSTEMD_PAYLOAD_OUT" == /nix/store/* ]] \
    || die "systemd payload path should be an absolute Nix store path: $SYSTEMD_PAYLOAD_OUT"
  [[ -d "$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system" ]] \
    || die "systemd unit tree missing inside image: $SYSTEMD_PAYLOAD_OUT/example/systemd/system"
}

load_systemd_payload_metadata_if_present() {
  if [[ -z "$SYSTEMD_PAYLOAD_OUT" && -f "$SYSTEMD_PAYLOAD_OUT_FILE" ]]; then
    SYSTEMD_PAYLOAD_OUT="$(< "$SYSTEMD_PAYLOAD_OUT_FILE")"
  fi

  if [[ -z "$SYSTEMD_PAYLOAD_OUT" ]]; then
    printf 'legacy  : old bootstrap systemd payload metadata absent; native reinstall remains OK\n'
    return 0
  fi

  [[ "$SYSTEMD_PAYLOAD_OUT" == /nix/store/* ]] \
    || die "systemd payload path should be an absolute Nix store path: $SYSTEMD_PAYLOAD_OUT"

  if [[ -d "$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system" ]]; then
    printf 'legacy  : old bootstrap systemd payload still present and will be pruned\n'
    return 0
  fi

  printf 'legacy  : old bootstrap systemd payload already absent: %s\n' "$SYSTEMD_PAYLOAD_OUT"
}

active_systemd_root_unit_dir() {
  if [[ -d "$MNT/usr/lib/systemd/system" && ! -L "$MNT/usr/lib/systemd/system" ]]; then
    printf '%s\n' "$MNT/usr/lib/systemd/system"
    return 0
  fi

  load_systemd_payload_metadata
  printf '%s\n' "$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system"
}

active_systemd_persist_unit_dir_if_present() {
  if [[ -d "$MNT/persist/usr/lib/systemd/system" && ! -L "$MNT/persist/usr/lib/systemd/system" ]]; then
    printf '%s\n' "$MNT/persist/usr/lib/systemd/system"
    return 0
  fi

  if [[ -z "$SYSTEMD_PAYLOAD_OUT" && -f "$SYSTEMD_PAYLOAD_OUT_FILE" ]]; then
    SYSTEMD_PAYLOAD_OUT="$(< "$SYSTEMD_PAYLOAD_OUT_FILE")"
  fi

  if [[ -n "$SYSTEMD_PAYLOAD_OUT" && -d "$MNT/persist$SYSTEMD_PAYLOAD_OUT/example/systemd/system" ]]; then
    printf '%s\n' "$MNT/persist$SYSTEMD_PAYLOAD_OUT/example/systemd/system"
  fi
}

ensure_os_release_link() {
  local link="$MNT/etc/os-release"

  install -dm0755 "$MNT/etc"
  [[ -f "$MNT/usr/lib/os-release" ]] || die "missing /usr/lib/os-release"

  if [[ -e "$link" && ! -L "$link" ]]; then
    die "/etc/os-release exists but is not a symlink; refusing to overwrite"
  fi

  ln -sfn ../usr/lib/os-release "$link"
  [[ "$(readlink "$link")" == "../usr/lib/os-release" ]] \
    || die "/etc/os-release symlink target is wrong"
  printf 'symlink  : /etc/os-release -> ../usr/lib/os-release\n'
}

ensure_machine_id() {
  install -dm0755 "$MNT/etc"
  if [[ ! -e "$MNT/etc/machine-id" ]]; then
    : > "$MNT/etc/machine-id"
    chmod 0644 "$MNT/etc/machine-id"
    printf 'created  : /etc/machine-id as empty first-boot placeholder\n'
    return 0
  fi

  chmod 0644 "$MNT/etc/machine-id"
  printf 'preserve : /etc/machine-id exists as machine-local state\n'
}

ensure_hostname() {
  install -dm0755 "$MNT/etc"
  if [[ ! -e "$MNT/etc/hostname" ]]; then
    printf 'onix\n' > "$MNT/etc/hostname"
    chmod 0644 "$MNT/etc/hostname"
    printf 'created  : /etc/hostname = onix\n'
    return 0
  fi

  printf 'preserve : /etc/hostname exists as machine-local state\n'
}

write_proof() {
  install -dm0755 "$MNT/usr/share/onix/bootstrap"
  cat > "$MNT/usr/share/onix/bootstrap/etc-materialization.txt" <<'EOF'
ONIX Phase 401 live /etc materialization

Policy:

- Packaged defaults live under /usr/share/defaults.
- Live machine configuration lives under /etc.
- Missing live files may be created from packaged defaults.
- Existing live files that differ from defaults are preserved as local overrides.
- /etc/os-release is a compatibility symlink to ../usr/lib/os-release.
- /etc/machine-id is machine-local state and is never replaced by defaults.

Materialized defaults:

- /usr/share/defaults/etc/issue -> /etc/issue
- /usr/share/defaults/etc/motd -> /etc/motd
- /usr/share/defaults/etc/fstab -> /etc/fstab
- /usr/share/defaults/etc/profile -> /etc/profile
- /usr/share/defaults/etc/profile.d/onix-path.sh -> /etc/profile.d/onix-path.sh

This is still bootstrap glue. Later ONIX should move this policy into a small
first-boot materializer or systemd unit owned by an ONIX stone.
EOF
  chmod 0644 "$MNT/usr/share/onix/bootstrap/etc-materialization.txt"
  printf 'proof    : /usr/share/onix/bootstrap/etc-materialization.txt\n'
}

find_nologin_target() {
  [[ -s "$CLOSURE_LIST" ]] \
    || die "missing systemd closure list: ${CLOSURE_LIST#$ONIX_ROOT/}; run make phase 213 first"

  while IFS= read -r store_path; do
    [[ -n "$store_path" ]] || continue
    if [[ -x "$MNT$store_path/bin/nologin" ]]; then
      printf '%s/bin/nologin\n' "$store_path"
      return 0
    fi
  done < "$CLOSURE_LIST"

  die "no executable nologin found in copied systemd closure"
}

ensure_nologin_link() {
  local link="$MNT/usr/sbin/nologin"
  local target

  target="$(find_nologin_target)"
  install -dm0755 "$MNT/usr/sbin"

  if [[ -e "$link" && ! -L "$link" ]]; then
    [[ -x "$link" ]] || die "/usr/sbin/nologin exists but is not executable"
    printf 'preserve : /usr/sbin/nologin exists as local executable\n'
    return 0
  fi

  ln -sfn "$target" "$link"
  [[ "$(readlink "$link")" == "$target" ]] \
    || die "/usr/sbin/nologin symlink target is wrong"
  [[ -x "$MNT$target" ]] || die "/usr/sbin/nologin target is not executable in image"
  printf 'symlink  : /usr/sbin/nologin -> %s\n' "$target"
}

write_sysusers_policy() {
  install -dm0755 "$MNT/usr/lib/sysusers.d"
  cat > "$MNT/usr/lib/sysusers.d/onix-base.conf" <<'EOF'
# ONIX Phase 402 base account policy.
#
# This is package-owned policy. systemd-sysusers reads it and creates missing
# live account database entries under /etc without overwriting local choices.
#
# Type Name             ID     GECOS / members
g root                  0      -
g bin                   1      -
g daemon                2      -
g sys                   3      -
g adm                   4      -
g tty                   5      -
g disk                  6      -
g wheel                 10     -
g shadow                42     -
g systemd-journal       190    -
g users                 100    -
g nogroup               65534  -

# Type Name             ID:GID      GECOS        Home        Shell
u root                  0:0         "Super User" /root       /usr/sbin/nologin
u nobody                65534:65534 "Nobody"     /var/empty  /usr/sbin/nologin
EOF
  chmod 0644 "$MNT/usr/lib/sysusers.d/onix-base.conf"
  printf 'policy   : /usr/lib/sysusers.d/onix-base.conf\n'
}

write_account_defaults() {
  install -dm0755 "$MNT/usr/share/defaults/etc"

  cat > "$MNT/usr/share/defaults/etc/nsswitch.conf" <<'EOF'
# ONIX default name-service switch policy.
#
# Phase 402 only has local files. Later networking/name-service phases may add
# DNS, mDNS, or other resolvers deliberately.
passwd: files
group: files
shadow: files
gshadow: files

hosts: files dns
networks: files

protocols: files
services: files
ethers: files
rpc: files
EOF
  chmod 0644 "$MNT/usr/share/defaults/etc/nsswitch.conf"

  cat > "$MNT/usr/share/defaults/etc/shells" <<'EOF'
# ONIX Phase 402 shell policy.
#
# There is no interactive shell provider yet. /usr/sbin/nologin is exposed so
# accounts can be explicit and safely non-interactive until a later phase adds
# and proves a real login path.
/usr/sbin/nologin
EOF
  chmod 0644 "$MNT/usr/share/defaults/etc/shells"

  printf 'default  : /usr/share/defaults/etc/nsswitch.conf\n'
  printf 'default  : /usr/share/defaults/etc/shells\n'
}

run_sysusers() {
  need_cmd systemd-sysusers
  install -dm0700 "$MNT/root"
  install -dm0555 "$MNT/var/empty"

  systemd-sysusers --root="$MNT" "$MNT/usr/lib/sysusers.d/onix-base.conf"
  printf 'sysusers : materialized missing /etc passwd/group/shadow entries\n'
}

write_account_proof() {
  install -dm0755 "$MNT/usr/share/onix/bootstrap"
  cat > "$MNT/usr/share/onix/bootstrap/account-policy.txt" <<'EOF'
ONIX Phase 402 base account policy

Policy:

- Package-owned account policy lives in /usr/lib/sysusers.d/onix-base.conf.
- systemd-sysusers materializes missing live account entries under /etc.
- Existing live users/groups are preserved instead of silently overwritten.
- /etc/nsswitch.conf starts with local files only for users and groups.
- /etc/shells intentionally lists /usr/sbin/nologin only.

Important limitation:

Phase 402 does not make serial login work yet.

The root account exists, but it is non-interactive:

- root has UID 0 and GID 0
- root's shell is /usr/sbin/nologin
- no root password is installed here

Phase 403 adds a temporary bootstrap serial root console. A later phase should
add and prove the real authenticated login path: a shell, getty or equivalent
terminal service, and an explicit authentication decision.
EOF
  chmod 0644 "$MNT/usr/share/onix/bootstrap/account-policy.txt"
  printf 'proof    : /usr/share/onix/bootstrap/account-policy.txt\n'
}

bootstrap_busybox_applets() {
  cat <<'EOF'
ash
awk
basename
cat
chmod
chown
clear
cp
cut
date
df
dmesg
du
echo
env
false
find
getty
grep
head
hostname
id
ifconfig
insmod
ip
less
ln
ls
lsmod
mkdir
modprobe
mount
mv
nc
netstat
nslookup
ping
ping6
ps
pwd
rm
rmdir
rmmod
route
sed
setsid
sh
sleep
sort
stty
sync
tail
tee
touch
true
tty
udhcpc
umount
uname
vi
wc
wget
whoami
cttyhack
EOF
}

link_busybox_applet() {
  local applet="$1"
  local link="$MNT/bin/$applet"

  grep -qx "$applet" "$SERIAL_CONSOLE_APPLETS" || return 0

  if [[ -e "$link" && ! -L "$link" ]]; then
    printf 'preserve : /bin/%s exists and is not a symlink\n' "$applet"
    return 0
  fi

  rm -f "$link"
  ln -s busybox "$link"
}

install_busybox_shell() {
  local applet

  load_serial_console_payload_metadata

  [[ -x "$MNT$SERIAL_CONSOLE_PAYLOAD_OUT/bin/busybox" ]] \
    || die "BusyBox payload was not copied into image root: $SERIAL_CONSOLE_PAYLOAD_OUT"

  install -dm0755 "$MNT/bin" "$MNT/usr/bin"
  rm -f "$MNT/bin/busybox"
  ln -s "$SERIAL_CONSOLE_PAYLOAD_OUT/bin/busybox" "$MNT/bin/busybox"
  while IFS= read -r applet; do
    [[ -n "$applet" ]] || continue
    link_busybox_applet "$applet"
  done < <(bootstrap_busybox_applets)

  printf 'shell    : /bin/busybox -> %s/bin/busybox\n' "$SERIAL_CONSOLE_PAYLOAD_OUT"
  printf 'shell    : /bin/sh -> busybox\n'
}

verify_busybox_stone_target() {
  local target="$1"
  local applet
  local interp
  local links_manifest="$target/usr/share/onix/packages/busybox.links"

  [[ -x "$target/usr/bin/busybox" ]] \
    || die "busybox target is missing /usr/bin/busybox: $target"

  interp="$(readelf -l "$target/usr/bin/busybox" 2>/dev/null |
    sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p' |
    head -n1)"
  [[ -z "$interp" ]] \
    || die "busybox should be static for this bootstrap phase; interpreter=$interp"

  "$target/usr/bin/busybox" true
  "$target/usr/bin/busybox" sh -c 'echo busybox shell works' >/dev/null

  [[ -f "$target/usr/share/onix/packages/busybox.applets" ]] \
    || die "busybox install target is missing applet manifest"
  [[ -f "$links_manifest" ]] \
    || die "busybox install target is missing link manifest"
  [[ -f "$target/usr/share/onix/packages/busybox.md" ]] \
    || die "busybox install target is missing package note"

  while IFS= read -r applet; do
    [[ -n "$applet" ]] || continue
    "$target/usr/bin/busybox" --list | grep -qx "$applet" \
      || die "busybox is missing applet: $applet"
    [[ -e "$target/usr/bin/$applet" ]] \
      || die "busybox install target is missing /usr/bin/$applet"
  done < "$links_manifest"
}

install_busybox_stone_payload() {
  [[ -x "$HOST_MOSS" ]] \
    || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run make phase 202)"
  [[ -f "$IMAGE_REPO_DIR/stone.index" ]] \
    || die "missing ONIX image package repo index: ${IMAGE_REPO_DIR#$ONIX_ROOT/}/stone.index (run make phase 505)"

  need_cmd readelf
  need_cmd tar
  need_cmd file

  log "materializing busybox from the image package repo into a scratch target"
  rm -rf "$BUSYBOX_MOSS_ROOT" "$BUSYBOX_MOSS_CACHE" "$BUSYBOX_INSTALL_TARGET"
  install -dm0755 "$BUSYBOX_MOSS_ROOT" "$BUSYBOX_MOSS_CACHE" "$BUSYBOX_INSTALL_TARGET"

  "$HOST_MOSS" -D "$BUSYBOX_MOSS_ROOT" --cache "$BUSYBOX_MOSS_CACHE" \
    repo add onix-image "file://$IMAGE_REPO_DIR/stone.index" \
    -c "ONIX image package repo" >/dev/null
  "$HOST_MOSS" -D "$BUSYBOX_MOSS_ROOT" --cache "$BUSYBOX_MOSS_CACHE" \
    repo update >/dev/null
  "$HOST_MOSS" -D "$BUSYBOX_MOSS_ROOT" --cache "$BUSYBOX_MOSS_CACHE" \
    -y install --to "$BUSYBOX_INSTALL_TARGET" busybox

  verify_busybox_stone_target "$BUSYBOX_INSTALL_TARGET"

  log "copying busybox package payload into the ONIX image"
  install -dm0755 "$MNT/usr"
  tar --numeric-owner -C "$BUSYBOX_INSTALL_TARGET" -cpf - \
    usr/bin \
    usr/share/onix/packages \
    | tar --numeric-owner -C "$MNT" -xpf -

  verify_busybox_stone_target "$MNT"
  printf 'stone    : busybox installed under /usr/bin\n'
}

link_stone_busybox_applet() {
  local applet="$1"
  local link="$MNT/bin/$applet"

  "$MNT/usr/bin/busybox" --list | grep -qx "$applet" \
    || die "stone BusyBox does not provide applet: $applet"

  if [[ -e "$link" && ! -L "$link" ]]; then
    die "refusing to replace non-symlink /bin/$applet"
  fi

  rm -f "$link"
  ln -s busybox "$link"
}

install_stone_busybox_compat_links() {
  local applet
  local bin_target

  if [[ -L "$MNT/bin" ]]; then
    bin_target="$(readlink "$MNT/bin")"
    case "$bin_target" in
      usr/bin|/usr/bin|../usr/bin) ;;
      *) die "refusing unexpected /bin symlink target: $bin_target" ;;
    esac

    while IFS= read -r applet; do
      [[ -n "$applet" ]] || continue
      [[ -e "$MNT/bin/$applet" ]] \
        || die "merged-/usr /bin compatibility path is missing applet: /bin/$applet"
    done < "$MNT/usr/share/onix/packages/busybox.links"

    printf 'compat  : /bin -> %s; applets resolve through /usr/bin\n' "$bin_target"
    return 0
  fi

  install -dm0755 "$MNT/bin"
  if [[ -e "$MNT/bin/busybox" && ! -L "$MNT/bin/busybox" ]]; then
    die "refusing to replace non-symlink /bin/busybox"
  fi

  rm -f "$MNT/bin/busybox"
  ln -s ../usr/bin/busybox "$MNT/bin/busybox"

  while IFS= read -r applet; do
    [[ -n "$applet" ]] || continue
    link_stone_busybox_applet "$applet"
  done < "$MNT/usr/share/onix/packages/busybox.links"

  printf 'compat  : /bin/busybox -> ../usr/bin/busybox\n'
  printf 'compat  : /bin/<applet> -> busybox\n'
}

rewrite_serial_unit_to_stone_busybox_one() {
  local unit="$1"

  [[ -f "$unit" ]] || die "missing serial unit to rewrite: ${unit#$MNT}"
  sed -i \
    's#^ExecStart=.*bin/busybox sh /usr/lib/onix/bootstrap-serial-shell$#ExecStart=/usr/bin/busybox sh /usr/lib/onix/bootstrap-serial-shell#' \
    "$unit"
  grep -q '^ExecStart=/usr/bin/busybox sh /usr/lib/onix/bootstrap-serial-shell$' "$unit" \
    || die "serial unit did not switch to /usr/bin/busybox: ${unit#$MNT}"
  printf 'unit     : %s now starts /usr/bin/busybox\n' "${unit#$MNT}"
}

rewrite_serial_unit_to_stone_busybox() {
  local root_unit_dir
  local persist_unit_dir
  local root_unit
  local persist_unit

  root_unit_dir="$(active_systemd_root_unit_dir)"
  persist_unit_dir="$(active_systemd_persist_unit_dir_if_present)"
  root_unit="$root_unit_dir/onix-bootstrap-serial-shell.service"
  persist_unit="$persist_unit_dir/onix-bootstrap-serial-shell.service"

  rewrite_serial_unit_to_stone_busybox_one "$root_unit"
  if [[ -n "$persist_unit_dir" && -f "$persist_unit" ]]; then
    rewrite_serial_unit_to_stone_busybox_one "$persist_unit"
  fi
}

write_busybox_stone_proof() {
  install -dm0755 "$MNT/usr/share/onix/bootstrap"
  cat > "$MNT/usr/share/onix/bootstrap/busybox-stone.txt" <<'EOF'
ONIX Phase 410 busybox image install

Policy:

- BusyBox is machine-plane software.
- Machine-plane software should come from moss/.stone packages.
- Phase 410 consumes busybox from the local Phase 4 moss repo.
- The package-owned payload lives under /usr/bin.
- /bin remains an image compatibility layer for early bootstrap scripts.

Installed package-owned payload:

- /usr/bin/busybox
- /usr/bin/sh
- /usr/bin/ifconfig
- /usr/bin/ip
- /usr/bin/nc
- /usr/share/onix/packages/busybox.applets
- /usr/share/onix/packages/busybox.md

Compatibility links:

- If the image uses merged-/usr, /bin itself points at /usr/bin.
- Otherwise /bin/busybox points at ../usr/bin/busybox and applets point at
  busybox.
- In either layout, /bin/sh, /bin/nc, and /bin/ifconfig resolve to the
  busybox payload.

Important limitation:

Phase 410 intentionally does not garbage-collect the older Nix BusyBox closure
yet. The active shell/network command path now points at busybox, but the
old copied closure may still exist on disk until the later no-Nix-payload audit.

The next phase should boot the image again and prove that shell, networking, and
SSH still work with the stone-provided BusyBox.
EOF
  chmod 0644 "$MNT/usr/share/onix/bootstrap/busybox-stone.txt"
  printf 'proof    : /usr/share/onix/bootstrap/busybox-stone.txt\n'
}

verify_dropbear_stone_target() {
  local target="$1"
  local interp
  local key_tmp

  [[ -x "$target/usr/sbin/dropbear" ]] \
    || die "dropbear target is missing /usr/sbin/dropbear: $target"
  [[ -x "$target/usr/bin/dropbearkey" ]] \
    || die "dropbear target is missing /usr/bin/dropbearkey: $target"

  interp="$(readelf -l "$target/usr/sbin/dropbear" 2>/dev/null |
    sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p' |
    head -n1)"
  [[ -z "$interp" ]] \
    || die "dropbear should be static for this bootstrap phase; interpreter=$interp"

  interp="$(readelf -l "$target/usr/bin/dropbearkey" 2>/dev/null |
    sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p' |
    head -n1)"
  [[ -z "$interp" ]] \
    || die "dropbearkey should be static for this bootstrap phase; interpreter=$interp"

  key_tmp="$(mktemp "${TMPDIR:-/tmp}/dropbearkey.XXXXXX")"
  rm -f "$key_tmp"
  "$target/usr/bin/dropbearkey" -t ed25519 -f "$key_tmp" >/dev/null
  [[ -s "$key_tmp" ]] || die "dropbearkey did not create a host key"
  rm -f "$key_tmp"

  [[ -f "$target/usr/share/onix/packages/dropbear.md" ]] \
    || die "dropbear install target is missing package note"
}

install_dropbear_stone_payload() {
  [[ -x "$HOST_MOSS" ]] \
    || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run make phase 202)"
  [[ -f "$IMAGE_REPO_DIR/stone.index" ]] \
    || die "missing ONIX image package repo index: ${IMAGE_REPO_DIR#$ONIX_ROOT/}/stone.index (run make phase 505)"

  need_cmd readelf
  need_cmd tar
  need_cmd file

  log "materializing dropbear from the image package repo into a scratch target"
  rm -rf "$DROPBEAR_MOSS_ROOT" "$DROPBEAR_MOSS_CACHE" "$DROPBEAR_INSTALL_TARGET"
  install -dm0755 "$DROPBEAR_MOSS_ROOT" "$DROPBEAR_MOSS_CACHE" "$DROPBEAR_INSTALL_TARGET"

  "$HOST_MOSS" -D "$DROPBEAR_MOSS_ROOT" --cache "$DROPBEAR_MOSS_CACHE" \
    repo add onix-image "file://$IMAGE_REPO_DIR/stone.index" \
    -c "ONIX image package repo" >/dev/null
  "$HOST_MOSS" -D "$DROPBEAR_MOSS_ROOT" --cache "$DROPBEAR_MOSS_CACHE" \
    repo update >/dev/null
  "$HOST_MOSS" -D "$DROPBEAR_MOSS_ROOT" --cache "$DROPBEAR_MOSS_CACHE" \
    -y install --to "$DROPBEAR_INSTALL_TARGET" dropbear

  verify_dropbear_stone_target "$DROPBEAR_INSTALL_TARGET"

  log "copying dropbear package payload into the ONIX image"
  install -dm0755 "$MNT/usr"
  tar --numeric-owner -C "$DROPBEAR_INSTALL_TARGET" -cpf - \
    usr/bin/dropbearkey \
    usr/sbin/dropbear \
    usr/share/onix/packages/dropbear.md \
    | tar --numeric-owner -C "$MNT" -xpf -

  verify_dropbear_stone_target "$MNT"
  printf 'stone    : dropbear installed under /usr/bin + /usr/sbin\n'
}

generate_stone_dropbear_host_key() {
  local key="$MNT/etc/dropbear/dropbear_ed25519_host_key"

  verify_dropbear_stone_target "$MNT"
  install -dm0700 "$MNT/etc/dropbear"

  if [[ ! -s "$key" ]]; then
    "$MNT/usr/bin/dropbearkey" -t ed25519 -f "$key" >/dev/null
    chmod 0600 "$key"
    printf 'ssh-host : /etc/dropbear/dropbear_ed25519_host_key generated by /usr/bin/dropbearkey\n'
    return 0
  fi

  chmod 0600 "$key"
  printf 'ssh-host : /etc/dropbear/dropbear_ed25519_host_key preserved\n'
}

write_stone_dropbear_unit_tree() {
  local unit_dir="$1"
  local unit="$unit_dir/onix-bootstrap-dropbear.service"
  local wants="$unit_dir/multi-user.target.wants"

  [[ "$unit_dir" == "$MNT"/nix/store/*/example/systemd/system ||
     "$unit_dir" == "$MNT"/persist/nix/store/*/example/systemd/system ||
     "$unit_dir" == "$MNT"/usr/lib/systemd/system ]] \
    || die "refusing to write systemd unit outside active image unit tree: $unit_dir"

  install -dm0755 "$unit_dir" "$wants"

  cat > "$unit" <<EOF
[Unit]
Description=ONIX bootstrap Dropbear SSH server
Documentation=file:/usr/share/onix/bootstrap/dropbear-stone.txt
After=onix-bootstrap-network.service
Requires=onix-bootstrap-network.service

[Service]
Type=simple
Environment=ONIX_SSH_USER=$SSH_USER
Environment=PATH=/bin:/usr/bin:/sbin:/usr/sbin
ExecStart=/usr/sbin/dropbear -F -E -e -m -s -w -j -k -p 0.0.0.0:22 -r /etc/dropbear/dropbear_ed25519_host_key -P /run/dropbear.pid
Restart=always
RestartSec=1
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "$unit"

  rm -f "$wants/onix-bootstrap-dropbear.service"
  ln -s ../onix-bootstrap-dropbear.service "$wants/onix-bootstrap-dropbear.service"

  printf 'unit     : %s\n' "${unit#$MNT}"
  printf 'enable   : %s\n' "${wants#$MNT}/onix-bootstrap-dropbear.service"
}

write_stone_dropbear_unit() {
  local root_unit_dir
  local persist_unit_dir

  root_unit_dir="$(active_systemd_root_unit_dir)"
  persist_unit_dir="$(active_systemd_persist_unit_dir_if_present)"

  write_stone_dropbear_unit_tree "$root_unit_dir"
  if [[ -n "$persist_unit_dir" ]]; then
    write_stone_dropbear_unit_tree "$persist_unit_dir"
  fi
}

write_dropbear_stone_proof() {
  install -dm0755 "$MNT/usr/share/onix/bootstrap"
  cat > "$MNT/usr/share/onix/bootstrap/dropbear-stone.txt" <<'EOF'
ONIX Phase 413 dropbear image install

Policy:

- Dropbear is machine-plane software.
- Machine-plane software should come from moss/.stone packages.
- Phase 413 consumes dropbear from the local Phase 4 moss repo.
- The package-owned server lives at /usr/sbin/dropbear.
- The package-owned host-key tool lives at /usr/bin/dropbearkey.
- The bootstrap SSH systemd unit now starts /usr/sbin/dropbear.

Installed package-owned payload:

- /usr/sbin/dropbear
- /usr/bin/dropbearkey
- /usr/share/onix/packages/dropbear.md

Security policy preserved from Phase 406:

- password login stays disabled
- root SSH login stays disabled
- public-key login for the bootstrap onix user stays enabled
- the machine host key stays under /etc/dropbear

Important limitation:

Phase 413 intentionally does not garbage-collect the older Nix Dropbear closure
yet. The active SSH service now points at dropbear, but old copied closure
files may still exist until the later no-Nix-payload audit.

The next phase should inspect remaining temporary system payload ownership and
continue moving machine-plane software into stones.
EOF
  chmod 0644 "$MNT/usr/share/onix/bootstrap/dropbear-stone.txt"
  printf 'proof    : /usr/share/onix/bootstrap/dropbear-stone.txt\n'
}

ensure_shells_has_sh() {
  local tmp_shells

  install -dm0755 "$MNT/usr/share/defaults/etc" "$MNT/etc"

  cat > "$MNT/usr/share/defaults/etc/shells" <<'EOF'
# ONIX Phase 403 shell policy.
#
# /bin/sh is a temporary BusyBox shell for the bootstrap serial console.
# /usr/sbin/nologin remains valid for deliberately non-interactive accounts.
/bin/sh
/usr/sbin/nologin
EOF
  chmod 0644 "$MNT/usr/share/defaults/etc/shells"

  if [[ ! -f "$MNT/etc/shells" ]]; then
    install -m0644 "$MNT/usr/share/defaults/etc/shells" "$MNT/etc/shells"
    printf 'created  : /etc/shells from Phase 403 shell default\n'
    return 0
  fi

  if grep -qx '/bin/sh' "$MNT/etc/shells"; then
    printf 'default  : /etc/shells already lists /bin/sh\n'
    return 0
  fi

  if grep -qx '/usr/sbin/nologin' "$MNT/etc/shells"; then
    tmp_shells="$(mktemp "${TMPDIR:-/tmp}/onix-shells.XXXXXX")"
    {
      printf '/bin/sh\n'
      cat "$MNT/etc/shells"
    } > "$tmp_shells"
    install -m0644 "$tmp_shells" "$MNT/etc/shells"
    rm -f "$tmp_shells"
    printf 'updated  : /etc/shells now includes /bin/sh\n'
    return 0
  fi

  printf 'override : /etc/shells exists without /bin/sh; preserved\n'
}

write_serial_shell_wrapper() {
  install -dm0755 "$MNT/usr/lib/onix"
  cat > "$MNT/usr/lib/onix/bootstrap-serial-shell" <<EOF
#!/bin/sh
export PATH=/bin:/usr/bin:/sbin:/usr/sbin
echo
echo "ONIX_BOOTSTRAP_SERIAL_CONSOLE_READY tty=/dev/$SERIAL_CONSOLE_TTY uid=\$(/bin/id -u) shell=/bin/sh"
echo "WARNING: Phase 403 bootstrap console is unauthenticated and temporary."
echo "Type commands here. This is not the final ONIX login design."
echo
exec /bin/sh -l
EOF
  chmod 0755 "$MNT/usr/lib/onix/bootstrap-serial-shell"
  printf 'wrapper  : /usr/lib/onix/bootstrap-serial-shell\n'
}

write_serial_console_unit_tree() {
  local unit_dir="$1"
  local unit="$unit_dir/onix-bootstrap-serial-shell.service"
  local wants="$unit_dir/multi-user.target.wants"

  [[ "$unit_dir" == "$MNT"/nix/store/*/example/systemd/system ||
     "$unit_dir" == "$MNT"/persist/nix/store/*/example/systemd/system ||
     "$unit_dir" == "$MNT"/usr/lib/systemd/system ]] \
    || die "refusing to write systemd unit outside active image unit tree: $unit_dir"

  install -dm0755 "$unit_dir" "$wants"

  cat > "$unit" <<EOF
[Unit]
Description=ONIX bootstrap serial root shell on $SERIAL_CONSOLE_TTY
Documentation=file:/usr/share/onix/bootstrap/serial-console.txt
After=systemd-user-sessions.service
Conflicts=serial-getty@$SERIAL_CONSOLE_TTY.service getty@$SERIAL_CONSOLE_TTY.service
ConditionPathExists=/dev/$SERIAL_CONSOLE_TTY

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/root
Environment=HOME=/root
Environment=TERM=vt220
Environment=PATH=/bin:/usr/bin:/sbin:/usr/sbin
ExecStart=$SERIAL_CONSOLE_PAYLOAD_OUT/bin/busybox sh /usr/lib/onix/bootstrap-serial-shell
StandardInput=tty-force
StandardOutput=tty
StandardError=tty
TTYPath=/dev/$SERIAL_CONSOLE_TTY
TTYReset=yes
TTYVHangup=no
TTYVTDisallocate=no
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "$unit"

  rm -f "$wants/onix-bootstrap-serial-shell@ttyS0.service"
  rm -f "$wants/onix-bootstrap-serial-shell.service"
  ln -s ../onix-bootstrap-serial-shell.service \
    "$wants/onix-bootstrap-serial-shell.service"

  printf 'unit     : %s\n' "${unit#$MNT}"
  printf 'enable   : %s\n' "${wants#$MNT}/onix-bootstrap-serial-shell.service"
}

write_serial_console_unit() {
  local root_unit_dir
  local persist_unit_dir
  local mask_tty

  root_unit_dir="$(active_systemd_root_unit_dir)"
  persist_unit_dir="$(active_systemd_persist_unit_dir_if_present)"

  write_serial_console_unit_tree "$root_unit_dir"
  if [[ -n "$persist_unit_dir" ]]; then
    write_serial_console_unit_tree "$persist_unit_dir"
  fi

  install -dm0755 "$MNT/etc/systemd/system"
  for mask_tty in ttyS0 "$SERIAL_CONSOLE_TTY"; do
    ln -sfn /dev/null "$MNT/etc/systemd/system/serial-getty@$mask_tty.service"
    printf 'mask     : /etc/systemd/system/serial-getty@%s.service -> /dev/null\n' "$mask_tty"
  done
  rm -f "$MNT/etc/systemd/system/getty.target.wants/onix-bootstrap-serial-shell@ttyS0.service"
  rm -f "$MNT/etc/systemd/system/getty.target.wants/onix-bootstrap-serial-shell@ttyS1.service"
  rm -f "$MNT/etc/systemd/system/multi-user.target.wants/onix-bootstrap-serial-shell@ttyS0.service"
  rm -f "$MNT/etc/systemd/system/multi-user.target.wants/onix-bootstrap-serial-shell@ttyS1.service"
  rm -f "$MNT/etc/systemd/system/multi-user.target.wants/onix-bootstrap-serial-shell.service"
}

write_serial_console_proof() {
  install -dm0755 "$MNT/usr/share/onix/bootstrap"
  cat > "$MNT/usr/share/onix/bootstrap/serial-console.txt" <<EOF
ONIX Phase 403 bootstrap serial console

Policy:

- This is a temporary bootstrap root console for learning and early bring-up.
- It is not the final authenticated ONIX login design.
- The normal root account still uses /usr/sbin/nologin in /etc/passwd.
- /bin/sh is provided by musl BusyBox from the pinned nixpkgs closure.
- ttyS0 remains the boot log / kernel console in the QEMU probe; its default
  serial getty is masked during this bootstrap proof to keep the log readable.
- serial-getty@$SERIAL_CONSOLE_TTY.service is masked for now so $SERIAL_CONSOLE_TTY has exactly one owner.
- onix-bootstrap-serial-shell.service owns /dev/$SERIAL_CONSOLE_TTY.

Proof marker:

ONIX_BOOTSTRAP_SERIAL_CONSOLE_READY

The Phase 403 probe waits for that marker, sends a command over the serial
line, and expects to see UID 0 command output.

BusyBox payload:

$SERIAL_CONSOLE_PAYLOAD_OUT

This remains bootstrap glue. Later ONIX should replace it with stones that own
the shell, getty/login stack, and authentication policy.
EOF
  chmod 0644 "$MNT/usr/share/onix/bootstrap/serial-console.txt"
  printf 'proof    : /usr/share/onix/bootstrap/serial-console.txt\n'
}

write_bootstrap_network_scripts() {
  install -dm0755 "$MNT/usr/lib/onix"

  cat > "$MNT/usr/lib/onix/bootstrap-network-up" <<'EOF'
#!/bin/sh
set -eu

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

find_iface() {
  for path in /sys/class/net/*; do
    iface="${path##*/}"
    [ "$iface" = "lo" ] && continue
    [ -e "$path" ] || continue
    printf '%s\n' "$iface"
    return 0
  done
  return 1
}

iface="${ONIX_BOOTSTRAP_NET_IFACE:-}"
if [ -z "$iface" ]; then
  i=0
  while [ "$i" -lt 30 ]; do
    iface="$(find_iface 2>/dev/null || true)"
    [ -n "$iface" ] && break
    i=$((i + 1))
    sleep 1
  done
  if [ -z "$iface" ]; then
    echo "ONIX_NETWORK_ERROR no-non-loopback-interface"
    exit 1
  fi
fi

ip="${ONIX_BOOTSTRAP_NET_IP:-10.0.2.15}"
netmask="${ONIX_BOOTSTRAP_NET_NETMASK:-255.255.255.0}"
router="${ONIX_BOOTSTRAP_NET_ROUTER:-10.0.2.2}"
dns="${ONIX_BOOTSTRAP_NET_DNS:-10.0.2.3}"

mkdir -p /run/onix

/bin/ifconfig lo 127.0.0.1 up || true
/bin/ifconfig "$iface" "$ip" netmask "$netmask" up
/bin/route del default 2>/dev/null || true
/bin/route add default gw "$router" dev "$iface"
rm -f /run/onix/network.env

if [ -n "$dns" ]; then
  : > /run/onix/resolv.conf
  for server in $dns; do
    echo "nameserver $server" >> /run/onix/resolv.conf
  done
fi

{
  echo "method=static-qemu-user"
  echo "interface=$iface"
  echo "ip=$ip"
  echo "subnet=$netmask"
  echo "router=$router"
  echo "dns=$dns"
} > /run/onix/network.env

if [ -s /run/onix/network.env ]; then
  # shellcheck source=/dev/null
  . /run/onix/network.env
  echo "ONIX_BOOTSTRAP_NETWORK_READY iface=$interface ip=$ip router=${router:-none}"
  exit 0
fi

echo "ONIX_NETWORK_ERROR no-runtime-network-state"
exit 1
EOF
  chmod 0755 "$MNT/usr/lib/onix/bootstrap-network-up"

  cat > "$MNT/usr/lib/onix/bootstrap-network-status" <<'EOF'
#!/bin/sh
set -eu

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

if [ ! -s /run/onix/network.env ]; then
  echo "ONIX_NETWORK_WAIT no-/run/onix/network.env"
  exit 1
fi

# shellcheck source=/dev/null
. /run/onix/network.env

if [ -z "${interface:-}" ] || [ -z "${ip:-}" ] || [ -z "${router:-}" ]; then
  echo "ONIX_NETWORK_WAIT incomplete-network.env"
  exit 1
fi

if ! /bin/ifconfig "$interface" | /bin/grep -F "$ip" >/dev/null 2>&1; then
  echo "ONIX_NETWORK_WAIT address-not-visible iface=$interface ip=$ip"
  exit 1
fi

if ! /bin/route -n | /bin/awk -v gw="$router" '$1 == "0.0.0.0" && $2 == gw { found=1 } END { exit found ? 0 : 1 }'; then
  echo "ONIX_NETWORK_WAIT default-route-missing router=$router"
  exit 1
fi

echo "ONIX_NETWORK_OK iface=$interface ip=$ip router=$router"
EOF
  chmod 0755 "$MNT/usr/lib/onix/bootstrap-network-status"

  cat > "$MNT/usr/lib/onix/bootstrap-network-proof" <<'EOF'
#!/bin/sh
set -eu

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

i=0
while [ "$i" -lt 25 ]; do
  i=$((i + 1))
  if /usr/lib/onix/bootstrap-network-status; then
    exit 0
  fi
  sleep 1
done

echo "ONIX_NETWORK_ERROR status-timeout"
/bin/ifconfig -a || true
/bin/route -n || true
exit 1
EOF
  chmod 0755 "$MNT/usr/lib/onix/bootstrap-network-proof"

  printf 'network  : /usr/lib/onix/bootstrap-network-up\n'
  printf 'network  : /usr/lib/onix/bootstrap-network-status\n'
  printf 'network  : /usr/lib/onix/bootstrap-network-proof\n'
}

write_bootstrap_network_unit_tree() {
  local unit_dir="$1"
  local unit="$unit_dir/onix-bootstrap-network.service"
  local wants="$unit_dir/multi-user.target.wants"

  [[ "$unit_dir" == "$MNT"/nix/store/*/example/systemd/system ||
     "$unit_dir" == "$MNT"/persist/nix/store/*/example/systemd/system ||
     "$unit_dir" == "$MNT"/usr/lib/systemd/system ]] \
    || die "refusing to write systemd unit outside active image unit tree: $unit_dir"

  install -dm0755 "$unit_dir" "$wants"

  cat > "$unit" <<'EOF'
[Unit]
Description=ONIX bootstrap QEMU user networking
Documentation=file:/usr/share/onix/bootstrap/networking.txt
After=systemd-udevd.service systemd-modules-load.service
Before=network.target
Wants=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh /usr/lib/onix/bootstrap-network-up
StandardOutput=journal+console
StandardError=journal+console
TimeoutStartSec=45

[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "$unit"

  rm -f "$wants/onix-bootstrap-network.service"
  ln -s ../onix-bootstrap-network.service "$wants/onix-bootstrap-network.service"

  printf 'unit     : %s\n' "${unit#$MNT}"
  printf 'enable   : %s\n' "${wants#$MNT}/onix-bootstrap-network.service"
}

write_bootstrap_network_unit() {
  local root_unit_dir
  local persist_unit_dir

  root_unit_dir="$(active_systemd_root_unit_dir)"
  persist_unit_dir="$(active_systemd_persist_unit_dir_if_present)"

  write_bootstrap_network_unit_tree "$root_unit_dir"
  if [[ -n "$persist_unit_dir" ]]; then
    write_bootstrap_network_unit_tree "$persist_unit_dir"
  fi
}

write_bootstrap_network_proof() {
  install -dm0755 "$MNT/usr/share/onix/bootstrap"
  cat > "$MNT/usr/share/onix/bootstrap/networking.txt" <<'EOF'
ONIX Phase 404 bootstrap networking

Policy:

- This is the first minimal networking proof for the booted ONIX image.
- It is intentionally small and QEMU-focused.
- QEMU user-mode networking has a deterministic guest contract.
- The guest uses 10.0.2.15 on its virtio NIC.
- The default route points at QEMU's gateway, 10.0.2.2.
- BusyBox provides the temporary interface and route commands.
- The bootstrap network service writes runtime state to /run/onix/network.env.
- /run state is runtime-only and disappears at reboot.
- DHCP is deliberately not used in this phase. BusyBox udhcpc needs Linux
  packet socket support, and the borrowed Phase 2 kernel-module subset does not
  currently include that module. Expanding module ownership belongs in Phase 3.

Important limitation:

This is not the final ONIX network stack. Later ONIX should decide whether the
real base uses systemd-networkd, another DHCP client, NetworkManager, or a
smaller native ONIX service.

Proof marker:

ONIX_NETWORK_OK iface=<name> ip=10.0.2.15 router=10.0.2.2
EOF
  chmod 0644 "$MNT/usr/share/onix/bootstrap/networking.txt"
  printf 'proof    : /usr/share/onix/bootstrap/networking.txt\n'
}

write_remote_inspection_scripts() {
  install -dm0755 "$MNT/usr/lib/onix"

  cat > "$MNT/usr/lib/onix/bootstrap-remote-inspection-response" <<'EOF'
#!/bin/sh
set -eu

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

echo "ONIX_REMOTE_INSPECTION_OK name=ONIX phase=405 uid=$(/bin/id -u) hostname=$(hostname) kernel=$(uname -s)"
EOF
  chmod 0755 "$MNT/usr/lib/onix/bootstrap-remote-inspection-response"

  cat > "$MNT/usr/lib/onix/bootstrap-remote-inspection-status" <<'EOF'
#!/bin/sh
set -eu

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

port="${ONIX_REMOTE_INSPECTION_GUEST_PORT:-6649}"

if /bin/netstat -ltn 2>/dev/null | /bin/grep -E "[.:]${port}[[:space:]]" >/dev/null 2>&1; then
  echo "ONIX_REMOTE_INSPECTION_READY port=$port"
  exit 0
fi

echo "ONIX_REMOTE_INSPECTION_WAIT port=$port"
exit 1
EOF
  chmod 0755 "$MNT/usr/lib/onix/bootstrap-remote-inspection-status"

  cat > "$MNT/usr/lib/onix/bootstrap-remote-inspection-proof" <<'EOF'
#!/bin/sh
set -eu

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

i=0
while [ "$i" -lt 25 ]; do
  i=$((i + 1))
  if /usr/lib/onix/bootstrap-remote-inspection-status; then
    exit 0
  fi
  sleep 1
done

echo "ONIX_REMOTE_INSPECTION_ERROR status-timeout"
/bin/netstat -ltn || true
exit 1
EOF
  chmod 0755 "$MNT/usr/lib/onix/bootstrap-remote-inspection-proof"

  printf 'remote   : /usr/lib/onix/bootstrap-remote-inspection-response\n'
  printf 'remote   : /usr/lib/onix/bootstrap-remote-inspection-status\n'
  printf 'remote   : /usr/lib/onix/bootstrap-remote-inspection-proof\n'
}

write_remote_inspection_unit_tree() {
  local unit_dir="$1"
  local unit="$unit_dir/onix-bootstrap-remote-inspection.service"
  local wants="$unit_dir/multi-user.target.wants"

  [[ "$unit_dir" == "$MNT"/nix/store/*/example/systemd/system ||
     "$unit_dir" == "$MNT"/persist/nix/store/*/example/systemd/system ||
     "$unit_dir" == "$MNT"/usr/lib/systemd/system ]] \
    || die "refusing to write systemd unit outside active image unit tree: $unit_dir"

  install -dm0755 "$unit_dir" "$wants"

  cat > "$unit" <<'EOF'
[Unit]
Description=ONIX bootstrap TCP inspection listener
Documentation=file:/usr/share/onix/bootstrap/remote-inspection.txt
After=onix-bootstrap-network.service
Requires=onix-bootstrap-network.service

[Service]
Type=simple
Environment=ONIX_REMOTE_INSPECTION_GUEST_PORT=6649
ExecStart=/bin/nc -lk -p 6649 -e /usr/lib/onix/bootstrap-remote-inspection-response
Restart=always
RestartSec=1
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "$unit"

  rm -f "$wants/onix-bootstrap-remote-inspection.service"
  ln -s ../onix-bootstrap-remote-inspection.service \
    "$wants/onix-bootstrap-remote-inspection.service"

  printf 'unit     : %s\n' "${unit#$MNT}"
  printf 'enable   : %s\n' "${wants#$MNT}/onix-bootstrap-remote-inspection.service"
}

write_remote_inspection_unit() {
  local root_unit_dir
  local persist_unit_dir

  root_unit_dir="$(active_systemd_root_unit_dir)"
  persist_unit_dir="$(active_systemd_persist_unit_dir_if_present)"

  write_remote_inspection_unit_tree "$root_unit_dir"
  if [[ -n "$persist_unit_dir" ]]; then
    write_remote_inspection_unit_tree "$persist_unit_dir"
  fi
}

write_remote_inspection_proof() {
  install -dm0755 "$MNT/usr/share/onix/bootstrap"
  cat > "$MNT/usr/share/onix/bootstrap/remote-inspection.txt" <<'EOF'
ONIX Phase 405 bootstrap remote inspection

Policy:

- This is the first host-to-guest remote inspection proof.
- It is not SSH and it is not the final authenticated remote access design.
- QEMU forwards host 127.0.0.1:7665 to guest TCP port 6649.
- BusyBox nc listens on guest TCP port 6649.
- Each connection runs /usr/lib/onix/bootstrap-remote-inspection-response.

Proof marker:

ONIX_REMOTE_INSPECTION_OK name=ONIX phase=405

Important limitation:

This listener is unauthenticated and temporary. It exists only to prove that the
host can reach a process inside the booted ONIX image over QEMU networking.
Later ONIX should replace it with real SSH or another authenticated remote
inspection path with explicit key and account policy.
EOF
  chmod 0644 "$MNT/usr/share/onix/bootstrap/remote-inspection.txt"
  printf 'proof    : /usr/share/onix/bootstrap/remote-inspection.txt\n'
}

write_ssh_account_policy() {
  install -dm0755 "$MNT/usr/lib/sysusers.d"
  cat > "$MNT/usr/lib/sysusers.d/onix-ssh.conf" <<EOF
# ONIX Phase 406 bootstrap SSH account policy.
#
# This is temporary bootstrap policy, not the final user model.
u $SSH_USER $SSH_UID:$SSH_GID "ONIX Bootstrap SSH User" /home/$SSH_USER /bin/sh
EOF
  chmod 0644 "$MNT/usr/lib/sysusers.d/onix-ssh.conf"
  printf 'policy   : /usr/lib/sysusers.d/onix-ssh.conf\n'

  need_cmd systemd-sysusers
  systemd-sysusers --root="$MNT" "$MNT/usr/lib/sysusers.d/onix-ssh.conf"
  printf 'sysusers : materialized bootstrap SSH user %s uid=%s gid=%s\n' "$SSH_USER" "$SSH_UID" "$SSH_GID"
}

install_ssh_authorized_key() {
  local home="$MNT/persist/home/$SSH_USER"
  local ssh_dir="$home/.ssh"

  [[ -s "$SSH_CLIENT_PUB" ]] || die "missing SSH client public key: $SSH_CLIENT_PUB"

  install -dm0750 "$home"
  install -dm0700 "$ssh_dir"
  install -m0600 "$SSH_CLIENT_PUB" "$ssh_dir/authorized_keys"
  chown -R "$SSH_UID:$SSH_GID" "$home"

  printf 'ssh-auth : /persist/home/%s/.ssh/authorized_keys from %s\n' \
    "$SSH_USER" "${SSH_CLIENT_PUB#$ONIX_ROOT/}"
}

generate_dropbear_host_key() {
  local key="$MNT/etc/dropbear/dropbear_ed25519_host_key"

  load_dropbear_payload_metadata
  install -dm0700 "$MNT/etc/dropbear"

  if [[ ! -s "$key" ]]; then
    "$DROPBEAR_PAYLOAD_OUT/bin/dropbearkey" -t ed25519 -f "$key" >/dev/null
    chmod 0600 "$key"
    printf 'ssh-host : /etc/dropbear/dropbear_ed25519_host_key generated\n'
    return 0
  fi

  chmod 0600 "$key"
  printf 'ssh-host : /etc/dropbear/dropbear_ed25519_host_key preserved\n'
}

write_dropbear_status_scripts() {
  install -dm0755 "$MNT/usr/lib/onix"

  cat > "$MNT/usr/lib/onix/bootstrap-ssh-status" <<EOF
#!/bin/sh
set -eu

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

port="\${ONIX_SSH_GUEST_PORT:-22}"
user="\${ONIX_SSH_USER:-$SSH_USER}"

if /bin/netstat -ltn 2>/dev/null | /bin/grep -E "[.:]\${port}[[:space:]]" >/dev/null 2>&1; then
  echo "ONIX_SSH_READY user=\$user port=\$port"
  exit 0
fi

echo "ONIX_SSH_WAIT user=\$user port=\$port"
exit 1
EOF
  chmod 0755 "$MNT/usr/lib/onix/bootstrap-ssh-status"

  cat > "$MNT/usr/lib/onix/bootstrap-ssh-proof" <<'EOF'
#!/bin/sh
set -eu

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

i=0
while [ "$i" -lt 25 ]; do
  i=$((i + 1))
  if /usr/lib/onix/bootstrap-ssh-status; then
    exit 0
  fi
  sleep 1
done

echo "ONIX_SSH_ERROR status-timeout"
/bin/netstat -ltn || true
exit 1
EOF
  chmod 0755 "$MNT/usr/lib/onix/bootstrap-ssh-proof"

  printf 'ssh      : /usr/lib/onix/bootstrap-ssh-status\n'
  printf 'ssh      : /usr/lib/onix/bootstrap-ssh-proof\n'
}

write_dropbear_unit_tree() {
  local unit_dir="$1"
  local unit="$unit_dir/onix-bootstrap-dropbear.service"
  local wants="$unit_dir/multi-user.target.wants"

  [[ "$unit_dir" == "$MNT"/nix/store/*/example/systemd/system ||
     "$unit_dir" == "$MNT"/persist/nix/store/*/example/systemd/system ||
     "$unit_dir" == "$MNT"/usr/lib/systemd/system ]] \
    || die "refusing to write systemd unit outside active image unit tree: $unit_dir"

  install -dm0755 "$unit_dir" "$wants"

  cat > "$unit" <<EOF
[Unit]
Description=ONIX bootstrap Dropbear SSH server
Documentation=file:/usr/share/onix/bootstrap/ssh.txt
After=onix-bootstrap-network.service
Requires=onix-bootstrap-network.service

[Service]
Type=simple
Environment=ONIX_SSH_USER=$SSH_USER
Environment=PATH=/bin:/usr/bin:/sbin:/usr/sbin
ExecStart=$DROPBEAR_PAYLOAD_OUT/bin/dropbear -F -E -e -m -s -w -j -k -p 0.0.0.0:22 -r /etc/dropbear/dropbear_ed25519_host_key -P /run/dropbear.pid
Restart=always
RestartSec=1
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "$unit"

  rm -f "$wants/onix-bootstrap-dropbear.service"
  ln -s ../onix-bootstrap-dropbear.service "$wants/onix-bootstrap-dropbear.service"

  printf 'unit     : %s\n' "${unit#$MNT}"
  printf 'enable   : %s\n' "${wants#$MNT}/onix-bootstrap-dropbear.service"
}

write_dropbear_unit() {
  local root_unit_dir
  local persist_unit_dir

  load_dropbear_payload_metadata

  root_unit_dir="$(active_systemd_root_unit_dir)"
  persist_unit_dir="$(active_systemd_persist_unit_dir_if_present)"

  write_dropbear_unit_tree "$root_unit_dir"
  if [[ -n "$persist_unit_dir" ]]; then
    write_dropbear_unit_tree "$persist_unit_dir"
  fi
}

write_ssh_proof() {
  install -dm0755 "$MNT/usr/share/onix/bootstrap"
  cat > "$MNT/usr/share/onix/bootstrap/ssh.txt" <<EOF
ONIX Phase 406 bootstrap SSH

Policy:

- This is the first authenticated remote access proof.
- Dropbear provides a small musl SSH server for bootstrap.
- The SSH account is $SSH_USER uid=$SSH_UID gid=$SSH_GID.
- Root SSH login is disabled.
- Password authentication is disabled.
- The proof uses public-key authentication only.
- The authorized key is installed in /persist/home/$SSH_USER/.ssh/authorized_keys.
- QEMU forwards host 127.0.0.1:7626 to guest TCP port 22.

Proof marker:

ONIX_SSH_OK user=$SSH_USER uid=$SSH_UID

Important limitation:

This is still bootstrap policy. Later ONIX should decide the final remote access
stack, host key lifecycle, user creation flow, authorized-key provisioning, and
whether OpenSSH replaces Dropbear.
EOF
  chmod 0644 "$MNT/usr/share/onix/bootstrap/ssh.txt"
  printf 'proof    : /usr/share/onix/bootstrap/ssh.txt\n'
}

verify_materialization() {
  log "verifying Phase 401 live /etc materialization"

  test -f "$MNT/usr/lib/os-release"
  grep -q '^NAME="ONIX"$' "$MNT/usr/lib/os-release"
  grep -q '^ID="onix"$' "$MNT/usr/lib/os-release"

  test -L "$MNT/etc/os-release"
  test "$(readlink "$MNT/etc/os-release")" = "../usr/lib/os-release"

  test -f "$MNT/usr/share/defaults/etc/issue"
  test -f "$MNT/usr/share/defaults/etc/motd"
  test -f "$MNT/usr/share/defaults/etc/fstab"
  test -f "$MNT/usr/share/defaults/etc/profile"
  test -f "$MNT/usr/share/defaults/etc/profile.d/onix-path.sh"
  test -f "$MNT/usr/share/defaults/etc/profile.d/onix-login.sh"

  test -f "$MNT/etc/issue"
  test -f "$MNT/etc/motd"
  test -f "$MNT/etc/fstab"
  test -f "$MNT/etc/profile"
  test -f "$MNT/etc/profile.d/onix-path.sh"
  test -f "$MNT/etc/profile.d/onix-login.sh"
  test -f "$MNT/etc/hostname"
  test -f "$MNT/etc/machine-id"

  grep -q 'LABEL=ONIX-ESP' "$MNT/etc/fstab"
  grep -q 'LABEL=ONIX-BOOT' "$MNT/etc/fstab"
  grep -q 'LABEL=onix-root' "$MNT/etc/fstab"
  grep -q 'LABEL=ONIX-PERSIST' "$MNT/etc/fstab"
  grep -q 'Welcome to ONIX' "$MNT/etc/motd"
  grep -q 'moss controls the machine' "$MNT/etc/motd"
  grep -q '▓' "$MNT/etc/motd"
  grep -q '▒' "$MNT/etc/motd"
  test "$(wc -c < "$MNT/etc/motd")" -lt 2048
  grep -q '/etc/profile.d' "$MNT/etc/profile"
  grep -q 'export PATH' "$MNT/etc/profile.d/onix-path.sh"
  grep -q "alias ll='ls -laF'" "$MNT/etc/profile.d/onix-path.sh"
  grep -q 'logo.ansi' "$MNT/etc/profile.d/onix-login.sh"
  grep -q 'live /etc materialization' "$MNT/usr/share/onix/bootstrap/etc-materialization.txt"
}

verify_account_policy() {
  local nologin_target

  log "verifying Phase 402 account policy"

  test -f "$MNT/usr/lib/sysusers.d/onix-base.conf"
  grep -q '^u root[[:space:]]*0:0' "$MNT/usr/lib/sysusers.d/onix-base.conf"
  grep -q '^u nobody[[:space:]]*65534:65534' "$MNT/usr/lib/sysusers.d/onix-base.conf"

  test -L "$MNT/usr/sbin/nologin"
  nologin_target="$(readlink "$MNT/usr/sbin/nologin")"
  [[ "$nologin_target" == /nix/store/*/bin/nologin ]] \
    || die "/usr/sbin/nologin target is not a Nix store nologin"
  test -x "$MNT$nologin_target"

  test -f "$MNT/usr/share/defaults/etc/nsswitch.conf"
  test -f "$MNT/usr/share/defaults/etc/shells"
  test -f "$MNT/etc/nsswitch.conf"
  test -f "$MNT/etc/shells"
  test -f "$MNT/etc/passwd"
  test -f "$MNT/etc/group"
  test -f "$MNT/etc/shadow"
  test -f "$MNT/etc/gshadow"
  test -d "$MNT/root"
  test -d "$MNT/var/empty"

  grep -q '^passwd:[[:space:]]*files' "$MNT/etc/nsswitch.conf"
  grep -q '^group:[[:space:]]*files' "$MNT/etc/nsswitch.conf"
  grep -q '^shadow:[[:space:]]*files' "$MNT/etc/nsswitch.conf"
  grep -qx '/usr/sbin/nologin' "$MNT/etc/shells"

  grep -q '^root:x:0:0:' "$MNT/etc/passwd"
  grep -q '^nobody:x:65534:65534:' "$MNT/etc/passwd"
  grep -q '^root:x:0:' "$MNT/etc/group"
  grep -q '^shadow:x:42:' "$MNT/etc/group"
  grep -q '^wheel:x:10:' "$MNT/etc/group"
  grep -q '^nogroup:x:65534:' "$MNT/etc/group"
  grep -q '^root:' "$MNT/etc/shadow"
  grep -q '^nobody:' "$MNT/etc/shadow"
  grep -q 'base account policy' "$MNT/usr/share/onix/bootstrap/account-policy.txt"
}

verify_serial_console() {
  local root_unit_dir
  local root_unit
  local root_wants

  log "verifying Phase 403 bootstrap serial console"

  load_serial_console_payload_metadata
  root_unit_dir="$(active_systemd_root_unit_dir)"
  root_unit="$root_unit_dir/onix-bootstrap-serial-shell.service"
  root_wants="$root_unit_dir/multi-user.target.wants/onix-bootstrap-serial-shell.service"

  [[ -x "$MNT$SERIAL_CONSOLE_PAYLOAD_OUT/bin/busybox" ]] \
    || die "BusyBox executable missing inside image: $SERIAL_CONSOLE_PAYLOAD_OUT/bin/busybox"
  [[ -x "$MNT/persist$SERIAL_CONSOLE_PAYLOAD_OUT/bin/busybox" ]] \
    || die "BusyBox executable missing inside ONIX-PERSIST: $SERIAL_CONSOLE_PAYLOAD_OUT/bin/busybox"
  [[ -L "$MNT/bin/busybox" ]] \
    || die "/bin/busybox is not a symlink"
  [[ "$(readlink "$MNT/bin/busybox")" == "$SERIAL_CONSOLE_PAYLOAD_OUT/bin/busybox" ]] \
    || die "/bin/busybox points to wrong target: $(readlink "$MNT/bin/busybox")"
  [[ -L "$MNT/bin/sh" ]] \
    || die "/bin/sh is not a symlink"
  [[ "$(readlink "$MNT/bin/sh")" == "busybox" ]] \
    || die "/bin/sh points to wrong target: $(readlink "$MNT/bin/sh")"
  [[ -L "$MNT/bin/getty" ]] \
    || die "/bin/getty is not a symlink"
  [[ "$(readlink "$MNT/bin/getty")" == "busybox" ]] \
    || die "/bin/getty points to wrong target: $(readlink "$MNT/bin/getty")"
  [[ -x "$MNT/usr/lib/onix/bootstrap-serial-shell" ]] \
    || die "/usr/lib/onix/bootstrap-serial-shell is not executable"

  grep -q 'ONIX_BOOTSTRAP_SERIAL_CONSOLE_READY' "$MNT/usr/lib/onix/bootstrap-serial-shell" \
    || die "serial shell wrapper does not print the ready marker"
  grep -qx '/bin/sh' "$MNT/etc/shells" \
    || die "/etc/shells does not list /bin/sh"
  grep -qx '/usr/sbin/nologin' "$MNT/etc/shells" \
    || die "/etc/shells does not list /usr/sbin/nologin"
  grep -q '^root:x:0:0:.*:/usr/sbin/nologin$' "$MNT/etc/passwd" \
    || die "root account shell should remain /usr/sbin/nologin"

  [[ -f "$root_unit" ]] \
    || die "missing onix-bootstrap-serial-shell systemd unit in active systemd unit tree"
  grep -q "^ExecStart=$SERIAL_CONSOLE_PAYLOAD_OUT/bin/busybox sh /usr/lib/onix/bootstrap-serial-shell$" \
    "$root_unit" \
    || die "serial console unit ExecStart is wrong"
  grep -q "^TTYPath=/dev/$SERIAL_CONSOLE_TTY$" \
    "$root_unit" \
    || die "serial console unit TTYPath is wrong"
  grep -q '^TTYVHangup=no$' \
    "$root_unit" \
    || die "serial console unit should avoid host-side serial hangups"

  [[ -L "$MNT/etc/systemd/system/serial-getty@$SERIAL_CONSOLE_TTY.service" ]] \
    || die "serial-getty@$SERIAL_CONSOLE_TTY.service is not masked"
  [[ "$(readlink "$MNT/etc/systemd/system/serial-getty@$SERIAL_CONSOLE_TTY.service")" == "/dev/null" ]] \
    || die "serial-getty@$SERIAL_CONSOLE_TTY.service mask target is wrong"
  [[ -L "$MNT/etc/systemd/system/serial-getty@ttyS0.service" ]] \
    || die "serial-getty@ttyS0.service is not masked for the boot-log console"
  [[ "$(readlink "$MNT/etc/systemd/system/serial-getty@ttyS0.service")" == "/dev/null" ]] \
    || die "serial-getty@ttyS0.service mask target is wrong"
  [[ -L "$root_wants" ]] \
    || die "serial console service is not enabled in active multi-user.target.wants"
  [[ "$(readlink "$root_wants")" == "../onix-bootstrap-serial-shell.service" ]] \
    || die "serial console enable symlink target is wrong"

  grep -q 'ONIX_BOOTSTRAP_SERIAL_CONSOLE_READY' "$MNT/usr/share/onix/bootstrap/serial-console.txt" \
    || die "serial console proof file does not record the ready marker"
  grep -q 'unauthenticated and temporary' "$MNT/usr/lib/onix/bootstrap-serial-shell" \
    || die "serial shell wrapper does not warn about temporary unauthenticated access"
}

verify_bootstrap_network() {
  local root_unit_dir
  local persist_unit_dir
  local root_unit
  local root_wants
  local persist_unit

  log "verifying Phase 404 bootstrap networking"

  root_unit_dir="$(active_systemd_root_unit_dir)"
  persist_unit_dir="$(active_systemd_persist_unit_dir_if_present)"
  root_unit="$root_unit_dir/onix-bootstrap-network.service"
  root_wants="$root_unit_dir/multi-user.target.wants/onix-bootstrap-network.service"
  persist_unit="$persist_unit_dir/onix-bootstrap-network.service"

  for applet in ifconfig ip route ping nslookup nc netstat wget; do
    [[ -L "$MNT/bin/$applet" ]] \
      || die "/bin/$applet is not a symlink"
    [[ "$(readlink "$MNT/bin/$applet")" == "busybox" ]] \
      || die "/bin/$applet points to wrong target: $(readlink "$MNT/bin/$applet")"
  done

  [[ -x "$MNT/usr/lib/onix/bootstrap-network-up" ]] \
    || die "/usr/lib/onix/bootstrap-network-up is not executable"
  [[ -x "$MNT/usr/lib/onix/bootstrap-network-status" ]] \
    || die "/usr/lib/onix/bootstrap-network-status is not executable"
  [[ -x "$MNT/usr/lib/onix/bootstrap-network-proof" ]] \
    || die "/usr/lib/onix/bootstrap-network-proof is not executable"

  grep -q 'ONIX_BOOTSTRAP_NETWORK_READY' "$MNT/usr/lib/onix/bootstrap-network-up" \
    || die "network-up script does not print the ready marker"
  grep -q 'ONIX_NETWORK_OK' "$MNT/usr/lib/onix/bootstrap-network-status" \
    || die "network-status script does not print the proof marker"

  [[ -f "$root_unit" ]] \
    || die "missing onix-bootstrap-network systemd unit in active systemd unit tree"
  grep -q '^ExecStart=/bin/sh /usr/lib/onix/bootstrap-network-up$' "$root_unit" \
    || die "bootstrap network unit ExecStart is wrong"
  [[ -L "$root_wants" ]] \
    || die "bootstrap network service is not enabled in active multi-user.target.wants"
  [[ "$(readlink "$root_wants")" == "../onix-bootstrap-network.service" ]] \
    || die "bootstrap network enable symlink target is wrong"

  if [[ -n "$persist_unit_dir" ]]; then
    [[ -f "$persist_unit" ]] \
      || die "missing onix-bootstrap-network unit in ONIX-PERSIST systemd unit tree"
  fi

  grep -q 'ONIX_NETWORK_OK' "$MNT/usr/share/onix/bootstrap/networking.txt" \
    || die "networking proof file does not record the proof marker"
}

verify_remote_inspection() {
  local root_unit_dir
  local persist_unit_dir
  local root_unit
  local root_wants
  local persist_unit

  log "verifying Phase 405 bootstrap remote inspection"

  root_unit_dir="$(active_systemd_root_unit_dir)"
  persist_unit_dir="$(active_systemd_persist_unit_dir_if_present)"
  root_unit="$root_unit_dir/onix-bootstrap-remote-inspection.service"
  root_wants="$root_unit_dir/multi-user.target.wants/onix-bootstrap-remote-inspection.service"
  persist_unit="$persist_unit_dir/onix-bootstrap-remote-inspection.service"

  [[ -L "$MNT/bin/nc" ]] \
    || die "/bin/nc is not a symlink"
  [[ "$(readlink "$MNT/bin/nc")" == "busybox" ]] \
    || die "/bin/nc points to wrong target: $(readlink "$MNT/bin/nc")"
  [[ -L "$MNT/bin/netstat" ]] \
    || die "/bin/netstat is not a symlink"
  [[ "$(readlink "$MNT/bin/netstat")" == "busybox" ]] \
    || die "/bin/netstat points to wrong target: $(readlink "$MNT/bin/netstat")"

  [[ -x "$MNT/usr/lib/onix/bootstrap-remote-inspection-response" ]] \
    || die "/usr/lib/onix/bootstrap-remote-inspection-response is not executable"
  [[ -x "$MNT/usr/lib/onix/bootstrap-remote-inspection-status" ]] \
    || die "/usr/lib/onix/bootstrap-remote-inspection-status is not executable"
  [[ -x "$MNT/usr/lib/onix/bootstrap-remote-inspection-proof" ]] \
    || die "/usr/lib/onix/bootstrap-remote-inspection-proof is not executable"

  grep -q 'ONIX_REMOTE_INSPECTION_OK' "$MNT/usr/lib/onix/bootstrap-remote-inspection-response" \
    || die "remote inspection response script does not print proof marker"
  grep -q 'ONIX_REMOTE_INSPECTION_READY' "$MNT/usr/lib/onix/bootstrap-remote-inspection-status" \
    || die "remote inspection status script does not print ready marker"

  [[ -f "$root_unit" ]] \
    || die "missing onix-bootstrap-remote-inspection systemd unit in active systemd unit tree"
  grep -q '^ExecStart=/bin/nc -lk -p 6649 -e /usr/lib/onix/bootstrap-remote-inspection-response$' "$root_unit" \
    || die "remote inspection unit ExecStart is wrong"
  [[ -L "$root_wants" ]] \
    || die "remote inspection service is not enabled in active multi-user.target.wants"
  [[ "$(readlink "$root_wants")" == "../onix-bootstrap-remote-inspection.service" ]] \
    || die "remote inspection enable symlink target is wrong"

  if [[ -n "$persist_unit_dir" ]]; then
    [[ -f "$persist_unit" ]] \
      || die "missing remote inspection unit in ONIX-PERSIST systemd unit tree"
  fi

  grep -q 'ONIX_REMOTE_INSPECTION_OK' "$MNT/usr/share/onix/bootstrap/remote-inspection.txt" \
    || die "remote inspection proof file does not record the proof marker"
  grep -q 'unauthenticated and temporary' "$MNT/usr/share/onix/bootstrap/remote-inspection.txt" \
    || die "remote inspection proof file does not record the security limitation"
}

verify_ssh_access() {
  local root_unit_dir
  local persist_unit_dir
  local root_unit
  local root_wants
  local persist_unit

  log "verifying Phase 406 bootstrap SSH"

  load_dropbear_payload_metadata
  root_unit_dir="$(active_systemd_root_unit_dir)"
  persist_unit_dir="$(active_systemd_persist_unit_dir_if_present)"
  root_unit="$root_unit_dir/onix-bootstrap-dropbear.service"
  root_wants="$root_unit_dir/multi-user.target.wants/onix-bootstrap-dropbear.service"
  persist_unit="$persist_unit_dir/onix-bootstrap-dropbear.service"

  [[ -x "$MNT$DROPBEAR_PAYLOAD_OUT/bin/dropbear" ]] \
    || die "Dropbear executable missing inside image: $DROPBEAR_PAYLOAD_OUT/bin/dropbear"
  [[ -x "$MNT/persist$DROPBEAR_PAYLOAD_OUT/bin/dropbear" ]] \
    || die "Dropbear executable missing inside ONIX-PERSIST: $DROPBEAR_PAYLOAD_OUT/bin/dropbear"
  [[ -x "$MNT$DROPBEAR_PAYLOAD_OUT/bin/dropbearkey" ]] \
    || die "Dropbear key tool missing inside image: $DROPBEAR_PAYLOAD_OUT/bin/dropbearkey"

  grep -q "^$SSH_USER:x:$SSH_UID:$SSH_GID:" "$MNT/etc/passwd" \
    || die "missing bootstrap SSH user in /etc/passwd"
  grep -q "^$SSH_USER:" "$MNT/etc/shadow" \
    || die "missing bootstrap SSH user in /etc/shadow"
  grep -qx '/bin/sh' "$MNT/etc/shells" \
    || die "/etc/shells does not list /bin/sh"

  [[ -f "$MNT/persist/home/$SSH_USER/.ssh/authorized_keys" ]] \
    || die "missing /persist/home/$SSH_USER/.ssh/authorized_keys"
  grep -q 'ssh-ed25519' "$MNT/persist/home/$SSH_USER/.ssh/authorized_keys" \
    || die "authorized_keys does not contain an ed25519 key"
  [[ -s "$MNT/etc/dropbear/dropbear_ed25519_host_key" ]] \
    || die "missing Dropbear ed25519 host key"

  [[ -x "$MNT/usr/lib/onix/bootstrap-ssh-status" ]] \
    || die "/usr/lib/onix/bootstrap-ssh-status is not executable"
  [[ -x "$MNT/usr/lib/onix/bootstrap-ssh-proof" ]] \
    || die "/usr/lib/onix/bootstrap-ssh-proof is not executable"
  grep -q 'ONIX_SSH_READY' "$MNT/usr/lib/onix/bootstrap-ssh-status" \
    || die "SSH status script does not print ready marker"

  [[ -f "$root_unit" ]] \
    || die "missing onix-bootstrap-dropbear systemd unit in active systemd unit tree"
  grep -q ' -s ' "$root_unit" \
    || die "Dropbear unit should disable password logins with -s"
  grep -q ' -w ' "$root_unit" \
    || die "Dropbear unit should disable root logins with -w"
  grep -q '^ExecStart=.*/bin/dropbear .* -p 0.0.0.0:22 ' "$root_unit" \
    || die "Dropbear unit ExecStart is wrong"
  [[ -L "$root_wants" ]] \
    || die "Dropbear service is not enabled in active multi-user.target.wants"
  [[ "$(readlink "$root_wants")" == "../onix-bootstrap-dropbear.service" ]] \
    || die "Dropbear enable symlink target is wrong"

  if [[ -n "$persist_unit_dir" ]]; then
    [[ -f "$persist_unit" ]] \
      || die "missing Dropbear unit in ONIX-PERSIST systemd unit tree"
  fi

  grep -q "ONIX_SSH_OK user=$SSH_USER uid=$SSH_UID" "$MNT/usr/share/onix/bootstrap/ssh.txt" \
    || die "SSH proof file does not record the proof marker"
  grep -q 'Password authentication is disabled' "$MNT/usr/share/onix/bootstrap/ssh.txt" \
    || die "SSH proof file does not record password-auth policy"
}

verify_busybox_stone_image() {
  local applet
  local bin_target
  local root_unit_dir
  local persist_unit_dir
  local root_unit
  local persist_unit

  log "verifying Phase 410 busybox image install"

  root_unit_dir="$(active_systemd_root_unit_dir)"
  persist_unit_dir="$(active_systemd_persist_unit_dir_if_present)"
  root_unit="$root_unit_dir/onix-bootstrap-serial-shell.service"
  persist_unit="$persist_unit_dir/onix-bootstrap-serial-shell.service"

  verify_busybox_stone_target "$MNT"

  if [[ -L "$MNT/bin" ]]; then
    bin_target="$(readlink "$MNT/bin")"
    case "$bin_target" in
      usr/bin|/usr/bin|../usr/bin) ;;
      *) die "/bin symlink target is unexpected: $bin_target" ;;
    esac
    [[ -x "$MNT/bin/busybox" ]] \
      || die "merged-/usr /bin/busybox does not resolve to an executable"
    while IFS= read -r applet; do
      [[ -n "$applet" ]] || continue
      [[ -e "$MNT/bin/$applet" ]] \
        || die "merged-/usr /bin/$applet does not resolve"
    done < <(bootstrap_busybox_applets)
  else
    [[ -L "$MNT/bin/busybox" ]] \
      || die "/bin/busybox is not a symlink"
    [[ "$(readlink "$MNT/bin/busybox")" == "../usr/bin/busybox" ]] \
      || die "/bin/busybox points to wrong target: $(readlink "$MNT/bin/busybox")"

    while IFS= read -r applet; do
      [[ -n "$applet" ]] || continue
      [[ -L "$MNT/bin/$applet" ]] \
        || die "/bin/$applet is not a symlink"
      [[ "$(readlink "$MNT/bin/$applet")" == "busybox" ]] \
        || die "/bin/$applet points to wrong target: $(readlink "$MNT/bin/$applet")"
    done < <(bootstrap_busybox_applets)
  fi

  [[ -f "$root_unit" ]] \
    || die "missing serial console unit in active systemd unit tree"
  grep -q '^ExecStart=/usr/bin/busybox sh /usr/lib/onix/bootstrap-serial-shell$' "$root_unit" \
    || die "serial console unit should now execute /usr/bin/busybox"
  if [[ -n "$persist_unit_dir" && -f "$persist_unit" ]]; then
    grep -q '^ExecStart=/usr/bin/busybox sh /usr/lib/onix/bootstrap-serial-shell$' "$persist_unit" \
      || die "persist serial console unit should now execute /usr/bin/busybox"
  fi

  grep -qx '/bin/sh' "$MNT/etc/shells" \
    || die "/etc/shells does not list /bin/sh"
  grep -q 'ONIX Phase 410 busybox image install' \
    "$MNT/usr/share/onix/bootstrap/busybox-stone.txt" \
    || die "BusyBox stone proof file is missing"
}

verify_dropbear_stone_image() {
  local root_unit_dir
  local persist_unit_dir
  local root_unit
  local root_wants
  local persist_unit

  log "verifying Phase 413 dropbear image install"

  root_unit_dir="$(active_systemd_root_unit_dir)"
  persist_unit_dir="$(active_systemd_persist_unit_dir_if_present)"
  root_unit="$root_unit_dir/onix-bootstrap-dropbear.service"
  root_wants="$root_unit_dir/multi-user.target.wants/onix-bootstrap-dropbear.service"
  persist_unit="$persist_unit_dir/onix-bootstrap-dropbear.service"

  verify_dropbear_stone_target "$MNT"

  grep -q "^$SSH_USER:x:$SSH_UID:$SSH_GID:" "$MNT/etc/passwd" \
    || die "missing bootstrap SSH user in /etc/passwd"
  grep -q "^$SSH_USER:" "$MNT/etc/shadow" \
    || die "missing bootstrap SSH user in /etc/shadow"
  grep -qx '/bin/sh' "$MNT/etc/shells" \
    || die "/etc/shells does not list /bin/sh"

  [[ -f "$MNT/persist/home/$SSH_USER/.ssh/authorized_keys" ]] \
    || die "missing /persist/home/$SSH_USER/.ssh/authorized_keys"
  grep -q 'ssh-ed25519' "$MNT/persist/home/$SSH_USER/.ssh/authorized_keys" \
    || die "authorized_keys does not contain an ed25519 key"
  [[ -s "$MNT/etc/dropbear/dropbear_ed25519_host_key" ]] \
    || die "missing Dropbear ed25519 host key"

  [[ -x "$MNT/usr/lib/onix/bootstrap-ssh-status" ]] \
    || die "/usr/lib/onix/bootstrap-ssh-status is not executable"
  [[ -x "$MNT/usr/lib/onix/bootstrap-ssh-proof" ]] \
    || die "/usr/lib/onix/bootstrap-ssh-proof is not executable"
  grep -q 'ONIX_SSH_READY' "$MNT/usr/lib/onix/bootstrap-ssh-status" \
    || die "SSH status script does not print ready marker"

  [[ -f "$root_unit" ]] \
    || die "missing onix-bootstrap-dropbear systemd unit in active systemd unit tree"
  grep -q ' -s ' "$root_unit" \
    || die "Dropbear unit should disable password logins with -s"
  grep -q ' -w ' "$root_unit" \
    || die "Dropbear unit should disable root logins with -w"
  grep -q '^ExecStart=/usr/sbin/dropbear -F -E -e -m -s -w -j -k -p 0.0.0.0:22 ' "$root_unit" \
    || die "Dropbear unit should now execute /usr/sbin/dropbear"
  [[ -L "$root_wants" ]] \
    || die "Dropbear service is not enabled in active multi-user.target.wants"
  [[ "$(readlink "$root_wants")" == "../onix-bootstrap-dropbear.service" ]] \
    || die "Dropbear enable symlink target is wrong"

  if [[ -n "$persist_unit_dir" && -f "$persist_unit" ]]; then
    grep -q '^ExecStart=/usr/sbin/dropbear -F -E -e -m -s -w -j -k -p 0.0.0.0:22 ' "$persist_unit" \
      || die "persist Dropbear unit should now execute /usr/sbin/dropbear"
  fi

  grep -q 'ONIX Phase 413 dropbear image install' \
    "$MNT/usr/share/onix/bootstrap/dropbear-stone.txt" \
    || die "Dropbear stone proof file is missing"
  grep -q 'dropbear' "$MNT/usr/share/onix/packages/dropbear.md" \
    || die "dropbear package note is missing or wrong"
}

verify_systemd_stone_target() {
  local target="$1"
  local interp

  [[ -n "$SYSTEMD_PAYLOAD_OUT" ]] \
    || die "systemd payload metadata was not loaded before verifying systemd"
  [[ -x "$target/usr/lib/onix/bootstrap$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd" ]] \
    || die "systemd target is missing packaged systemd binary: $target"
  [[ -f "$target/usr/lib/onix/bootstrap$SYSTEMD_PAYLOAD_OUT/example/systemd/system/multi-user.target" ]] \
    || die "systemd target is missing packaged system unit tree: $target"
  [[ -d "$target/usr/lib/onix/bootstrap/nix/store" ]] \
    || die "systemd target is missing bootstrap Nix store copy: $target"

  [[ -L "$target/usr/lib/systemd/systemd" ]] \
    || die "systemd target is missing /usr/lib/systemd/systemd symlink"
  [[ "$(readlink "$target/usr/lib/systemd/systemd")" == "$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd" ]] \
    || die "systemd /usr/lib/systemd/systemd symlink target is wrong"
  [[ "$(readlink "$target/usr/lib/systemd/system")" == "$SYSTEMD_PAYLOAD_OUT/example/systemd/system" ]] \
    || die "systemd /usr/lib/systemd/system symlink target is wrong"
  [[ "$(readlink "$target/usr/lib/systemd/user")" == "$SYSTEMD_PAYLOAD_OUT/example/systemd/user" ]] \
    || die "systemd /usr/lib/systemd/user symlink target is wrong"

  for bin in systemctl journalctl systemd-tmpfiles systemd-sysusers udevadm; do
    [[ -L "$target/usr/bin/$bin" ]] \
      || die "systemd target is missing /usr/bin/$bin symlink"
    [[ "$(readlink "$target/usr/bin/$bin")" == "$SYSTEMD_PAYLOAD_OUT/bin/$bin" ]] \
      || die "systemd /usr/bin/$bin symlink target is wrong"
  done

  [[ -f "$target/usr/share/onix/packages/systemd.md" ]] \
    || die "systemd install target is missing package note"
  [[ -f "$target/usr/share/onix/packages/systemd.closure" ]] \
    || die "systemd install target is missing closure note"
  [[ -f "$target/usr/share/onix/packages/systemd.links" ]] \
    || die "systemd install target is missing link note"
  grep -q "$SYSTEMD_PAYLOAD_OUT" "$target/usr/share/onix/packages/systemd.closure" \
    || die "systemd closure note does not record the systemd output"

  interp="$(readelf -l "$target/usr/lib/onix/bootstrap$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd" 2>/dev/null |
    sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p' |
    head -n1)"
  [[ "$interp" == /nix/store/*/lib/ld-musl-x86_64.so.1 ]] \
    || die "systemd systemd binary should use the musl loader path; interpreter=$interp"
}

install_systemd_stone_payload() {
  [[ -x "$HOST_MOSS" ]] \
    || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run make phase 202)"
  [[ -f "$IMAGE_REPO_DIR/stone.index" ]] \
    || die "missing ONIX image package repo index: ${IMAGE_REPO_DIR#$ONIX_ROOT/}/stone.index (run make phase 505)"

  need_cmd readelf
  need_cmd tar
  need_cmd file

  load_systemd_payload_metadata

  log "materializing systemd from the image package repo into a scratch target"
  if [[ -d "$SYSTEMD_MOSS_ROOT" || -d "$SYSTEMD_MOSS_CACHE" || -d "$SYSTEMD_INSTALL_TARGET" ]]; then
    chmod -R u+rwX "$SYSTEMD_MOSS_ROOT" "$SYSTEMD_MOSS_CACHE" "$SYSTEMD_INSTALL_TARGET" 2>/dev/null || true
  fi
  rm -rf "$SYSTEMD_MOSS_ROOT" "$SYSTEMD_MOSS_CACHE" "$SYSTEMD_INSTALL_TARGET"
  install -dm0755 "$SYSTEMD_MOSS_ROOT" "$SYSTEMD_MOSS_CACHE" "$SYSTEMD_INSTALL_TARGET"

  "$HOST_MOSS" -D "$SYSTEMD_MOSS_ROOT" --cache "$SYSTEMD_MOSS_CACHE" \
    repo add onix-image "file://$IMAGE_REPO_DIR/stone.index" \
    -c "ONIX image package repo" >/dev/null
  "$HOST_MOSS" -D "$SYSTEMD_MOSS_ROOT" --cache "$SYSTEMD_MOSS_CACHE" \
    repo update >/dev/null
  "$HOST_MOSS" -D "$SYSTEMD_MOSS_ROOT" --cache "$SYSTEMD_MOSS_CACHE" \
    -y install --to "$SYSTEMD_INSTALL_TARGET" systemd

  verify_systemd_stone_target "$SYSTEMD_INSTALL_TARGET"

  log "copying systemd package payload into the ONIX image"
  install -dm0755 "$MNT/usr" "$MNT/usr/share/onix/packages"
  tar --numeric-owner -C "$SYSTEMD_INSTALL_TARGET" -cpf - \
    usr/bin \
    usr/lib/onix/bootstrap \
    usr/lib/systemd \
    usr/share/onix/packages/systemd.md \
    usr/share/onix/packages/systemd.closure \
    usr/share/onix/packages/systemd.links \
    | tar --numeric-owner -C "$MNT" -xpf -

  verify_systemd_stone_target "$MNT"
  printf 'stone    : systemd installed under /usr/lib/systemd + /usr/bin\n'
}

materialize_systemd_bootstrap_store_into() {
  local dest="$1"
  local label="$2"
  local src="$MNT/usr/lib/onix/bootstrap/nix/store"

  [[ -d "$src" ]] \
    || die "missing package-owned systemd bootstrap store: /usr/lib/onix/bootstrap/nix/store"

  install -dm0755 "$dest/nix/store"
  tar --numeric-owner -C "$src" -cpf - . |
    tar --numeric-owner -C "$dest/nix/store" -xpf -
  find "$dest/nix/store" -type d -exec chmod 0755 {} +

  [[ -x "$dest$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd" ]] \
    || die "systemd binary did not materialize into $label$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd"
  [[ -f "$dest$SYSTEMD_PAYLOAD_OUT/example/systemd/system/multi-user.target" ]] \
    || die "systemd unit tree did not materialize into $label$SYSTEMD_PAYLOAD_OUT/example/systemd/system"

  printf 'runtime  : materialized systemd bootstrap store into %s/nix/store\n' "$label"
}

materialize_systemd_bootstrap_store() {
  materialize_systemd_bootstrap_store_into "$MNT" ""
  materialize_systemd_bootstrap_store_into "$MNT/persist" "/persist"
}

write_systemd_stone_proof() {
  install -dm0755 "$MNT/usr/share/onix/bootstrap"
  cat > "$MNT/usr/share/onix/bootstrap/systemd-stone.txt" <<EOF
ONIX Phase 416 systemd image install

Policy:

- systemd is machine-plane software.
- Machine-plane software should come from moss/.stone packages.
- Phase 416 consumes systemd from the local Phase 4 moss repo.
- This first systemd package is a bootstrap ownership package.
- The package-owned closure lives under /usr/lib/onix/bootstrap/nix/store.
- Image assembly materializes that bootstrap copy into /nix/store and
  /persist/nix/store so the absolute musl loader/runtime paths resolve.

Installed package-owned payload:

- /usr/lib/onix/bootstrap/nix/store/...
- /usr/lib/systemd/systemd
- /usr/lib/systemd/system
- /usr/lib/systemd/user
- /usr/bin/systemctl
- /usr/bin/journalctl
- /usr/bin/systemd-tmpfiles
- /usr/bin/systemd-sysusers
- /usr/bin/udevadm
- /usr/share/onix/packages/systemd.md
- /usr/share/onix/packages/systemd.closure
- /usr/share/onix/packages/systemd.links

Runtime materialization:

- $SYSTEMD_PAYLOAD_OUT exists under /nix/store
- $SYSTEMD_PAYLOAD_OUT exists under /persist/nix/store

Important limitation:

The systemd bytes are still built by pinned nixpkgs pkgsMusl.systemd. This
phase moves image ownership to moss/systemd, but it does not yet create a
native source-built ONIX systemd recipe or split all dependencies into separate
stones.

The next phase should boot the image and prove that /usr/lib/systemd/systemd can
still run as PID 1 from the systemd-owned payload.
EOF
  chmod 0644 "$MNT/usr/share/onix/bootstrap/systemd-stone.txt"
  printf 'proof    : /usr/share/onix/bootstrap/systemd-stone.txt\n'
}

verify_systemd_stone_image() {
  local root_unit_dir
  local serial_unit
  local network_unit
  local remote_unit
  local dropbear_unit
  local systemd_link
  local systemctl_link

  log "verifying Phase 416 systemd image install"

  load_systemd_payload_metadata
  verify_systemd_stone_target "$MNT"

  [[ -x "$MNT$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd" ]] \
    || die "runtime /nix/store systemd binary is missing from image root"
  [[ -x "$MNT/persist$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd" ]] \
    || die "runtime /persist/nix/store systemd binary is missing"
  [[ -f "$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system/multi-user.target" ]] \
    || die "runtime /nix/store system unit tree is missing from image root"
  [[ -f "$MNT/persist$SYSTEMD_PAYLOAD_OUT/example/systemd/system/multi-user.target" ]] \
    || die "runtime /persist/nix/store system unit tree is missing"

  systemd_link="$(readlink "$MNT/usr/lib/systemd/systemd" 2>/dev/null || true)"
  [[ "$systemd_link" == "$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd" ]] \
    || die "/usr/lib/systemd/systemd points at wrong target: $systemd_link"
  [[ "$(readlink "$MNT/usr/lib/systemd/system")" == "$SYSTEMD_PAYLOAD_OUT/example/systemd/system" ]] \
    || die "/usr/lib/systemd/system points at wrong target"
  [[ "$(readlink "$MNT/usr/lib/systemd/user")" == "$SYSTEMD_PAYLOAD_OUT/example/systemd/user" ]] \
    || die "/usr/lib/systemd/user points at wrong target"
  systemctl_link="$(readlink "$MNT/usr/bin/systemctl" 2>/dev/null || true)"
  [[ "$systemctl_link" == "$SYSTEMD_PAYLOAD_OUT/bin/systemctl" ]] \
    || die "/usr/bin/systemctl points at wrong target: $systemctl_link"

  [[ -f "$MNT/boot/loader/entries/onix-phase-213.conf" ]] \
    || die "missing Phase 213 BLS entry"
  grep -q 'init=/usr/lib/systemd/systemd' "$MNT/boot/loader/entries/onix-phase-213.conf" \
    || die "BLS entry does not boot /usr/lib/systemd/systemd"

  root_unit_dir="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system"
  serial_unit="$root_unit_dir/onix-bootstrap-serial-shell.service"
  network_unit="$root_unit_dir/onix-bootstrap-network.service"
  remote_unit="$root_unit_dir/onix-bootstrap-remote-inspection.service"
  dropbear_unit="$root_unit_dir/onix-bootstrap-dropbear.service"

  [[ -f "$serial_unit" ]] || die "missing serial bootstrap unit after systemd stone install"
  [[ -f "$network_unit" ]] || die "missing network bootstrap unit after systemd stone install"
  [[ -f "$remote_unit" ]] || die "missing remote inspection bootstrap unit after systemd stone install"
  [[ -f "$dropbear_unit" ]] || die "missing Dropbear bootstrap unit after systemd stone install"

  grep -q '^ExecStart=/usr/bin/busybox sh /usr/lib/onix/bootstrap-serial-shell$' "$serial_unit" \
    || die "serial unit should still use busybox"
  grep -q '^ExecStart=/bin/sh /usr/lib/onix/bootstrap-network-up$' "$network_unit" \
    || die "network unit should still use /bin/sh compatibility path"
  grep -q '^ExecStart=/bin/nc -lk -p 6649 -e /usr/lib/onix/bootstrap-remote-inspection-response$' "$remote_unit" \
    || die "remote inspection unit should still use /bin/nc compatibility path"
  grep -q '^ExecStart=/usr/sbin/dropbear ' "$dropbear_unit" \
    || die "Dropbear unit should still use dropbear"

  verify_busybox_stone_image
  verify_dropbear_stone_image

  grep -q 'ONIX Phase 416 systemd image install' \
    "$MNT/usr/share/onix/bootstrap/systemd-stone.txt" \
    || die "systemd stone proof file is missing"
  grep -q 'systemd' "$MNT/usr/share/onix/packages/systemd.md" \
    || die "systemd package note is missing or wrong"
}

verify_native_systemd_stone_target() {
  local target="$1"
  local bin
  local interp
  local link_target

  [[ -x "$target/usr/lib/systemd/systemd" ]] \
    || die "native systemd target is missing /usr/lib/systemd/systemd: $target"
  [[ ! -L "$target/usr/lib/systemd/systemd" ]] \
    || die "native systemd /usr/lib/systemd/systemd must be a real file"
  [[ -f "$target/usr/lib/systemd/system/multi-user.target" ]] \
    || die "native systemd target is missing /usr/lib/systemd/system/multi-user.target"
  [[ -d "$target/usr/lib/systemd/user" ]] \
    || die "native systemd target is missing /usr/lib/systemd/user"

  for bin in systemctl journalctl systemd-tmpfiles systemd-sysusers udevadm; do
    [[ -x "$target/usr/bin/$bin" ]] \
      || die "native systemd target is missing /usr/bin/$bin"
    if [[ -L "$target/usr/bin/$bin" ]]; then
      link_target="$(readlink "$target/usr/bin/$bin")"
      [[ "$link_target" != /nix/store/* ]] \
        || die "native systemd /usr/bin/$bin points into the old bootstrap store"
    fi
  done

  interp="$(readelf -l "$target/usr/lib/systemd/systemd" 2>/dev/null |
    sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p' |
    head -n1)"
  [[ "$interp" == /lib/ld-musl-x86_64.so.1 ]] \
    || die "native systemd should use /lib/ld-musl-x86_64.so.1; interpreter=$interp"
  [[ -e "$target/usr/lib/ld-musl-x86_64.so.1" ]] \
    || die "native systemd target is missing musl dependency loader /usr/lib/ld-musl-x86_64.so.1"

  [[ -f "$target/usr/share/onix/packages/systemd.md" ]] \
    || die "native systemd install target is missing package note"
  [[ -f "$target/usr/share/onix/packages/musl.md" ]] \
    || die "native systemd install target is missing musl dependency package note"
  [[ -f "$target/usr/share/onix/packages/systemd.helpers" ]] \
    || die "native systemd install target is missing helper note"
  [[ -f "$target/usr/share/onix/packages/systemd.needed" ]] \
    || die "native systemd install target is missing needed-library note"
  grep -q 'Phase 422 native systemd userspace package' \
    "$target/usr/share/onix/packages/systemd.md" \
    || die "native systemd package note has the wrong phase marker"

  if grep -R -I -F '/nix/store' \
      "$target/usr/share/onix/packages/systemd.md" \
      "$target/usr/share/onix/packages/systemd.helpers" \
      "$target/usr/share/onix/packages/systemd.needed" >/dev/null 2>&1; then
    die "native systemd package notes must not mention the old bootstrap store path"
  fi

  while IFS= read -r link; do
    [[ -n "$link" ]] || continue
    link_target="$(readlink "$link")"
    [[ "$link_target" != /nix/store/* ]] \
      || die "native systemd symlink points into old bootstrap store: ${link#$target} -> $link_target"
  done < <(find "$target/usr" -type l 2>/dev/null || true)
}

install_native_systemd_stone_payload() {
  local name

  [[ -x "$HOST_MOSS" ]] \
    || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run make phase 202)"
  [[ -f "$IMAGE_REPO_DIR/stone.index" ]] \
    || die "missing ONIX image package repo index: ${IMAGE_REPO_DIR#$ONIX_ROOT/}/stone.index (run make phase 505)"

  need_cmd readelf
  need_cmd tar

  log "materializing native systemd from the image package repo into a scratch target"
  if [[ -d "$SYSTEMD_MOSS_ROOT" || -d "$SYSTEMD_MOSS_CACHE" || -d "$SYSTEMD_INSTALL_TARGET" ]]; then
    chmod -R u+rwX "$SYSTEMD_MOSS_ROOT" "$SYSTEMD_MOSS_CACHE" "$SYSTEMD_INSTALL_TARGET" 2>/dev/null || true
  fi
  rm -rf "$SYSTEMD_MOSS_ROOT" "$SYSTEMD_MOSS_CACHE" "$SYSTEMD_INSTALL_TARGET"
  install -dm0755 "$SYSTEMD_MOSS_ROOT" "$SYSTEMD_MOSS_CACHE" "$SYSTEMD_INSTALL_TARGET"

  "$HOST_MOSS" -D "$SYSTEMD_MOSS_ROOT" --cache "$SYSTEMD_MOSS_CACHE" \
    repo add onix-image "file://$IMAGE_REPO_DIR/stone.index" \
    -c "ONIX image package repo" >/dev/null
  "$HOST_MOSS" -D "$SYSTEMD_MOSS_ROOT" --cache "$SYSTEMD_MOSS_CACHE" \
    repo update >/dev/null
  "$HOST_MOSS" -D "$SYSTEMD_MOSS_ROOT" --cache "$SYSTEMD_MOSS_CACHE" \
    -y install --to "$SYSTEMD_INSTALL_TARGET" systemd

  verify_native_systemd_stone_target "$SYSTEMD_INSTALL_TARGET"

  log "removing old bootstrap systemd activation paths before native install"
  rm -rf "$MNT/usr/lib/systemd"
  rm -rf "$MNT/usr/lib/onix/bootstrap"
  rm -f \
    "$MNT/usr/share/onix/packages/systemd.md" \
    "$MNT/usr/share/onix/packages/systemd.closure" \
    "$MNT/usr/share/onix/packages/systemd.links"

  if [[ -d "$SYSTEMD_INSTALL_TARGET/usr/bin" ]]; then
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      rm -rf "$MNT/usr/bin/$name"
    done < <(find "$SYSTEMD_INSTALL_TARGET/usr/bin" -mindepth 1 -maxdepth 1 -printf '%f\n')
  fi
  if [[ -d "$SYSTEMD_INSTALL_TARGET/usr/sbin" ]]; then
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      rm -rf "$MNT/usr/sbin/$name"
    done < <(find "$SYSTEMD_INSTALL_TARGET/usr/sbin" -mindepth 1 -maxdepth 1 -printf '%f\n')
  fi

  log "copying native systemd package payload into the ONIX image"
  install -dm0755 "$MNT/usr"
  tar --numeric-owner -C "$SYSTEMD_INSTALL_TARGET" -cpf - usr |
    tar --numeric-owner -C "$MNT" -xpf -

  verify_native_systemd_stone_target "$MNT"
  printf 'stone    : native systemd installed under /usr/lib/systemd + /usr/bin\n'
}

prune_systemd_bootstrap_nix_payloads() {
  local store_path

  log "pruning old bootstrap systemd runtime compatibility payloads"
  if [[ ! -s "$CLOSURE_LIST" ]]; then
    printf 'skip     : systemd closure metadata absent (%s)\n' "${CLOSURE_LIST#$ONIX_ROOT/}"
    return 0
  fi

  while IFS= read -r store_path; do
    [[ -n "$store_path" ]] || continue
    assert_nix_store_path "$store_path"
    prune_store_path_from_tree "$MNT" "root" "$store_path"
    prune_store_path_from_tree "$MNT/persist" "persist" "$store_path"
  done < "$CLOSURE_LIST"

  rm -rf "$MNT/usr/lib/onix/bootstrap"
  printf 'removed  : old package-owned systemd bootstrap compatibility copy\n'
}

activate_bootstrap_policy_units_native() {
  local native_unit_dir="$MNT/usr/lib/systemd/system"
  local mask_tty

  activate_bootstrap_policy_unit_tree "$native_unit_dir"

  install -dm0755 "$MNT/etc/systemd/system"
  for mask_tty in ttyS0 "$SERIAL_CONSOLE_TTY"; do
    ln -sfn /dev/null "$MNT/etc/systemd/system/serial-getty@$mask_tty.service"
    printf 'mask     : /etc/systemd/system/serial-getty@%s.service -> /dev/null\n' "$mask_tty"
  done
}

write_native_systemd_stone_proof() {
  install -dm0755 "$MNT/usr/share/onix/bootstrap"
  cat > "$MNT/usr/share/onix/bootstrap/native-systemd-stone.txt" <<'EOF'
ONIX Phase 422 native systemd image install

Policy:

- systemd is machine-plane software.
- Machine-plane software should come from moss/.stone packages.
- Phase 422 consumes the native source-built systemd stone.
- The active PID 1 binary is now a real file at /usr/lib/systemd/systemd.
- The active unit tree is now the native /usr/lib/systemd/system tree.
- Bootstrap unit sources still come from bootstrap-policy.

Installed package-owned payload:

- /usr/lib/systemd/systemd
- /usr/lib/systemd/system
- /usr/lib/systemd/user
- /usr/bin/systemctl
- /usr/bin/journalctl
- /usr/bin/systemd-tmpfiles
- /usr/bin/systemd-sysusers
- /usr/bin/udevadm
- /usr/share/onix/packages/systemd.md
- /usr/share/onix/packages/systemd.helpers
- /usr/share/onix/packages/systemd.needed

Dependency payload consumed through moss:

- musl owns /usr/lib/ld-musl-x86_64.so.1
- musl owns /usr/lib/libc.so
- musl owns /usr/lib/libc.musl-x86_64.so.1
- /usr/share/onix/packages/musl.md records that ownership

Important limitation:

The first native systemd package is intentionally monolithic. It may bundle
immediate non-musl runtime/helper files so we can prove the boot before
splitting every dependency into its own stone. The musl loader/libc family is
not part of that bundle; it comes from the canonical musl stone.

The next cleanup can split native runtime libraries/helpers into smaller stones
once the native boot path is stable.
EOF
  chmod 0644 "$MNT/usr/share/onix/bootstrap/native-systemd-stone.txt"
  printf 'proof    : /usr/share/onix/bootstrap/native-systemd-stone.txt\n'
}

verify_native_bootstrap_units() {
  local unit_dir="$MNT/usr/lib/systemd/system"
  local wants="$unit_dir/multi-user.target.wants"
  local unit

  while IFS= read -r unit; do
    [[ -n "$unit" ]] || continue
    [[ -f "$MNT/usr/lib/onix/systemd/system/$unit" ]] \
      || die "missing package-owned bootstrap unit source: $unit"
    [[ -f "$unit_dir/$unit" ]] \
      || die "missing active native bootstrap unit: $unit"
    cmp -s "$MNT/usr/lib/onix/systemd/system/$unit" "$unit_dir/$unit" \
      || die "active native bootstrap unit differs from package-owned source: $unit"
    [[ -L "$wants/$unit" ]] \
      || die "active native bootstrap unit is not enabled: $unit"
    [[ "$(readlink "$wants/$unit")" == "../$unit" ]] \
      || die "active native bootstrap unit enable symlink target is wrong: $unit"
  done < <(bootstrap_policy_units)

  grep -q '^ExecStart=/usr/bin/busybox sh /usr/lib/onix/bootstrap-serial-shell$' \
    "$unit_dir/onix-bootstrap-serial-shell.service" \
    || die "native serial unit should use busybox"
  grep -q '^ExecStart=/bin/sh /usr/lib/onix/bootstrap-network-up$' \
    "$unit_dir/onix-bootstrap-network.service" \
    || die "native network unit should use /bin/sh compatibility path"
  grep -q '^ExecStart=/bin/nc -lk -p 6649 -e /usr/lib/onix/bootstrap-remote-inspection-response$' \
    "$unit_dir/onix-bootstrap-remote-inspection.service" \
    || die "native remote-inspection unit should use /bin/nc compatibility path"
  grep -q '^ExecStart=/usr/sbin/dropbear ' \
    "$unit_dir/onix-bootstrap-dropbear.service" \
    || die "native Dropbear unit should use dropbear"
  grep -q ' -m ' \
    "$unit_dir/onix-bootstrap-dropbear.service" \
    || die "native Dropbear unit should disable Dropbear MOTD with -m"
}

assert_systemd_bootstrap_closure_absent() {
  local store_path

  if [[ ! -s "$CLOSURE_LIST" ]]; then
    printf 'verify   : systemd closure metadata absent (%s)\n' "${CLOSURE_LIST#$ONIX_ROOT/}"
    return 0
  fi

  while IFS= read -r store_path; do
    [[ -n "$store_path" ]] || continue
    assert_nix_store_path "$store_path"
    [[ ! -e "$MNT$store_path" && ! -L "$MNT$store_path" ]] \
      || die "old bootstrap systemd closure path still exists in root store: $store_path"
    [[ ! -e "$MNT/persist$store_path" && ! -L "$MNT/persist$store_path" ]] \
      || die "old bootstrap systemd closure path still exists in persist store: $store_path"
  done < "$CLOSURE_LIST"

  printf 'verify   : old bootstrap systemd closure paths absent from root and persist stores\n'
}

verify_native_systemd_stone_image() {
  log "verifying Phase 422 native systemd image install"

  verify_native_systemd_stone_target "$MNT"
  verify_bootstrap_policy_target "$MNT"
  verify_busybox_stone_target "$MNT"
  verify_dropbear_stone_target "$MNT"

  [[ -f "$MNT/boot/loader/entries/onix-phase-213.conf" ]] \
    || die "missing Phase 213 BLS entry"
  grep -q 'init=/usr/lib/systemd/systemd' "$MNT/boot/loader/entries/onix-phase-213.conf" \
    || die "BLS entry does not boot /usr/lib/systemd/systemd"

  verify_native_bootstrap_units
  assert_systemd_bootstrap_closure_absent
  [[ ! -e "$MNT/usr/lib/onix/bootstrap" && ! -L "$MNT/usr/lib/onix/bootstrap" ]] \
    || die "old package-owned bootstrap compatibility directory still exists"

  [[ -f "$MNT/usr/share/onix/bootstrap/native-systemd-stone.txt" ]] \
    || die "native systemd proof file is missing"
  grep -q 'ONIX Phase 422 native systemd image install' \
    "$MNT/usr/share/onix/bootstrap/native-systemd-stone.txt" \
    || die "native systemd proof file has the wrong marker"
  grep -q 'systemd' "$MNT/usr/share/onix/packages/systemd.md" \
    || die "native systemd package note is missing or wrong"
}

preview_native_systemd_stone() {
  local unit_dir="$MNT/usr/lib/systemd/system"

  log "native systemd image preview"
  find \
    "$MNT/usr/lib/systemd/systemd" \
    "$MNT/usr/lib/systemd/system" \
    "$MNT/usr/lib/systemd/user" \
    "$MNT/usr/bin/systemctl" \
    "$MNT/usr/bin/journalctl" \
    "$MNT/usr/bin/systemd-tmpfiles" \
    "$MNT/usr/bin/systemd-sysusers" \
    "$MNT/usr/bin/udevadm" \
    "$MNT/usr/lib/ld-musl-x86_64.so.1" \
    "$MNT/usr/share/onix/packages/systemd.md" \
    "$MNT/usr/share/onix/packages/systemd.helpers" \
    "$MNT/usr/share/onix/packages/systemd.needed" \
    "$MNT/usr/share/onix/bootstrap/native-systemd-stone.txt" \
    "$MNT/boot/loader/entries/onix-phase-213.conf" \
    "$unit_dir/onix-bootstrap-serial-shell.service" \
    "$unit_dir/onix-bootstrap-network.service" \
    "$unit_dir/onix-bootstrap-remote-inspection.service" \
    "$unit_dir/onix-bootstrap-dropbear.service" \
    -maxdepth 0 -printf '%M %p -> %l\n' |
    sed "s# $MNT/# /#" |
    sed "s#-> $MNT/#-> /#"

  printf '%s\n' '--- native /usr/lib/systemd/systemd file ---'
  file "$MNT/usr/lib/systemd/systemd"
  printf '%s\n' '--- native systemd ELF interpreter ---'
  readelf -l "$MNT/usr/lib/systemd/systemd" |
    sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p'
  printf '%s\n' '--- native bootstrap unit ExecStart lines ---'
  grep '^ExecStart=' \
    "$unit_dir/onix-bootstrap-serial-shell.service" \
    "$unit_dir/onix-bootstrap-network.service" \
    "$unit_dir/onix-bootstrap-remote-inspection.service" \
    "$unit_dir/onix-bootstrap-dropbear.service" |
    sed "s#$MNT##"
  printf '%s\n' '--- native systemd package note ---'
  sed -n '1,120p' "$MNT/usr/share/onix/packages/systemd.md"
}

bootstrap_policy_units() {
  cat <<'EOF'
onix-bootstrap-serial-shell.service
onix-bootstrap-network.service
onix-bootstrap-remote-inspection.service
onix-bootstrap-dropbear.service
EOF
}

verify_bootstrap_policy_target() {
  local target="$1"
  local script
  local unit

  for script in \
    bootstrap-serial-shell \
    bootstrap-network-up \
    bootstrap-network-status \
    bootstrap-network-proof \
    bootstrap-remote-inspection-response \
    bootstrap-remote-inspection-status \
    bootstrap-remote-inspection-proof \
    bootstrap-ssh-status \
    bootstrap-ssh-proof
  do
    [[ -x "$target/usr/lib/onix/$script" ]] \
      || die "bootstrap-policy target is missing executable /usr/lib/onix/$script"
  done

  while IFS= read -r unit; do
    [[ -n "$unit" ]] || continue
    [[ -f "$target/usr/lib/onix/systemd/system/$unit" ]] \
      || die "bootstrap-policy target is missing unit source: $unit"
  done < <(bootstrap_policy_units)

  [[ -f "$target/usr/share/onix/bootstrap/bootstrap-policy.txt" ]] \
    || die "bootstrap-policy target is missing bootstrap policy proof"
  [[ -f "$target/usr/share/onix/packages/bootstrap-policy.md" ]] \
    || die "bootstrap-policy target is missing package note"

  grep -q 'ONIX_BOOTSTRAP_SERIAL_CONSOLE_READY' "$target/usr/lib/onix/bootstrap-serial-shell" \
    || die "bootstrap serial shell script does not print the ready marker"
  grep -q '^ExecStart=/usr/bin/busybox sh /usr/lib/onix/bootstrap-serial-shell$' \
    "$target/usr/lib/onix/systemd/system/onix-bootstrap-serial-shell.service" \
    || die "package-owned serial unit should use busybox"
  grep -q '^ExecStart=/usr/sbin/dropbear ' \
    "$target/usr/lib/onix/systemd/system/onix-bootstrap-dropbear.service" \
    || die "package-owned Dropbear unit should use dropbear"
  grep -q 'ONIX Phase 418 bootstrap policy package' \
    "$target/usr/share/onix/bootstrap/bootstrap-policy.txt" \
    || die "bootstrap policy proof file is missing the Phase 418 marker"
  grep -q 'bootstrap-policy' \
    "$target/usr/share/onix/packages/bootstrap-policy.md" \
    || die "bootstrap policy package note is missing package name"
}

ensure_dropbear_no_motd_unit() {
  local unit="$1"

  [[ -f "$unit" ]] || die "missing Dropbear unit to normalize: ${unit#$MNT/}"

  if grep -q '^ExecStart=.*dropbear .* -m ' "$unit"; then
    return 0
  fi

  sed -i \
    's/dropbear -F -E -e /dropbear -F -E -e -m /' \
    "$unit"

  grep -q '^ExecStart=.*dropbear .* -m ' "$unit" \
    || die "failed to add Dropbear -m to ${unit#$MNT/}"

  printf 'unit     : %s disables Dropbear MOTD with -m\n' "${unit#$MNT}"
}

ensure_bootstrap_policy_dropbear_no_motd() {
  ensure_dropbear_no_motd_unit \
    "$MNT/usr/lib/onix/systemd/system/onix-bootstrap-dropbear.service"
}

install_bootstrap_policy_stone_payload() {
  [[ -x "$HOST_MOSS" ]] \
    || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run make phase 202)"
  [[ -f "$IMAGE_REPO_DIR/stone.index" ]] \
    || die "missing ONIX image package repo index: ${IMAGE_REPO_DIR#$ONIX_ROOT/}/stone.index (run make phase 505)"

  need_cmd tar

  log "materializing bootstrap-policy from the image package repo into a scratch target"
  if [[ -d "$BOOTSTRAP_POLICY_MOSS_ROOT" ||
        -d "$BOOTSTRAP_POLICY_MOSS_CACHE" ||
        -d "$BOOTSTRAP_POLICY_INSTALL_TARGET" ]]; then
    chmod -R u+rwX \
      "$BOOTSTRAP_POLICY_MOSS_ROOT" \
      "$BOOTSTRAP_POLICY_MOSS_CACHE" \
      "$BOOTSTRAP_POLICY_INSTALL_TARGET" 2>/dev/null || true
  fi
  rm -rf "$BOOTSTRAP_POLICY_MOSS_ROOT" "$BOOTSTRAP_POLICY_MOSS_CACHE" "$BOOTSTRAP_POLICY_INSTALL_TARGET"
  install -dm0755 "$BOOTSTRAP_POLICY_MOSS_ROOT" "$BOOTSTRAP_POLICY_MOSS_CACHE" "$BOOTSTRAP_POLICY_INSTALL_TARGET"

  "$HOST_MOSS" -D "$BOOTSTRAP_POLICY_MOSS_ROOT" --cache "$BOOTSTRAP_POLICY_MOSS_CACHE" \
    repo add onix-image "file://$IMAGE_REPO_DIR/stone.index" \
    -c "ONIX image package repo" >/dev/null
  "$HOST_MOSS" -D "$BOOTSTRAP_POLICY_MOSS_ROOT" --cache "$BOOTSTRAP_POLICY_MOSS_CACHE" \
    repo update >/dev/null
  "$HOST_MOSS" -D "$BOOTSTRAP_POLICY_MOSS_ROOT" --cache "$BOOTSTRAP_POLICY_MOSS_CACHE" \
    -y install --to "$BOOTSTRAP_POLICY_INSTALL_TARGET" bootstrap-policy

  verify_bootstrap_policy_target "$BOOTSTRAP_POLICY_INSTALL_TARGET"

  log "copying bootstrap-policy package payload into the ONIX image"
  install -dm0755 "$MNT/usr"
  tar --numeric-owner -C "$BOOTSTRAP_POLICY_INSTALL_TARGET" -cpf - \
    usr/lib/onix \
    usr/share/onix/bootstrap \
    usr/share/onix/packages/bootstrap-policy.md \
    | tar --numeric-owner -C "$MNT" -xpf -

  verify_bootstrap_policy_target "$MNT"
  printf 'stone    : bootstrap-policy installed under /usr/lib/onix + /usr/share/onix\n'
}

phase5_runtime_packages() {
  cat <<'EOF'
busybox
uutils-coreutils
musl
linux-pam
libseccomp
libgcc-runtime
rootasrole
rootasrole-policy
moss
EOF
}

live_moss_installed_packages() {
  cat <<'EOF'
branding
filesystem
busybox
uutils-coreutils
dropbear
systemd
bootstrap-policy
musl
linux-pam
libseccomp
libgcc-runtime
rootasrole
rootasrole-policy
moss
EOF
}

install_phase5_runtime_payload() {
  [[ -x "$HOST_MOSS" ]] \
    || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run make phase 202)"
  [[ -f "$IMAGE_REPO_DIR/stone.index" ]] \
    || die "missing ONIX image package repo index: ${IMAGE_REPO_DIR#$ONIX_ROOT/}/stone.index (run make phase 505)"

  need_cmd tar

  log "materializing Phase 5 runtime package set from the image package repo"
  if [[ -d "$PHASE5_RUNTIME_MOSS_ROOT" ||
        -d "$PHASE5_RUNTIME_MOSS_CACHE" ||
        -d "$PHASE5_RUNTIME_INSTALL_TARGET" ]]; then
    chmod -R u+rwX \
      "$PHASE5_RUNTIME_MOSS_ROOT" \
      "$PHASE5_RUNTIME_MOSS_CACHE" \
      "$PHASE5_RUNTIME_INSTALL_TARGET" 2>/dev/null || true
  fi
  rm -rf "$PHASE5_RUNTIME_MOSS_ROOT" "$PHASE5_RUNTIME_MOSS_CACHE" "$PHASE5_RUNTIME_INSTALL_TARGET"
  install -dm0755 "$PHASE5_RUNTIME_MOSS_ROOT" "$PHASE5_RUNTIME_MOSS_CACHE" "$PHASE5_RUNTIME_INSTALL_TARGET"

  "$HOST_MOSS" -D "$PHASE5_RUNTIME_MOSS_ROOT" --cache "$PHASE5_RUNTIME_MOSS_CACHE" \
    repo add onix-image "file://$IMAGE_REPO_DIR/stone.index" \
    -c "ONIX image package repo" >/dev/null
  "$HOST_MOSS" -D "$PHASE5_RUNTIME_MOSS_ROOT" --cache "$PHASE5_RUNTIME_MOSS_CACHE" \
    repo update >/dev/null

  mapfile -t phase5_packages < <(phase5_runtime_packages)
  "$HOST_MOSS" -D "$PHASE5_RUNTIME_MOSS_ROOT" --cache "$PHASE5_RUNTIME_MOSS_CACHE" \
    -y install --to "$PHASE5_RUNTIME_INSTALL_TARGET" "${phase5_packages[@]}"

  verify_phase5_runtime_target "$PHASE5_RUNTIME_INSTALL_TARGET"

  log "removing old coreutils command links before installing uutils links"
  while IFS= read -r command_name; do
    [[ -n "$command_name" ]] || continue
    case "$command_name" in
      */*|"") die "unsafe uutils command name in manifest: $command_name" ;;
    esac
    rm -f "$MNT/usr/bin/$command_name"
  done < "$PHASE5_RUNTIME_INSTALL_TARGET/usr/share/onix/packages/uutils-coreutils.commands"

  log "copying Phase 5 runtime package payload into the ONIX image"
  install -dm0755 "$MNT/usr"
  tar --numeric-owner \
    -C "$PHASE5_RUNTIME_INSTALL_TARGET" -cpf - usr \
    | tar --numeric-owner -C "$MNT" -xpf -

  materialize_rootasrole_live_policy
  ensure_var_run_points_to_run
  initialize_phase5_live_moss_root
  write_phase5_runtime_proof
  verify_phase5_runtime_image
  printf 'stone    : Phase 5 runtime package set installed under /usr\n'
}

materialize_rootasrole_live_policy() {
  local factory_policy="$MNT/usr/share/factory/etc/security/rootasrole.json"
  local factory_policy_data="$MNT/usr/share/factory/etc/security/rootasrole.d/policy.json"
  local factory_pam_sr="$MNT/usr/share/factory/etc/pam.d/sr"
  local factory_pam_dosr="$MNT/usr/share/factory/etc/pam.d/dosr"
  local live_policy="$MNT/etc/security/rootasrole.json"
  local live_policy_data="$MNT/etc/security/rootasrole.d/policy.json"
  local factory_pam live_pam pam_name

  [[ -f "$factory_policy" ]] || die "missing RootAsRole factory policy after Phase 5 install"
  [[ -f "$factory_policy_data" ]] || die "missing RootAsRole factory policy data after Phase 5 install"
  [[ -f "$factory_pam_sr" ]] || die "missing RootAsRole factory PAM service sr after Phase 5 install"
  [[ -f "$factory_pam_dosr" ]] || die "missing RootAsRole factory PAM companion dosr after Phase 5 install"

  install -dm0755 "$MNT/etc/security/rootasrole.d" "$MNT/etc/pam.d"

  if [[ ! -e "$live_policy" ]]; then
    install -m0600 "$factory_policy" "$live_policy"
    printf 'created  : /etc/security/rootasrole.json from /usr/share/factory\n'
  elif cmp -s "$factory_policy" "$live_policy"; then
    chmod 0600 "$live_policy"
    printf 'default  : /etc/security/rootasrole.json already matches factory policy\n'
  elif ! grep -q '/etc/security/rootasrole.d/' "$live_policy" &&
       grep -q 'r_onix_root_bootstrap' "$live_policy"; then
    install -m0600 "$factory_policy" "$live_policy"
    printf 'migrated : /etc/security/rootasrole.json to split settings/data policy\n'
  else
    printf 'override : /etc/security/rootasrole.json exists and differs; preserved\n'
  fi

  if [[ ! -e "$live_policy_data" ]]; then
    install -m0600 "$factory_policy_data" "$live_policy_data"
    printf 'created  : /etc/security/rootasrole.d/policy.json from /usr/share/factory\n'
  elif cmp -s "$factory_policy_data" "$live_policy_data"; then
    chmod 0600 "$live_policy_data"
    printf 'default  : /etc/security/rootasrole.d/policy.json already matches factory policy\n'
  elif grep -q '"name": "onix"' "$live_policy_data" ||
       ! grep -q '"id": 1000' "$live_policy_data"; then
    install -m0600 "$factory_policy_data" "$live_policy_data"
    printf 'migrated : /etc/security/rootasrole.d/policy.json to uid-based bootstrap policy\n'
  else
    printf 'override : /etc/security/rootasrole.d/policy.json exists and differs; preserved\n'
  fi

  for pam_name in sr dosr; do
    factory_pam="$MNT/usr/share/factory/etc/pam.d/$pam_name"
    live_pam="$MNT/etc/pam.d/$pam_name"
    if [[ ! -e "$live_pam" ]]; then
      install -m0644 "$factory_pam" "$live_pam"
      printf 'created  : /etc/pam.d/%s from /usr/share/factory\n' "$pam_name"
    elif cmp -s "$factory_pam" "$live_pam"; then
      chmod 0644 "$live_pam"
      printf 'default  : /etc/pam.d/%s already matches factory policy\n' "$pam_name"
    else
      printf 'override : /etc/pam.d/%s exists and differs; preserved\n' "$pam_name"
    fi
  done
}

ensure_var_run_points_to_run() {
  local var_run="$MNT/var/run"
  local target

  install -dm0755 "$MNT/var"

  if [[ -L "$var_run" ]]; then
    target="$(readlink "$var_run")"
    case "$target" in
      ../run|/run)
        printf 'default  : /var/run already points at /run\n'
        return
        ;;
    esac
    rm -f "$var_run"
  elif [[ -e "$var_run" ]]; then
    if [[ -d "$var_run" ]] && ! find "$var_run" -mindepth 1 -print -quit | grep -q .; then
      rmdir "$var_run"
    else
      die "/var/run exists but is not an empty directory or symlink; refusing to replace it"
    fi
  fi

  ln -s ../run "$var_run"
  printf 'created  : /var/run -> ../run for runtime state compatibility\n'
}

initialize_phase5_live_moss_root() {
  local live_packages=()
  local installed_log="$PHASE5_LIVE_MOSS_CACHE/installed.list"
  local package_name

  [[ -x "$HOST_MOSS" ]] \
    || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run make phase 202)"
  [[ -f "$IMAGE_REPO_DIR/stone.index" ]] \
    || die "missing ONIX image package repo index: ${IMAGE_REPO_DIR#$ONIX_ROOT/}/stone.index (run make phase 505)"

  log "initializing live / moss root metadata and installed package state"
  rm -rf "$MNT/.moss" "$MNT/etc/moss" "$PHASE5_LIVE_MOSS_ROOT" "$PHASE5_LIVE_MOSS_CACHE"
  install -dm0755 "$PHASE5_LIVE_MOSS_ROOT" "$PHASE5_LIVE_MOSS_CACHE"

  "$HOST_MOSS" -D "$PHASE5_LIVE_MOSS_ROOT" --cache "$PHASE5_LIVE_MOSS_CACHE" \
    repo add onix-image "file://$IMAGE_REPO_DIR/stone.index" \
    -c "ONIX image package repo" >/dev/null
  "$HOST_MOSS" -D "$PHASE5_LIVE_MOSS_ROOT" --cache "$PHASE5_LIVE_MOSS_CACHE" \
    repo update >/dev/null

  mapfile -t live_packages < <(live_moss_installed_packages)
  "$HOST_MOSS" -D "$PHASE5_LIVE_MOSS_ROOT" --cache "$PHASE5_LIVE_MOSS_CACHE" \
    -y install "${live_packages[@]}" >/dev/null

  install -dm0755 "$MNT/etc" "$MNT/usr/lib"
  cp -a "$PHASE5_LIVE_MOSS_ROOT/.moss" "$MNT/.moss"
  cp -a "$PHASE5_LIVE_MOSS_ROOT/etc/moss" "$MNT/etc/moss"
  install -m0644 "$PHASE5_LIVE_MOSS_ROOT/usr/.stateID" "$MNT/usr/.stateID"
  install -m0644 "$PHASE5_LIVE_MOSS_ROOT/usr/lib/system-model.kdl" \
    "$MNT/usr/lib/system-model.kdl"

  chmod -R a+rX "$MNT/.moss" "$MNT/etc/moss"
  "$HOST_MOSS" -D "$MNT" --cache "$PHASE5_LIVE_MOSS_CACHE" \
    list available >/dev/null
  "$HOST_MOSS" -D "$MNT" --cache "$PHASE5_LIVE_MOSS_CACHE" \
    list installed > "$installed_log"
  for package_name in "${live_packages[@]}"; do
    grep -q "^${package_name}[[:space:]]" "$installed_log" \
      || die "live moss installed DB does not list $package_name"
  done
  printf 'moss     : initialized /.moss and /etc/moss for direct live package queries\n'
}

write_phase5_runtime_proof() {
  install -dm0755 "$MNT/usr/share/onix/bootstrap"
  cat > "$MNT/usr/share/onix/bootstrap/phase5-runtime.txt" <<'EOF'
ONIX Phase 514 runtime package set

Installed from the image package repository:

- busybox
- uutils-coreutils
- musl
- linux-pam
- libseccomp
- libgcc-runtime
- rootasrole
- rootasrole-policy
- moss

This proof means the booted image has consumed the Phase 5 package/repository
plane instead of only building those stones on the host.
EOF
  chmod 0644 "$MNT/usr/share/onix/bootstrap/phase5-runtime.txt"
}

verify_phase5_runtime_target() {
  local target="$1"
  local command_name command_count=0

  [[ -x "$target/usr/bin/busybox" ]] || die "Phase 5 target missing /usr/bin/busybox"
  [[ -x "$target/usr/bin/coreutils" ]] || die "Phase 5 target missing /usr/bin/coreutils"
  [[ -x "$target/usr/bin/moss" ]] || die "Phase 5 target missing /usr/bin/moss"
  [[ -x "$target/usr/bin/dosr" ]] || die "Phase 5 target missing /usr/bin/dosr"
  [[ -x "$target/usr/bin/chsr" ]] || die "Phase 5 target missing /usr/bin/chsr"
  [[ -e "$target/usr/lib/libpam.so.0" ]] || die "Phase 5 target missing libpam.so.0"
  [[ -e "$target/usr/lib/libseccomp.so.2" ]] || die "Phase 5 target missing libseccomp.so.2"
  [[ -e "$target/usr/lib/libgcc_s.so.1" ]] || die "Phase 5 target missing libgcc_s.so.1"
  [[ -e "$target/usr/lib/ld-musl-x86_64.so.1" ]] || die "Phase 5 target missing musl loader"
  [[ -f "$target/usr/share/onix/packages/uutils-coreutils.commands" ]] \
    || die "Phase 5 target missing uutils command manifest"
  [[ -f "$target/usr/share/onix/packages/moss.md" ]] \
    || die "Phase 5 target missing moss package note"
  [[ -f "$target/usr/share/factory/etc/security/rootasrole.json" ]] \
    || die "Phase 5 target missing RootAsRole factory settings"
  [[ -f "$target/usr/share/factory/etc/security/rootasrole.d/policy.json" ]] \
    || die "Phase 5 target missing RootAsRole factory policy data"
  [[ -f "$target/usr/share/factory/etc/pam.d/sr" ]] \
    || die "Phase 5 target missing RootAsRole PAM service sr"
  [[ -f "$target/usr/share/factory/etc/pam.d/dosr" ]] \
    || die "Phase 5 target missing RootAsRole PAM companion dosr"

  while IFS= read -r command_name; do
    [[ -n "$command_name" ]] || continue
    command_count=$((command_count + 1))
    [[ -L "$target/usr/bin/$command_name" ]] \
      || die "Phase 5 target missing uutils command link: /usr/bin/$command_name"
    [[ "$(readlink "$target/usr/bin/$command_name")" == "coreutils" ]] \
      || die "Phase 5 target /usr/bin/$command_name does not point at coreutils"
  done < "$target/usr/share/onix/packages/uutils-coreutils.commands"

  [[ "$command_count" -gt 0 ]] || die "Phase 5 target uutils command manifest is empty"
}

verify_phase5_runtime_image() {
  local installed_log="$PHASE5_LIVE_MOSS_CACHE/verify-installed.list"
  local package_name

  log "verifying Phase 514 runtime package set image install"
  verify_phase5_runtime_target "$MNT"

  [[ -f "$MNT/usr/share/factory/etc/security/rootasrole.json" ]] \
    || die "missing factory RootAsRole policy in image"
  [[ -f "$MNT/usr/share/factory/etc/security/rootasrole.d/policy.json" ]] \
    || die "missing factory RootAsRole policy data in image"
  [[ -f "$MNT/usr/share/factory/etc/pam.d/sr" ]] \
    || die "missing factory RootAsRole PAM service sr in image"
  [[ -f "$MNT/usr/share/factory/etc/pam.d/dosr" ]] \
    || die "missing factory RootAsRole PAM config in image"
  [[ -f "$MNT/etc/security/rootasrole.json" ]] \
    || die "missing live RootAsRole policy in image"
  [[ -f "$MNT/etc/security/rootasrole.d/policy.json" ]] \
    || die "missing live RootAsRole policy data in image"
  [[ -f "$MNT/etc/pam.d/sr" ]] \
    || die "missing live PAM service sr in image"
  [[ -f "$MNT/etc/pam.d/dosr" ]] \
    || die "missing live PAM config for dosr in image"
  [[ -d "$MNT/.moss/db" ]] \
    || die "missing live moss database directory in image"
  [[ -d "$MNT/.moss/repo" ]] \
    || die "missing live moss repo cache in image"
  [[ -f "$MNT/etc/moss/repo.d/onix-image.kdl" ]] \
    || die "missing live moss repo config in image"
  [[ -f "$MNT/usr/share/onix/bootstrap/phase5-runtime.txt" ]] \
    || die "missing Phase 514 runtime proof note"
  [[ -L "$MNT/var/run" ]] \
    || die "missing /var/run compatibility symlink"
  case "$(readlink "$MNT/var/run")" in
    ../run|/run) ;;
    *) die "/var/run does not point at /run" ;;
  esac

  grep -q '/etc/security/rootasrole.d/' "$MNT/usr/share/factory/etc/security/rootasrole.json" \
    || die "factory RootAsRole settings do not point at rootasrole.d"
  grep -q '"id": 0' "$MNT/usr/share/factory/etc/security/rootasrole.d/policy.json" \
    || die "factory RootAsRole policy does not mention root actor uid 0"
  grep -q '"id": 1000' "$MNT/usr/share/factory/etc/security/rootasrole.d/policy.json" \
    || die "factory RootAsRole policy does not mention onix actor uid 1000"
  if grep -q 'ROOTADMINISTRATOR' "$MNT/usr/share/factory/etc/security/rootasrole.d/policy.json"; then
    die "factory RootAsRole policy grants legacy ROOTADMINISTRATOR"
  fi
  grep -q '/etc/security/rootasrole.d/' "$MNT/etc/security/rootasrole.json" \
    || die "live RootAsRole settings do not point at rootasrole.d"
  grep -q '"id": 0' "$MNT/etc/security/rootasrole.d/policy.json" \
    || die "live RootAsRole policy does not mention root actor uid 0"
  grep -q '"id": 1000' "$MNT/etc/security/rootasrole.d/policy.json" \
    || die "live RootAsRole policy does not mention onix actor uid 1000"
  if grep -q 'ROOTADMINISTRATOR' "$MNT/etc/security/rootasrole.d/policy.json"; then
    die "live RootAsRole policy grants legacy ROOTADMINISTRATOR"
  fi
  grep -q 'pam_permit.so' "$MNT/etc/pam.d/dosr" \
    || die "live PAM config for dosr does not mention pam_permit.so"
  grep -q 'pam_permit.so' "$MNT/etc/pam.d/sr" \
    || die "live PAM service sr does not mention pam_permit.so"
  "$HOST_MOSS" -D "$MNT" --cache "$PHASE5_LIVE_MOSS_CACHE" \
    list available | grep -q '^moss[[:space:]]' \
    || die "live moss root cannot list moss as available"
  "$HOST_MOSS" -D "$MNT" --cache "$PHASE5_LIVE_MOSS_CACHE" \
    list installed > "$installed_log"
  while IFS= read -r package_name; do
    [[ -n "$package_name" ]] || continue
    grep -q "^${package_name}[[:space:]]" "$installed_log" \
      || die "live moss root does not list $package_name as installed"
  done < <(live_moss_installed_packages)
}

preview_phase5_runtime() {
  log "Phase 5 runtime image preview"
  for path in \
    /usr/bin/moss \
    /usr/bin/coreutils \
    /usr/bin/ls \
    /usr/bin/sh \
    /usr/bin/dosr \
    /usr/bin/chsr \
    /usr/lib/libpam.so.0 \
    /usr/lib/libseccomp.so.2 \
    /usr/lib/libgcc_s.so.1 \
    /.moss/db \
    /etc/moss/repo.d/onix-image.kdl \
    /etc/security/rootasrole.json \
    /etc/security/rootasrole.d/policy.json \
    /etc/pam.d/sr \
    /etc/pam.d/dosr \
    /var/run \
    /usr/share/onix/bootstrap/phase5-runtime.txt
  do
    print_path_status "phase5" "$path"
  done
  printf '%s\n' '--- first uutils command links ---'
  sed -n '1,40p' "$MNT/usr/share/onix/packages/uutils-coreutils.commands"
}

activate_bootstrap_policy_unit_tree() {
  local unit_dir="$1"
  local src_dir="$MNT/usr/lib/onix/systemd/system"
  local unit
  local wants="$unit_dir/multi-user.target.wants"

  [[ "$unit_dir" == "$MNT"/nix/store/*/example/systemd/system ||
     "$unit_dir" == "$MNT"/persist/nix/store/*/example/systemd/system ||
     "$unit_dir" == "$MNT"/usr/lib/systemd/system ]] \
    || die "refusing to activate bootstrap policy unit outside image systemd tree: $unit_dir"
  [[ -d "$src_dir" ]] \
    || die "missing package-owned bootstrap unit source dir: /usr/lib/onix/systemd/system"

  install -dm0755 "$unit_dir" "$wants"

  while IFS= read -r unit; do
    [[ -n "$unit" ]] || continue
    install -m0644 "$src_dir/$unit" "$unit_dir/$unit"
    rm -f "$wants/$unit"
    ln -s "../$unit" "$wants/$unit"
    printf 'unit     : %s from /usr/lib/onix/systemd/system/%s\n' \
      "${unit_dir#$MNT}/$unit" "$unit"
    printf 'enable   : %s\n' "${wants#$MNT}/$unit"
  done < <(bootstrap_policy_units)
}

activate_bootstrap_policy_units() {
  local root_unit_dir
  local persist_unit_dir
  local mask_tty

  load_systemd_payload_metadata

  root_unit_dir="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system"
  persist_unit_dir="$MNT/persist$SYSTEMD_PAYLOAD_OUT/example/systemd/system"

  activate_bootstrap_policy_unit_tree "$root_unit_dir"
  if [[ -d "$persist_unit_dir" ]]; then
    activate_bootstrap_policy_unit_tree "$persist_unit_dir"
  fi

  install -dm0755 "$MNT/etc/systemd/system"
  for mask_tty in ttyS0 "$SERIAL_CONSOLE_TTY"; do
    ln -sfn /dev/null "$MNT/etc/systemd/system/serial-getty@$mask_tty.service"
    printf 'mask     : /etc/systemd/system/serial-getty@%s.service -> /dev/null\n' "$mask_tty"
  done
}

verify_bootstrap_policy_image() {
  local src_dir="$MNT/usr/lib/onix/systemd/system"
  local root_unit_dir
  local persist_unit_dir
  local wants
  local unit

  log "verifying Phase 418 bootstrap-policy image install"

  verify_bootstrap_policy_target "$MNT"
  if [[ -f "$MNT/usr/share/onix/bootstrap/native-systemd-stone.txt" ]]; then
    verify_native_systemd_stone_image
    return 0
  elif [[ -f "$MNT/usr/share/onix/bootstrap/systemd-stone.txt" ]]; then
    load_systemd_payload_metadata
    verify_systemd_stone_image
  else
    load_systemd_payload_metadata
    [[ -x "$MNT$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd" ]] \
      || die "Phase 213 systemd payload is missing while verifying bootstrap policy"
    [[ -d "$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system" ]] \
      || die "Phase 213 systemd unit tree is missing while verifying bootstrap policy"
    printf 'legacy  : verified bootstrap policy against Phase 213 systemd tree; Phase 416 proof absent\n'
  fi

  root_unit_dir="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system"
  persist_unit_dir="$MNT/persist$SYSTEMD_PAYLOAD_OUT/example/systemd/system"
  wants="$root_unit_dir/multi-user.target.wants"

  while IFS= read -r unit; do
    [[ -n "$unit" ]] || continue
    cmp -s "$src_dir/$unit" "$root_unit_dir/$unit" \
      || die "active root systemd unit does not match package-owned source: $unit"
    [[ -L "$wants/$unit" ]] \
      || die "active root unit is not enabled: $unit"
    [[ "$(readlink "$wants/$unit")" == "../$unit" ]] \
      || die "active root unit enable symlink target is wrong for $unit"

    if [[ -d "$persist_unit_dir" ]]; then
      cmp -s "$src_dir/$unit" "$persist_unit_dir/$unit" \
        || die "persist systemd unit does not match package-owned source: $unit"
    fi
  done < <(bootstrap_policy_units)

  grep -q 'ONIX Phase 418 bootstrap policy package' \
    "$MNT/usr/share/onix/bootstrap/bootstrap-policy.txt" \
    || die "Phase 418 proof text is missing"
  grep -q 'bootstrap-policy' \
    "$MNT/usr/share/onix/packages/bootstrap-policy.md" \
    || die "bootstrap-policy package note is missing"
}

preview_bootstrap_policy() {
  local root_unit_dir

  if [[ -f "$MNT/usr/share/onix/bootstrap/native-systemd-stone.txt" ]]; then
    root_unit_dir="$MNT/usr/lib/systemd/system"
  else
    load_systemd_payload_metadata
    root_unit_dir="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system"
  fi

  log "bootstrap-policy image preview"
  find \
    "$MNT/usr/lib/onix/bootstrap-serial-shell" \
    "$MNT/usr/lib/onix/bootstrap-network-up" \
    "$MNT/usr/lib/onix/bootstrap-network-proof" \
    "$MNT/usr/lib/onix/bootstrap-remote-inspection-response" \
    "$MNT/usr/lib/onix/bootstrap-ssh-proof" \
    "$MNT/usr/lib/onix/systemd/system/onix-bootstrap-serial-shell.service" \
    "$MNT/usr/lib/onix/systemd/system/onix-bootstrap-network.service" \
    "$MNT/usr/lib/onix/systemd/system/onix-bootstrap-remote-inspection.service" \
    "$MNT/usr/lib/onix/systemd/system/onix-bootstrap-dropbear.service" \
    "$MNT/usr/share/onix/bootstrap/bootstrap-policy.txt" \
    "$MNT/usr/share/onix/packages/bootstrap-policy.md" \
    "$root_unit_dir/onix-bootstrap-serial-shell.service" \
    "$root_unit_dir/onix-bootstrap-network.service" \
    "$root_unit_dir/onix-bootstrap-remote-inspection.service" \
    "$root_unit_dir/onix-bootstrap-dropbear.service" \
    -maxdepth 0 -printf '%M %p -> %l\n' |
    sed "s# $MNT/# /#" |
    sed "s#-> $MNT/#-> /#"

  printf '%s\n' '--- package-owned unit source ExecStart lines ---'
  grep '^ExecStart=' "$MNT"/usr/lib/onix/systemd/system/*.service |
    sed "s#$MNT##"
  printf '%s\n' '--- active unit ExecStart lines ---'
  grep '^ExecStart=' \
    "$root_unit_dir/onix-bootstrap-serial-shell.service" \
    "$root_unit_dir/onix-bootstrap-network.service" \
    "$root_unit_dir/onix-bootstrap-remote-inspection.service" \
    "$root_unit_dir/onix-bootstrap-dropbear.service" |
    sed "s#$MNT##"
  printf '%s\n' '--- bootstrap-policy package note ---'
  sed -n '1,120p' "$MNT/usr/share/onix/packages/bootstrap-policy.md"
}

preview() {
  log "live /etc preview"
  find \
    "$MNT/etc/os-release" \
    "$MNT/etc/issue" \
    "$MNT/etc/motd" \
    "$MNT/etc/fstab" \
    "$MNT/etc/profile" \
    "$MNT/etc/profile.d/onix-path.sh" \
    "$MNT/etc/profile.d/onix-login.sh" \
    "$MNT/etc/hostname" \
    "$MNT/etc/machine-id" \
    "$MNT/usr/share/onix/bootstrap/etc-materialization.txt" \
    -maxdepth 0 -printf '%M %p -> %l\n' |
    sed "s# $MNT/# /#" |
    sed "s#-> $MNT/#-> /#"
}

preview_accounts() {
  log "account policy preview"
  find \
    "$MNT/usr/lib/sysusers.d/onix-base.conf" \
    "$MNT/usr/sbin/nologin" \
    "$MNT/usr/share/defaults/etc/nsswitch.conf" \
    "$MNT/usr/share/defaults/etc/shells" \
    "$MNT/etc/passwd" \
    "$MNT/etc/group" \
    "$MNT/etc/shadow" \
    "$MNT/etc/gshadow" \
    "$MNT/etc/nsswitch.conf" \
    "$MNT/etc/shells" \
    "$MNT/usr/share/onix/bootstrap/account-policy.txt" \
    -maxdepth 0 -printf '%M %p -> %l\n' |
    sed "s# $MNT/# /#" |
    sed "s#-> $MNT/#-> /#"

  printf '%s\n' '--- /etc/passwd ---'
  sed -n '1,40p' "$MNT/etc/passwd"
  printf '%s\n' '--- /etc/group ---'
  sed -n '1,80p' "$MNT/etc/group"
  printf '%s\n' '--- /etc/shadow users (secrets redacted) ---'
  awk -F: '{ print $1 ":<redacted>:" $3 ":" $4 ":" $5 ":" $6 ":" $7 ":" $8 ":" $9 }' "$MNT/etc/shadow"
}

preview_serial_console() {
  local root_unit_dir
  local root_unit
  local root_wants

  root_unit_dir="$(active_systemd_root_unit_dir)"
  root_unit="$root_unit_dir/onix-bootstrap-serial-shell.service"
  root_wants="$root_unit_dir/multi-user.target.wants/onix-bootstrap-serial-shell.service"

  log "serial console preview"
  find \
    "$MNT/bin/busybox" \
    "$MNT/bin/sh" \
    "$MNT/bin/getty" \
    "$MNT/etc/shells" \
    "$MNT/usr/lib/onix/bootstrap-serial-shell" \
    "$root_unit" \
    "$MNT/etc/systemd/system/serial-getty@ttyS0.service" \
    "$MNT/etc/systemd/system/serial-getty@$SERIAL_CONSOLE_TTY.service" \
    "$root_wants" \
    "$MNT/usr/share/onix/bootstrap/serial-console.txt" \
    -maxdepth 0 -printf '%M %p -> %l\n' |
    sed "s# $MNT/# /#" |
    sed "s#-> $MNT/#-> /#"

  printf '%s\n' '--- serial console service ---'
  sed -n '1,120p' "$root_unit"
  printf '%s\n' '--- serial shell wrapper ---'
  sed -n '1,80p' "$MNT/usr/lib/onix/bootstrap-serial-shell"
}

preview_bootstrap_network() {
  local root_unit_dir
  local root_unit
  local root_wants

  root_unit_dir="$(active_systemd_root_unit_dir)"
  root_unit="$root_unit_dir/onix-bootstrap-network.service"
  root_wants="$root_unit_dir/multi-user.target.wants/onix-bootstrap-network.service"

  log "bootstrap networking preview"
  find \
    "$MNT/bin/ifconfig" \
    "$MNT/bin/ip" \
    "$MNT/bin/route" \
    "$MNT/usr/lib/onix/bootstrap-network-up" \
    "$MNT/usr/lib/onix/bootstrap-network-status" \
    "$MNT/usr/lib/onix/bootstrap-network-proof" \
    "$root_unit" \
    "$root_wants" \
    "$MNT/usr/share/onix/bootstrap/networking.txt" \
    -maxdepth 0 -printf '%M %p -> %l\n' |
    sed "s# $MNT/# /#" |
    sed "s#-> $MNT/#-> /#"

  printf '%s\n' '--- bootstrap network service ---'
  sed -n '1,120p' "$root_unit"
  printf '%s\n' '--- bootstrap network-up script ---'
  sed -n '1,180p' "$MNT/usr/lib/onix/bootstrap-network-up"
}

preview_remote_inspection() {
  local root_unit_dir
  local root_unit
  local root_wants

  root_unit_dir="$(active_systemd_root_unit_dir)"
  root_unit="$root_unit_dir/onix-bootstrap-remote-inspection.service"
  root_wants="$root_unit_dir/multi-user.target.wants/onix-bootstrap-remote-inspection.service"

  log "remote inspection preview"
  find \
    "$MNT/bin/nc" \
    "$MNT/bin/netstat" \
    "$MNT/usr/lib/onix/bootstrap-remote-inspection-response" \
    "$MNT/usr/lib/onix/bootstrap-remote-inspection-status" \
    "$MNT/usr/lib/onix/bootstrap-remote-inspection-proof" \
    "$root_unit" \
    "$root_wants" \
    "$MNT/usr/share/onix/bootstrap/remote-inspection.txt" \
    -maxdepth 0 -printf '%M %p -> %l\n' |
    sed "s# $MNT/# /#" |
    sed "s#-> $MNT/#-> /#"

  printf '%s\n' '--- bootstrap remote inspection service ---'
  sed -n '1,120p' "$root_unit"
  printf '%s\n' '--- remote inspection response script ---'
  sed -n '1,80p' "$MNT/usr/lib/onix/bootstrap-remote-inspection-response"
}

preview_ssh_access() {
  local root_unit_dir
  local root_unit
  local root_wants

  root_unit_dir="$(active_systemd_root_unit_dir)"
  root_unit="$root_unit_dir/onix-bootstrap-dropbear.service"
  root_wants="$root_unit_dir/multi-user.target.wants/onix-bootstrap-dropbear.service"

  log "SSH access preview"
  find \
    "$MNT/usr/lib/sysusers.d/onix-ssh.conf" \
    "$MNT/persist/home/$SSH_USER/.ssh/authorized_keys" \
    "$MNT/etc/dropbear/dropbear_ed25519_host_key" \
    "$MNT/usr/lib/onix/bootstrap-ssh-status" \
    "$MNT/usr/lib/onix/bootstrap-ssh-proof" \
    "$root_unit" \
    "$root_wants" \
    "$MNT/usr/share/onix/bootstrap/ssh.txt" \
    -maxdepth 0 -printf '%M %p -> %l\n' |
    sed "s# $MNT/# /#" |
    sed "s#-> $MNT/#-> /#"

  printf '%s\n' '--- bootstrap Dropbear service ---'
  sed -n '1,120p' "$root_unit"
  printf '%s\n' "--- /etc/passwd entry for $SSH_USER ---"
  grep "^$SSH_USER:" "$MNT/etc/passwd"
}

preview_busybox_stone() {
  local root_unit_dir
  local root_unit

  root_unit_dir="$(active_systemd_root_unit_dir)"
  root_unit="$root_unit_dir/onix-bootstrap-serial-shell.service"

  log "busybox image preview"
  find \
    "$MNT/usr/bin/busybox" \
    "$MNT/usr/bin/sh" \
    "$MNT/usr/bin/ifconfig" \
    "$MNT/usr/bin/nc" \
    "$MNT/bin/busybox" \
    "$MNT/bin/sh" \
    "$MNT/bin/ifconfig" \
    "$MNT/bin/nc" \
    "$MNT/usr/share/onix/packages/busybox.applets" \
    "$MNT/usr/share/onix/packages/busybox.md" \
    "$MNT/usr/share/onix/bootstrap/busybox-stone.txt" \
    "$root_unit" \
    -maxdepth 0 -printf '%M %p -> %l\n' |
    sed "s# $MNT/# /#" |
    sed "s#-> $MNT/#-> /#"

  printf '%s\n' '--- /usr/bin/busybox file ---'
  file "$MNT/usr/bin/busybox"
  printf '%s\n' '--- serial console ExecStart ---'
  grep '^ExecStart=' "$root_unit"
  printf '%s\n' '--- first applets in busybox manifest ---'
  sed -n '1,80p' "$MNT/usr/share/onix/packages/busybox.applets"
}

preview_dropbear_stone() {
  local root_unit_dir
  local root_unit

  root_unit_dir="$(active_systemd_root_unit_dir)"
  root_unit="$root_unit_dir/onix-bootstrap-dropbear.service"

  log "dropbear image preview"
  find \
    "$MNT/usr/sbin/dropbear" \
    "$MNT/usr/bin/dropbearkey" \
    "$MNT/usr/share/onix/packages/dropbear.md" \
    "$MNT/etc/dropbear/dropbear_ed25519_host_key" \
    "$MNT/usr/share/onix/bootstrap/dropbear-stone.txt" \
    "$root_unit" \
    -maxdepth 0 -printf '%M %p -> %l\n' |
    sed "s# $MNT/# /#" |
    sed "s#-> $MNT/#-> /#"

  printf '%s\n' '--- /usr/sbin/dropbear file ---'
  file "$MNT/usr/sbin/dropbear"
  printf '%s\n' '--- /usr/bin/dropbearkey file ---'
  file "$MNT/usr/bin/dropbearkey"
  printf '%s\n' '--- Dropbear ExecStart ---'
  grep '^ExecStart=' "$root_unit"
  printf '%s\n' '--- dropbear package note ---'
  sed -n '1,80p' "$MNT/usr/share/onix/packages/dropbear.md"
}

preview_systemd_stone() {
  local root_unit_dir

  load_systemd_payload_metadata
  root_unit_dir="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system"

  log "systemd image preview"
  find \
    "$MNT/usr/lib/systemd/systemd" \
    "$MNT/usr/lib/systemd/system" \
    "$MNT/usr/lib/systemd/user" \
    "$MNT/usr/bin/systemctl" \
    "$MNT/usr/bin/journalctl" \
    "$MNT/usr/bin/systemd-tmpfiles" \
    "$MNT/usr/bin/systemd-sysusers" \
    "$MNT/usr/bin/udevadm" \
    "$MNT/usr/lib/onix/bootstrap$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd" \
    "$MNT$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd" \
    "$MNT/persist$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd" \
    "$MNT/usr/share/onix/packages/systemd.md" \
    "$MNT/usr/share/onix/packages/systemd.closure" \
    "$MNT/usr/share/onix/packages/systemd.links" \
    "$MNT/usr/share/onix/bootstrap/systemd-stone.txt" \
    "$MNT/boot/loader/entries/onix-phase-213.conf" \
    "$root_unit_dir/onix-bootstrap-serial-shell.service" \
    "$root_unit_dir/onix-bootstrap-network.service" \
    "$root_unit_dir/onix-bootstrap-remote-inspection.service" \
    "$root_unit_dir/onix-bootstrap-dropbear.service" \
    -maxdepth 0 -printf '%M %p -> %l\n' |
    sed "s# $MNT/# /#" |
    sed "s#-> $MNT/#-> /#"

  printf '%s\n' '--- /usr/lib/systemd/systemd file ---'
  file "$MNT$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd"
  printf '%s\n' '--- systemd ELF interpreter ---'
  readelf -l "$MNT$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd" |
    sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p'
  printf '%s\n' '--- BLS init line ---'
  grep 'init=/usr/lib/systemd/systemd' "$MNT/boot/loader/entries/onix-phase-213.conf"
  printf '%s\n' '--- active bootstrap unit ExecStart lines ---'
  grep '^ExecStart=' \
    "$root_unit_dir/onix-bootstrap-serial-shell.service" \
    "$root_unit_dir/onix-bootstrap-network.service" \
    "$root_unit_dir/onix-bootstrap-remote-inspection.service" \
    "$root_unit_dir/onix-bootstrap-dropbear.service" |
    sed "s#$MNT##"
  printf '%s\n' '--- systemd package note ---'
  sed -n '1,120p' "$MNT/usr/share/onix/packages/systemd.md"
}

audit_stale_payload_path() {
  local label="$1"
  local file="$2"
  local path

  if [[ ! -f "$file" ]]; then
    printf 'stale    : %s metadata absent (%s)\n' "$label" "${file#$ONIX_ROOT/}"
    return 0
  fi

  path="$(< "$file")"
  if [[ -z "$path" ]]; then
    printf 'stale    : %s metadata empty (%s)\n' "$label" "${file#$ONIX_ROOT/}"
    return 0
  fi

  if [[ -e "$MNT$path" || -e "$MNT/persist$path" ]]; then
    printf 'stale    : %s old Nix payload still present at %s\n' "$label" "$path"
    return 0
  fi

  printf 'stale    : %s old Nix payload path not present in mounted image (%s)\n' "$label" "$path"
}

audit_systemd_ownership() {
  local root_unit_dir
  local serial_unit
  local network_unit
  local dropbear_unit
  local remote_unit
  local systemctl_link
  local systemd_link
  local closure_count

  log "auditing Phase 414 systemd ownership boundary"
  load_systemd_payload_metadata

  [[ "$SYSTEMD_PAYLOAD_OUT" == /nix/store/*-systemd-* ]] \
    || die "systemd payload path is not a Nix systemd output: $SYSTEMD_PAYLOAD_OUT"

  root_unit_dir="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system"
  serial_unit="$root_unit_dir/onix-bootstrap-serial-shell.service"
  network_unit="$root_unit_dir/onix-bootstrap-network.service"
  remote_unit="$root_unit_dir/onix-bootstrap-remote-inspection.service"
  dropbear_unit="$root_unit_dir/onix-bootstrap-dropbear.service"

  [[ -x "$MNT/usr/lib/systemd/systemd" ]] \
    || die "missing active /usr/lib/systemd/systemd"
  [[ -x "$MNT$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd" ]] \
    || die "missing copied Nix systemd binary: $SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd"
  [[ -f "$MNT/boot/loader/entries/onix-phase-213.conf" ]] \
    || die "missing Phase 213 BLS entry"
  grep -q 'init=/usr/lib/systemd/systemd' "$MNT/boot/loader/entries/onix-phase-213.conf" \
    || die "BLS entry does not boot /usr/lib/systemd/systemd"

  systemd_link="$(readlink "$MNT/usr/lib/systemd/systemd" 2>/dev/null || true)"
  [[ "$systemd_link" == "$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd" ]] \
    || die "/usr/lib/systemd/systemd should still point at Nix payload; got: $systemd_link"

  [[ "$(readlink "$MNT/usr/lib/systemd/system")" == "$SYSTEMD_PAYLOAD_OUT/example/systemd/system" ]] \
    || die "/usr/lib/systemd/system should still point at Nix example unit tree"

  systemctl_link="$(readlink "$MNT/usr/bin/systemctl" 2>/dev/null || true)"
  [[ "$systemctl_link" == "$SYSTEMD_PAYLOAD_OUT/bin/systemctl" ]] \
    || die "/usr/bin/systemctl should still point at Nix payload; got: $systemctl_link"

  [[ -f "$serial_unit" ]] || die "missing serial bootstrap unit"
  [[ -f "$network_unit" ]] || die "missing network bootstrap unit"
  [[ -f "$remote_unit" ]] || die "missing remote inspection bootstrap unit"
  [[ -f "$dropbear_unit" ]] || die "missing Dropbear bootstrap unit"

  grep -q '^ExecStart=/usr/bin/busybox sh /usr/lib/onix/bootstrap-serial-shell$' "$serial_unit" \
    || die "serial unit should use busybox"
  grep -q '^ExecStart=/bin/sh /usr/lib/onix/bootstrap-network-up$' "$network_unit" \
    || die "network unit should still use /bin/sh compatibility path"
  grep -q '^ExecStart=/bin/nc -lk -p 6649 -e /usr/lib/onix/bootstrap-remote-inspection-response$' "$remote_unit" \
    || die "remote inspection unit should still use /bin/nc compatibility path"
  grep -q '^ExecStart=/usr/sbin/dropbear ' "$dropbear_unit" \
    || die "Dropbear unit should use dropbear"

  [[ -x "$MNT/usr/bin/busybox" ]] || die "missing busybox payload"
  [[ -x "$MNT/usr/sbin/dropbear" ]] || die "missing dropbear payload"
  [[ -f "$MNT/usr/share/onix/packages/busybox.md" ]] \
    || die "missing busybox package note"
  [[ -f "$MNT/usr/share/onix/packages/dropbear.md" ]] \
    || die "missing dropbear package note"

  closure_count="$(wc -l < "$CLOSURE_LIST" | tr -d '[:space:]')"

  printf 'systemd  : active PID 1 path is /usr/lib/systemd/systemd\n'
  printf 'systemd  : /usr/lib/systemd/systemd -> %s\n' "$systemd_link"
  printf 'systemd  : /usr/lib/systemd/system -> %s\n' "$(readlink "$MNT/usr/lib/systemd/system")"
  printf 'systemd  : /usr/bin/systemctl -> %s\n' "$systemctl_link"
  printf 'closure  : %s entries in %s\n' "$closure_count" "${CLOSURE_LIST#$ONIX_ROOT/}"
  printf 'stone    : /usr/bin/busybox is present from busybox\n'
  printf 'stone    : /usr/sbin/dropbear is present from dropbear\n'
  printf 'unit     : serial ExecStart uses /usr/bin/busybox\n'
  printf 'unit     : dropbear ExecStart uses /usr/sbin/dropbear\n'
  printf 'debt     : systemd, udev, systemctl, kmod/libkmod, util-linux helpers, and musl loader support remain in the Nix systemd closure\n'

  audit_stale_payload_path "BusyBox" "$SERIAL_CONSOLE_PAYLOAD_OUT_FILE"
  audit_stale_payload_path "Dropbear" "$DROPBEAR_PAYLOAD_OUT_FILE"

  printf '%s\n' '--- systemd closure roots ---'
  sed 's#^#- #' "$CLOSURE_LIST" | sed -n '1,80p'
  printf '%s\n' '--- active bootstrap unit ExecStart lines ---'
  grep '^ExecStart=' "$serial_unit" "$network_unit" "$remote_unit" "$dropbear_unit" |
    sed "s#$MNT##"
}

print_path_status() {
  local label="$1"
  local path="$2"

  if [[ -L "$MNT$path" ]]; then
    printf '%-12s: %-58s -> %s\n' "$label" "$path" "$(readlink "$MNT$path")"
  elif [[ -e "$MNT$path" ]]; then
    printf '%-12s: %-58s present\n' "$label" "$path"
  else
    printf '%-12s: %-58s missing\n' "$label" "$path"
  fi
}

print_host_artifact_status() {
  local label="$1"
  local path="$2"

  if [[ -e "$ONIX_ROOT/$path" ]]; then
    printf '%-12s: %-58s present\n' "$label" "$path"
  else
    printf '%-12s: %-58s missing\n' "$label" "$path"
  fi
}

print_unit_match_status() {
  local unit="$1"
  local root_unit="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system/$unit"
  local persist_unit="$MNT/persist$SYSTEMD_PAYLOAD_OUT/example/systemd/system/$unit"
  local source_unit="$MNT/usr/lib/onix/systemd/system/$unit"

  if cmp -s "$source_unit" "$root_unit"; then
    printf 'unit-match : %-58s source == active root unit\n' "$unit"
  else
    printf 'unit-match : %-58s source differs from active root unit\n' "$unit"
  fi

  if [[ -f "$persist_unit" ]]; then
    if cmp -s "$source_unit" "$persist_unit"; then
      printf 'unit-match : %-58s source == active persist unit\n' "$unit"
    else
      printf 'unit-match : %-58s source differs from active persist unit\n' "$unit"
    fi
  fi
}

path_list_contains() {
  local path="$1"
  local list="$2"

  [[ -f "$list" ]] || return 1
  grep -Fxq "$path" "$list"
}

assert_nix_store_path() {
  local path="$1"

  case "$path" in
    /nix/store/*) ;;
    *) die "refusing unsafe non-store path while pruning stale bootstrap payload: $path" ;;
  esac
}

prune_store_path_from_tree() {
  local tree="$1"
  local label="$2"
  local store_path="$3"
  local target="$tree$store_path"

  assert_nix_store_path "$store_path"

  if [[ -e "$target" || -L "$target" ]]; then
    rm -rf --one-file-system "$target"
    printf 'removed  : %-10s %s\n' "$label" "$store_path"
    return 0
  fi

  printf 'absent   : %-10s %s\n' "$label" "$store_path"
}

prune_stale_payload_closure() {
  local label="$1"
  local closure_file="$2"
  local store_path

  if [[ ! -s "$closure_file" ]]; then
    printf 'skip     : %-10s missing closure metadata %s\n' \
      "$label" "${closure_file#$ONIX_ROOT/}"
    return 0
  fi

  while IFS= read -r store_path; do
    [[ -n "$store_path" ]] || continue
    assert_nix_store_path "$store_path"

    if path_list_contains "$store_path" "$CLOSURE_LIST"; then
      printf 'keep     : %-10s %s (shared with active systemd closure)\n' \
        "$label" "$store_path"
      continue
    fi

    prune_store_path_from_tree "$MNT" "root" "$store_path"
    prune_store_path_from_tree "$MNT/persist" "persist" "$store_path"
  done < "$closure_file"
}

assert_old_payload_root_absent() {
  local label="$1"
  local out_file="$2"
  local store_path

  if [[ ! -f "$out_file" ]]; then
    printf 'verify   : %-10s output metadata absent (%s)\n' \
      "$label" "${out_file#$ONIX_ROOT/}"
    return 0
  fi

  store_path="$(< "$out_file")"
  [[ -n "$store_path" ]] || die "$label output metadata is empty: ${out_file#$ONIX_ROOT/}"
  assert_nix_store_path "$store_path"

  if path_list_contains "$store_path" "$CLOSURE_LIST"; then
    printf 'verify   : %-10s output path is shared with systemd closure; kept: %s\n' \
      "$label" "$store_path"
    return 0
  fi

  [[ ! -e "$MNT$store_path" && ! -L "$MNT$store_path" ]] \
    || die "$label old Nix output still exists in root store: $store_path"
  [[ ! -e "$MNT/persist$store_path" && ! -L "$MNT/persist$store_path" ]] \
    || die "$label old Nix output still exists in persist store: $store_path"

  printf 'verify   : %-10s old output removed from root and persist stores: %s\n' \
    "$label" "$store_path"
}

verify_no_old_payload_references() {
  local label="$1"
  local out_file="$2"
  local old_path=""
  local unit_dir="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system"
  local persist_unit_dir="$MNT/persist$SYSTEMD_PAYLOAD_OUT/example/systemd/system"

  if [[ -f "$out_file" ]]; then
    old_path="$(< "$out_file")"
  fi

  [[ -z "$old_path" ]] && return 0
  assert_nix_store_path "$old_path"

  grep -R -F "$old_path" "$MNT/usr/lib/onix/systemd/system" >/dev/null 2>&1 \
    && die "package-owned bootstrap unit source still references old $label path: $old_path"
  grep -R -F "$old_path" "$unit_dir" >/dev/null 2>&1 \
    && die "active root systemd unit tree still references old $label path: $old_path"
  if [[ -d "$persist_unit_dir" ]]; then
    grep -R -F "$old_path" "$persist_unit_dir" >/dev/null 2>&1 \
      && die "active persist systemd unit tree still references old $label path: $old_path"
  fi

  printf 'verify   : no active bootstrap unit references old %s path\n' "$label"
}

write_stale_bootstrap_nix_prune_proof() {
  install -dm0755 "$MNT/usr/share/onix/bootstrap"
  cat > "$MNT/usr/share/onix/bootstrap/stale-bootstrap-nix-prune.txt" <<'EOF'
ONIX Phase 420 stale bootstrap Nix payload prune

Policy:

- BusyBox runtime commands are now provided by busybox.
- Dropbear runtime commands are now provided by dropbear.
- The older bootstrap-only Nix BusyBox/Dropbear output roots are no longer
  allowed to stay in the booted image merely because earlier phases copied them.
- Shared store paths are preserved when they also belong to the active systemd
  closure.

This phase intentionally keeps the active systemd /nix/store closure.

The cleanup is narrow on purpose:

- remove stale BusyBox/Dropbear closure paths from /nix/store when unshared,
- remove the same stale paths from /persist/nix/store when unshared,
- keep any path still listed in the systemd closure metadata.

This is still image-assembly cleanup. It is not the final ONIX garbage
collector, package trigger system, or native systemd packaging split.
EOF
  chmod 0644 "$MNT/usr/share/onix/bootstrap/stale-bootstrap-nix-prune.txt"
  printf 'proof    : /usr/share/onix/bootstrap/stale-bootstrap-nix-prune.txt\n'
}

verify_stale_bootstrap_nix_pruned_image() {
  log "verifying Phase 420 stale bootstrap Nix prune"

  verify_bootstrap_policy_image
  assert_old_payload_root_absent "BusyBox" "$SERIAL_CONSOLE_PAYLOAD_OUT_FILE"
  assert_old_payload_root_absent "Dropbear" "$DROPBEAR_PAYLOAD_OUT_FILE"
  verify_no_old_payload_references "BusyBox" "$SERIAL_CONSOLE_PAYLOAD_OUT_FILE"
  verify_no_old_payload_references "Dropbear" "$DROPBEAR_PAYLOAD_OUT_FILE"

  [[ -x "$MNT$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd" ]] \
    || die "active systemd payload disappeared while pruning stale bootstrap paths"
  [[ -x "$MNT/persist$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd" ]] \
    || die "persist systemd payload disappeared while pruning stale bootstrap paths"
  [[ -f "$MNT/usr/share/onix/bootstrap/stale-bootstrap-nix-prune.txt" ]] \
    || die "Phase 420 prune proof file is missing"
}

preview_stale_bootstrap_nix_prune() {
  printf '\n%s\n' '== Phase 420 stale bootstrap Nix prune result =='
  audit_stale_payload_path "BusyBox" "$SERIAL_CONSOLE_PAYLOAD_OUT_FILE"
  audit_stale_payload_path "Dropbear" "$DROPBEAR_PAYLOAD_OUT_FILE"

  printf '\n%s\n' '== Active stone-owned replacements =='
  print_path_status "stone" "/usr/bin/busybox"
  print_path_status "stone" "/usr/bin/sh"
  print_path_status "stone" "/usr/sbin/dropbear"
  print_path_status "stone" "/usr/bin/dropbearkey"

  printf '\n%s\n' '== systemd Nix store compatibility intentionally kept =='
  print_path_status "systemd" "$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd"
  print_path_status "persist" "/persist$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd"
  print_path_status "package" "/usr/lib/onix/bootstrap$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd"

  printf '\n%s\n' '== Phase 420 conclusion =='
  cat <<'EOF'
removed   : stale old Nix BusyBox/Dropbear output roots are gone from the image.
kept      : shared paths needed by the active systemd closure remain.
kept      : systemd still uses /nix/store compatibility in Phase 4.
next      : continue reducing booted-base debt: activation glue, native systemd dependency ownership, or kernel Phase 3 work.
EOF
}

prune_stale_bootstrap_nix_payloads() {
  log "Phase 420 pruning stale bootstrap Nix BusyBox/Dropbear payloads"
  log "scope     : /nix/store and /persist/nix/store only"
  log "preserve  : every path listed in the active systemd closure"

  mount_boot_partition
  mount_persist_partition
  load_systemd_payload_metadata
  verify_bootstrap_policy_image

  prune_stale_payload_closure "BusyBox" "$SERIAL_CONSOLE_CLOSURE_LIST"
  prune_stale_payload_closure "Dropbear" "$DROPBEAR_CLOSURE_LIST"
  write_stale_bootstrap_nix_prune_proof

  verify_stale_bootstrap_nix_pruned_image
  preview_stale_bootstrap_nix_prune
}

audit_booted_base_ownership() {
  local closure_count
  local systemd_link
  local unit
  local old_path

  log "Phase 419 booted-base ownership audit"
  log "mode      : read-only image mount"

  mount_boot_partition
  mount_persist_partition
  load_systemd_payload_metadata

  verify_bootstrap_policy_image

  closure_count="$(wc -l < "$CLOSURE_LIST" | tr -d '[:space:]')"
  systemd_link="$(readlink "$MNT/usr/lib/systemd/systemd")"

  printf '\n%s\n' '== Stone-owned machine-plane payloads =='
  print_path_status "stone" "/usr/bin/busybox"
  print_path_status "stone" "/usr/bin/sh"
  print_path_status "stone" "/usr/sbin/dropbear"
  print_path_status "stone" "/usr/bin/dropbearkey"
  print_path_status "stone" "/usr/lib/systemd/systemd"
  print_path_status "stone" "/usr/lib/systemd/system"
  print_path_status "stone" "/usr/bin/systemctl"
  print_path_status "stone" "/usr/bin/journalctl"
  print_path_status "stone" "/usr/bin/udevadm"
  print_path_status "stone" "/usr/lib/onix/bootstrap-serial-shell"
  print_path_status "stone" "/usr/lib/onix/bootstrap-network-up"
  print_path_status "stone" "/usr/lib/onix/bootstrap-network-proof"
  print_path_status "stone" "/usr/lib/onix/bootstrap-remote-inspection-response"
  print_path_status "stone" "/usr/lib/onix/bootstrap-ssh-proof"

  printf '\n%s\n' '== Package notes present in the image =='
  print_path_status "package" "/usr/share/onix/packages/busybox.md"
  print_path_status "package" "/usr/share/onix/packages/dropbear.md"
  print_path_status "package" "/usr/share/onix/packages/systemd.md"
  print_path_status "package" "/usr/share/onix/packages/systemd.closure"
  print_path_status "package" "/usr/share/onix/packages/bootstrap-policy.md"

  printf '\n%s\n' '== Active bootstrap units =='
  while IFS= read -r unit; do
    [[ -n "$unit" ]] || continue
    print_path_status "unit-src" "/usr/lib/onix/systemd/system/$unit"
    print_path_status "unit-live" "$SYSTEMD_PAYLOAD_OUT/example/systemd/system/$unit"
    print_unit_match_status "$unit"
  done < <(bootstrap_policy_units)

  printf '\n%s\n' '== Activation glue still present =='
  cat <<EOF
activation : package-owned unit sources are copied into:
activation :   $SYSTEMD_PAYLOAD_OUT/example/systemd/system
activation : enabled symlinks are written under:
activation :   $SYSTEMD_PAYLOAD_OUT/example/systemd/system/multi-user.target.wants
activation : this is still image-assembly glue, not final package trigger/preset flow
EOF

  printf '\n%s\n' '== Nix-built bootstrap debt still present =='
  printf 'nix-built  : systemd payload path        %s\n' "$SYSTEMD_PAYLOAD_OUT"
  printf 'nix-built  : /usr/lib/systemd/systemd -> %s\n' "$systemd_link"
  printf 'nix-built  : runtime closure entries     %s (%s)\n' "$closure_count" "${CLOSURE_LIST#$ONIX_ROOT/}"
  print_path_status "nix-built" "$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd"
  print_path_status "nix-built" "$SYSTEMD_PAYLOAD_OUT/bin/systemctl"
  print_path_status "nix-built" "$SYSTEMD_PAYLOAD_OUT/bin/udevadm"
  print_path_status "bootstrap" "/usr/lib/onix/bootstrap$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd"
  print_path_status "persist" "/persist$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd"

  printf '\n%s\n' '== Old Nix BusyBox/Dropbear payload status =='
  for file in "$SERIAL_CONSOLE_PAYLOAD_OUT_FILE" "$DROPBEAR_PAYLOAD_OUT_FILE"; do
    if [[ -f "$file" ]]; then
      old_path="$(< "$file")"
      if [[ -n "$old_path" && ( -e "$MNT$old_path" || -e "$MNT/persist$old_path" ) ]]; then
        printf 'stale     : %-18s old Nix payload still exists at %s\n' "$(basename "$file" .out)" "$old_path"
      else
        printf 'stale     : %-18s old Nix payload not present in mounted image\n' "$(basename "$file" .out)"
      fi
    else
      printf 'stale     : %-18s metadata file missing\n' "$(basename "$file" .out)"
    fi
  done

  printf '\n%s\n' '== Borrowed kernel/initramfs/module debt =='
  print_host_artifact_status "borrowed" "vm/state/vmlinuz-virt"
  print_host_artifact_status "borrowed" "vm/state/initramfs-virt"
  print_path_status "borrowed" "/usr/lib/modules"
  cat <<'EOF'
borrowed   : Phase 4 still intentionally uses the Alpine virt kernel/initramfs/module payload.
borrowed   : ONIX-owned kernel/initramfs/module work remains reserved for Phase 3.
EOF

  printf '\n%s\n' '== Live machine state that is not package payload =='
  print_path_status "live-state" "/etc/passwd"
  print_path_status "live-state" "/etc/group"
  print_path_status "live-state" "/etc/shadow"
  print_path_status "live-state" "/etc/dropbear/dropbear_ed25519_host_key"
  print_path_status "live-state" "/persist/home/$SSH_USER/.ssh/authorized_keys"
  print_path_status "live-state" "/etc/machine-id"
  cat <<'EOF'
live-state : these files are machine state or materialized policy, not immutable package payload.
EOF

  printf '\n%s\n' '== Current local Phase 4 repo artifact =='
  print_host_artifact_status "repo" "artifacts/onix-local-repo/stone.index"
  print_host_artifact_status "stone" "artifacts/onix-local-repo/busybox-1.37.0-1-1-x86_64.stone"
  print_host_artifact_status "stone" "artifacts/onix-local-repo/dropbear-2025.89-1-1-x86_64.stone"
  print_host_artifact_status "stone" "artifacts/onix-local-repo/systemd-259.3-1-1-x86_64.stone"
  print_host_artifact_status "stone" "artifacts/onix-local-repo/bootstrap-policy-0.1.0-1-1-x86_64.stone"

  printf '\n%s\n' '== Phase 419 conclusion =='
  cat <<EOF
owned-now : BusyBox command payload is stone-owned by busybox.
owned-now : Dropbear SSH payload is stone-owned by dropbear.
owned-now : systemd runtime bytes are package-owned by systemd, but still Nix-built.
owned-now : bootstrap scripts/unit source files are stone-owned by bootstrap-policy.
debt      : active unit activation is still image-assembly glue.
debt      : systemd and its runtime closure are still built by pinned nixpkgs pkgsMusl.systemd.
debt      : /nix/store runtime compatibility remains required for systemd.
debt      : kernel/initramfs/modules remain borrowed from Alpine and belong to Phase 3.
next      : Phase 420 prunes stale old Nix BusyBox/Dropbear paths if present; then continue with activation glue or native systemd dependency ownership.
EOF
}

safe_generated_paths
validate_serial_tty

need_cmd awk
need_cmd blkid
need_cmd cmp
need_cmd find
need_cmd findmnt
need_cmd grep
need_cmd install
need_cmd losetup
need_cmd mkdir
need_cmd mount
need_cmd partprobe
need_cmd readlink
need_cmd rm
need_cmd sed
need_cmd sort
need_cmd sync
need_cmd umount
need_cmd wc

case "${1:-}" in
  --sudoers-check)
    [[ $EUID -eq 0 ]] || die "sudoers check must run through sudo"
    log "sudoers  : passwordless Phase 4 materializer OK"
    exit 0
    ;;
  --cleanup-stale)
    need_root "$@"
    cleanup_stale
    exit 0
    ;;
  --accounts)
    ACTION="accounts"
    ;;
  --serial-console)
    ACTION="serial-console"
    ;;
  --network)
    ACTION="network"
    ;;
  --remote-inspection)
    ACTION="remote-inspection"
    ;;
  --ssh)
    ACTION="ssh"
    ;;
  --busybox-stone)
    ACTION="busybox-stone"
    ;;
  --dropbear-stone)
    ACTION="dropbear-stone"
    ;;
  --systemd-stone)
    ACTION="systemd-stone"
    ;;
  --native-systemd-stone)
    ACTION="native-systemd-stone"
    ;;
  --bootstrap-policy-stone)
    ACTION="bootstrap-policy-stone"
    ;;
  --phase5-runtime)
    ACTION="phase5-runtime"
    ;;
  --booted-base-audit)
    ACTION="booted-base-audit"
    READ_ONLY_MOUNTS=1
    ;;
  --prune-stale-bootstrap-nix)
    ACTION="prune-stale-bootstrap-nix"
    ;;
  --systemd-audit)
    ACTION="systemd-audit"
    ;;
  "")
    ACTION="etc"
    ;;
  *)
    die "unknown option: $1"
    ;;
esac

if [[ "$ACTION" =~ ^(serial-console|network|remote-inspection|ssh)$ && $EUID -ne 0 ]]; then
  prepare_serial_console_payload
fi

if [[ "$ACTION" == "ssh" && $EUID -ne 0 ]]; then
  prepare_dropbear_payload
  ensure_ssh_client_key
fi

if [[ "$ACTION" == "dropbear-stone" && $EUID -ne 0 ]]; then
  ensure_ssh_client_key
fi

need_root "$@"

[[ -f "$IMAGE_RAW" ]] || die "missing ONIX image: ${IMAGE_RAW#$ONIX_ROOT/}; run make phase 205+ first"

if have_stale_mounts || have_stale_loops; then
  die "stale Phase 4 image mounts/loops exist; run make cleanup"
fi

rm -rf "$WORK_DIR"
mkdir -p "$MNT"

trap detach EXIT

log "attaching ONIX image via loop"
DISK_DEV="$(losetup --find --show --partscan "$IMAGE_RAW")"
[[ -n "$DISK_DEV" ]] || die "no free loop device"
partprobe "$DISK_DEV" 2>/dev/null || true
wait_for_partitions

log "verifying root partition"
expect_blkid "$(part_path 3)" "onix-root" "xfs"

log "mounting ONIX root"
mount_image_partition "$(part_path 3)" "$MNT" "xfs"

case "$ACTION" in
  etc)
    log "materializing live /etc from packaged defaults"
    ensure_os_release_link
    refresh_login_defaults
    copy_default_if_missing etc/issue
    copy_default_if_missing etc/motd
    copy_default_if_missing etc/fstab
    copy_default_if_missing etc/profile
    copy_default_if_missing etc/profile.d/onix-path.sh
    ensure_hostname
    ensure_machine_id
    write_proof

    verify_materialization
    preview
    ;;
  accounts)
    log "materializing base account policy with systemd-sysusers"
    ensure_nologin_link
    write_sysusers_policy
    write_account_defaults
    run_sysusers
    copy_default_if_missing etc/nsswitch.conf
    copy_default_if_missing etc/shells
    write_account_proof

    verify_account_policy
    preview_accounts
    ;;
  serial-console)
    log "materializing bootstrap serial root console"
    test -f "$MNT/etc/passwd" || die "missing /etc/passwd; run make phase 402 first"
    grep -q '^root:x:0:0:' "$MNT/etc/passwd" || die "missing root account; run make phase 402 first"
    load_serial_console_payload_metadata
    log "copying BusyBox shell closure into root /nix/store"
    copy_nix_closure_into "$MNT" "$SERIAL_CONSOLE_CLOSURE_LIST"
    log "mounting actual ONIX-PERSIST partition"
    mount_persist_partition
    log "copying BusyBox shell closure into ONIX-PERSIST /nix/store"
    copy_nix_closure_into "$MNT/persist" "$SERIAL_CONSOLE_CLOSURE_LIST"
    install_busybox_shell
    ensure_shells_has_sh
    write_serial_shell_wrapper
    write_serial_console_unit
    write_serial_console_proof

    verify_serial_console
    preview_serial_console
    ;;
  network)
    log "materializing bootstrap QEMU user networking"
    test -x "$MNT/usr/lib/onix/bootstrap-serial-shell" \
      || die "missing bootstrap serial shell; run make phase 403 first"
    load_serial_console_payload_metadata
    log "copying BusyBox shell closure into root /nix/store"
    copy_nix_closure_into "$MNT" "$SERIAL_CONSOLE_CLOSURE_LIST"
    log "mounting actual ONIX-PERSIST partition"
    mount_persist_partition
    log "copying BusyBox shell closure into ONIX-PERSIST /nix/store"
    copy_nix_closure_into "$MNT/persist" "$SERIAL_CONSOLE_CLOSURE_LIST"
    install_busybox_shell
    write_bootstrap_network_scripts
    write_bootstrap_network_unit
    write_bootstrap_network_proof

    verify_bootstrap_network
    preview_bootstrap_network
    ;;
  remote-inspection)
    log "materializing bootstrap remote inspection"
    test -x "$MNT/usr/lib/onix/bootstrap-serial-shell" \
      || die "missing bootstrap serial shell; run make phase 403 first"
    load_serial_console_payload_metadata
    log "copying BusyBox shell closure into root /nix/store"
    copy_nix_closure_into "$MNT" "$SERIAL_CONSOLE_CLOSURE_LIST"
    log "mounting actual ONIX-PERSIST partition"
    mount_persist_partition
    log "copying BusyBox shell closure into ONIX-PERSIST /nix/store"
    copy_nix_closure_into "$MNT/persist" "$SERIAL_CONSOLE_CLOSURE_LIST"
    install_busybox_shell
    write_bootstrap_network_scripts
    write_bootstrap_network_unit
    write_bootstrap_network_proof
    write_remote_inspection_scripts
    write_remote_inspection_unit
    write_remote_inspection_proof

    verify_bootstrap_network
    verify_remote_inspection
    preview_remote_inspection
    ;;
  ssh)
    log "materializing bootstrap SSH access"
    test -x "$MNT/usr/lib/onix/bootstrap-serial-shell" \
      || die "missing bootstrap serial shell; run make phase 403 first"
    load_serial_console_payload_metadata
    load_dropbear_payload_metadata
    log "copying BusyBox shell closure into root /nix/store"
    copy_nix_closure_into "$MNT" "$SERIAL_CONSOLE_CLOSURE_LIST"
    log "copying Dropbear SSH closure into root /nix/store"
    copy_nix_closure_into "$MNT" "$DROPBEAR_CLOSURE_LIST"
    log "mounting actual ONIX-PERSIST partition"
    mount_persist_partition
    log "copying BusyBox shell closure into ONIX-PERSIST /nix/store"
    copy_nix_closure_into "$MNT/persist" "$SERIAL_CONSOLE_CLOSURE_LIST"
    log "copying Dropbear SSH closure into ONIX-PERSIST /nix/store"
    copy_nix_closure_into "$MNT/persist" "$DROPBEAR_CLOSURE_LIST"
    install_busybox_shell
    ensure_shells_has_sh
    write_bootstrap_network_scripts
    write_bootstrap_network_unit
    write_bootstrap_network_proof
    write_ssh_account_policy
    install_ssh_authorized_key
    generate_dropbear_host_key
    write_dropbear_status_scripts
    write_dropbear_unit
    write_ssh_proof

    verify_bootstrap_network
    verify_ssh_access
    preview_ssh_access
    ;;
  busybox-stone)
    log "installing and activating busybox from the ONIX image package repo"
    test -x "$MNT/usr/lib/onix/bootstrap-serial-shell" \
      || die "missing bootstrap serial shell; run make phase 403 first"
    test -f "$MNT/usr/lib/onix/bootstrap-network-up" \
      || die "missing bootstrap network scripts; run make phase 404 first"
    test -f "$MNT/usr/lib/onix/bootstrap-ssh-status" \
      || die "missing bootstrap SSH scripts; run make phase 406 first"

    log "mounting actual ONIX-PERSIST partition"
    mount_persist_partition
    install_busybox_stone_payload
    install_stone_busybox_compat_links
    ensure_shells_has_sh
    rewrite_serial_unit_to_stone_busybox
    write_busybox_stone_proof

    verify_busybox_stone_image
    preview_busybox_stone
    ;;
  dropbear-stone)
    log "installing and activating dropbear from the ONIX image package repo"
    test -x "$MNT/usr/lib/onix/bootstrap-serial-shell" \
      || die "missing bootstrap serial shell; run make phase 403 first"
    test -x "$MNT/usr/bin/busybox" \
      || die "missing busybox /usr/bin/busybox; run make phase 410 first"
    test -f "$MNT/usr/share/onix/bootstrap/busybox-stone.txt" \
      || die "missing busybox proof; run make phase 410 first"

    log "mounting actual ONIX-PERSIST partition"
    mount_persist_partition
    install_dropbear_stone_payload
    ensure_shells_has_sh
    write_bootstrap_network_scripts
    write_bootstrap_network_unit
    write_bootstrap_network_proof
    write_ssh_account_policy
    install_ssh_authorized_key
    generate_stone_dropbear_host_key
    write_dropbear_status_scripts
    write_stone_dropbear_unit
    write_dropbear_stone_proof

    verify_bootstrap_network
    verify_dropbear_stone_image
    preview_dropbear_stone
    ;;
  systemd-stone)
    log "installing and activating systemd from the ONIX image package repo"
    test -x "$MNT/usr/bin/busybox" \
      || die "missing busybox /usr/bin/busybox; run make phase 410 first"
    test -x "$MNT/usr/sbin/dropbear" \
      || die "missing dropbear /usr/sbin/dropbear; run make phase 413 first"
    test -f "$MNT/usr/share/onix/bootstrap/dropbear-stone.txt" \
      || die "missing dropbear proof; run make phase 413 first"

    log "mounting ONIX-BOOT partition for BLS verification"
    mount_boot_partition
    log "mounting actual ONIX-PERSIST partition"
    mount_persist_partition
    install_systemd_stone_payload
    materialize_systemd_bootstrap_store
    write_systemd_stone_proof

    verify_systemd_stone_image
    preview_systemd_stone
    ;;
  native-systemd-stone)
    log "installing and activating native systemd from the ONIX image package repo"
    test -x "$MNT/usr/bin/busybox" \
      || die "missing busybox /usr/bin/busybox; run make phase 410 first"
    test -x "$MNT/usr/sbin/dropbear" \
      || die "missing dropbear /usr/sbin/dropbear; run make phase 413 first"
    test -f "$MNT/usr/share/onix/bootstrap/bootstrap-policy.txt" \
      || die "missing bootstrap-policy proof; run make phase 418 first"

    refresh_login_defaults
    log "mounting ONIX-BOOT partition for BLS verification"
    mount_boot_partition
    log "mounting actual ONIX-PERSIST partition"
    mount_persist_partition
    load_systemd_payload_metadata_if_present
    install_native_systemd_stone_payload
    ensure_bootstrap_policy_dropbear_no_motd
    activate_bootstrap_policy_units_native
    prune_systemd_bootstrap_nix_payloads
    write_native_systemd_stone_proof

    verify_native_systemd_stone_image
    preview_native_systemd_stone
    ;;
  bootstrap-policy-stone)
    log "installing and activating bootstrap-policy from the ONIX image package repo"
    test -x "$MNT/usr/bin/busybox" \
      || die "missing busybox /usr/bin/busybox; run make phase 410 first"
    test -x "$MNT/usr/sbin/dropbear" \
      || die "missing dropbear /usr/sbin/dropbear; run make phase 413 first"
    if [[ -f "$MNT/usr/share/onix/bootstrap/native-systemd-stone.txt" ]]; then
      printf 'native   : activating bootstrap policy on native /usr/lib/systemd/system tree\n'
    elif [[ ! -f "$MNT/usr/share/onix/bootstrap/systemd-stone.txt" ]]; then
      load_systemd_payload_metadata
      printf 'legacy  : activating bootstrap policy on Phase 213 systemd tree; Phase 416 proof absent\n'
    fi

    log "mounting ONIX-BOOT partition for BLS verification"
    mount_boot_partition
    log "mounting actual ONIX-PERSIST partition"
    mount_persist_partition
    install_bootstrap_policy_stone_payload
    ensure_bootstrap_policy_dropbear_no_motd
    if [[ -f "$MNT/usr/share/onix/bootstrap/native-systemd-stone.txt" ]]; then
      activate_bootstrap_policy_units_native
    else
      activate_bootstrap_policy_units
    fi

    verify_bootstrap_policy_image
    preview_bootstrap_policy
    ;;
  phase5-runtime)
    log "installing and activating the Phase 5 runtime package set"
    test -x "$MNT/usr/bin/busybox" \
      || die "missing busybox /usr/bin/busybox; run make phase 410 first"
    test -x "$MNT/usr/sbin/dropbear" \
      || die "missing dropbear /usr/sbin/dropbear; run make phase 413 first"
    test -f "$MNT/usr/share/onix/bootstrap/native-systemd-stone.txt" \
      || die "missing native systemd proof; run make phase 422 first"

    mount_persist_partition
    install_phase5_runtime_payload
    preview_phase5_runtime
    ;;
  booted-base-audit)
    audit_booted_base_ownership
    ;;
  prune-stale-bootstrap-nix)
    prune_stale_bootstrap_nix_payloads
    ;;
  systemd-audit)
    log "auditing current image ownership before systemd"
    mount_boot_partition
    mount_persist_partition
    audit_systemd_ownership
    ;;
  *)
    die "internal error: unknown action $ACTION"
    ;;
esac
sync

log "success"
echo "image : $IMAGE_RAW"
case "$ACTION" in
  etc) echo "status: live /etc materialization policy applied" ;;
  accounts) echo "status: base account policy materialized; authenticated login proof is still later" ;;
  serial-console) echo "status: bootstrap serial root console installed and ready for probe" ;;
  network) echo "status: bootstrap QEMU user networking installed and ready for probe" ;;
  remote-inspection) echo "status: bootstrap remote inspection installed and ready for probe" ;;
  ssh) echo "status: bootstrap SSH access installed and ready for probe" ;;
  busybox-stone) echo "status: busybox stone is installed and active for /bin compatibility links" ;;
  dropbear-stone) echo "status: dropbear stone is installed and active for bootstrap SSH" ;;
  systemd-stone) echo "status: systemd stone is installed and materialized for PID 1 runtime paths" ;;
  native-systemd-stone) echo "status: native systemd stone is installed and active as the PID 1 runtime" ;;
  bootstrap-policy-stone) echo "status: bootstrap-policy owns bootstrap scripts/unit sources and active units match it" ;;
  phase5-runtime) echo "status: Phase 5 runtime package set is installed and active in the image" ;;
  booted-base-audit) echo "status: booted-base ownership audit complete; no image mutations performed" ;;
  prune-stale-bootstrap-nix) echo "status: stale old Nix BusyBox/Dropbear payloads pruned; systemd closure preserved" ;;
  systemd-audit) echo "status: systemd ownership boundary audited; systemd remains next package target" ;;
esac
