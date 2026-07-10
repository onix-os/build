#!/usr/bin/env bash
# vm/phase5/package-name-guard.sh — keep ONIX package ids canonical.
#
# This is a small regression guard for two easy-to-miss package bugs:
#
# 1. Old package ids with an "onix-" prefix must not return. The distro name is
#    ONIX, but package ids should be short nouns like "systemd", "busybox", or
#    "bootstrap".
# 2. Stone selectors must not use "$package-*.stone". Some package ids are
#    prefixes of other ids from older builds. Selectors must not accidentally
#    match retired package ids.
#    Selectors must require the version segment: "$package-[0-9]*.stone".
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

MODE="${1:---check}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*"
}

usage() {
  cat <<'EOF'
usage: package-name-guard.sh [--check]

--check  scan tracked source/docs for old package ids and unsafe stone globs
EOF
}

case "$MODE" in
  --check) ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; die "unknown argument: $MODE" ;;
esac

cd "$ONIX_ROOT"

forbidden_ids=(
  onix-branding
  onix-filesystem
  onix-busybox
  onix-dropbear
  onix-systemd
  onix-bootstrap-policy
  onix-rootasrole-policy
)

source_files() {
  find "$ONIX_ROOT" \
    \( \
      -path "$ONIX_ROOT/.git" -o \
      -path "$ONIX_ROOT/.git/*" -o \
      -path "$ONIX_ROOT/artifacts" -o \
      -path "$ONIX_ROOT/artifacts/*" -o \
      -path "$ONIX_ROOT/site" -o \
      -path "$ONIX_ROOT/site/*" -o \
      -path "$ONIX_ROOT/vm/state" -o \
      -path "$ONIX_ROOT/vm/state/*" -o \
      -path "$ONIX_ROOT/vm/downloads" -o \
      -path "$ONIX_ROOT/vm/downloads/*" \
    \) -prune -o \
    -type f -print
}

script_files() {
  find "$ONIX_ROOT" \
    \( \
      -path "$ONIX_ROOT/.git" -o \
      -path "$ONIX_ROOT/.git/*" -o \
      -path "$ONIX_ROOT/artifacts" -o \
      -path "$ONIX_ROOT/artifacts/*" -o \
      -path "$ONIX_ROOT/site" -o \
      -path "$ONIX_ROOT/site/*" -o \
      -path "$ONIX_ROOT/vm/state" -o \
      -path "$ONIX_ROOT/vm/state/*" -o \
      -path "$ONIX_ROOT/vm/downloads" -o \
      -path "$ONIX_ROOT/vm/downloads/*" \
    \) -prune -o \
    \( -name '*.sh' -o -name Makefile \) -type f -print
}

recipe_files() {
  find \
    "$ONIX_ROOT/packages" \
    "$ONIX_ROOT/vm/phase4/stone-recipes" \
    -type f \( -name 'stone.yaml' -o -name 'stone.yaml.in' \) \
    -print 2>/dev/null || true
}

check_no_forbidden_source_ids() {
  local failed=0
  local id
  local file
  local hit_file

  log "guard: old onix-* package ids are absent from source/docs"
  for id in "${forbidden_ids[@]}"; do
    while IFS= read -r file; do
      # This guard contains the banned spellings as test data; do not report
      # itself.
      [[ "$file" == "$SCRIPT_DIR/package-name-guard.sh" ]] && continue
      hit_file=0
      if grep -I -n -F "$id" "$file" >/tmp/onix-package-name-guard.grep 2>/dev/null; then
        if [[ "$hit_file" -eq 0 ]]; then
          printf 'forbidden package id "%s" in %s\n' "$id" "${file#$ONIX_ROOT/}" >&2
          hit_file=1
        fi
        sed "s#^#  #" /tmp/onix-package-name-guard.grep >&2
        failed=1
      fi
    done < <(source_files)
  done
  rm -f /tmp/onix-package-name-guard.grep

  [[ "$failed" -eq 0 ]] || die "old onix-* package ids returned"
}

check_recipe_names() {
  local failed=0
  local file
  local name

  log "guard: package recipe names do not start with onix-"
  while IFS= read -r file; do
    name="$(
      sed -n 's/^[[:space:]]*name[[:space:]]*:[[:space:]]*//p' "$file" |
        sed -n '1p' |
        sed "s/[[:space:]]*$//"
    )"
    [[ -n "$name" ]] || continue
    case "$name" in
      onix-*)
        printf 'forbidden recipe package id "%s" in %s\n' "$name" "${file#$ONIX_ROOT/}" >&2
        failed=1
        ;;
    esac
  done < <(recipe_files)

  [[ "$failed" -eq 0 ]] || die "recipe package id starts with onix-"
}

check_no_unsafe_stone_globs() {
  local failed=0
  local file

  log "guard: variable stone selectors require a version digit"
  while IFS= read -r file; do
    [[ "$file" == "$SCRIPT_DIR/package-name-guard.sh" ]] && continue
    if grep -I -n -E '"\$[A-Za-z_][A-Za-z0-9_]*-\*\.stone|"\$\{[A-Za-z_][A-Za-z0-9_]*\}-\*\.stone|"\$[A-Za-z_][A-Za-z0-9_]*"-\*\.stone|"\$\{[A-Za-z_][A-Za-z0-9_]*\}"-\*\.stone' "$file" \
      >/tmp/onix-package-name-guard.grep 2>/dev/null; then
      printf 'unsafe variable stone glob in %s\n' "${file#$ONIX_ROOT/}" >&2
      sed "s#^#  #" /tmp/onix-package-name-guard.grep >&2
      failed=1
    fi
  done < <(script_files)
  rm -f /tmp/onix-package-name-guard.grep

  [[ "$failed" -eq 0 ]] || die "replace unsafe selector with package-[0-9]*.stone or inspect package metadata"
}

check_no_unsafe_rootasrole_examples() {
  local failed=0
  local file

  log "guard: docs do not teach rootasrole-*.stone prefix matching"
  while IFS= read -r file; do
    [[ "$file" == "$SCRIPT_DIR/package-name-guard.sh" ]] && continue
    if grep -I -n -F 'rootasrole-*.stone' "$file" >/tmp/onix-package-name-guard.grep 2>/dev/null; then
      printf 'unsafe rootasrole wildcard example in %s\n' "${file#$ONIX_ROOT/}" >&2
      sed "s#^#  #" /tmp/onix-package-name-guard.grep >&2
      failed=1
    fi
  done < <(source_files)
  rm -f /tmp/onix-package-name-guard.grep

  [[ "$failed" -eq 0 ]] || die "use rootasrole-[0-9]*.stone in docs/examples"
}

check_no_forbidden_runtime_proof_ids() {
  log "guard: live runtime proof checks reject old package ids"
  grep -q 'old_prefix=onix-' \
    "$SCRIPT_DIR/phase5-runtime-proof.sh" \
    || die "Phase 514 proof does not reject old onix-* package ids"
  grep -q 'for forbidden_suffix in systemd busybox dropbear bootstrap branding filesystem' \
    "$SCRIPT_DIR/phase5-runtime-proof.sh" \
    || die "Phase 514 proof does not enumerate old package suffixes"
  grep -q 'old_prefix=onix-' \
    "$SCRIPT_DIR/moss-runtime-self-repo-proof.sh" \
    || die "Phase 515 proof does not reject old onix-* package ids"
  grep -q 'for forbidden_suffix in systemd busybox dropbear bootstrap branding filesystem' \
    "$SCRIPT_DIR/moss-runtime-self-repo-proof.sh" \
    || die "Phase 515 proof does not enumerate old package suffixes"
}

check_no_forbidden_source_ids
check_recipe_names
check_no_unsafe_stone_globs
check_no_unsafe_rootasrole_examples
check_no_forbidden_runtime_proof_ids

log "package names: guard OK"
