#!/usr/bin/env bash
# vm/phase0/config.sh — single source of truth for the ONIX "forge" VM (quarry).
#
# SOURCED by the other scripts; never runs QEMU itself. Everything is
# overridable from the environment, e.g.:  VM_RAM=8G VM_CPUS=8 ./launch.sh
#
# WHAT THIS IS: a minimal, musl-based Alpine VM built from scratch out of the
# 3.7 MB minirootfs tarball. It is the *forge* where we build AerynOS's tooling
# — moss (atomic package/state manager) + boulder (the .stone builder) — and
# cut our first musl .stone. Alpine is throwaway scaffolding; the endgame is our
# own musl distro managed by moss. Names/numbers come from ONIX.md §0.

# --- resolve paths (independent of the caller's CWD) --------------------------
ONIX_PHASE0_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONIX_VM_DIR="$(cd "$ONIX_PHASE0_DIR/.." && pwd)"
ONIX_ROOT="$(cd "$ONIX_VM_DIR/.." && pwd)"

DOWNLOAD_DIR="${ONIX_DOWNLOAD_DIR:-$ONIX_VM_DIR/downloads}"   # tarballs (gitignored)
STATE_DIR="${ONIX_STATE_DIR:-$ONIX_VM_DIR/state}"            # disk, NVRAM, ssh key, kernel (gitignored)

# --- identity (ONIX.md §0) ----------------------------------------------------
ONIX_MAGIC=6649                   # "ONIX" on a phone keypad
VM_NAME="${VM_NAME:-quarry}"      # the forge hostname — where onix gets cut
BUILD_USER="${BUILD_USER:-mason}"  # non-root user that runs boulder/moss (needs subuid/subgid)

# --- Alpine musl seed (pinned for reproducibility) ---------------------------
ALPINE_VERSION="${ALPINE_VERSION:-3.24.1}"
ALPINE_BRANCH="${ALPINE_BRANCH:-v3.24}"     # repo dir (major.minor)
ALPINE_ARCH="${ALPINE_ARCH:-x86_64}"
ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine}"
ROOTFS_NAME="alpine-minirootfs-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz"
ROOTFS_URL="${ALPINE_MIRROR}/${ALPINE_BRANCH}/releases/${ALPINE_ARCH}/${ROOTFS_NAME}"
ROOTFS_SHA256="41f73e3cf5fa919b8aa5ca6b30dc48f0da2720776d7423e2a7748211456fe081"
ROOTFS_PATH="$DOWNLOAD_DIR/$ROOTFS_NAME"
# apk repositories written into the image (pinned to the same branch)
APK_REPO_MAIN="${ALPINE_MIRROR}/${ALPINE_BRANCH}/main"
APK_REPO_COMMUNITY="${ALPINE_MIRROR}/${ALPINE_BRANCH}/community"

KERNEL_FLAVOR="${KERNEL_FLAVOR:-virt}"      # linux-virt: smallest VM-tuned Alpine kernel

# --- AerynOS tooling pin ------------------------------------------------------
# Pinned for reproducibility; override OS_TOOLS_REF only when intentionally
# rebasing the forge to a newer os-tools snapshot.
OS_TOOLS_REPO="${OS_TOOLS_REPO:-https://github.com/AerynOS/os-tools.git}"
OS_TOOLS_REF="${OS_TOOLS_REF:-36f78e5bcfa9d594d65d1c6d2e332e950f3e4d0e}"

# --- VM resources (a Rust build host wants cores + RAM) ----------------------
VM_CPUS="${VM_CPUS:-6}"
VM_RAM="${VM_RAM:-6G}"
DISK_SIZE="${DISK_SIZE:-20G}"      # sparse raw image; room for rust builds + .stone output
DISK_FORMAT="${DISK_FORMAT:-raw}"
DISK_IMG="${ONIX_DISK_IMG:-$STATE_DIR/${VM_NAME}.raw}"
QEMU_PROCESS_NAME="${QEMU_PROCESS_NAME:-onix-$VM_NAME}"  # launch.sh sets this via QEMU -name process=

# --- networking ---------------------------------------------------------------
# User-mode NAT + one host->guest forward for SSH. Host port = the magic number.
SSH_PORT="${SSH_PORT:-$ONIX_MAGIC}"
MAC_ADDR="${MAC_ADDR:-52:54:00:66:49:01}"           # QEMU OUI + magic (66:49) — §0
SSH_KEY="$STATE_DIR/id_ed25519"                     # generated; pubkey baked into the image

# --- boot artifacts -----------------------------------------------------------
OVMF_VARS="$STATE_DIR/${VM_NAME}_OVMF_VARS.fd"       # per-VM writable UEFI NVRAM
KERNEL_IMG="$STATE_DIR/vmlinuz-${KERNEL_FLAVOR}"     # exported for `launch.sh --direct`
INITRD_IMG="$STATE_DIR/initramfs-${KERNEL_FLAVOR}"

# =============================================================================
# helpers (shared by all scripts)
# =============================================================================
_c_reset=$'\033[0m'; _c_blue=$'\033[34m'; _c_yellow=$'\033[33m'; _c_red=$'\033[31m'
log()  { printf '%s==>%s %s\n'  "$_c_blue"   "$_c_reset" "$*" >&2; }
warn() { printf '%swarn:%s %s\n' "$_c_yellow" "$_c_reset" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$_c_red"   "$_c_reset" "$*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

# Locate OVMF (UEFI) firmware. Sets OVMF_CODE + OVMF_VARS_TEMPLATE.
# Returns non-zero when absent; detect_ovmf wraps this with a fatal error.
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

detect_ovmf() {
  find_ovmf || die "no OVMF_CODE/OVMF_VARS firmware — install 'edk2-ovmf' or set ONIX_OVMF_CODE + ONIX_OVMF_VARS_TEMPLATE"
}

# Ensure a per-VM writable NVRAM copy exists (never mutate the system template).
ensure_ovmf_vars() {
  detect_ovmf
  mkdir -p "$STATE_DIR"
  if [[ ! -f "$OVMF_VARS" ]]; then
    install -m 0644 "$OVMF_VARS_TEMPLATE" "$OVMF_VARS"
    log "initialized per-VM UEFI NVRAM: ${OVMF_VARS#$ONIX_ROOT/}"
  fi
  chmod u+rw "$OVMF_VARS"
}

# Ensure the passwordless SSH keypair exists (pubkey gets baked into the image).
ensure_ssh_key() {
  mkdir -p "$STATE_DIR"
  if [[ ! -f "$SSH_KEY" ]]; then
    need_cmd ssh-keygen
    ssh-keygen -t ed25519 -N '' -C "onix-forge" -f "$SSH_KEY" >/dev/null
    log "generated SSH key: ${SSH_KEY#$ONIX_ROOT/}"
  fi
}
