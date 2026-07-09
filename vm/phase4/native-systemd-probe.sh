#!/usr/bin/env bash
# vm/phase4/native-systemd-probe.sh — Phase 422 live native systemd proof.
#
# Boots the image and proves that the active PID 1 runtime is the native
# source-built onix-systemd package, not the older bootstrap /nix/store copy.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${ONIX_STATE_DIR:-$ONIX_ROOT/vm/state}"
IMAGE_REPO_DIR="${ONIX_IMAGE_REPO_DIR:-${ONIX_LOCAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-local-repo}}"
BOOT_LOG="${ONIX_NATIVE_SYSTEMD_BOOT_LOG:-$STATE_DIR/phase422.ssh-boot.log}"
SERIAL_LOG="${ONIX_NATIVE_SYSTEMD_SERIAL_LOG:-$STATE_DIR/phase422.ssh-serial.log}"
SERIAL_SOCKET="${ONIX_NATIVE_SYSTEMD_SERIAL_SOCKET:-$STATE_DIR/phase422.ssh.sock}"

WAIT_SECONDS="${ONIX_NATIVE_SYSTEMD_SECONDS:-150}"
DRY_RUN=0
KILL_ONLY=0
KEEP_RUNNING=0

PROBE_CONTEXT="${ONIX_NATIVE_SYSTEMD_CONTEXT:-Phase 422}"
LIVE_PROOF_LABEL="${ONIX_NATIVE_SYSTEMD_LIVE_PROOF_LABEL:-$PROBE_CONTEXT native systemd live proof}"
SSH_PROOF_LABEL="${ONIX_NATIVE_SYSTEMD_SSH_PROOF_LABEL:-$PROBE_CONTEXT native systemd proof}"
SUCCESS_MESSAGE="${ONIX_NATIVE_SYSTEMD_SUCCESS_MESSAGE:-$PROBE_CONTEXT proved the image boots with native source-built onix-systemd as PID 1.}"
SUCCESS_DETAILS="${ONIX_NATIVE_SYSTEMD_SUCCESS_DETAILS:-$PROBE_CONTEXT proved the booted ONIX image can use the native source-built
onix-systemd package as PID 1 while bootstrap networking and authenticated SSH
still work.}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*"
}

usage() {
  cat >&2 <<EOF
usage: native-systemd-probe.sh [options]

  --seconds N      seconds to wait for the boot proof (default: $WAIT_SECONDS)
  --kill           stop existing Phase 422 QEMU probe and exit
  --keep-running   leave QEMU running after a successful proof
  --dry-run        print underlying QEMU commands and exit
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --seconds) WAIT_SECONDS="${2:?missing seconds}"; shift ;;
    --kill) KILL_ONLY=1 ;;
    --keep-running) KEEP_RUNNING=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "unknown argument: $1" ;;
  esac
  shift
done

probe_args=(--seconds "$WAIT_SECONDS")
if [[ "$KEEP_RUNNING" -eq 1 ]]; then
  probe_args+=(--keep-running)
fi
if [[ "$DRY_RUN" -eq 1 ]]; then
  probe_args+=(--dry-run)
fi

native_systemd_serial_command() {
  cat <<'EOF'
/usr/bin/busybox sh -c 'set -eu; bb=/usr/bin/busybox; test -x /usr/lib/systemd/systemd; if [ -L /usr/lib/systemd/systemd ]; then echo "bad-systemd-symlink=$($bb readlink /usr/lib/systemd/systemd)"; exit 1; fi; test -f /usr/lib/systemd/system/multi-user.target; test -x /usr/bin/systemctl; test -x /usr/bin/journalctl; test -x /usr/bin/udevadm; test -e /usr/lib/ld-musl-x86_64.so.1; test -f /usr/share/onix/bootstrap/native-systemd-stone.txt; test -f /usr/share/onix/packages/onix-systemd.md; if $bb grep -R -F /nix/store /usr/share/onix/packages/onix-systemd.md /usr/share/onix/bootstrap/native-systemd-stone.txt >/dev/null 2>&1; then echo "bad-native-systemd-note-mentions-nix-store"; exit 1; fi; pid1="$($bb cat /proc/1/comm)"; test "$pid1" = systemd; version="$(/usr/bin/systemctl --version | "$bb" head -n1)"; printf "ONIX_NATIVE_SYSTEMD_SERIAL_OK pid1=%s systemd=native version=%s\n" "$pid1" "$version"'
EOF
}

native_systemd_remote_command() {
  cat <<'EOF'
/usr/bin/busybox sh -c 'set -eu; bb=/usr/bin/busybox; test -x /usr/lib/systemd/systemd; if [ -L /usr/lib/systemd/systemd ]; then echo "bad-systemd-symlink=$($bb readlink /usr/lib/systemd/systemd)"; exit 1; fi; test -f /usr/lib/systemd/system/multi-user.target; test -x /usr/bin/systemctl; test -x /usr/bin/journalctl; test -x /usr/bin/systemd-tmpfiles; test -x /usr/bin/systemd-sysusers; test -x /usr/bin/udevadm; test -e /usr/lib/ld-musl-x86_64.so.1; pid1="$($bb cat /proc/1/comm)"; test "$pid1" = systemd; version="$(/usr/bin/systemctl --version | "$bb" head -n1)"; printf "ONIX_NATIVE_SYSTEMD_SSH_OK user=%s uid=%s pid1=%s systemd=native version=%s\n" "$("$bb" id -un)" "$("$bb" id -u)" "$pid1" "$version"'
EOF
}

kill_probe() {
  ONIX_SSH_PROBE_NAME=p422ssh \
    "$SCRIPT_DIR/ssh-probe.sh" --kill || true
}

if [[ "$KILL_ONLY" -eq 1 ]]; then
  kill_probe
  exit 0
fi

[[ -f "$ONIX_ROOT/artifacts/onix-image/onix.raw" ]] \
  || die "missing ONIX image: artifacts/onix-image/onix.raw (run make phase 2 first)"
[[ -f "$IMAGE_REPO_DIR/stone.index" ]] \
  || die "missing ONIX image package repo index: ${IMAGE_REPO_DIR#$ONIX_ROOT/}/stone.index"
compgen -G "$IMAGE_REPO_DIR/onix-systemd-*.stone" >/dev/null \
  || die "missing onix-systemd stone in ${IMAGE_REPO_DIR#$ONIX_ROOT/} (run make phase 505)"

log "$LIVE_PROOF_LABEL"
log "goal      : boot with source-built onix-systemd as PID 1"
log "window    : ${WAIT_SECONDS}s"

kill_probe >/dev/null 2>&1 || true

ONIX_SSH_PROBE_NAME=p422ssh \
ONIX_SSH_BOOT_LOG="$BOOT_LOG" \
ONIX_SSH_SERIAL_LOG="$SERIAL_LOG" \
ONIX_SSH_SERIAL_SOCKET="$SERIAL_SOCKET" \
ONIX_SSH_HOST_PORT="${ONIX_NATIVE_SYSTEMD_SSH_HOST_PORT:-7630}" \
ONIX_SSH_PROBE_LABEL="$SSH_PROOF_LABEL" \
ONIX_SSH_SERIAL_COMMAND="/usr/lib/onix/bootstrap-network-proof && /usr/lib/onix/bootstrap-ssh-proof && $(native_systemd_serial_command)" \
ONIX_SSH_READY_MARKER='ONIX_NATIVE_SYSTEMD_SERIAL_OK pid1=systemd systemd=native version=systemd' \
ONIX_SSH_MARKER='ONIX_NATIVE_SYSTEMD_SSH_OK user=onix uid=1000 pid1=systemd systemd=native version=systemd' \
ONIX_SSH_REMOTE_COMMAND="$(native_systemd_remote_command)" \
ONIX_SSH_SUCCESS_MESSAGE="$SUCCESS_MESSAGE" \
  "$SCRIPT_DIR/ssh-probe.sh" "${probe_args[@]}"

cat <<EOF

==> success
${SUCCESS_DETAILS}

Evidence logs:
  ${BOOT_LOG#$ONIX_ROOT/}
  ${SERIAL_LOG#$ONIX_ROOT/}

EOF
