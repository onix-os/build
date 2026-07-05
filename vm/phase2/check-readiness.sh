#!/usr/bin/env bash
# vm/phase2/check-readiness.sh — host-side readiness gate for first ONIX image work.
#
# Runs on the host only. It does not build an image, mount anything, or SSH into
# the forge. It verifies that Phase 1 produced a clean repo artifact and that
# the host/dev-shell has the tools Phase 2 will need.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PHASE1_DIR="$ONIX_ROOT/vm/phase1"
EXPORT_ROOT="${ONIX_PUBLISH_EXPORT_DIR:-$ONIX_ROOT/artifacts/onix-publish}"
REPO_DIR="$EXPORT_ROOT/unstable/x86_64"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'missing   : %s\n' "$1" >&2
    missing=1
  fi
}

need_file() {
  [[ -f "$1" ]] || die "missing expected file: ${1#$ONIX_ROOT/}"
}

echo "==> Phase 2 readiness: exported repo artifact"
"$PHASE1_DIR/verify-exported-repo.sh" >/dev/null
echo "artifact  : OK (${EXPORT_ROOT#$ONIX_ROOT/})"

need_file "$REPO_DIR/stone.index"
need_file "$REPO_DIR/SHA256SUMS"

branding_count="$(find "$REPO_DIR" -maxdepth 1 -type f -name 'onix-branding-*.stone' | wc -l)"
filesystem_count="$(find "$REPO_DIR" -maxdepth 1 -type f -name 'onix-filesystem-*.stone' | wc -l)"
[[ "$branding_count" -eq 1 ]] || die "expected exactly one onix-branding stone, found $branding_count"
[[ "$filesystem_count" -eq 1 ]] || die "expected exactly one onix-filesystem stone, found $filesystem_count"
echo "stones    : OK (onix-branding + onix-filesystem)"

echo
echo "==> Phase 2 readiness: host image tools"
missing=0
for cmd in \
  awk \
  find \
  grep \
  losetup \
  mount \
  mkfs.ext4 \
  mkfs.fat \
  mkfs.xfs \
  partprobe \
  sed \
  sgdisk \
  sha256sum \
  sort \
  sudo \
  tar \
  truncate \
  umount
do
  need_cmd "$cmd"
done

if [[ "$missing" -ne 0 ]]; then
  cat >&2 <<'EOF'

Phase 2 needs these tools to assemble disks/images.
If you just pulled the updated flake, run:

  direnv reload

or re-enter the Nix dev shell, then retry:

  make phase 200
EOF
  exit 1
fi
echo "tools     : OK"

echo
echo "==> Phase 2 readiness: repo hygiene"
bad_brand='O''nix'
if grep -RIn "$bad_brand" "$ONIX_ROOT" \
  --exclude-dir=.git \
  --exclude-dir=.direnv \
  --exclude-dir=artifacts \
  --exclude-dir=vm/downloads \
  --exclude-dir=vm/state \
  --exclude='*.raw' \
  --exclude='*.fd' >/tmp/onix-phase2-bad-brand.txt 2>/dev/null; then
  cat /tmp/onix-phase2-bad-brand.txt >&2
  rm -f /tmp/onix-phase2-bad-brand.txt
  die "forbidden spelling found; use ONIX or onix only"
fi
rm -f /tmp/onix-phase2-bad-brand.txt
echo "branding  : OK (no forbidden spelling)"

echo
echo "==> success"
echo "Phase 2 can begin: host has repo artifact + image assembly tools"
