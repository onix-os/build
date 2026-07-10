#!/usr/bin/env bash
# vm/phase5/shell-runtime-proof.sh — Phase 518.
#
# Install fish into the ONIX image, switch the normal user's login shell to
# fish, then boot-prove that BusyBox still owns sh.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PHASE4_DIR="$ONIX_ROOT/vm/phase4"

STATE_DIR="${ONIX_STATE_DIR:-$ONIX_ROOT/vm/state}"
LOCAL_REPO_DIR="${ONIX_LOCAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-local-repo}"
CHANNEL="${ONIX_REPO_CHANNEL:-unstable}"
ARCH="${ONIX_REPO_ARCH:-x86_64}"
CANONICAL_REPO_ROOT="${ONIX_CANONICAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-repo}"
IMAGE_REPO_DIR="${ONIX_PHASE518_IMAGE_REPO_DIR:-${ONIX_IMAGE_REPO_DIR:-$CANONICAL_REPO_ROOT/$CHANNEL/$ARCH}}"
HOST_MOSS="${ONIX_HOST_MOSS:-$ONIX_ROOT/artifacts/host-tools/bin/moss}"

HOST_PORT="${ONIX_PHASE518_SSH_HOST_PORT:-7636}"
WAIT_SECONDS="${ONIX_PHASE518_SECONDS:-150}"
BOOT_LOG="${ONIX_PHASE518_BOOT_LOG:-$STATE_DIR/phase518.ssh-boot.log}"
SERIAL_LOG="${ONIX_PHASE518_SERIAL_LOG:-$STATE_DIR/phase518.ssh-serial.log}"
SERIAL_SOCKET="${ONIX_PHASE518_SERIAL_SOCKET:-$STATE_DIR/phase518.ssh.sock}"

MODE="apply"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*"
}

usage() {
  cat <<EOF
usage: shell-runtime-proof.sh [--apply|--check]

--apply  install fish into the image, boot it, and prove shell policy over SSH
--check  validate docs/scripts only; does not require a running VM

Environment:
  ONIX_PHASE518_SECONDS=N
  ONIX_PHASE518_SSH_HOST_PORT=PORT
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) MODE="apply" ;;
    --check) MODE="check" ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
  shift
done

cd "$ONIX_ROOT"

local_stone_for() {
  local package="$1"
  find "$LOCAL_REPO_DIR" -maxdepth 1 -name "$package-[0-9]*.stone" ! -name '*dbginfo*' ! -name '*devel*' | sort | tail -n 1
}

image_stone_for() {
  local package="$1"
  find "$IMAGE_REPO_DIR" -maxdepth 1 -name "$package-[0-9]*.stone" ! -name '*dbginfo*' ! -name '*devel*' | sort | tail -n 1
}

ensure_fish_in_image_repo() {
  local fish_stone

  [[ -d "$IMAGE_REPO_DIR" ]] \
    || die "missing image repo directory: ${IMAGE_REPO_DIR#$ONIX_ROOT/} (run make phase 505)"

  if [[ -n "$(image_stone_for fish)" ]]; then
    [[ -f "$IMAGE_REPO_DIR/stone.index" ]] || "$HOST_MOSS" index "$IMAGE_REPO_DIR"
    return 0
  fi

  fish_stone="$(local_stone_for fish)"
  if [[ -z "$fish_stone" ]]; then
    log "fish stone missing; building Phase 517 first"
    "$SCRIPT_DIR/build-fish-stone.sh" --apply
    fish_stone="$(local_stone_for fish)"
  fi
  [[ -n "$fish_stone" ]] || die "fish stone was not built"

  rm -f \
    "$IMAGE_REPO_DIR"/fish-*.stone \
    "$IMAGE_REPO_DIR"/fish-dbginfo-*.stone \
    "$IMAGE_REPO_DIR"/fish-devel-*.stone
  cp "$fish_stone" "$IMAGE_REPO_DIR/"
  "$HOST_MOSS" index "$IMAGE_REPO_DIR" >/dev/null
  log "image repo: synced fish into ${IMAGE_REPO_DIR#$ONIX_ROOT/}"
}

check_source_files() {
  [[ -f "$SCRIPT_DIR/docs/518_default_login_shell_runtime_proof.md" ]] \
    || die "missing Phase 518 doc page"
  [[ -f "$ONIX_ROOT/packages/core/fish/PACKAGE.md" ]] \
    || die "missing fish package contract"
  [[ -f "$ONIX_ROOT/packages/core/fish/stone.yaml.in" ]] \
    || die "missing fish recipe template"
  [[ -x "$SCRIPT_DIR/build-fish-stone.sh" ]] \
    || die "missing fish stone builder"
  [[ -x "$PHASE4_DIR/materialize-etc.sh" ]] \
    || die "missing Phase 4 image materializer"
  [[ -x "$PHASE4_DIR/ssh-probe.sh" ]] \
    || die "missing Phase 4 SSH probe"

  grep -q -- '--phase5-shell-runtime' "$PHASE4_DIR/materialize-etc.sh"
  grep -q 'ONIX Phase 518 shell runtime policy' "$PHASE4_DIR/materialize-etc.sh"
  grep -q 'BusyBox' "$ONIX_ROOT/packages/core/fish/PACKAGE.md"
  grep -q 'branding.fish' "$ONIX_ROOT/packages/core/fish/PACKAGE.md"
}

phase518_serial_command() {
  cat <<'EOF'
/usr/bin/busybox sh -c 'set -eu; bb=/usr/bin/busybox; test -x /usr/bin/fish; test -x /usr/bin/sh; test "$($bb readlink /usr/bin/sh)" = busybox; test -x /bin/sh; user_line="$($bb grep "^onix:" /etc/passwd)"; user_shell="${user_line##*:}"; test "$user_shell" = /usr/bin/fish; $bb grep -qx /usr/bin/fish /etc/shells; $bb mkdir -p /run/onix-phase518-fish-home /run/onix-phase518-fish-config; HOME=/run/onix-phase518-fish-home XDG_CONFIG_HOME=/run/onix-phase518-fish-config /usr/bin/fish --version | $bb grep -q "^fish, version"; HOME=/run/onix-phase518-fish-home XDG_CONFIG_HOME=/run/onix-phase518-fish-config /usr/bin/fish -c "echo ONIX_FISH_SERIAL_COMMAND_OK" | $bb grep -qx ONIX_FISH_SERIAL_COMMAND_OK; printf "ONIX_PHASE518_SERIAL_OK user_shell=%s sh=busybox fish=fish\n" "$user_shell"'
EOF
}

phase518_remote_command() {
  cat <<'EOF'
/usr/bin/busybox sh -c 'set -eu; bb=/usr/bin/busybox; test -x /usr/bin/fish; test -x /usr/bin/sh; test "$($bb readlink /usr/bin/sh)" = busybox; test -x /bin/sh; user_line="$($bb grep "^onix:" /etc/passwd)"; user_shell="${user_line##*:}"; test "$user_shell" = /usr/bin/fish; $bb grep -qx /usr/bin/fish /etc/shells; test -f /usr/share/onix/packages/fish.md; test -f /usr/share/onix/shells/fish-policy.txt; test -f /usr/share/onix/bootstrap/phase5-shell-runtime.txt; test -f /etc/fish/conf.d/branding.fish; $bb grep -q "Welcome to ONIX" /etc/fish/conf.d/branding.fish; /usr/bin/fish --version | $bb grep -q "^fish, version"; /usr/bin/fish -c "echo ONIX_FISH_SSH_COMMAND_OK" | $bb grep -qx ONIX_FISH_SSH_COMMAND_OK; ghome="/tmp/onix-phase518-greeting-home-$$"; gconfig="/tmp/onix-phase518-greeting-config-$$"; $bb rm -rf "$ghome" "$gconfig"; $bb mkdir -p "$ghome" "$gconfig"; unset ONIX_LOGIN_BANNER_SHOWN; TERM=xterm HOME="$ghome" XDG_CONFIG_HOME="$gconfig" /usr/bin/fish -c "fish_greeting" 2>&1 | $bb grep -q "Welcome to ONIX."; $bb rm -rf "$ghome" "$gconfig"; /usr/bin/moss li | $bb grep -q "^fish[[:space:]]"; printf "ONIX_PHASE518_SSH_OK user=%s uid=%s shell=%s sh=busybox fish=fish\n" "$($bb id -un)" "$($bb id -u)" "$user_shell"'
EOF
}

run_check() {
  check_source_files
  if [[ -z "$(local_stone_for fish)" ]]; then
    log "stone     : fish not built yet"
  else
    [[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"
    "$HOST_MOSS" inspect --check "$(local_stone_for fish)" >/dev/null
    log "stone     : $(local_stone_for fish | sed "s|^$ONIX_ROOT/||")"
  fi
  log "phase518  : check OK"
}

run_apply() {
  check_source_files
  [[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"
  [[ -f "$ONIX_ROOT/artifacts/onix-image/onix.raw" ]] \
    || die "missing ONIX image: artifacts/onix-image/onix.raw (run make phase 2 first)"

  if [[ -z "$(local_stone_for fish)" ]]; then
    log "fish stone missing locally; Phase 518 will build it during --apply"
  fi
  if [[ -z "$(image_stone_for fish)" ]]; then
    log "image repo: fish not present in ${IMAGE_REPO_DIR#$ONIX_ROOT/}"
  fi
  ensure_fish_in_image_repo

  log "stopping any previous Phase 518 QEMU probe"
  ONIX_SSH_PROBE_NAME=p518ssh "$PHASE4_DIR/ssh-probe.sh" --kill >/dev/null 2>&1 || true

  log "installing fish and applying shell policy to the image"
  ONIX_IMAGE_REPO_DIR="$IMAGE_REPO_DIR" \
    "$PHASE4_DIR/materialize-etc.sh" --phase5-shell-runtime

  log "boot-proving BusyBox sh + fish login shell"
  ONIX_SSH_PROBE_NAME=p518ssh \
  ONIX_SSH_BOOT_LOG="$BOOT_LOG" \
  ONIX_SSH_SERIAL_LOG="$SERIAL_LOG" \
  ONIX_SSH_SERIAL_SOCKET="$SERIAL_SOCKET" \
  ONIX_SSH_HOST_PORT="$HOST_PORT" \
  ONIX_SSH_PROBE_LABEL="Phase 518 fish login shell proof" \
  ONIX_SSH_SERIAL_COMMAND="/usr/lib/onix/bootstrap-network-proof && /usr/lib/onix/bootstrap-ssh-proof && $(phase518_serial_command)" \
  ONIX_SSH_READY_MARKER='ONIX_PHASE518_SERIAL_OK user_shell=/usr/bin/fish sh=busybox fish=fish' \
  ONIX_SSH_MARKER='ONIX_PHASE518_SSH_OK user=onix uid=1000 shell=/usr/bin/fish sh=busybox fish=fish' \
  ONIX_SSH_REMOTE_COMMAND="$(phase518_remote_command)" \
  ONIX_SSH_SUCCESS_MESSAGE="Phase 518 proved fish is the normal user's login shell while BusyBox remains sh." \
    "$PHASE4_DIR/ssh-probe.sh" --seconds "$WAIT_SECONDS"

  cat <<EOF_SUCCESS

==> success
fish stone : $(image_stone_for fish | sed "s|^$ONIX_ROOT/||")
boot log   : ${BOOT_LOG#$ONIX_ROOT/}
serial log : ${SERIAL_LOG#$ONIX_ROOT/}

Phase 518 proved the shell split:
  - onix logs in through /usr/bin/fish
  - /usr/bin/sh still points at BusyBox
EOF_SUCCESS
}

case "$MODE" in
  apply) run_apply ;;
  check) run_check ;;
  *) die "unknown mode: $MODE" ;;
esac
