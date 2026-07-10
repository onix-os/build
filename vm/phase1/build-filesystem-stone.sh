#!/usr/bin/env bash
# vm/phase1/build-filesystem-stone.sh — build ONIX filesystem layout policy stone.
#
# Runs on the host. Boulder and Moss run inside the Phase 0 forge VM.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHASE0_DIR="$(cd "$SCRIPT_DIR/../phase0" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=vm/phase0/config.sh
source "$PHASE0_DIR/config.sh"

user="${1:-$BUILD_USER}"
RECIPE_DIR="${ONIX_FILESYSTEM_RECIPE_DIR:-$ONIX_ROOT/packages/base/filesystem}"
LAB="/home/$user/stone-lab/filesystem"

[[ -f "$RECIPE_DIR/stone.yaml" ]] || die "missing recipe: ${RECIPE_DIR#$ONIX_ROOT/}/stone.yaml"

log "copying filesystem recipe into the forge"
tar -C "$RECIPE_DIR" -cf - stone.yaml \
  | "$PHASE0_DIR/ssh.sh" "$user" "rm -rf '$LAB' && mkdir -p '$LAB' && tar -C '$LAB' -xf -"

"$PHASE0_DIR/ssh.sh" "$user" /bin/sh -s <<'REMOTE'
set -eu

export PATH="$HOME/.local/bin:$PATH"

need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: missing '$1' in the forge. From the host, run: make phase 004" >&2
        exit 1
    fi
}

need_tool boulder
need_tool moss

LAB="$HOME/stone-lab/filesystem"
BRANDING_OUT="$HOME/stone-lab/branding/out"
OUT="$LAB/out"
EXTRACT="$LAB/extracted"
REPO="$LAB/repo"
ROOT="$LAB/moss-root"
CACHE="$LAB/moss-cache"
TARGET="$LAB/install-target"

set -- "$BRANDING_OUT"/*.stone
BRANDING_STONE="$1"
if [ ! -f "$BRANDING_STONE" ]; then
    echo "error: missing branding stone. From the host, run: make phase 101" >&2
    exit 1
fi

echo "==> recipe"
sed -n '1,240p' "$LAB/stone.yaml"

echo
echo "==> building filesystem stone"
rm -rf "$OUT"
mkdir -p "$OUT"
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
moss inspect "$STONE" | sed -n '1,180p'

echo
echo "==> extract and verify filesystem policy files"
rm -rf "$EXTRACT"
mkdir -p "$EXTRACT"
moss extract -o "$EXTRACT" "$STONE"
set -- "$EXTRACT"/*
PAYLOAD="$1"

test -f "$PAYLOAD/usr/share/onix/filesystem-layout.md"
test -f "$PAYLOAD/usr/share/defaults/etc/fstab"
test -f "$PAYLOAD/usr/share/defaults/etc/profile"
test -f "$PAYLOAD/usr/share/defaults/etc/profile.d/onix-path.sh"
test -f "$PAYLOAD/usr/share/defaults/etc/profile.d/onix-login.sh"
grep -q 'moss owns /usr' "$PAYLOAD/usr/share/onix/filesystem-layout.md"
grep -q 'LABEL=ONIX-PERSIST' "$PAYLOAD/usr/share/defaults/etc/fstab"
grep -q '/etc/profile.d' "$PAYLOAD/usr/share/defaults/etc/profile"
grep -q 'export PATH' "$PAYLOAD/usr/share/defaults/etc/profile.d/onix-path.sh"
grep -q "alias ll='ls -laF'" "$PAYLOAD/usr/share/defaults/etc/profile.d/onix-path.sh"
grep -q 'logo.ansi' "$PAYLOAD/usr/share/defaults/etc/profile.d/onix-login.sh"

echo
echo "==> filesystem layout doc"
sed -n '1,180p' "$PAYLOAD/usr/share/onix/filesystem-layout.md"

echo
echo "==> index local repo and install branding + filesystem into disposable target"
rm -rf "$REPO" "$ROOT" "$CACHE" "$TARGET"
mkdir -p "$REPO" "$ROOT" "$CACHE" "$TARGET"
cp "$BRANDING_STONE" "$STONE" "$REPO/"
moss index "$REPO"
moss -D "$ROOT" --cache "$CACHE" repo add local "file://$REPO/stone.index" -c "local onix phase1 repo"
moss -D "$ROOT" --cache "$CACHE" repo update
moss -D "$ROOT" --cache "$CACHE" -y install --to "$TARGET" branding filesystem

test -f "$TARGET/usr/lib/os-release"
test -f "$TARGET/usr/lib/os-info.json"
test -f "$TARGET/usr/share/onix/filesystem-layout.md"
test -f "$TARGET/usr/share/defaults/etc/fstab"
test -f "$TARGET/usr/share/defaults/etc/profile"
test -f "$TARGET/usr/share/defaults/etc/profile.d/onix-path.sh"
test -f "$TARGET/usr/share/defaults/etc/profile.d/onix-login.sh"
grep -q '^ID="onix"$' "$TARGET/usr/lib/os-release"
grep -q 'LABEL=onix-root' "$TARGET/usr/share/defaults/etc/fstab"
grep -q '/etc/profile.d' "$TARGET/usr/share/defaults/etc/profile"
grep -q "alias ll='ls -laF'" "$TARGET/usr/share/defaults/etc/profile.d/onix-path.sh"
grep -q 'logo.ansi' "$TARGET/usr/share/defaults/etc/profile.d/onix-login.sh"

echo
echo "==> installed target proof"
echo "--- generated os-release ---"
cat "$TARGET/usr/lib/os-release"
printf '\n'
echo "--- default fstab ---"
cat "$TARGET/usr/share/defaults/etc/fstab"

echo
echo "==> success"
echo "filesystem stone: $STONE"
echo "branding stone  : $BRANDING_STONE"
echo "repo            : $REPO/stone.index"
echo "root            : $ROOT"
echo "target          : $TARGET"
REMOTE
