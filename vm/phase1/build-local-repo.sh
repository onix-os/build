#!/usr/bin/env bash
# vm/phase1/build-local-repo.sh — assemble the first named local ONIX repo.
#
# Runs on the host. Moss runs inside the Phase 0 forge VM.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHASE0_DIR="$(cd "$SCRIPT_DIR/../phase0" && pwd)"

# shellcheck source=vm/phase0/config.sh
source "$PHASE0_DIR/config.sh"

user="${1:-$BUILD_USER}"

log "building first named local ONIX repo inside the forge"
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

BRANDING_OUT="$HOME/stone-lab/onix-branding/out"
FILESYSTEM_OUT="$HOME/stone-lab/onix-filesystem/out"
LAB="$HOME/stone-lab/onix-repo"
REPO="$LAB/repo"
ROOT="$LAB/moss-root"
CACHE="$LAB/moss-cache"
TARGET="$LAB/install-target"

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
echo "==> create named local repo: onix-local"
rm -rf "$LAB"
mkdir -p "$REPO" "$ROOT" "$CACHE" "$TARGET"
cp "$BRANDING_STONE" "$FILESYSTEM_STONE" "$REPO/"

moss index "$REPO"
test -f "$REPO/stone.index"

echo
echo "==> repo contents"
ls -lh "$REPO"

moss -D "$ROOT" --cache "$CACHE" repo add onix-local "file://$REPO/stone.index" -c "local ONIX phase1 repo"
moss -D "$ROOT" --cache "$CACHE" repo update

echo
echo "==> install from named repo by package name"
moss -D "$ROOT" --cache "$CACHE" -y install --to "$TARGET" onix-branding onix-filesystem

test -f "$TARGET/usr/lib/os-release"
test -f "$TARGET/usr/lib/os-info.json"
test -f "$TARGET/usr/share/onix/filesystem-layout.md"
test -f "$TARGET/usr/share/defaults/etc/fstab"
test -f "$TARGET/usr/share/defaults/etc/profile.d/onix-path.sh"

grep -q '^NAME="ONIX"$' "$TARGET/usr/lib/os-release"
grep -q '^ID="onix"$' "$TARGET/usr/lib/os-release"
grep -q '^PRETTY_NAME="ONIX (atomic musl base + Nix toolbox)"$' "$TARGET/usr/lib/os-release"
grep -q 'LABEL=ONIX-PERSIST' "$TARGET/usr/share/defaults/etc/fstab"

echo
echo "==> installed target proof"
echo "--- generated os-release ---"
cat "$TARGET/usr/lib/os-release"
printf '\n'
echo "--- installed ONIX policy files ---"
find "$TARGET/usr/share/onix" "$TARGET/usr/share/defaults/etc" -type f | sort

echo
echo "==> success"
echo "repo  : $REPO/stone.index"
echo "root  : $ROOT"
echo "cache : $CACHE"
echo "target: $TARGET"
echo "proof : installed onix-branding + onix-filesystem from repo 'onix-local'"
REMOTE
