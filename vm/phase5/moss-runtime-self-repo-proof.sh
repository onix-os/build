#!/usr/bin/env bash
# vm/phase5/moss-runtime-self-repo-proof.sh — Phase 515 live proof.
#
# Build/package moss, refresh the canonical repo, boot ONIX with moss installed,
# copy the current local repo into the VM, and prove the packaged in-VM moss can
# consume that repo from inside ONIX.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${ONIX_STATE_DIR:-$ONIX_ROOT/vm/state}"
PHASE4_DIR="$ONIX_ROOT/vm/phase4"

CHANNEL="${ONIX_REPO_CHANNEL:-unstable}"
ARCH="${ONIX_REPO_ARCH:-x86_64}"
CANONICAL_REPO_ROOT="${ONIX_CANONICAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-repo}"
IMAGE_REPO_DIR="${ONIX_PHASE515_IMAGE_REPO_DIR:-${ONIX_IMAGE_REPO_DIR:-$CANONICAL_REPO_ROOT/$CHANNEL/$ARCH}}"

HOST="${ONIX_PHASE515_SSH_HOST:-127.0.0.1}"
PORT="${ONIX_PHASE515_SSH_PORT:-${ONIX_NATIVE_SYSTEMD_SSH_HOST_PORT:-7630}}"
USER="${ONIX_PHASE515_SSH_USER:-onix}"
KEY="${ONIX_PHASE515_SSH_KEY:-${ONIX_SSH_CLIENT_KEY:-$STATE_DIR/id_ed25519}}"
REMOTE_REPO="${ONIX_PHASE515_REMOTE_REPO:-/tmp/onix-phase515-repo}"

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
usage: moss-runtime-self-repo-proof.sh [--apply|--check]

--apply  build/package moss, refresh the repo, boot ONIX with moss installed,
         copy the current repo into the VM, and prove in-VM moss can consume it
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
  [[ -x "$SCRIPT_DIR/build-moss-runtime.sh" ]] || die "missing build-moss-runtime.sh"
  [[ -x "$SCRIPT_DIR/assemble-canonical-local-repo.sh" ]] || die "missing canonical repo assembler"
  [[ -x "$SCRIPT_DIR/phase5-runtime-proof.sh" ]] || die "missing Phase 514 runtime proof script"
  [[ -x "$PHASE4_DIR/native-systemd-probe.sh" ]] || die "missing native systemd probe"
  [[ -f "$ONIX_ROOT/packages/core/moss/PACKAGE.md" ]] || die "missing moss PACKAGE.md"
  [[ -f "$ONIX_ROOT/packages/core/moss/stone.yaml.in" ]] || die "missing moss stone template"
  [[ -f "$ONIX_ROOT/vm/phase5/docs/515_moss_runtime_package_and_self_repo_probe.md" ]] \
    || die "missing Phase 515 doc page"

  grep -q 'moss' "$ONIX_ROOT/packages/STONES.md"
  grep -q 'moss' "$ONIX_ROOT/vm/phase5/docs/515_moss_runtime_package_and_self_repo_probe.md"
  grep -q '^moss$' < <(sed -n '/^phase5_runtime_packages()/,/^EOF/p' "$PHASE4_DIR/materialize-etc.sh" | sed -n '/^moss$/p') \
    || die "Phase 5 runtime package list does not include moss"
}

remote_script() {
  cat <<'EOF_REMOTE'
set -eu

bb=/usr/bin/busybox
repo="${ONIX_PHASE515_REMOTE_REPO:-/tmp/onix-phase515-repo}"
work="/tmp/onix-phase515-work"

fail() {
  printf 'ONIX_PHASE515_FAIL %s\n' "$*" >&2
  exit 1
}

need_exec() {
  test -x "$1" || fail "missing executable: $1"
}

need_file() {
  test -f "$1" || fail "missing file: $1"
}

need_exec /usr/bin/busybox
need_exec /usr/bin/moss
need_file /usr/share/onix/packages/moss.md
need_file "$repo/stone.index"

/usr/bin/moss version >/tmp/onix-phase515-moss.version 2>&1 \
  || fail "moss version failed"

rm -rf "$work"
mkdir -p "$work/root" "$work/cache" "$work/target"

/usr/bin/moss -D "$work/root" \
  --cache "$work/cache" \
  repo add onix-self "file://$repo/stone.index" \
  -c "ONIX Phase 515 in-VM self repo" >/tmp/onix-phase515-repo-add.log 2>&1 \
  || fail "moss repo add failed"

/usr/bin/moss -D "$work/root" --cache "$work/cache" repo update \
  >/tmp/onix-phase515-repo-update.log 2>&1 \
  || fail "moss repo update failed"

/usr/bin/moss -D "$work/root" --cache "$work/cache" info \
  moss uutils-coreutils rootasrole systemd \
  >/tmp/onix-phase515-info.log 2>&1 \
  || fail "moss info failed"

/usr/bin/moss -D "$work/root" --cache "$work/cache" list available \
  >/tmp/onix-phase515-available.log 2>&1 \
  || fail "moss list available failed"

$bb grep -q 'moss' /tmp/onix-phase515-info.log \
  || fail "moss info output does not mention moss"
$bb grep -q 'uutils-coreutils' /tmp/onix-phase515-info.log \
  || fail "moss info output does not mention uutils-coreutils"
$bb grep -q 'rootasrole' /tmp/onix-phase515-info.log \
  || fail "moss info output does not mention rootasrole"
$bb grep -q 'systemd' /tmp/onix-phase515-info.log \
  || fail "moss info output does not mention systemd"

/usr/bin/moss -D "$work/root" \
  --cache "$work/cache" \
  -y install --to "$work/target" \
  moss uutils-coreutils >/tmp/onix-phase515-install.log 2>&1 \
  || fail "moss scratch install failed"

need_exec "$work/target/usr/bin/moss"
need_exec "$work/target/usr/bin/coreutils"
need_file "$work/target/usr/share/onix/packages/moss.md"
need_file "$work/target/usr/share/onix/packages/uutils-coreutils.commands"

"$work/target/usr/bin/moss" version >/tmp/onix-phase515-installed-moss.version 2>&1 \
  || fail "installed moss version failed"
"$work/target/usr/bin/coreutils" --list >/tmp/onix-phase515-coreutils.list 2>&1 \
  || fail "installed coreutils --list failed"
$bb grep -qx 'ls' /tmp/onix-phase515-coreutils.list \
  || fail "scratch-installed uutils command list does not contain ls"

if $bb grep -R -F /nix/store \
    /usr/share/onix/packages/moss.md \
    "$work/target/usr/share/onix/packages/moss.md" \
    "$work/target/usr/share/onix/packages/uutils-coreutils.md" >/dev/null 2>&1; then
  fail "moss proof notes contain /nix/store"
fi

printf 'ONIX_PHASE515_REMOTE_OK user=%s uid=%s moss="%s" repo=file://%s scratch_install=moss+uutils\n' \
  "$($bb id -un)" "$($bb id -u)" "$($bb head -n1 /tmp/onix-phase515-moss.version)" "$repo"
EOF_REMOTE
}

ssh_base_args() {
  printf '%s\0' \
    -F /dev/null \
    -i "$KEY" \
    -p "$PORT" \
    -o BatchMode=yes \
    -o PasswordAuthentication=no \
    -o PreferredAuthentications=publickey \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o GlobalKnownHostsFile=/dev/null \
    -o ConnectTimeout=3 \
    -o LogLevel=ERROR
}

run_check() {
  check_source_files
  "$SCRIPT_DIR/build-moss-runtime.sh" --check >/dev/null
  log "phase515  : check OK"
}

run_apply() {
  check_source_files
  [[ -f "$KEY" ]] || die "missing SSH key: $(rel "$KEY")"

  log "Phase 515 moss runtime + self-repo proof"
  log "step 1/5 : build/audit moss.stone"
  "$SCRIPT_DIR/build-moss-runtime.sh" --apply

  log "step 2/5 : refresh canonical repo so it includes moss"
  "$SCRIPT_DIR/assemble-canonical-local-repo.sh" --assemble
  [[ -f "$IMAGE_REPO_DIR/stone.index" ]] \
    || die "missing image repo index after assemble: $(rel "$IMAGE_REPO_DIR")/stone.index"

  cleanup_vm_on_exit() {
    if [[ "${ONIX_PHASE515_KEEP_RUNNING:-0}" != "1" ]]; then
      "$PHASE4_DIR/native-systemd-probe.sh" --kill >/dev/null 2>&1 || true
    fi
  }
  trap cleanup_vm_on_exit EXIT

  log "step 3/5 : install Phase 5 runtime including moss, boot ONIX, prove SSH"
  ONIX_PHASE514_KEEP_RUNNING=1 \
  ONIX_IMAGE_REPO_DIR="$IMAGE_REPO_DIR" \
    "$SCRIPT_DIR/phase5-runtime-proof.sh" --apply

  local ssh_opts=()
  while IFS= read -r -d '' opt; do
    ssh_opts+=("$opt")
  done < <(ssh_base_args)

  log "step 4/5 : copy canonical repo into the running VM scratch space"
  tar -C "$IMAGE_REPO_DIR" -cf - . \
    | ssh "${ssh_opts[@]}" "$USER@$HOST" \
        "rm -rf '$REMOTE_REPO' && mkdir -p '$REMOTE_REPO' && /usr/bin/busybox tar -C '$REMOTE_REPO' -xf -"

  log "step 5/5 : prove packaged in-VM moss can consume that repo"
  local remote_output remote_status
  set +e
  remote_output="$(ONIX_PHASE515_REMOTE_REPO="$REMOTE_REPO" \
    ssh "${ssh_opts[@]}" "$USER@$HOST" /usr/bin/busybox sh -s 2>&1 < <(remote_script))"
  remote_status=$?
  set -e

  if [[ "$remote_status" -ne 0 ]]; then
    printf '%s\n' "$remote_output" >&2
    cat >&2 <<EOF

Phase 515 could not prove in-VM moss repository consumption.

Most common reasons:
  - moss was not installed into the image
  - the scratch repo copy failed
  - packaged moss could not read/install from the file:// repo

SSH attempted:
  ssh -i $(rel "$KEY") -p $PORT $USER@$HOST
EOF
    exit "$remote_status"
  fi

  printf '%s\n' "$remote_output"
  printf '%s\n' "$remote_output" | grep -qa 'ONIX_PHASE515_REMOTE_OK' \
    || die "remote Phase 515 marker was not observed"

  cat <<EOF

==> success
Phase 515 proved the running ONIX VM has an ONIX-owned moss package:

  - moss.stone was built from the pinned os-tools commit
  - moss was added to the canonical local ONIX repo
  - the image consumed the Phase 5 runtime set including moss
  - the booted VM ran /usr/bin/moss
  - in-VM moss added a file:// ONIX repo
  - in-VM moss queried package info/list output
  - in-VM moss scratch-installed moss + uutils-coreutils from that repo

EOF
}

case "$MODE" in
  apply) run_apply ;;
  check) run_check ;;
  *) die "unknown mode: $MODE" ;;
esac
