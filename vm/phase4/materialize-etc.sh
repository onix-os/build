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
# Phase 410 consumes the locally built onix-busybox stone from the Phase 4 local
# moss repo. It makes /usr/bin/busybox package-owned and leaves /bin as an image
# compatibility layer for the bootstrap scripts that still call /bin/sh, /bin/nc,
# /bin/ifconfig, and friends.
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
HOST_MOSS="${ONIX_HOST_MOSS:-$ONIX_ROOT/artifacts/host-tools/bin/moss}"
BUSYBOX_MOSS_ROOT="$WORK_DIR/busybox-moss-root"
BUSYBOX_MOSS_CACHE="$WORK_DIR/busybox-moss-cache"
BUSYBOX_INSTALL_TARGET="$WORK_DIR/busybox-install-target"
MNT="$WORK_DIR/mnt"
DISK_DEV=""
ACTION="etc"

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
  case "$LOCAL_REPO_DIR" in
    "$ONIX_ROOT"/artifacts/onix-local-repo) ;;
    "$ONIX_ROOT"/artifacts/onix-local-repo/*) ;;
    *) die "refusing unsafe local repo path outside artifacts/onix-local-repo: $LOCAL_REPO_DIR" ;;
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
      ONIX_SSH_CLIENT_PUB ONIX_STATE_DIR ONIX_LOCAL_REPO_DIR ONIX_HOST_MOSS \
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
  install -dm0755 "$MNT/persist"

  if findmnt "$MNT/persist" >/dev/null 2>&1; then
    return 0
  fi

  mount "$persist_dev" "$MNT/persist"
  printf 'mount    : ONIX-PERSIST -> /persist\n'
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
poweroff
ps
pwd
reboot
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

  [[ -x "$target/usr/bin/busybox" ]] \
    || die "onix-busybox target is missing /usr/bin/busybox: $target"

  interp="$(readelf -l "$target/usr/bin/busybox" 2>/dev/null |
    sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p' |
    head -n1)"
  [[ -z "$interp" ]] \
    || die "onix-busybox should be static for this bootstrap phase; interpreter=$interp"

  "$target/usr/bin/busybox" true
  "$target/usr/bin/busybox" sh -c 'echo onix-busybox shell works' >/dev/null

  while IFS= read -r applet; do
    [[ -n "$applet" ]] || continue
    "$target/usr/bin/busybox" --list | grep -qx "$applet" \
      || die "onix-busybox is missing applet: $applet"
    [[ -e "$target/usr/bin/$applet" ]] \
      || die "onix-busybox install target is missing /usr/bin/$applet"
  done < <(bootstrap_busybox_applets)

  [[ -f "$target/usr/share/onix/packages/onix-busybox.applets" ]] \
    || die "onix-busybox install target is missing applet manifest"
  [[ -f "$target/usr/share/onix/packages/onix-busybox.md" ]] \
    || die "onix-busybox install target is missing package note"
}

install_busybox_stone_payload() {
  [[ -x "$HOST_MOSS" ]] \
    || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run make phase 202)"
  [[ -f "$LOCAL_REPO_DIR/stone.index" ]] \
    || die "missing local Phase 4 repo index: ${LOCAL_REPO_DIR#$ONIX_ROOT/}/stone.index (run make phase 409)"

  need_cmd readelf
  need_cmd tar
  need_cmd file

  log "materializing onix-busybox from local moss repo into a scratch target"
  rm -rf "$BUSYBOX_MOSS_ROOT" "$BUSYBOX_MOSS_CACHE" "$BUSYBOX_INSTALL_TARGET"
  install -dm0755 "$BUSYBOX_MOSS_ROOT" "$BUSYBOX_MOSS_CACHE" "$BUSYBOX_INSTALL_TARGET"

  "$HOST_MOSS" -D "$BUSYBOX_MOSS_ROOT" --cache "$BUSYBOX_MOSS_CACHE" \
    repo add onix-local "file://$LOCAL_REPO_DIR/stone.index" \
    -c "ONIX Phase 4 local repo" >/dev/null
  "$HOST_MOSS" -D "$BUSYBOX_MOSS_ROOT" --cache "$BUSYBOX_MOSS_CACHE" \
    repo update >/dev/null
  "$HOST_MOSS" -D "$BUSYBOX_MOSS_ROOT" --cache "$BUSYBOX_MOSS_CACHE" \
    -y install --to "$BUSYBOX_INSTALL_TARGET" onix-busybox

  verify_busybox_stone_target "$BUSYBOX_INSTALL_TARGET"

  log "copying onix-busybox package payload into the ONIX image"
  install -dm0755 "$MNT/usr"
  tar --numeric-owner -C "$BUSYBOX_INSTALL_TARGET" -cpf - \
    usr/bin \
    usr/share/onix/packages \
    | tar --numeric-owner -C "$MNT" -xpf -

  verify_busybox_stone_target "$MNT"
  printf 'stone    : onix-busybox installed under /usr/bin\n'
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
    done < <(bootstrap_busybox_applets)

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
  done < <(bootstrap_busybox_applets)

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
  local root_unit
  local persist_unit

  load_systemd_payload_metadata
  root_unit="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system/onix-bootstrap-serial-shell.service"
  persist_unit="$MNT/persist$SYSTEMD_PAYLOAD_OUT/example/systemd/system/onix-bootstrap-serial-shell.service"

  rewrite_serial_unit_to_stone_busybox_one "$root_unit"
  if [[ -f "$persist_unit" ]]; then
    rewrite_serial_unit_to_stone_busybox_one "$persist_unit"
  fi
}

write_busybox_stone_proof() {
  install -dm0755 "$MNT/usr/share/onix/bootstrap"
  cat > "$MNT/usr/share/onix/bootstrap/busybox-stone.txt" <<'EOF'
ONIX Phase 410 onix-busybox image install

Policy:

- BusyBox is machine-plane software.
- Machine-plane software should come from moss/.stone packages.
- Phase 410 consumes onix-busybox from the local Phase 4 moss repo.
- The package-owned payload lives under /usr/bin.
- /bin remains an image compatibility layer for early bootstrap scripts.

Installed package-owned payload:

- /usr/bin/busybox
- /usr/bin/sh
- /usr/bin/ifconfig
- /usr/bin/ip
- /usr/bin/nc
- /usr/share/onix/packages/onix-busybox.applets
- /usr/share/onix/packages/onix-busybox.md

Compatibility links:

- If the image uses merged-/usr, /bin itself points at /usr/bin.
- Otherwise /bin/busybox points at ../usr/bin/busybox and applets point at
  busybox.
- In either layout, /bin/sh, /bin/nc, and /bin/ifconfig resolve to the
  onix-busybox payload.

Important limitation:

Phase 410 intentionally does not garbage-collect the older Nix BusyBox closure
yet. The active shell/network command path now points at onix-busybox, but the
old copied closure may still exist on disk until the later no-Nix-payload audit.

The next phase should boot the image again and prove that shell, networking, and
SSH still work with the stone-provided BusyBox.
EOF
  chmod 0644 "$MNT/usr/share/onix/bootstrap/busybox-stone.txt"
  printf 'proof    : /usr/share/onix/bootstrap/busybox-stone.txt\n'
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
     "$unit_dir" == "$MNT"/persist/nix/store/*/example/systemd/system ]] \
    || die "refusing to write systemd unit outside image Nix unit tree: $unit_dir"

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

  load_systemd_payload_metadata

  root_unit_dir="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system"
  persist_unit_dir="$MNT/persist$SYSTEMD_PAYLOAD_OUT/example/systemd/system"

  write_serial_console_unit_tree "$root_unit_dir"
  if [[ -d "$persist_unit_dir" ]]; then
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
     "$unit_dir" == "$MNT"/persist/nix/store/*/example/systemd/system ]] \
    || die "refusing to write systemd unit outside image Nix unit tree: $unit_dir"

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

  load_systemd_payload_metadata

  root_unit_dir="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system"
  persist_unit_dir="$MNT/persist$SYSTEMD_PAYLOAD_OUT/example/systemd/system"

  write_bootstrap_network_unit_tree "$root_unit_dir"
  if [[ -d "$persist_unit_dir" ]]; then
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
     "$unit_dir" == "$MNT"/persist/nix/store/*/example/systemd/system ]] \
    || die "refusing to write systemd unit outside image Nix unit tree: $unit_dir"

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

  load_systemd_payload_metadata

  root_unit_dir="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system"
  persist_unit_dir="$MNT/persist$SYSTEMD_PAYLOAD_OUT/example/systemd/system"

  write_remote_inspection_unit_tree "$root_unit_dir"
  if [[ -d "$persist_unit_dir" ]]; then
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
     "$unit_dir" == "$MNT"/persist/nix/store/*/example/systemd/system ]] \
    || die "refusing to write systemd unit outside image Nix unit tree: $unit_dir"

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
ExecStart=$DROPBEAR_PAYLOAD_OUT/bin/dropbear -F -E -e -s -w -j -k -p 0.0.0.0:22 -r /etc/dropbear/dropbear_ed25519_host_key -P /run/dropbear.pid
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

  load_systemd_payload_metadata
  load_dropbear_payload_metadata

  root_unit_dir="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system"
  persist_unit_dir="$MNT/persist$SYSTEMD_PAYLOAD_OUT/example/systemd/system"

  write_dropbear_unit_tree "$root_unit_dir"
  if [[ -d "$persist_unit_dir" ]]; then
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
  test -f "$MNT/usr/share/defaults/etc/profile.d/onix-path.sh"

  test -f "$MNT/etc/issue"
  test -f "$MNT/etc/motd"
  test -f "$MNT/etc/fstab"
  test -f "$MNT/etc/profile.d/onix-path.sh"
  test -f "$MNT/etc/hostname"
  test -f "$MNT/etc/machine-id"

  grep -q 'LABEL=ONIX-ESP' "$MNT/etc/fstab"
  grep -q 'LABEL=ONIX-BOOT' "$MNT/etc/fstab"
  grep -q 'LABEL=onix-root' "$MNT/etc/fstab"
  grep -q 'LABEL=ONIX-PERSIST' "$MNT/etc/fstab"
  grep -q 'export PATH' "$MNT/etc/profile.d/onix-path.sh"
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
  local root_unit
  local root_wants

  log "verifying Phase 403 bootstrap serial console"

  load_serial_console_payload_metadata
  load_systemd_payload_metadata
  root_unit="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system/onix-bootstrap-serial-shell.service"
  root_wants="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system/multi-user.target.wants/onix-bootstrap-serial-shell.service"

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
    || die "missing onix-bootstrap-serial-shell systemd unit in copied Nix unit tree"
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
    || die "serial console service is not enabled in copied Nix multi-user.target.wants"
  [[ "$(readlink "$root_wants")" == "../onix-bootstrap-serial-shell.service" ]] \
    || die "serial console enable symlink target is wrong"

  grep -q 'ONIX_BOOTSTRAP_SERIAL_CONSOLE_READY' "$MNT/usr/share/onix/bootstrap/serial-console.txt" \
    || die "serial console proof file does not record the ready marker"
  grep -q 'unauthenticated and temporary' "$MNT/usr/lib/onix/bootstrap-serial-shell" \
    || die "serial shell wrapper does not warn about temporary unauthenticated access"
}

verify_bootstrap_network() {
  local root_unit
  local root_wants
  local persist_unit

  log "verifying Phase 404 bootstrap networking"

  load_systemd_payload_metadata
  root_unit="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system/onix-bootstrap-network.service"
  root_wants="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system/multi-user.target.wants/onix-bootstrap-network.service"
  persist_unit="$MNT/persist$SYSTEMD_PAYLOAD_OUT/example/systemd/system/onix-bootstrap-network.service"

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
    || die "missing onix-bootstrap-network systemd unit in copied Nix unit tree"
  grep -q '^ExecStart=/bin/sh /usr/lib/onix/bootstrap-network-up$' "$root_unit" \
    || die "bootstrap network unit ExecStart is wrong"
  [[ -L "$root_wants" ]] \
    || die "bootstrap network service is not enabled in copied Nix multi-user.target.wants"
  [[ "$(readlink "$root_wants")" == "../onix-bootstrap-network.service" ]] \
    || die "bootstrap network enable symlink target is wrong"

  if [[ -d "$(dirname "$persist_unit")" ]]; then
    [[ -f "$persist_unit" ]] \
      || die "missing onix-bootstrap-network unit in ONIX-PERSIST Nix unit tree"
  fi

  grep -q 'ONIX_NETWORK_OK' "$MNT/usr/share/onix/bootstrap/networking.txt" \
    || die "networking proof file does not record the proof marker"
}

verify_remote_inspection() {
  local root_unit
  local root_wants
  local persist_unit

  log "verifying Phase 405 bootstrap remote inspection"

  load_systemd_payload_metadata
  root_unit="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system/onix-bootstrap-remote-inspection.service"
  root_wants="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system/multi-user.target.wants/onix-bootstrap-remote-inspection.service"
  persist_unit="$MNT/persist$SYSTEMD_PAYLOAD_OUT/example/systemd/system/onix-bootstrap-remote-inspection.service"

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
    || die "missing onix-bootstrap-remote-inspection systemd unit in copied Nix unit tree"
  grep -q '^ExecStart=/bin/nc -lk -p 6649 -e /usr/lib/onix/bootstrap-remote-inspection-response$' "$root_unit" \
    || die "remote inspection unit ExecStart is wrong"
  [[ -L "$root_wants" ]] \
    || die "remote inspection service is not enabled in copied Nix multi-user.target.wants"
  [[ "$(readlink "$root_wants")" == "../onix-bootstrap-remote-inspection.service" ]] \
    || die "remote inspection enable symlink target is wrong"

  if [[ -d "$(dirname "$persist_unit")" ]]; then
    [[ -f "$persist_unit" ]] \
      || die "missing remote inspection unit in ONIX-PERSIST Nix unit tree"
  fi

  grep -q 'ONIX_REMOTE_INSPECTION_OK' "$MNT/usr/share/onix/bootstrap/remote-inspection.txt" \
    || die "remote inspection proof file does not record the proof marker"
  grep -q 'unauthenticated and temporary' "$MNT/usr/share/onix/bootstrap/remote-inspection.txt" \
    || die "remote inspection proof file does not record the security limitation"
}

verify_ssh_access() {
  local root_unit
  local root_wants
  local persist_unit

  log "verifying Phase 406 bootstrap SSH"

  load_systemd_payload_metadata
  load_dropbear_payload_metadata
  root_unit="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system/onix-bootstrap-dropbear.service"
  root_wants="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system/multi-user.target.wants/onix-bootstrap-dropbear.service"
  persist_unit="$MNT/persist$SYSTEMD_PAYLOAD_OUT/example/systemd/system/onix-bootstrap-dropbear.service"

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
    || die "missing onix-bootstrap-dropbear systemd unit in copied Nix unit tree"
  grep -q ' -s ' "$root_unit" \
    || die "Dropbear unit should disable password logins with -s"
  grep -q ' -w ' "$root_unit" \
    || die "Dropbear unit should disable root logins with -w"
  grep -q '^ExecStart=.*/bin/dropbear .* -p 0.0.0.0:22 ' "$root_unit" \
    || die "Dropbear unit ExecStart is wrong"
  [[ -L "$root_wants" ]] \
    || die "Dropbear service is not enabled in copied Nix multi-user.target.wants"
  [[ "$(readlink "$root_wants")" == "../onix-bootstrap-dropbear.service" ]] \
    || die "Dropbear enable symlink target is wrong"

  if [[ -d "$(dirname "$persist_unit")" ]]; then
    [[ -f "$persist_unit" ]] \
      || die "missing Dropbear unit in ONIX-PERSIST Nix unit tree"
  fi

  grep -q "ONIX_SSH_OK user=$SSH_USER uid=$SSH_UID" "$MNT/usr/share/onix/bootstrap/ssh.txt" \
    || die "SSH proof file does not record the proof marker"
  grep -q 'Password authentication is disabled' "$MNT/usr/share/onix/bootstrap/ssh.txt" \
    || die "SSH proof file does not record password-auth policy"
}

verify_busybox_stone_image() {
  local applet
  local bin_target
  local root_unit
  local persist_unit

  log "verifying Phase 410 onix-busybox image install"

  load_systemd_payload_metadata
  root_unit="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system/onix-bootstrap-serial-shell.service"
  persist_unit="$MNT/persist$SYSTEMD_PAYLOAD_OUT/example/systemd/system/onix-bootstrap-serial-shell.service"

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
    || die "missing serial console unit in copied Nix unit tree"
  grep -q '^ExecStart=/usr/bin/busybox sh /usr/lib/onix/bootstrap-serial-shell$' "$root_unit" \
    || die "serial console unit should now execute /usr/bin/busybox"
  if [[ -f "$persist_unit" ]]; then
    grep -q '^ExecStart=/usr/bin/busybox sh /usr/lib/onix/bootstrap-serial-shell$' "$persist_unit" \
      || die "persist serial console unit should now execute /usr/bin/busybox"
  fi

  grep -qx '/bin/sh' "$MNT/etc/shells" \
    || die "/etc/shells does not list /bin/sh"
  grep -q 'ONIX Phase 410 onix-busybox image install' \
    "$MNT/usr/share/onix/bootstrap/busybox-stone.txt" \
    || die "BusyBox stone proof file is missing"
}

preview() {
  log "live /etc preview"
  find \
    "$MNT/etc/os-release" \
    "$MNT/etc/issue" \
    "$MNT/etc/motd" \
    "$MNT/etc/fstab" \
    "$MNT/etc/profile.d/onix-path.sh" \
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
  local root_unit
  local root_wants

  load_systemd_payload_metadata
  root_unit="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system/onix-bootstrap-serial-shell.service"
  root_wants="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system/multi-user.target.wants/onix-bootstrap-serial-shell.service"

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
  local root_unit
  local root_wants

  load_systemd_payload_metadata
  root_unit="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system/onix-bootstrap-network.service"
  root_wants="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system/multi-user.target.wants/onix-bootstrap-network.service"

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
  local root_unit
  local root_wants

  load_systemd_payload_metadata
  root_unit="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system/onix-bootstrap-remote-inspection.service"
  root_wants="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system/multi-user.target.wants/onix-bootstrap-remote-inspection.service"

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
  local root_unit
  local root_wants

  load_systemd_payload_metadata
  root_unit="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system/onix-bootstrap-dropbear.service"
  root_wants="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system/multi-user.target.wants/onix-bootstrap-dropbear.service"

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
  local root_unit

  load_systemd_payload_metadata
  root_unit="$MNT$SYSTEMD_PAYLOAD_OUT/example/systemd/system/onix-bootstrap-serial-shell.service"

  log "onix-busybox image preview"
  find \
    "$MNT/usr/bin/busybox" \
    "$MNT/usr/bin/sh" \
    "$MNT/usr/bin/ifconfig" \
    "$MNT/usr/bin/nc" \
    "$MNT/bin/busybox" \
    "$MNT/bin/sh" \
    "$MNT/bin/ifconfig" \
    "$MNT/bin/nc" \
    "$MNT/usr/share/onix/packages/onix-busybox.applets" \
    "$MNT/usr/share/onix/packages/onix-busybox.md" \
    "$MNT/usr/share/onix/bootstrap/busybox-stone.txt" \
    "$root_unit" \
    -maxdepth 0 -printf '%M %p -> %l\n' |
    sed "s# $MNT/# /#" |
    sed "s#-> $MNT/#-> /#"

  printf '%s\n' '--- /usr/bin/busybox file ---'
  file "$MNT/usr/bin/busybox"
  printf '%s\n' '--- serial console ExecStart ---'
  grep '^ExecStart=' "$root_unit"
  printf '%s\n' '--- first applets in onix-busybox manifest ---'
  sed -n '1,80p' "$MNT/usr/share/onix/packages/onix-busybox.applets"
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
mount "$(part_path 3)" "$MNT"

case "$ACTION" in
  etc)
    log "materializing live /etc from packaged defaults"
    ensure_os_release_link
    copy_default_if_missing etc/issue
    copy_default_if_missing etc/motd
    copy_default_if_missing etc/fstab
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
    log "installing and activating onix-busybox from the local Phase 4 repo"
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
  busybox-stone) echo "status: onix-busybox stone is installed and active for /bin compatibility links" ;;
esac
