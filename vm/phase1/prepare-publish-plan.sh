#!/usr/bin/env bash
# vm/phase1/prepare-publish-plan.sh — verify the no-upload repo publishing plan.
#
# Runs on the host only. It does not SSH into the forge and does not publish.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PLAN="$SCRIPT_DIR/README.md"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

need_cmd grep

[[ -f "$PLAN" ]] || die "missing Phase 1 README: ${PLAN#$ONIX_ROOT/}"

echo "==> verify exported artifact first"
"$SCRIPT_DIR/verify-exported-repo.sh"

echo
echo "==> verify publish plan contract"
grep -q '^### Phase 107 — verify no-upload publishing plan$' "$PLAN"
grep -q '^#### Phase 107 publication contract$' "$PLAN"
grep -q 'https://onix-os.com' "$PLAN"
grep -q 'https://github.com/onix-os' "$PLAN"
grep -q 'https://repo.onix-os.com/unstable/x86_64/stone.index' "$PLAN"
grep -q 'artifacts/onix-publish/' "$PLAN"
grep -q 'make phase 106' "$PLAN"
grep -q 'No phase currently changes' "$PLAN"
grep -q 'Do not publish this as an installation instruction until the public URL is live' "$PLAN"

bad_brand='O''nix'
if grep -q "$bad_brand" "$PLAN"; then
  die "forbidden spelling found in publish plan: use ONIX or onix only"
fi

echo
echo "==> publication plan"
sed -n '/^### Phase 107 /,/^### Phase 108 /p' "$PLAN" | sed '$d'

echo
echo "==> success"
echo "Phase 1 README publish plan is no-upload and matches the exported repo artifact"
echo "plan: ${PLAN#$ONIX_ROOT/}"
