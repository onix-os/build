#!/usr/bin/env bash
# vm/phase5/canonical-image-repo-consumption.sh — Phase 507 image repo input.
#
# Phase 507 proves that image assembly can consume the canonical local ONIX
# repository instead of reaching directly into the older split artifact roots.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PHASE4_DIR="$ONIX_ROOT/vm/phase4"
HOST_MOSS="${ONIX_HOST_MOSS:-$ONIX_ROOT/artifacts/host-tools/bin/moss}"

CHANNEL="${ONIX_REPO_CHANNEL:-unstable}"
ARCH="${ONIX_REPO_ARCH:-x86_64}"
CANONICAL_REPO_ROOT="${ONIX_CANONICAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-repo}"
CANONICAL_REPO_DIR="${ONIX_IMAGE_REPO_DIR:-$CANONICAL_REPO_ROOT/$CHANNEL/$ARCH}"
WORK_ROOT="${ONIX_PHASE507_WORK_DIR:-$ONIX_ROOT/artifacts/onix-phase5-work/507}"
IMAGE_RAW="${ONIX_IMAGE_RAW:-$ONIX_ROOT/artifacts/onix-image/onix.raw}"

MODE="check"

REQUIRED_PACKAGES=(
  onix-branding
  onix-filesystem
  onix-busybox
  onix-dropbear
  onix-systemd
  onix-bootstrap-policy
)

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
usage: canonical-image-repo-consumption.sh [--check|--apply]

--check  verify the canonical repo and image-assembly wiring without mounting
         the ONIX image
--apply  re-materialize the current ONIX image from the canonical repo, boot it,
         prove native systemd + SSH, and shut the probe down
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE="check" ;;
    --apply) MODE="apply" ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
  shift
done

cd "$ONIX_ROOT"
shopt -s nullglob

need_file() {
  [[ -f "$1" ]] || die "missing expected file: $(rel "$1")"
}

need_exe() {
  [[ -x "$1" ]] || die "missing executable: $(rel "$1")"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

need_host_moss() {
  need_exe "$HOST_MOSS"
}

select_one_stone() {
  local package="$1"
  local matches=("$CANONICAL_REPO_DIR/$package"-*.stone)
  [[ "${#matches[@]}" -eq 1 ]] \
    || die "expected exactly one $package stone in $(rel "$CANONICAL_REPO_DIR"), found ${#matches[@]}"
  printf '%s\n' "${matches[0]}"
}

check_materializer_wiring() {
  need_file "$PHASE4_DIR/materialize-etc.sh"
  need_file "$PHASE4_DIR/native-systemd-probe.sh"

  grep -q 'ONIX_IMAGE_REPO_DIR' "$PHASE4_DIR/materialize-etc.sh" \
    || die "Phase 4 materializer does not accept ONIX_IMAGE_REPO_DIR"
  grep -q 'file://$IMAGE_REPO_DIR/stone.index' "$PHASE4_DIR/materialize-etc.sh" \
    || die "Phase 4 materializer is not wired to consume IMAGE_REPO_DIR"
  grep -q 'ONIX_IMAGE_REPO_DIR' "$PHASE4_DIR/native-systemd-probe.sh" \
    || die "native systemd probe does not check ONIX_IMAGE_REPO_DIR"

  log "wiring    : image assembly repo input is ONIX_IMAGE_REPO_DIR"
}

check_canonical_repo() {
  need_cmd sha256sum
  need_cmd awk
  need_host_moss

  log "repo      : checking $(rel "$CANONICAL_REPO_DIR")"
  need_file "$CANONICAL_REPO_DIR/stone.index"
  need_file "$CANONICAL_REPO_DIR/SHA256SUMS"
  need_file "$CANONICAL_REPO_DIR/MANIFEST.tsv"

  (
    cd "$CANONICAL_REPO_DIR"
    sha256sum -c SHA256SUMS >/dev/null
  )

  local package count stone
  for package in "${REQUIRED_PACKAGES[@]}"; do
    count="$(
      awk -F '\t' -v package="$package" \
        '$1 == package { count++ } END { print count + 0 }' \
        "$CANONICAL_REPO_DIR/MANIFEST.tsv"
    )"
    [[ "$count" -eq 1 ]] \
      || die "canonical MANIFEST.tsv must contain exactly one row for $package, found $count"
    stone="$(select_one_stone "$package")"
    "$HOST_MOSS" inspect --check "$stone" >/dev/null
  done

  log "repo      : checksum + stone integrity OK"
}

prove_canonical_install() {
  need_host_moss

  log "proof     : installing essential set from canonical repo"
  rm -rf "$WORK_ROOT"
  mkdir -p "$WORK_ROOT/moss-root" "$WORK_ROOT/moss-cache" "$WORK_ROOT/install-target"

  "$HOST_MOSS" -D "$WORK_ROOT/moss-root" \
    --cache "$WORK_ROOT/moss-cache" \
    repo add onix-image \
    "file://$CANONICAL_REPO_DIR/stone.index" \
    -c "ONIX Phase 507 canonical image repo" >/dev/null
  "$HOST_MOSS" -D "$WORK_ROOT/moss-root" \
    --cache "$WORK_ROOT/moss-cache" \
    repo update >/dev/null

  local install_log="$WORK_ROOT/moss-install.log"
  if ! "$HOST_MOSS" -D "$WORK_ROOT/moss-root" \
      --cache "$WORK_ROOT/moss-cache" \
      -y install --to "$WORK_ROOT/install-target" \
      "${REQUIRED_PACKAGES[@]}" >"$install_log" 2>&1; then
    cat "$install_log" >&2
    die "Moss could not install the essential package set from the canonical repo"
  fi

  if grep -q 'duplicate entry:' "$install_log"; then
    log "ownership : Moss reported current package path collisions"
    grep 'duplicate entry:' "$install_log" | sed 's/^error: /    /'
    log "ownership : Phase 507 tolerates existing repo ownership cleanup work"
  fi

  need_file "$WORK_ROOT/install-target/usr/lib/os-release"
  need_file "$WORK_ROOT/install-target/usr/share/onix/filesystem-layout.md"
  need_file "$WORK_ROOT/install-target/usr/bin/busybox"
  need_file "$WORK_ROOT/install-target/usr/sbin/dropbear"
  need_file "$WORK_ROOT/install-target/usr/lib/systemd/systemd"
  need_file "$WORK_ROOT/install-target/usr/share/onix/packages/onix-bootstrap-policy.md"

  log "proof     : canonical install target OK"
}

run_check() {
  log "Phase 507 canonical image repo consumption"
  log "mode      : check"
  check_materializer_wiring
  check_canonical_repo
  "$SCRIPT_DIR/assemble-canonical-local-repo.sh" --check >/dev/null
  prove_canonical_install

  cat <<EOF

==> success
Phase 507 check proved the canonical local repo is usable as the single image
package input:

  $(rel "$CANONICAL_REPO_DIR")/stone.index
EOF
}

apply_materializer_step() {
  local action="$1"
  log "image     : materialize $action from canonical repo"
  ONIX_IMAGE_REPO_DIR="$CANONICAL_REPO_DIR" \
    "$PHASE4_DIR/materialize-etc.sh" "$action"
}

run_apply() {
  log "Phase 507 canonical image repo consumption"
  log "mode      : apply to current ONIX image and boot-prove"
  need_file "$IMAGE_RAW"
  run_check

  log "boot      : stopping any existing native ONIX probe before image mutation"
  ONIX_IMAGE_REPO_DIR="$CANONICAL_REPO_DIR" \
    "$PHASE4_DIR/native-systemd-probe.sh" --kill >/dev/null 2>&1 || true

  apply_materializer_step --native-systemd-stone

  log "boot      : proving image after canonical repo consumption"
  ONIX_IMAGE_REPO_DIR="$CANONICAL_REPO_DIR" \
  ONIX_NATIVE_SYSTEMD_CONTEXT="Phase 507" \
  ONIX_NATIVE_SYSTEMD_BOOT_LOG="$ONIX_ROOT/vm/state/phase507.ssh-boot.log" \
  ONIX_NATIVE_SYSTEMD_SERIAL_LOG="$ONIX_ROOT/vm/state/phase507.ssh-serial.log" \
  ONIX_NATIVE_SYSTEMD_SERIAL_SOCKET="$ONIX_ROOT/vm/state/phase507.ssh.sock" \
  ONIX_NATIVE_SYSTEMD_LIVE_PROOF_LABEL="Phase 507 canonical image repo live proof" \
  ONIX_NATIVE_SYSTEMD_SSH_PROOF_LABEL="Phase 507 canonical image repo SSH proof" \
  ONIX_NATIVE_SYSTEMD_SUCCESS_MESSAGE="Phase 507 proved the image boots after consuming the canonical local repo." \
  ONIX_NATIVE_SYSTEMD_SUCCESS_DETAILS="Phase 507 proved the canonical local repo can install the essential package set, then re-materialized native onix-systemd from that repo and proved native systemd plus SSH still work." \
    "$PHASE4_DIR/native-systemd-probe.sh"

  cat <<EOF

==> success
Phase 507 used the canonical local repo as the image package input and
boot-proved the result.

image repo: $(rel "$CANONICAL_REPO_DIR")/stone.index
image     : $(rel "$IMAGE_RAW")
EOF
}

case "$MODE" in
  check) run_check ;;
  apply) run_apply ;;
  *) die "unknown mode: $MODE" ;;
esac
