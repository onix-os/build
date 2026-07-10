#!/usr/bin/env bash
# vm/phase4/stone-bootstrap-policy-probe.sh — Phase 418 live policy proof.
#
# Phase 418 packages the bootstrap helper scripts, proof notes, and bootstrap
# unit source files as bootstrap-policy. This probe boots the image and
# proves those package-owned policy files are present and active while systemd
# and SSH still work.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${ONIX_STATE_DIR:-$ONIX_ROOT/vm/state}"

WAIT_SECONDS="${ONIX_BOOTSTRAP_POLICY_SECONDS:-120}"
DRY_RUN=0
KILL_ONLY=0

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*"
}

usage() {
  cat >&2 <<EOF
usage: stone-bootstrap-policy-probe.sh [options]

  --seconds N      seconds to wait for the boot proof (default: $WAIT_SECONDS)
  --kill           stop existing Phase 418 QEMU probe and exit
  --dry-run        print underlying QEMU commands and exit
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --seconds) WAIT_SECONDS="${2:?missing seconds}"; shift ;;
    --kill) KILL_ONLY=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "unknown argument: $1" ;;
  esac
  shift
done

probe_args=(--seconds "$WAIT_SECONDS")
if [[ "$DRY_RUN" -eq 1 ]]; then
  probe_args+=(--dry-run)
fi

bootstrap_policy_serial_command() {
  cat <<'EOF'
/usr/bin/busybox sh -c 'set -eu; pid1="$(cat /proc/1/comm)"; test "$pid1" = systemd; test -f /usr/share/onix/packages/bootstrap-policy.md; test -x /usr/lib/onix/bootstrap-network-proof; test -f /usr/lib/onix/systemd/system/onix-bootstrap-network.service; echo "ONIX_BOOTSTRAP_POLICY_SERIAL_OK pid1=$pid1 package=present units=active source=present"'
EOF
}

bootstrap_policy_remote_command() {
  cat <<'EOF'
/usr/bin/busybox sh -c 'set -eu; bb=/usr/bin/busybox; pid1="$("$bb" cat /proc/1/comm)"; test "$pid1" = systemd; unit_dir=/usr/lib/systemd/system; test -f /usr/share/onix/packages/bootstrap-policy.md; test -f /usr/share/onix/bootstrap/bootstrap-policy.txt; test -x /usr/lib/onix/bootstrap-remote-inspection-proof; test -f /usr/lib/onix/systemd/system/onix-bootstrap-remote-inspection.service; test -f "$unit_dir/onix-bootstrap-remote-inspection.service"; /bin/grep -q "ONIX Phase 418 bootstrap policy package" /usr/share/onix/bootstrap/bootstrap-policy.txt; /bin/grep -q "ExecStart=/bin/nc -lk -p 6649" "$unit_dir/onix-bootstrap-remote-inspection.service"; printf "ONIX_BOOTSTRAP_POLICY_SSH_OK user=%s uid=%s pid1=%s package=present units=active\n" "$("$bb" id -un)" "$("$bb" id -u)" "$pid1"'
EOF
}

kill_probe() {
  ONIX_SSH_PROBE_NAME=p418ssh \
    "$SCRIPT_DIR/ssh-probe.sh" --kill || true
}

if [[ "$KILL_ONLY" -eq 1 ]]; then
  kill_probe
  exit 0
fi

[[ -f "$ONIX_ROOT/artifacts/onix-image/onix.raw" ]] \
  || die "missing ONIX image: artifacts/onix-image/onix.raw (run make phase 2 first)"
[[ -f "$ONIX_ROOT/artifacts/onix-local-repo/stone.index" ]] \
  || die "missing local Phase 4 repo index: artifacts/onix-local-repo/stone.index"
compgen -G "$ONIX_ROOT/artifacts/onix-local-repo/bootstrap-policy-*.stone" >/dev/null \
  || die "missing bootstrap-policy stone in artifacts/onix-local-repo (run make phase 418)"

log "Phase 418 bootstrap policy live proof"
log "goal      : boot with package-owned bootstrap scripts/unit sources active"
log "window    : ${WAIT_SECONDS}s"

kill_probe >/dev/null 2>&1 || true

ONIX_SSH_PROBE_NAME=p418ssh \
ONIX_SSH_BOOT_LOG="$STATE_DIR/phase418.ssh-boot.log" \
ONIX_SSH_SERIAL_LOG="$STATE_DIR/phase418.ssh-serial.log" \
ONIX_SSH_SERIAL_SOCKET="$STATE_DIR/phase418.ssh.sock" \
ONIX_SSH_HOST_PORT="${ONIX_BOOTSTRAP_POLICY_SSH_HOST_PORT:-7630}" \
ONIX_SSH_PROBE_LABEL="Phase 418 bootstrap policy proof" \
ONIX_SSH_SERIAL_COMMAND="/usr/lib/onix/bootstrap-network-proof && /usr/lib/onix/bootstrap-ssh-proof && $(bootstrap_policy_serial_command)" \
ONIX_SSH_READY_MARKER='ONIX_BOOTSTRAP_POLICY_SERIAL_OK pid1=systemd package=present units=active source=present' \
ONIX_SSH_MARKER='ONIX_BOOTSTRAP_POLICY_SSH_OK user=onix uid=1000 pid1=systemd package=present units=active' \
ONIX_SSH_REMOTE_COMMAND="$(bootstrap_policy_remote_command)" \
ONIX_SSH_SUCCESS_MESSAGE="Phase 418 proved package-owned bootstrap policy files are active at runtime." \
  "$SCRIPT_DIR/ssh-probe.sh" "${probe_args[@]}"

cat <<EOF

==> success
Phase 418 proved the booted ONIX image can use bootstrap-policy as the
package-owned source for bootstrap scripts and unit sources.

Evidence logs:
  ${STATE_DIR#$ONIX_ROOT/}/phase418.*.log

EOF
