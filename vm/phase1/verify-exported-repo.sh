#!/usr/bin/env bash
# vm/phase1/verify-exported-repo.sh — verify exported ONIX repo artifact on host.
#
# Runs on the host only. It does not SSH into the forge and does not publish.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

REPO_ROOT="${ONIX_PUBLISH_EXPORT_DIR:-$ONIX_ROOT/artifacts/onix-publish}"
CHANNEL="${ONIX_REPO_CHANNEL:-unstable}"
ARCH="${ONIX_REPO_ARCH:-x86_64}"
REPO_DIR="$REPO_ROOT/$CHANNEL/$ARCH"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_file() {
  [[ -f "$1" ]] || die "missing expected file: ${1#$ONIX_ROOT/}"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

need_cmd sha256sum
need_cmd grep
need_cmd find
need_cmd sort

echo "==> exported repo location"
echo "root : ${REPO_ROOT#$ONIX_ROOT/}"
echo "index: ${REPO_DIR#$ONIX_ROOT/}/stone.index"

need_file "$REPO_ROOT/README.txt"
need_file "$REPO_ROOT/repo.json"
need_file "$REPO_DIR/stone.index"
need_file "$REPO_DIR/SHA256SUMS"

branding_count="$(find "$REPO_DIR" -maxdepth 1 -type f -name 'branding-*.stone' | wc -l)"
filesystem_count="$(find "$REPO_DIR" -maxdepth 1 -type f -name 'filesystem-*.stone' | wc -l)"
[[ "$branding_count" -eq 1 ]] || die "expected exactly one branding stone, found $branding_count"
[[ "$filesystem_count" -eq 1 ]] || die "expected exactly one filesystem stone, found $filesystem_count"

echo
echo "==> metadata contract"
grep -q '"name": "ONIX"' "$REPO_ROOT/repo.json"
grep -q '"id": "onix"' "$REPO_ROOT/repo.json"
grep -q '"homepage": "https://onix-os.com"' "$REPO_ROOT/repo.json"
grep -q '"source": "https://github.com/onix-os"' "$REPO_ROOT/repo.json"
grep -q '"repo_url_hint": "https://repo.onix-os.com/unstable/x86_64/stone.index"' "$REPO_ROOT/repo.json"
cat "$REPO_ROOT/repo.json"

echo
echo "==> checksum contract"
(
  cd "$REPO_DIR"
  sha256sum -c SHA256SUMS
)

echo
echo "==> publish tree contains only publish files"
if find "$REPO_ROOT" \( -name '.moss' -o -name 'moss-root' -o -name 'moss-cache' -o -name 'install-target' \) | grep -q .; then
  find "$REPO_ROOT" \( -name '.moss' -o -name 'moss-root' -o -name 'moss-cache' -o -name 'install-target' \) >&2
  die "artifact contains Moss test state"
fi

echo
echo "==> exported files"
find "$REPO_ROOT" -maxdepth 3 -type f | sort

echo
echo "==> gitignore protection"
if command -v git >/dev/null 2>&1 && git -C "$ONIX_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$ONIX_ROOT" check-ignore -q "${REPO_ROOT#$ONIX_ROOT/}/$CHANNEL/$ARCH/stone.index" \
    || die "exported artifacts are not gitignored"
  git -C "$ONIX_ROOT" check-ignore -v "${REPO_ROOT#$ONIX_ROOT/}/$CHANNEL/$ARCH/stone.index"
else
  echo "git not available or not inside a work tree; skipping gitignore check"
fi

echo
echo "==> success"
echo "host artifact is clean and self-consistent"
echo "host index : $REPO_DIR/stone.index"
echo "future URL : https://repo.onix-os.com/$CHANNEL/$ARCH/stone.index"
