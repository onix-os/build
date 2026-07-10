#!/usr/bin/env bash
# vm/phase5/shell-policy.sh — Phase 516.
#
# Record/prove the ONIX shell split before building fish:
#
#   BusyBox -> /bin/sh and /usr/bin/sh for system scripts
#   fish    -> /usr/bin/fish for the normal interactive user
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

MODE="apply"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*"
}

usage() {
  cat <<'EOF'
usage: shell-policy.sh [--apply|--check]

--apply  print and validate the Phase 516 shell policy
--check  validate docs/package/materializer wiring only
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

need_file() {
  [[ -f "$1" ]] || die "missing file: ${1#$ONIX_ROOT/}"
}

check_source_files() {
  need_file "$SCRIPT_DIR/docs/phase_5_rust_first_musl_package_repository_plane.md"
  need_file "$SCRIPT_DIR/docs/516_busybox_sh_and_fish_shell_policy.md"
  need_file "$SCRIPT_DIR/docs/517_fish_shell_stone.md"
  need_file "$SCRIPT_DIR/docs/518_default_login_shell_runtime_proof.md"
  need_file "$SCRIPT_DIR/build-fish-stone.sh"
  need_file "$SCRIPT_DIR/shell-runtime-proof.sh"
  need_file "$ONIX_ROOT/packages/core/fish/PACKAGE.md"
  need_file "$ONIX_ROOT/packages/core/fish/stone.yaml.in"
  need_file "$ONIX_ROOT/packages/STONES.md"
  need_file "$ONIX_ROOT/vm/phase4/materialize-etc.sh"
  need_file "$ONIX_ROOT/vm/phase5/wire-uutils-coreutils.sh"

  grep -q 'BusyBox remains the ONIX /bin/sh provider' \
    "$ONIX_ROOT/packages/core/fish/stone.yaml.in" \
    || die "fish recipe does not record BusyBox sh policy"
  grep -q 'BusyBox remains `/bin/sh`' "$ONIX_ROOT/packages/STONES.md" \
    || die "stone catalog does not record fish/BusyBox split"
  grep -q -- '--phase5-shell-runtime' "$ONIX_ROOT/vm/phase4/materialize-etc.sh" \
    || die "Phase 4 materializer is not wired for Phase 5 shell runtime"
  grep -q 'need_link_to /usr/bin/sh busybox' "$ONIX_ROOT/vm/phase5/phase5-runtime-proof.sh" \
    || die "Phase 5 proof no longer protects /usr/bin/sh as BusyBox"
  grep -q 'fish' "$SCRIPT_DIR/docs/518_default_login_shell_runtime_proof.md" \
    || die "Phase 518 docs do not mention fish"
}

run_apply() {
  check_source_files

  cat <<'EOF'
Phase 516 shell policy

System shell:
  /bin/sh and /usr/bin/sh stay BusyBox ash.

Interactive shell:
  /usr/bin/fish becomes the normal ONIX user's login shell after Phase 518.

Reason:
  fish is a good human shell, but it is not POSIX /bin/sh. System scripts need
  the small stable sh contract. Humans get fish; scripts get BusyBox sh.

Next:
  make phase 517
EOF
}

case "$MODE" in
  apply) run_apply ;;
  check)
    check_source_files
    log "phase516  : check OK"
    ;;
  *) die "unknown mode: $MODE" ;;
esac
