#!/usr/bin/env bash
# vm/phase1/build-publishable-repo.sh — prepare a publishable ONIX repo layout.
#
# Runs on the host. Moss runs inside the Phase 0 forge VM.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHASE0_DIR="$(cd "$SCRIPT_DIR/../phase0" && pwd)"

# shellcheck source=vm/phase0/config.sh
source "$PHASE0_DIR/config.sh"

user="${1:-$BUILD_USER}"

log "preparing publishable ONIX repo layout inside the forge"
"$PHASE0_DIR/ssh.sh" "$user" /bin/sh -s <<'REMOTE'
set -eu

export PATH="$HOME/.local/bin:$PATH"

need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: missing '$1' in the forge. From the host, run: make phase 004" >&2
        exit 1
    fi
}

need_tool moss
need_tool sha256sum

BRANDING_OUT="$HOME/stone-lab/onix-branding/out"
FILESYSTEM_OUT="$HOME/stone-lab/onix-filesystem/out"
LAB="$HOME/stone-lab/onix-publish"
TEST_LAB="$HOME/stone-lab/onix-publish-test"
CHANNEL="unstable"
ARCH="$(uname -m)"
PUBLISH_REPO="$LAB/$CHANNEL/$ARCH"
ROOT="$TEST_LAB/moss-root"
CACHE="$TEST_LAB/moss-cache"
TARGET="$TEST_LAB/install-target"

set -- "$BRANDING_OUT"/*.stone
BRANDING_STONE="$1"
if [ ! -f "$BRANDING_STONE" ]; then
    echo "error: missing onix-branding stone. From the host, run: make phase 101" >&2
    exit 1
fi

set -- "$FILESYSTEM_OUT"/*.stone
FILESYSTEM_STONE="$1"
if [ ! -f "$FILESYSTEM_STONE" ]; then
    echo "error: missing onix-filesystem stone. From the host, run: make phase 102" >&2
    exit 1
fi

echo "==> input stones"
echo "branding  : $BRANDING_STONE"
echo "filesystem: $FILESYSTEM_STONE"

echo
echo "==> create publishable layout"
rm -rf "$LAB" "$TEST_LAB"
mkdir -p "$PUBLISH_REPO" "$ROOT" "$CACHE" "$TARGET"
cp "$BRANDING_STONE" "$FILESYSTEM_STONE" "$PUBLISH_REPO/"

moss index "$PUBLISH_REPO"

(
    cd "$PUBLISH_REPO"
    sha256sum *.stone stone.index > SHA256SUMS
    sha256sum -c SHA256SUMS
)

cat > "$LAB/repo.json" <<EOF_JSON
{
  "name": "ONIX",
  "id": "onix",
  "channel": "$CHANNEL",
  "architecture": "$ARCH",
  "homepage": "https://onix-os.com",
  "source": "https://github.com/onix-os",
  "repo_url_hint": "https://repo.onix-os.com/$CHANNEL/$ARCH/stone.index",
  "local_index": "$PUBLISH_REPO/stone.index"
}
EOF_JSON

cat > "$LAB/README.txt" <<EOF_README
ONIX publishable package repo layout

Channel: $CHANNEL
Architecture: $ARCH

Local test index:
  file://$PUBLISH_REPO/stone.index

Future public index:
  https://repo.onix-os.com/$CHANNEL/$ARCH/stone.index

Files:
  repo.json                         repo metadata for humans/tools
  $CHANNEL/$ARCH/stone.index        Moss index
  $CHANNEL/$ARCH/SHA256SUMS         checksums for stones + index
  $CHANNEL/$ARCH/*.stone            package payloads
EOF_README

echo
echo "==> publish tree"
find "$LAB" -maxdepth 3 -type f | sort

echo
echo "==> metadata"
cat "$LAB/repo.json"

echo
echo "==> verify install from publish-style repo URL"
moss -D "$ROOT" --cache "$CACHE" repo add onix-unstable "file://$PUBLISH_REPO/stone.index" -c "ONIX unstable local publish test"
moss -D "$ROOT" --cache "$CACHE" repo update
moss -D "$ROOT" --cache "$CACHE" -y install --to "$TARGET" onix-branding onix-filesystem

test -f "$TARGET/usr/lib/os-release"
test -f "$TARGET/usr/share/onix/filesystem-layout.md"
test -f "$TARGET/usr/share/defaults/etc/fstab"

grep -q '^NAME="ONIX"$' "$TARGET/usr/lib/os-release"
grep -q '^ID="onix"$' "$TARGET/usr/lib/os-release"
grep -q 'LABEL=ONIX-PERSIST' "$TARGET/usr/share/defaults/etc/fstab"

echo
echo "==> installed target proof"
cat "$TARGET/usr/lib/os-release"

echo
echo "==> success"
echo "publish root: $LAB"
echo "index       : $PUBLISH_REPO/stone.index"
echo "checksums   : $PUBLISH_REPO/SHA256SUMS"
echo "metadata    : $LAB/repo.json"
echo "future URL  : https://repo.onix-os.com/$CHANNEL/$ARCH/stone.index"
echo "proof       : installed packages from publish-style repo 'onix-unstable'"
REMOTE
