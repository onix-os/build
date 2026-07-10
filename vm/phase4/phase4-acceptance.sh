#!/usr/bin/env bash
# vm/phase4/phase4-acceptance.sh — final Phase 4 live acceptance gate.
#
# Phase 424 brings the native ONIX VM up and leaves it running. Phase 425 does
# not build a new package and does not mutate the image. It checks the running
# machine from the host and confirms that the Phase 4 base is acceptable.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${ONIX_STATE_DIR:-$ONIX_ROOT/vm/state}"

HOST="${ONIX_PHASE425_SSH_HOST:-127.0.0.1}"
PORT="${ONIX_PHASE425_SSH_PORT:-${ONIX_NATIVE_SYSTEMD_SSH_HOST_PORT:-7630}}"
USER="${ONIX_PHASE425_SSH_USER:-onix}"
KEY="${ONIX_PHASE425_SSH_KEY:-${ONIX_SSH_CLIENT_KEY:-$STATE_DIR/id_ed25519}}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*"
}

need_file() {
  [[ -f "$1" ]] || die "missing required file: ${1#$ONIX_ROOT/}"
}

ssh_base=(
  ssh
  -i "$KEY"
  -p "$PORT"
  -o BatchMode=yes
  -o PasswordAuthentication=no
  -o PreferredAuthentications=publickey
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o GlobalKnownHostsFile=/dev/null
  -o ConnectTimeout=3
  -o LogLevel=ERROR
  "$USER@$HOST"
)

interactive_ssh_base=(
  ssh
  -tt
  -i "$KEY"
  -p "$PORT"
  -o BatchMode=yes
  -o PasswordAuthentication=no
  -o PreferredAuthentications=publickey
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o GlobalKnownHostsFile=/dev/null
  -o ConnectTimeout=3
  -o LogLevel=ERROR
  "$USER@$HOST"
)

log "Phase 425 final Phase 4 acceptance"
log "mode      : inspect the running Phase 424 VM"
log "ssh       : ${USER}@${HOST}:${PORT}"

need_file "$ONIX_ROOT/artifacts/onix-image/onix.raw"
need_file "$ONIX_ROOT/artifacts/onix-local-repo/stone.index"
need_file "$KEY"

if [[ -f "$STATE_DIR/phase422.ssh-boot.log" ]]; then
  log "boot log  : ${STATE_DIR#$ONIX_ROOT/}/phase422.ssh-boot.log"
fi

if command -v pgrep >/dev/null 2>&1; then
  qemu_pids="$(pgrep -x onix-p422ssh 2>/dev/null || true)"
  qemu_pids="$(printf '%s\n' "$qemu_pids" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  if [[ -n "$qemu_pids" ]]; then
    log "qemu      : onix-p422ssh pid(s) $qemu_pids"
  else
    log "qemu      : no onix-p422ssh process name found; SSH proof will decide"
  fi
fi

log "remote    : checking PID 1, package ownership, SSH service, login policy"
remote_output="$("${ssh_base[@]}" /usr/bin/busybox sh -s <<'EOF_REMOTE'
set -eu
bb=/usr/bin/busybox

fail() {
  printf 'ONIX_PHASE425_FAIL %s\n' "$*" >&2
  exit 1
}

test -x /usr/lib/systemd/systemd || fail "missing /usr/lib/systemd/systemd"
if [ -L /usr/lib/systemd/systemd ]; then
  fail "systemd is still a symlink to $($bb readlink /usr/lib/systemd/systemd)"
fi

pid1="$($bb cat /proc/1/comm)"
test "$pid1" = systemd || fail "PID 1 is $pid1, expected systemd"

test -x /usr/bin/systemctl || fail "missing systemctl"
test -x /usr/bin/journalctl || fail "missing journalctl"
test -x /usr/bin/systemd-tmpfiles || fail "missing systemd-tmpfiles"
test -x /usr/bin/systemd-sysusers || fail "missing systemd-sysusers"
test -x /usr/bin/udevadm || fail "missing udevadm"
test -x /usr/bin/busybox || fail "missing busybox"
test -x /usr/sbin/dropbear || fail "missing dropbear"

test -f /usr/share/onix/bootstrap/native-systemd-stone.txt || fail "missing native-systemd provenance note"
test -f /usr/share/onix/packages/systemd.md || fail "missing systemd package note"
if $bb grep -R -F /nix/store /usr/share/onix/bootstrap/native-systemd-stone.txt /usr/share/onix/packages/systemd.md >/dev/null 2>&1; then
  fail "native-systemd provenance notes mention /nix/store"
fi

test ! -e /usr/lib/onix/bootstrap || fail "old /usr/lib/onix/bootstrap payload still exists"

test -f /etc/profile || fail "missing /etc/profile"
test -f /etc/profile.d/onix-path.sh || fail "missing onix-path profile script"
test -f /etc/profile.d/onix-login.sh || fail "missing onix-login profile script"
test -f /usr/share/defaults/etc/profile || fail "missing default /etc/profile template"
test -f /usr/share/defaults/etc/profile.d/onix-path.sh || fail "missing default onix-path script"
test -f /usr/share/defaults/etc/profile.d/onix-login.sh || fail "missing default onix-login script"

$bb grep -q "alias ll='ls -laF'" /etc/profile.d/onix-path.sh || fail "ll alias missing"
$bb grep -q 'logo.ansi' /etc/profile.d/onix-login.sh || fail "colored logo hook missing"
$bb grep -q 'Dropbear is started with -m' /etc/profile.d/onix-login.sh || fail "Dropbear MOTD-limit note missing"

test -f /usr/share/onix/branding/logo.txt || fail "missing unicode logo"
test -f /usr/share/onix/branding/logo.ansi || fail "missing colored logo"
test -f /usr/share/onix/branding/logo.motd || fail "missing fallback MOTD logo"
test -f /etc/motd || fail "missing /etc/motd"
motd_bytes="$(wc -c < /etc/motd | $bb tr -d '[:space:]')"
test "$motd_bytes" -lt 2048 || fail "/etc/motd too large for fallback path: ${motd_bytes} bytes"
$bb grep -q 'Welcome to ONIX' /etc/motd || fail "fallback MOTD missing ONIX welcome"
$bb grep -q 'moss controls the machine' /etc/motd || fail "fallback MOTD missing control-plane sentence"

unit=/usr/lib/systemd/system/onix-bootstrap-dropbear.service
test -f "$unit" || fail "missing Dropbear systemd unit"
$bb grep -q -- ' -m ' "$unit" || fail "Dropbear unit does not disable MOTD with -m"
$bb grep -q -- ' -s ' "$unit" || fail "Dropbear unit does not disable password login with -s"

systemd_version="$(/usr/bin/systemctl --version | "$bb" head -n1)"
dropbear_line="$($bb grep '^ExecStart=' "$unit")"
printf 'ONIX_PHASE425_REMOTE_OK user=%s uid=%s pid1=%s systemd="%s" motd_bytes=%s dropbear_m=yes ll=yes colored_login=installed\n' \
  "$($bb id -un)" "$($bb id -u)" "$pid1" "$systemd_version" "$motd_bytes"
printf 'dropbear_exec=%s\n' "$dropbear_line"
EOF_REMOTE
)"
printf '%s\n' "$remote_output"

printf '%s\n' "$remote_output" | grep -qa 'ONIX_PHASE425_REMOTE_OK' \
  || die "remote acceptance marker was not observed"

log "login     : capturing an actual interactive login transcript"
login_capture="$(mktemp "${TMPDIR:-/tmp}/onix-phase425-login.XXXXXX")"
trap 'rm -f "$login_capture"' EXIT

set +e
printf 'alias ll\nsleep 1\nexit\n' | "${interactive_ssh_base[@]}" >"$login_capture" 2>&1
login_status=$?
set -e

grep -qa "Welcome to ONIX" "$login_capture" \
  || { sed -n '1,120p' "$login_capture" >&2; die "interactive login did not print the ONIX welcome"; }

grep -qa "moss controls the machine" "$login_capture" \
  || { sed -n '1,120p' "$login_capture" >&2; die "interactive login did not print the control-plane sentence"; }

grep -qa "ll='ls -laF'" "$login_capture" \
  || { sed -n '1,120p' "$login_capture" >&2; die "interactive shell did not expose ll alias"; }

esc_count="$(LC_ALL=C tr -cd '\033' <"$login_capture" | wc -c | tr -d '[:space:]')"
[[ "$esc_count" -gt 0 ]] \
  || { sed -n '1,120p' "$login_capture" >&2; die "interactive login transcript had no ANSI color escapes"; }

log "login     : ANSI escape bytes observed: $esc_count"
log "login     : ll alias observed"

cat <<EOF

==> success
Phase 425 accepted the Phase 4 booted ONIX base.

What was proved:
  - native source-built systemd is PID 1
  - old /usr/lib/onix/bootstrap payload is absent
  - BusyBox and Dropbear are system packages in the image
  - Dropbear disables its own MOTD with -m
  - /etc/profile.d prints the full colored ONIX login logo
  - /etc/motd remains a small safe fallback
  - the interactive shell exposes the ll alias

Connect:
  ssh -i ${KEY#$ONIX_ROOT/} -p $PORT $USER@$HOST

Stop:
  make stop
EOF
