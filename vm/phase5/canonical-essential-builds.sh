#!/usr/bin/env bash
# vm/phase5/canonical-essential-builds.sh — Phase 504 canonical build lane proof.
#
# This phase switches builder defaults to packages/ recipes and verifies the
# current essential package artifacts exist. It does not force a full native
# systemd rebuild unless --rebuild is explicitly requested.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PHASE1_DIR="$ONIX_ROOT/vm/phase1"
PHASE4_DIR="$ONIX_ROOT/vm/phase4"
HOST_MOSS="${ONIX_HOST_MOSS:-$ONIX_ROOT/artifacts/host-tools/bin/moss}"

MODE="check"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*"
}

usage() {
  cat <<'EOF'
usage: canonical-essential-builds.sh [--check|--rebuild]

--check    prove builders default to packages/ recipes and existing essential
           artifacts are present/integrity-checkable
--rebuild  explicitly run the existing builders with canonical recipe defaults

The default make target uses --check. Full rebuilds can be expensive,
especially native systemd.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE="check" ;;
    --rebuild) MODE="rebuild" ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
  shift
done

cd "$ONIX_ROOT"

require_file() {
  [[ -f "$1" ]] || die "missing required file: $1"
}

require_glob() {
  local pattern="$1"
  compgen -G "$pattern" >/dev/null || die "missing artifact matching: $pattern"
}

expect_line() {
  local file="$1"
  local needle="$2"
  grep -Fq "$needle" "$file" || die "expected line not found in $file: $needle"
}

first_glob() {
  local pattern="$1"
  compgen -G "$pattern" | sort | sed -n '1p'
}

check_builder_defaults() {
  log "builder   : verifying canonical packages/ recipe defaults"

  expect_line \
    "vm/phase1/build-branding-stone.sh" \
    'RECIPE_DIR="${ONIX_BRANDING_RECIPE_DIR:-$ONIX_ROOT/packages/base/branding}"'
  expect_line \
    "vm/phase1/build-filesystem-stone.sh" \
    'RECIPE_DIR="${ONIX_FILESYSTEM_RECIPE_DIR:-$ONIX_ROOT/packages/base/filesystem}"'
  expect_line \
    "vm/phase4/build-busybox-stone.sh" \
    'RECIPE_TEMPLATE="${ONIX_BUSYBOX_RECIPE_TEMPLATE:-$ONIX_ROOT/packages/core/busybox/stone.yaml.in}"'
  expect_line \
    "vm/phase4/build-dropbear-stone.sh" \
    'RECIPE_TEMPLATE="${ONIX_DROPBEAR_RECIPE_TEMPLATE:-$ONIX_ROOT/packages/services/dropbear/stone.yaml.in}"'
  expect_line \
    "vm/phase4/build-bootstrap-policy-stone.sh" \
    'RECIPE_TEMPLATE="${ONIX_BOOTSTRAP_POLICY_RECIPE_TEMPLATE:-$ONIX_ROOT/packages/services/bootstrap-policy/stone.yaml.in}"'
  expect_line \
    "vm/phase4/build-native-systemd-stone.sh" \
    'RECIPE_TEMPLATE="${ONIX_SYSTEMD_NATIVE_RECIPE_TEMPLATE:-$ONIX_ROOT/packages/services/systemd/stone.yaml.in}"'
  expect_line \
    "vm/phase4/native-systemd-prep.sh" \
    'NATIVE_RECIPE_DRAFT="${ONIX_NATIVE_SYSTEMD_RECIPE_DRAFT:-$ONIX_ROOT/packages/services/systemd/stone.yaml.in}"'
}

check_canonical_inputs() {
  log "recipes   : verifying canonical package recipe inputs"

  require_file "packages/base/branding/stone.yaml"
  require_file "packages/base/branding/PACKAGE.md"
  require_file "packages/base/filesystem/stone.yaml"
  require_file "packages/base/filesystem/PACKAGE.md"
  require_file "packages/core/busybox/stone.yaml.in"
  require_file "packages/core/busybox/PACKAGE.md"
  require_file "packages/services/dropbear/stone.yaml.in"
  require_file "packages/services/dropbear/PACKAGE.md"
  require_file "packages/services/systemd/stone.yaml.in"
  require_file "packages/services/systemd/PACKAGE.md"
  require_file "packages/services/bootstrap-policy/stone.yaml.in"
  require_file "packages/services/bootstrap-policy/PACKAGE.md"
}

check_old_paths_still_exist() {
  log "safety    : verifying old paths still exist for compatibility"

  require_file "recipes/branding/stone.yaml"
  require_file "recipes/filesystem/stone.yaml"
  require_file "vm/phase4/stone-recipes/busybox/stone.yaml.in"
  require_file "vm/phase4/stone-recipes/dropbear/stone.yaml.in"
  require_file "vm/phase4/stone-recipes/systemd-native/stone.yaml.in"
  require_file "vm/phase4/stone-recipes/bootstrap-policy/stone.yaml.in"
}

check_existing_artifacts() {
  log "artifacts : verifying essential package artifacts exist"

  require_glob "artifacts/onix-publish/unstable/x86_64/branding-*.stone"
  require_glob "artifacts/onix-publish/unstable/x86_64/filesystem-*.stone"
  require_file "artifacts/onix-publish/unstable/x86_64/stone.index"

  require_glob "artifacts/onix-local-repo/busybox-*.stone"
  require_glob "artifacts/onix-local-repo/dropbear-*.stone"
  require_glob "artifacts/onix-local-repo/systemd-*.stone"
  require_glob "artifacts/onix-local-repo/bootstrap-policy-*.stone"
  require_file "artifacts/onix-local-repo/stone.index"
}

check_moss_integrity() {
  log "moss      : checking existing essential stones"
  [[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"

  local stone
  for stone in \
    "$(first_glob 'artifacts/onix-publish/unstable/x86_64/branding-*.stone')" \
    "$(first_glob 'artifacts/onix-publish/unstable/x86_64/filesystem-*.stone')" \
    "$(first_glob 'artifacts/onix-local-repo/busybox-*.stone')" \
    "$(first_glob 'artifacts/onix-local-repo/dropbear-*.stone')" \
    "$(first_glob 'artifacts/onix-local-repo/systemd-*.stone')" \
    "$(first_glob 'artifacts/onix-local-repo/bootstrap-policy-*.stone')"; do
    [[ -f "$stone" ]] || die "missing stone selected for check"
    "$HOST_MOSS" inspect --check "$stone" >/dev/null
    log "stone     : ${stone#$ONIX_ROOT/}"
  done
}

run_check() {
  log "Phase 504 canonical essential package build lane"
  log "mode      : check canonical builders + existing artifacts"
  check_builder_defaults
  check_canonical_inputs
  check_old_paths_still_exist
  check_existing_artifacts
  check_moss_integrity

  cat <<'EOF'

==> success
Phase 504 proved the essential package build lane is canonicalized.

What changed:
  - builders now default to packages/ recipes
  - old paths remain for compatibility/history
  - existing essential stones are present and pass moss integrity checks

Full rebuild is explicit:
  ONIX_PHASE504_REBUILD=1 make phase 504
EOF
}

run_rebuild() {
  log "Phase 504 canonical essential package rebuild"
  log "mode      : explicit rebuild from packages/ recipe defaults"
  check_builder_defaults
  check_canonical_inputs

  "$PHASE1_DIR/build-branding-stone.sh"
  "$PHASE1_DIR/build-filesystem-stone.sh"
  "$PHASE4_DIR/build-busybox-stone.sh"
  "$PHASE4_DIR/build-dropbear-stone.sh"
  "$PHASE4_DIR/build-bootstrap-policy-stone.sh"

  if [[ "${ONIX_PHASE504_REBUILD_NATIVE_SYSTEMD:-0}" = "1" ]]; then
    "$PHASE4_DIR/native-systemd-prep.sh"
    "$PHASE4_DIR/build-native-systemd-stone.sh"
  else
    log "native    : skipped native systemd rebuild"
    log "native    : set ONIX_PHASE504_REBUILD_NATIVE_SYSTEMD=1 to rebuild it"
  fi

  check_existing_artifacts
  check_moss_integrity
}

case "$MODE" in
  check) run_check ;;
  rebuild) run_rebuild ;;
  *) die "unknown mode: $MODE" ;;
esac
