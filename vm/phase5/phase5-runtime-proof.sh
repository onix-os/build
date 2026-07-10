#!/usr/bin/env bash
# vm/phase5/phase5-runtime-proof.sh — Phase 514.
#
# Prove that the Phase 5 package/repository decisions are true inside a running
# ONIX VM. This phase is intentionally live/inspection-only: it does not rebuild
# packages and it does not mutate the image. Run Phase 424 first to bring up the
# native ONIX VM and leave it running.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${ONIX_STATE_DIR:-$ONIX_ROOT/vm/state}"
PHASE4_DIR="$ONIX_ROOT/vm/phase4"

CHANNEL="${ONIX_REPO_CHANNEL:-unstable}"
ARCH="${ONIX_REPO_ARCH:-x86_64}"
CANONICAL_REPO_ROOT="${ONIX_CANONICAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-repo}"
IMAGE_REPO_DIR="${ONIX_PHASE514_IMAGE_REPO_DIR:-${ONIX_IMAGE_REPO_DIR:-$CANONICAL_REPO_ROOT/$CHANNEL/$ARCH}}"

HOST="${ONIX_PHASE514_SSH_HOST:-127.0.0.1}"
PORT="${ONIX_PHASE514_SSH_PORT:-${ONIX_NATIVE_SYSTEMD_SSH_HOST_PORT:-7630}}"
USER="${ONIX_PHASE514_SSH_USER:-onix}"
KEY="${ONIX_PHASE514_SSH_KEY:-${ONIX_SSH_CLIENT_KEY:-$STATE_DIR/id_ed25519}}"

MODE="apply"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*"
}

rel() {
  local path="$1"
  case "$path" in
    "$ONIX_ROOT") printf '.' ;;
    "$ONIX_ROOT"/*) printf '%s' "${path#$ONIX_ROOT/}" ;;
    *) printf '%s' "$path" ;;
  esac
}

usage() {
  cat <<'EOF'
usage: phase5-runtime-proof.sh [--apply|--check]

--apply  refresh the canonical local repo, install the Phase 5 runtime package
         set into the ONIX image, boot the VM, then prove Phase 5 runtime
         ownership over SSH: uutils links, RootAsRole, owned PAM/seccomp/libgcc
         shared surface, and no obvious /nix/store runtime leak
--check  validate local docs/scripts only; does not require a running VM
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

check_source_files() {
  [[ -f "$ONIX_ROOT/vm/phase5/docs/514_booted_phase_5_runtime_proof.md" ]] \
    || die "missing Phase 514 doc page"
  [[ -f "$ONIX_ROOT/packages/core/uutils-coreutils/PACKAGE.md" ]] \
    || die "missing uutils package contract"
  [[ -f "$ONIX_ROOT/packages/core/rootasrole/PACKAGE.md" ]] \
    || die "missing rootasrole package contract"
  [[ -f "$ONIX_ROOT/packages/services/rootasrole-policy/PACKAGE.md" ]] \
    || die "missing rootasrole-policy package contract"
  [[ -f "$ONIX_ROOT/packages/libs/linux-pam/PACKAGE.md" ]] \
    || die "missing linux-pam package contract"
  [[ -f "$ONIX_ROOT/packages/libs/libseccomp/PACKAGE.md" ]] \
    || die "missing libseccomp package contract"
  [[ -f "$ONIX_ROOT/packages/libs/libgcc-runtime/PACKAGE.md" ]] \
    || die "missing libgcc-runtime package contract"
  [[ -f "$ONIX_ROOT/packages/core/moss/PACKAGE.md" ]] \
    || die "missing moss package contract"
  [[ -x "$SCRIPT_DIR/assemble-canonical-local-repo.sh" ]] \
    || die "missing canonical repo assembler"
  [[ -x "$PHASE4_DIR/materialize-etc.sh" ]] \
    || die "missing Phase 4 image materializer"
  [[ -x "$PHASE4_DIR/native-systemd-probe.sh" ]] \
    || die "missing Phase 4 native boot probe"

  grep -q 'Phase 514' "$ONIX_ROOT/vm/phase5/docs/514_booted_phase_5_runtime_proof.md"
  grep -q -- '--phase5-runtime' "$PHASE4_DIR/materialize-etc.sh"
  grep -q 'Phase 513' "$ONIX_ROOT/packages/core/uutils-coreutils/PACKAGE.md"
  grep -q 'dosr' "$ONIX_ROOT/packages/core/rootasrole/PACKAGE.md"
  grep -q '/etc/pam.d/sr' "$ONIX_ROOT/packages/core/rootasrole/PACKAGE.md"
  grep -q '/etc/pam.d/sr' "$ONIX_ROOT/packages/services/rootasrole-policy/PACKAGE.md"
  grep -q '/etc/pam.d/sr' "$ONIX_ROOT/vm/phase5/docs/514_booted_phase_5_runtime_proof.md"
  grep -q 'libpam.so.0' "$ONIX_ROOT/packages/core/rootasrole/PACKAGE.md"
  grep -q 'libseccomp.so.2' "$ONIX_ROOT/packages/core/rootasrole/PACKAGE.md"
}

remote_script() {
  cat <<'EOF_REMOTE'
set -eu
bb=/usr/bin/busybox

fail() {
  printf 'ONIX_PHASE514_FAIL %s\n' "$*" >&2
  exit 1
}

need_file() {
  test -f "$1" || fail "missing file: $1"
}

need_exec() {
  test -x "$1" || fail "missing executable: $1"
}

need_link_to() {
  path="$1"
  target="$2"
  test -L "$path" || fail "$path is not a symlink"
  actual="$($bb readlink "$path")"
  test "$actual" = "$target" || fail "$path points at $actual, expected $target"
}

need_not_link_to_busybox() {
  path="$1"
  if test -L "$path"; then
    actual="$($bb readlink "$path")"
    test "$actual" != "busybox" || fail "$path still points at busybox"
    case "$actual" in
      /nix/store/*) fail "$path points into /nix/store: $actual" ;;
    esac
  fi
}

need_exec /usr/bin/busybox
need_exec /usr/bin/coreutils
need_exec /usr/bin/moss
need_file /usr/share/onix/packages/uutils-coreutils.md
need_file /usr/share/onix/packages/uutils-coreutils.commands
need_file /usr/share/onix/packages/moss.md
need_file /etc/moss/repo.d/onix-image.kdl
test -d /.moss/db || fail "missing live moss database directory"
test -d /.moss/repo || fail "missing live moss repo cache"

need_link_to /usr/bin/ls coreutils
need_link_to /usr/bin/cp coreutils
need_link_to /usr/bin/mv coreutils
need_link_to /usr/bin/rm coreutils
need_link_to /usr/bin/mkdir coreutils
need_link_to /usr/bin/[ coreutils

command_count=0
while IFS= read -r command_name; do
  test -n "$command_name" || continue
  command_count=$((command_count + 1))
  case "$command_name" in
    */*|'') fail "unsafe uutils command name in manifest: $command_name" ;;
  esac
  need_link_to "/usr/bin/$command_name" coreutils
done < /usr/share/onix/packages/uutils-coreutils.commands

test "$command_count" -gt 0 || fail "uutils command manifest is empty"
need_link_to /usr/bin/sh busybox
need_not_link_to_busybox /usr/bin/ls
need_not_link_to_busybox /usr/bin/cp
need_not_link_to_busybox /usr/bin/rm

/usr/bin/coreutils --list >/tmp/onix-phase514-coreutils.list
test -s /tmp/onix-phase514-coreutils.list || fail "coreutils --list produced no commands"
/usr/bin/ls --version >/tmp/onix-phase514-ls.version 2>&1 || fail "uutils ls --version failed"
/usr/bin/moss version >/tmp/onix-phase514-moss.version 2>&1 || fail "moss version failed"
/usr/bin/moss list available >/tmp/onix-phase514-moss-available.log 2>&1 \
  || fail "direct live moss list available failed"
$bb grep -q '^moss[[:space:]]' /tmp/onix-phase514-moss-available.log \
  || fail "direct live moss list available does not show moss"
$bb grep -q '^uutils-coreutils[[:space:]]' /tmp/onix-phase514-moss-available.log \
  || fail "direct live moss list available does not show uutils-coreutils"
/usr/bin/moss li >/tmp/onix-phase514-moss-installed.log 2>&1 \
  || fail "direct live moss li failed"
for installed_package in \
  branding \
  filesystem \
  busybox \
  uutils-coreutils \
  dropbear \
  systemd \
  bootstrap-policy \
  musl \
  linux-pam \
  libseccomp \
  libgcc-runtime \
  rootasrole \
  rootasrole-policy \
  moss
do
  $bb grep -q "^${installed_package}[[:space:]]" /tmp/onix-phase514-moss-installed.log \
    || fail "direct live moss li does not show ${installed_package}"
done
if ! $bb grep -i 'uutils' /tmp/onix-phase514-ls.version >/dev/null 2>&1 \
  && ! $bb grep -i 'coreutils' /tmp/onix-phase514-ls.version >/dev/null 2>&1; then
  fail "ls --version did not look like uutils/coreutils"
fi

need_exec /usr/bin/dosr
need_exec /usr/bin/chsr
test -u /usr/bin/dosr || fail "/usr/bin/dosr is not setuid"
need_file /usr/share/onix/packages/rootasrole.md
need_file /usr/share/onix/packages/rootasrole-policy.md
need_file /usr/share/factory/etc/security/rootasrole.json
need_file /usr/share/factory/etc/security/rootasrole.d/policy.json
need_file /usr/share/factory/etc/pam.d/sr
need_file /usr/share/factory/etc/pam.d/dosr
need_file /etc/security/rootasrole.json
need_file /etc/security/rootasrole.d/policy.json
need_file /etc/pam.d/sr
need_file /etc/pam.d/dosr
need_file /usr/share/onix/bootstrap/phase5-runtime.txt
test -L /var/run || fail "/var/run is not a symlink"
case "$($bb readlink /var/run)" in
  ../run|/run) ;;
  *) fail "/var/run does not point at /run" ;;
esac

if test -r /usr/share/factory/etc/security/rootasrole.json; then
  fail "factory RootAsRole settings are readable by the unprivileged SSH user"
fi
if test -r /usr/share/factory/etc/security/rootasrole.d/policy.json; then
  fail "factory RootAsRole policy data is readable by the unprivileged SSH user"
fi
if test -r /etc/security/rootasrole.json; then
  fail "live RootAsRole settings are readable by the unprivileged SSH user"
fi
if test -r /etc/security/rootasrole.d/policy.json; then
  fail "live RootAsRole policy data is readable by the unprivileged SSH user"
fi
$bb grep -q 'pam_permit.so' /usr/share/factory/etc/pam.d/dosr \
  || fail "factory PAM policy does not mention pam_permit.so"
$bb grep -q 'pam_permit.so' /usr/share/factory/etc/pam.d/sr \
  || fail "factory RootAsRole PAM service sr does not mention pam_permit.so"
$bb grep -q 'pam_permit.so' /etc/pam.d/dosr \
  || fail "live PAM policy does not mention pam_permit.so"
$bb grep -q 'pam_permit.so' /etc/pam.d/sr \
  || fail "live RootAsRole PAM service sr does not mention pam_permit.so"
/usr/bin/dosr /usr/bin/busybox id >/tmp/onix-phase514-dosr-id.log 2>&1 \
  || fail "dosr could not execute /usr/bin/busybox id"
$bb grep -q 'uid=0(root)' /tmp/onix-phase514-dosr-id.log \
  || fail "dosr /usr/bin/busybox id did not execute as root"
test -d /run/rar/ts || fail "RootAsRole did not create timeout storage under /run/rar/ts"

need_file /usr/lib/libpam.so.0
need_file /usr/lib/libseccomp.so.2
need_file /usr/lib/libgcc_s.so.1
need_file /usr/lib/ld-musl-x86_64.so.1
need_file /usr/share/onix/packages/linux-pam.md
need_file /usr/share/onix/packages/libseccomp.md
need_file /usr/share/onix/packages/libgcc-runtime.md
need_file /usr/share/onix/packages/musl.md

if $bb grep -R -F /nix/store \
    /usr/share/onix/packages/uutils-coreutils.md \
    /usr/share/onix/packages/moss.md \
    /usr/share/onix/packages/rootasrole.md \
    /usr/share/onix/packages/rootasrole-policy.md \
    /usr/share/onix/packages/linux-pam.md \
    /usr/share/onix/packages/libseccomp.md \
    /usr/share/onix/packages/libgcc-runtime.md \
    /usr/share/onix/packages/musl.md \
    /etc/moss/repo.d/onix-image.kdl \
    /usr/share/factory/etc/pam.d/sr \
    /usr/share/factory/etc/pam.d/dosr \
    /etc/pam.d/sr \
    /etc/pam.d/dosr \
    /usr/share/onix/bootstrap/phase5-runtime.txt >/dev/null 2>&1; then
  fail "Phase 5 package notes, PAM policy, or proof note contain /nix/store"
fi

pid1="$($bb cat /proc/1/comm)"
test "$pid1" = systemd || fail "PID 1 is $pid1, expected systemd"

printf 'ONIX_PHASE514_REMOTE_OK user=%s uid=%s pid1=%s uutils_commands=%s dosr=exec-root shared_surface=owned rootasrole_policy=bootstrap-onix\n' \
  "$($bb id -un)" "$($bb id -u)" "$pid1" "$command_count"
printf 'ls_version=%s\n' "$($bb head -n1 /tmp/onix-phase514-ls.version)"
printf 'moss_version=%s\n' "$($bb head -n1 /tmp/onix-phase514-moss.version)"
printf 'dosr_id=%s\n' "$($bb head -n1 /tmp/onix-phase514-dosr-id.log)"
EOF_REMOTE
}

run_check() {
  check_source_files
  log "phase514  : check OK"
}

prepare_image_and_boot() {
  [[ -f "$ONIX_ROOT/artifacts/onix-image/onix.raw" ]] \
    || die "missing ONIX image: artifacts/onix-image/onix.raw (run make phase 2 first)"

  log "Phase 514 Phase 5 image consumption"
  log "repo      : $(rel "$IMAGE_REPO_DIR")"
  log "step 1/5 : refresh canonical local repo from latest stones"
  "$SCRIPT_DIR/assemble-canonical-local-repo.sh" --assemble

  [[ -f "$IMAGE_REPO_DIR/stone.index" ]] \
    || die "missing image package repo index after assemble: $(rel "$IMAGE_REPO_DIR")/stone.index"

  log "step 2/5 : stop current native ONIX VM before image mutation"
  "$PHASE4_DIR/native-systemd-probe.sh" --kill >/dev/null 2>&1 || true

  log "step 3/5 : restore native systemd runtime before Phase 5 install"
  ONIX_IMAGE_REPO_DIR="$IMAGE_REPO_DIR" \
    "$PHASE4_DIR/materialize-etc.sh" --native-systemd-stone

  log "step 4/5 : install Phase 5 runtime package set into image"
  ONIX_IMAGE_REPO_DIR="$IMAGE_REPO_DIR" \
    "$PHASE4_DIR/materialize-etc.sh" --phase5-runtime

  log "step 5/5 : boot the Phase 5 image for runtime proof"
  ONIX_IMAGE_REPO_DIR="$IMAGE_REPO_DIR" \
  ONIX_NATIVE_SYSTEMD_CONTEXT="Phase 514" \
  ONIX_NATIVE_SYSTEMD_BOOT_LOG="$STATE_DIR/phase514.ssh-boot.log" \
  ONIX_NATIVE_SYSTEMD_SERIAL_LOG="$STATE_DIR/phase514.ssh-serial.log" \
  ONIX_NATIVE_SYSTEMD_SERIAL_SOCKET="$STATE_DIR/phase514.ssh.sock" \
  ONIX_NATIVE_SYSTEMD_LIVE_PROOF_LABEL="Phase 514 Phase 5 runtime bring-up" \
  ONIX_NATIVE_SYSTEMD_SSH_PROOF_LABEL="Phase 514 Phase 5 runtime SSH proof" \
  ONIX_NATIVE_SYSTEMD_SUCCESS_MESSAGE="Phase 514 booted the ONIX image after installing the Phase 5 runtime package set." \
  ONIX_NATIVE_SYSTEMD_SUCCESS_DETAILS="Phase 514 installed the Phase 5 runtime package set into the image, then booted ONIX with native systemd and authenticated SSH." \
    "$PHASE4_DIR/native-systemd-probe.sh" --keep-running
}

run_apply() {
  check_source_files
  prepare_image_and_boot
  cleanup_vm_on_exit() {
    if [[ "${ONIX_PHASE514_KEEP_RUNNING:-0}" != "1" ]]; then
      "$PHASE4_DIR/native-systemd-probe.sh" --kill >/dev/null 2>&1 || true
    fi
  }
  trap cleanup_vm_on_exit EXIT

  [[ -f "$KEY" ]] \
    || die "missing SSH key: $(rel "$KEY")"

  local ssh_base=(
    ssh
    -F /dev/null
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

  log "Phase 514 booted Phase 5 runtime proof"
  log "mode      : inspect the freshly booted Phase 514 VM"
  log "ssh       : ${USER}@${HOST}:${PORT}"
  log "goal      : prove uutils, RootAsRole, PAM/seccomp/libgcc ownership at runtime"

  local remote_output remote_status
  set +e
  remote_output="$("${ssh_base[@]}" /usr/bin/busybox sh -s 2>&1 < <(remote_script))"
  remote_status=$?
  set -e

  if [[ "$remote_status" -ne 0 ]]; then
    printf '%s\n' "$remote_output" >&2
    cat >&2 <<EOF

Phase 514 could not prove the live Phase 5 runtime.

Most common reasons:
  - the Phase 5 runtime package set did not install into the image correctly
  - the VM booted but SSH is not reachable
  - the freshly booted runtime is missing an expected Phase 5 file

SSH attempted:
  ssh -i $(rel "$KEY") -p $PORT $USER@$HOST
EOF
    exit "$remote_status"
  fi

  printf '%s\n' "$remote_output"
  printf '%s\n' "$remote_output" | grep -qa 'ONIX_PHASE514_REMOTE_OK' \
    || die "remote Phase 514 marker was not observed"

  cat <<EOF

==> success
Phase 514 proved the running ONIX VM has the Phase 5 runtime package ownership:

  - the canonical local repo was refreshed from latest stones
  - the image consumed the Phase 5 runtime package set
  - the VM rebooted with native systemd after that install
  - uutils owns normal coreutils command links
  - BusyBox remains present as the recovery shell provider
  - RootAsRole dosr/chsr are installed, and dosr can execute "busybox id" as root
  - moss is installed as an ONIX-owned runtime package
  - direct live-root "moss list available" works against /
  - direct live-root "moss li" shows the Phase 5 packages as installed
  - PAM, seccomp, musl, and libgcc runtime files are ONIX-owned package files
  - package notes, PAM policy, and proof notes have no obvious /nix/store runtime leak

The Phase 514 VM was stopped after the proof.
Set ONIX_PHASE514_KEEP_RUNNING=1 if you want to keep it running for manual
inspection.

EOF
}

case "$MODE" in
  check) run_check ;;
  apply) run_apply ;;
  *) die "unknown mode: $MODE" ;;
esac
