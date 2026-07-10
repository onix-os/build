#!/usr/bin/env bash
# vm/phase5/canonical-package-copies.sh — Phase 503 copy-only canonicalization check.
#
# Phase 503 copies existing recipe sources into packages/ without removing old
# locations. This script proves the copies exist and still match their old
# source files. Builders continue using old paths until a later phase migrates
# them intentionally.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*"
}

usage() {
  cat <<'EOF'
usage: canonical-package-copies.sh [--check]

Verifies Phase 503 copy-only canonical package recipe layout.
EOF
}

case "${1:---check}" in
  --check) ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; die "unknown argument: $1" ;;
esac

cd "$ONIX_ROOT"

log "Phase 503 canonical package copies"
log "policy    : copy-only; old recipe paths remain for existing builders"

mappings=(
  "recipes/branding/stone.yaml|packages/base/branding/stone.yaml"
  "recipes/filesystem/stone.yaml|packages/base/filesystem/stone.yaml"
  "vm/phase4/stone-recipes/busybox/stone.yaml.in|packages/core/busybox/stone.yaml.in"
  "vm/phase4/stone-recipes/dropbear/stone.yaml.in|packages/services/dropbear/stone.yaml.in"
  "vm/phase4/stone-recipes/systemd-native/stone.yaml.in|packages/services/systemd/stone.yaml.in"
  "vm/phase4/stone-recipes/bootstrap/stone.yaml.in|packages/services/bootstrap/stone.yaml.in"
)

packages=(
  "packages/base/branding"
  "packages/base/filesystem"
  "packages/core/busybox"
  "packages/services/dropbear"
  "packages/services/systemd"
  "packages/services/bootstrap"
)

for mapping in "${mappings[@]}"; do
  src="${mapping%%|*}"
  dst="${mapping##*|}"
  [[ -f "$src" ]] || die "missing source recipe: $src"
  [[ -f "$dst" ]] || die "missing canonical copy: $dst"
  cmp -s "$src" "$dst" || die "canonical copy differs from source: $dst"
  log "copy      : $src -> $dst"
done

for pkg in "${packages[@]}"; do
  [[ -f "$pkg/PACKAGE.md" ]] || die "missing package contract: $pkg/PACKAGE.md"
  grep -q 'Implementation language' "$pkg/PACKAGE.md" \
    || die "PACKAGE.md missing implementation language field: $pkg"
  grep -q 'Rust alternative considered' "$pkg/PACKAGE.md" \
    || die "PACKAGE.md missing Rust alternative field: $pkg"
  grep -q 'Link model' "$pkg/PACKAGE.md" \
    || die "PACKAGE.md missing link model field: $pkg"
  grep -q 'No runtime .*nix/store.* dependency' "$pkg/PACKAGE.md" \
    || die "PACKAGE.md missing runtime-clean field: $pkg"
  grep -q 'Exceptions' "$pkg/PACKAGE.md" \
    || die "PACKAGE.md missing exceptions section: $pkg"
done

cat <<'EOF'

==> success
Phase 503 canonical package copies are present and non-destructive.

Old paths still exist for existing builders.
New packages/ paths now exist for Phase 5 canonical work.
EOF
