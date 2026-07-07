#!/usr/bin/env bash
# vm/phase4/local-stone-contract.sh — Phase 408 local stone/repo contract.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

STONE_DIR="${ONIX_STONE_DIR:-$ONIX_ROOT/artifacts/onix-stones}"
LOCAL_REPO_DIR="${ONIX_LOCAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-local-repo}"
STONE_WORK_DIR="${ONIX_STONE_WORK_DIR:-$ONIX_ROOT/artifacts/onix-stone-work}"
RECIPE_DIR="${ONIX_PHASE4_RECIPE_DIR:-$SCRIPT_DIR/stone-recipes}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*"
}

rel() {
  local path="$1"
  printf '%s\n' "${path#$ONIX_ROOT/}"
}

need_doc_text() {
  local pattern="$1"
  local file="$2"

  grep -qE "$pattern" "$ONIX_ROOT/$file" \
    || die "missing local-stone contract wording in $file: $pattern"
}

safe_artifact_path() {
  local path="$1"
  case "$path" in
    "$ONIX_ROOT"/artifacts/*) ;;
    *) die "refusing artifact path outside artifacts/: $path" ;;
  esac
}

safe_recipe_path() {
  local path="$1"
  case "$path" in
    "$SCRIPT_DIR"/stone-recipes | "$SCRIPT_DIR"/stone-recipes/*) ;;
    *) die "refusing recipe path outside vm/phase4/stone-recipes: $path" ;;
  esac
}

safe_artifact_path "$STONE_DIR"
safe_artifact_path "$LOCAL_REPO_DIR"
safe_artifact_path "$STONE_WORK_DIR"
safe_recipe_path "$RECIPE_DIR"

log "Phase 408 local stone/repo contract"
mkdir -p "$STONE_DIR" "$LOCAL_REPO_DIR" "$STONE_WORK_DIR" "$RECIPE_DIR"

cat > "$STONE_DIR/CONTRACT.txt" <<'EOF'
ONIX Phase 408 local stone output

Generated .stone files for the Phase 4 bootstrap replacement loop go here.
This directory is generated output and is ignored by git.
EOF

cat > "$LOCAL_REPO_DIR/CONTRACT.txt" <<'EOF'
ONIX Phase 408 local moss repo

This directory is the local bootstrap moss repository for Phase 4 proofs.
It is generated output and is ignored by git.

Remote publishing, repo.onix-os.com, signing policy, retention, and promotion
belong to a later 5xx repository/publishing phase.
EOF

cat > "$STONE_WORK_DIR/CONTRACT.txt" <<'EOF'
ONIX Phase 408 local stone work directory

Temporary build roots, extraction roots, and validation scratch data for local
bootstrap stones go here. This directory is generated output and is ignored by
git.
EOF

cat <<EOF

Local Phase 4 stone loop:

  source recipes : $(rel "$RECIPE_DIR")
  built stones   : $(rel "$STONE_DIR")
  local repo     : $(rel "$LOCAL_REPO_DIR")
  work dir       : $(rel "$STONE_WORK_DIR")

Phase split:

  4xx = local bootstrap stones needed to replace current Nix-sourced system payloads
  5xx = real stone factory, recipe repository, remote publishing, repo.onix-os.com

Planned local replacement path:

  409  build onix-busybox.stone
  410  install/use onix-busybox in the image
  411  rerun shell/network/SSH proofs against stone BusyBox
  412  build onix-dropbear.stone
  413  install/use onix-dropbear and rerun SSH proof
  414  audit systemd stone dependencies
  415  build first onix-systemd.stone
  416  install onix-systemd into the image
  417  boot with onix-systemd as PID 1
  418  move bootstrap units/defaults into stone ownership
  419  audit that systemd/busybox/dropbear are no longer Nix-sourced

EOF

log "checking mdBook contract wording"
need_doc_text 'artifacts/onix-stones' "book/src/phases/408.md"
need_doc_text 'artifacts/onix-local-repo' "book/src/phases/408.md"
need_doc_text 'vm/phase4/stone-recipes' "book/src/phases/408.md"
need_doc_text '5xx = real stone factory' "book/src/phases/408.md"
need_doc_text '409 — build `onix-busybox.stone`' "book/src/phases/408.md"
need_doc_text '414 — systemd stone dependency audit' "book/src/phases/408.md"

echo
echo "==> success"
echo "Phase 408 local stone/repo contract is ready."
