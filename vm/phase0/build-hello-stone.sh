#!/usr/bin/env bash
# vm/phase0/build-hello-stone.sh — cut and verify the first tiny .stone in the forge.
#
# Runs on the host, but all package-building work happens inside the running
# forge VM as the build user. It intentionally writes only under:
#
#   /home/<build-user>/stone-lab/onix-hello
#
# The package is intentionally boring: /usr/bin/onix-hello prints one line.
# The point is proving the boulder -> .stone -> local moss repo -> install flow.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=vm/phase0/config.sh
source "$SCRIPT_DIR/config.sh"

user="${1:-$BUILD_USER}"

"$SCRIPT_DIR/ssh.sh" "$user" /bin/sh -s <<'REMOTE'
set -eu

export PATH="$HOME/.local/bin:$PATH"

need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: missing '$1' in the forge. From the host, run: make phase 04" >&2
        exit 1
    fi
}

need_tool boulder
need_tool moss
need_tool tar
need_tool sha256sum

LAB="$HOME/stone-lab/onix-hello"
SRC="$LAB/src/onix-hello-0.1.0"
OUT="$LAB/out"
EXTRACT="$LAB/extracted"
REPO="$LAB/repo"
ROOT="$LAB/moss-root"
CACHE="$LAB/moss-cache"
TARGET="$LAB/install-target"

echo "==> preparing first-stone lab at $LAB"
rm -rf "$LAB"
mkdir -p "$SRC" "$OUT"

cat > "$SRC/onix-hello" <<'EOF_HELLO'
#!/bin/sh
echo "hello from onix forge"
EOF_HELLO
chmod +x "$SRC/onix-hello"

(
    cd "$LAB/src"
    tar -czf onix-hello-0.1.0.tar.gz onix-hello-0.1.0
)

HASH="$(sha256sum "$LAB/src/onix-hello-0.1.0.tar.gz" | awk '{print $1}')"
ARCHIVE_URL="file://$LAB/src/onix-hello-0.1.0.tar.gz"

cat > "$LAB/stone.yaml" <<EOF_RECIPE
name        : onix-hello
version     : 0.1.0
release     : 1
summary     : Tiny hello package for proving the Onix forge
license     : MIT
homepage    : https://onix.local
upstreams   :
    - $ARCHIVE_URL: $HASH
description : |
    Minimal package built inside the Onix forge to verify that
    boulder can create a .stone from a local source archive.
install     : |
    install -Dm00755 onix-hello %(installroot)%(bindir)/onix-hello
    # Boulder build dirs inherit setgid. If /usr keeps g+s, boulder records
    # /usr/ as a special directory and moss extract/install rejects it.
    chmod g-s %(installroot)/usr %(installroot)%(bindir)
EOF_RECIPE

echo "==> recipe"
sed -n '1,220p' "$LAB/stone.yaml"

echo
echo "==> building .stone"
(
    cd "$LAB"
    boulder build -y --normal-priority -o "$OUT" stone.yaml
)

STONE="$(ls "$OUT"/*.stone | head -n 1)"

echo
echo "==> built artifact"
ls -lh "$OUT"
file "$STONE"

echo
echo "==> moss integrity check"
moss inspect --check "$STONE"

echo
echo "==> moss layout"
moss inspect "$STONE" | sed -n '1,140p'

echo
echo "==> extract and run"
rm -rf "$EXTRACT"
mkdir -p "$EXTRACT"
moss extract -o "$EXTRACT" "$STONE"
set -- "$EXTRACT"/*
"$1/usr/bin/onix-hello"

echo
echo "==> index local repo and install into disposable target"
rm -rf "$REPO" "$ROOT" "$CACHE" "$TARGET"
mkdir -p "$REPO" "$ROOT" "$CACHE" "$TARGET"
cp "$STONE" "$REPO/"
moss index "$REPO"
moss -D "$ROOT" --cache "$CACHE" repo add local "file://$REPO/stone.index" -c "local onix hello repo"
moss -D "$ROOT" --cache "$CACHE" repo update
moss -D "$ROOT" --cache "$CACHE" -y install --to "$TARGET" onix-hello
"$TARGET/usr/bin/onix-hello"

echo
echo "==> success"
echo "stone : $STONE"
echo "repo  : $REPO/stone.index"
echo "root  : $ROOT"
echo "target: $TARGET"
REMOTE
