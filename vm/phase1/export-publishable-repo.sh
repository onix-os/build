#!/usr/bin/env bash
# vm/phase1/export-publishable-repo.sh — copy publishable ONIX repo to host.
#
# Runs on the host. Reads the publishable repo created inside the Phase 0 forge
# by phase 104 and exports it into a gitignored host artifact directory.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHASE0_DIR="$(cd "$SCRIPT_DIR/../phase0" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=vm/phase0/config.sh
source "$PHASE0_DIR/config.sh"

user="${1:-$BUILD_USER}"
EXPORT_DIR="${ONIX_PUBLISH_EXPORT_DIR:-$ONIX_ROOT/artifacts/onix-publish}"
EXPORT_PARENT="$(dirname "$EXPORT_DIR")"
REMOTE_SRC="/home/$user/stone-lab/onix-publish"

mkdir -p "$EXPORT_PARENT"
tmp="$(mktemp -d "$EXPORT_PARENT/.onix-publish.XXXXXX")"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

log "exporting publishable ONIX repo from forge"
log "remote: $REMOTE_SRC"
log "host  : ${EXPORT_DIR#$ONIX_ROOT/}"

"$PHASE0_DIR/ssh.sh" "$user" /bin/sh -s <<'REMOTE' | tar -C "$tmp" -xf -
set -eu

SRC="$HOME/stone-lab/onix-publish"
ARCH="$(uname -m)"
REPO="$SRC/unstable/$ARCH"

if [ ! -f "$SRC/repo.json" ] || [ ! -f "$SRC/README.txt" ] || [ ! -f "$REPO/stone.index" ]; then
    echo "error: publishable repo missing in forge. From the host, run: make phase 104" >&2
    exit 1
fi

if ! command -v sha256sum >/dev/null 2>&1; then
    echo "error: missing sha256sum in forge" >&2
    exit 1
fi

echo "==> remote checksum verification" >&2
(cd "$REPO" && sha256sum -c SHA256SUMS >&2)

echo "==> streaming publish tree to host" >&2
tar -C "$SRC" -cf - README.txt repo.json unstable
REMOTE

test -f "$tmp/repo.json"
test -f "$tmp/README.txt"
test -f "$tmp/unstable/x86_64/stone.index"
test -f "$tmp/unstable/x86_64/SHA256SUMS"

(
  cd "$tmp/unstable/x86_64"
  sha256sum -c SHA256SUMS >/dev/null
)

if find "$tmp" \( -name '.moss' -o -name 'moss-root' -o -name 'moss-cache' -o -name 'install-target' \) | grep -q .; then
  find "$tmp" \( -name '.moss' -o -name 'moss-root' -o -name 'moss-cache' -o -name 'install-target' \) >&2
  die "export contains Moss test state; publish artifact must contain only repo files"
fi

rm -rf "$EXPORT_DIR"
mv "$tmp" "$EXPORT_DIR"
trap - EXIT

echo
echo "==> exported publish tree"
find "$EXPORT_DIR" -maxdepth 3 -type f | sort

echo
echo "==> metadata"
cat "$EXPORT_DIR/repo.json"

echo
echo "==> success"
echo "host publish root: $EXPORT_DIR"
echo "host index       : $EXPORT_DIR/unstable/x86_64/stone.index"
echo "host checksums   : $EXPORT_DIR/unstable/x86_64/SHA256SUMS"
echo "future URL       : https://repo.onix-os.com/unstable/x86_64/stone.index"
