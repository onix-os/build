#!/usr/bin/env bash
# vm/phase1/build-branding-stone.sh — build the first real ONIX base stone.
#
# Runs on the host. Boulder and Moss run inside the Phase 0 forge VM.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHASE0_DIR="$(cd "$SCRIPT_DIR/../phase0" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=vm/phase0/config.sh
source "$PHASE0_DIR/config.sh"

user="${1:-$BUILD_USER}"
RECIPE_DIR="${ONIX_BRANDING_RECIPE_DIR:-$ONIX_ROOT/packages/base/branding}"
LAB="/home/$user/stone-lab/branding"

[[ -f "$RECIPE_DIR/stone.yaml" ]] || die "missing recipe: ${RECIPE_DIR#$ONIX_ROOT/}/stone.yaml"

log "copying branding recipe into the forge"
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

LAB="$HOME/stone-lab/branding"
OUT="$LAB/out"
EXTRACT="$LAB/extracted"
REPO="$LAB/repo"
ROOT="$LAB/moss-root"
CACHE="$LAB/moss-cache"
TARGET="$LAB/install-target"

echo "==> recipe"
sed -n '1,240p' "$LAB/stone.yaml"

echo
echo "==> building branding stone"
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
echo "==> extract and verify identity files"
rm -rf "$EXTRACT"
mkdir -p "$EXTRACT"
moss extract -o "$EXTRACT" "$STONE"
set -- "$EXTRACT"/*
PAYLOAD="$1"

test -f "$PAYLOAD/usr/lib/os-info.json"
test -f "$PAYLOAD/usr/share/onix/branding/logo.txt"
test -f "$PAYLOAD/usr/share/onix/branding/logo.ansi"
test -f "$PAYLOAD/usr/share/onix/branding/logo.motd"
test -f "$PAYLOAD/usr/share/defaults/etc/issue"
test -f "$PAYLOAD/usr/share/defaults/etc/motd"
grep -q '"id": "onix"' "$PAYLOAD/usr/lib/os-info.json"
grep -q '"name": "ONIX"' "$PAYLOAD/usr/lib/os-info.json"
grep -q '▓' "$PAYLOAD/usr/share/onix/branding/logo.txt"
grep -q '▒' "$PAYLOAD/usr/share/onix/branding/logo.txt"
grep -Fq "$(printf '\033[38;2;231;89;15m')" "$PAYLOAD/usr/share/onix/branding/logo.ansi"
grep -Fq "$(printf '\033[38;2;79;110;145m')" "$PAYLOAD/usr/share/onix/branding/logo.ansi"
grep -q '▓' "$PAYLOAD/usr/share/onix/branding/logo.motd"
grep -q '▒' "$PAYLOAD/usr/share/onix/branding/logo.motd"
grep -q 'moss controls the machine' "$PAYLOAD/usr/share/defaults/etc/motd"
test "$(wc -c < "$PAYLOAD/usr/share/defaults/etc/motd")" -lt 2048

echo
echo "==> /usr/lib/os-info.json"
sed -n '1,160p' "$PAYLOAD/usr/lib/os-info.json"

echo
echo "==> plain ONIX logo"
cat "$PAYLOAD/usr/share/onix/branding/logo.txt"

echo
echo "==> index local repo and install into disposable target"
rm -rf "$REPO" "$ROOT" "$CACHE" "$TARGET"
mkdir -p "$REPO" "$ROOT" "$CACHE" "$TARGET"
cp "$STONE" "$REPO/"
moss index "$REPO"
moss -D "$ROOT" --cache "$CACHE" repo add local "file://$REPO/stone.index" -c "local onix branding repo"
moss -D "$ROOT" --cache "$CACHE" repo update
moss -D "$ROOT" --cache "$CACHE" -y install --to "$TARGET" branding

test -f "$TARGET/usr/lib/os-release"
test -f "$TARGET/usr/lib/os-info.json"
test -f "$TARGET/usr/share/onix/branding/logo.txt"
test -f "$TARGET/usr/share/onix/branding/logo.ansi"
test -f "$TARGET/usr/share/onix/branding/logo.motd"
test -f "$TARGET/usr/share/defaults/etc/issue"
test -f "$TARGET/usr/share/defaults/etc/motd"
grep -q '^PRETTY_NAME="ONIX (atomic musl base + Nix toolbox)"$' "$TARGET/usr/lib/os-release"
grep -q '^ID="onix"$' "$TARGET/usr/lib/os-release"
grep -q '^HOME_URL="https://onix-os.com"$' "$TARGET/usr/lib/os-release"
grep -q '^ANSI_COLOR="38;2;79;110;145"$' "$TARGET/usr/lib/os-release"
grep -Fq "$(printf '\033[38;2;231;89;15m')" "$TARGET/usr/share/onix/branding/logo.ansi"
grep -Fq "$(printf '\033[38;2;79;110;145m')" "$TARGET/usr/share/onix/branding/logo.ansi"
grep -q '▓' "$TARGET/usr/share/onix/branding/logo.motd"
grep -q '▒' "$TARGET/usr/share/onix/branding/logo.motd"
grep -q 'moss controls the machine' "$TARGET/usr/share/defaults/etc/motd"
test "$(wc -c < "$TARGET/usr/share/defaults/etc/motd")" -lt 2048

echo
echo "==> installed target proof"
echo "--- generated os-release ---"
cat "$TARGET/usr/lib/os-release"
printf '\n'
echo "--- default issue ---"
cat "$TARGET/usr/share/defaults/etc/issue"
printf '\n'
echo "--- default motd preview ---"
cat "$TARGET/usr/share/defaults/etc/motd"

echo
echo "==> success"
echo "stone : $STONE"
echo "repo  : $REPO/stone.index"
echo "root  : $ROOT"
echo "target: $TARGET"
REMOTE
