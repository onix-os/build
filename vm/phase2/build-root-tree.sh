#!/usr/bin/env bash
# vm/phase2/build-root-tree.sh — assemble the first ONIX root tree.
#
# Runs on the host. The exported Phase 1 repo artifact is the input. Because
# the host does not yet have moss, the Phase 0 forge uses moss to install the
# packages, then this script exports the assembled root tree back to the host.
#
# This does not create a disk image, partition anything, mount anything, or boot.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHASE0_DIR="$(cd "$SCRIPT_DIR/../phase0" && pwd)"
PHASE1_DIR="$(cd "$SCRIPT_DIR/../phase1" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=vm/phase0/config.sh
source "$PHASE0_DIR/config.sh"

user="${1:-$BUILD_USER}"
CHANNEL="${ONIX_REPO_CHANNEL:-unstable}"
ARCH="${ONIX_REPO_ARCH:-x86_64}"
EXPORT_ROOT="${ONIX_PUBLISH_EXPORT_DIR:-$ONIX_ROOT/artifacts/onix-publish}"
REPO_DIR="$EXPORT_ROOT/$CHANNEL/$ARCH"
ROOT_TREE_DIR="${ONIX_ROOT_TREE_DIR:-$ONIX_ROOT/artifacts/onix-root-tree}"
ROOT_TREE_PARENT="$(dirname "$ROOT_TREE_DIR")"
REMOTE_LAB="/home/$user/stone-lab/onix-root-tree"
REMOTE_REPO="$REMOTE_LAB/input-repo"
REMOTE_TARGET="$REMOTE_LAB/root-tree"

need_cmd tar
need_cmd find
need_cmd grep
need_cmd sort
need_cmd sha256sum
need_cmd readlink
need_cmd stat

[[ -d "$EXPORT_ROOT" ]] || die "missing exported repo artifact: ${EXPORT_ROOT#$ONIX_ROOT/}; run make phase 105"
[[ -f "$REPO_DIR/stone.index" ]] || die "missing repo index: ${REPO_DIR#$ONIX_ROOT/}/stone.index; run make phase 106"

echo "==> Phase 201 input check: Phase 2 readiness"
"$SCRIPT_DIR/check-readiness.sh"

echo "==> Phase 201 input check: exported repo artifact"
"$PHASE1_DIR/verify-exported-repo.sh" >/dev/null
echo "artifact: ${EXPORT_ROOT#$ONIX_ROOT/}"
echo "index   : ${REPO_DIR#$ONIX_ROOT/}/stone.index"

mkdir -p "$ROOT_TREE_PARENT"
tmp="$(mktemp -d "$ROOT_TREE_PARENT/.onix-root-tree.XXXXXX")"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

echo "==> streaming exported repo artifact to the forge"
tar -C "$EXPORT_ROOT" -cf - README.txt repo.json "$CHANNEL" \
  | "$PHASE0_DIR/ssh.sh" "$user" "rm -rf '$REMOTE_LAB' && mkdir -p '$REMOTE_REPO' && tar -C '$REMOTE_REPO' -xf -"

echo "==> assembling root tree inside the forge with moss"
"$PHASE0_DIR/ssh.sh" "$user" "ONIX_REPO_CHANNEL='$CHANNEL' ONIX_REPO_ARCH='$ARCH' /bin/sh -s" <<'REMOTE'
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
need_tool tar
need_tool find
need_tool sort
need_tool readlink

CHANNEL="${ONIX_REPO_CHANNEL:-unstable}"
ARCH="${ONIX_REPO_ARCH:-x86_64}"
LAB="$HOME/stone-lab/onix-root-tree"
INPUT_REPO="$LAB/input-repo"
REPO="$INPUT_REPO/$CHANNEL/$ARCH"
ROOT="$LAB/moss-root"
CACHE="$LAB/moss-cache"
TARGET="$LAB/root-tree"

if [ ! -f "$REPO/stone.index" ] || [ ! -f "$REPO/SHA256SUMS" ]; then
    echo "error: missing repo files under $REPO" >&2
    exit 1
fi

echo "==> input repo copied from host artifact"
echo "root : $INPUT_REPO"
echo "index: $REPO/stone.index"

echo
echo "==> checksum input stones"
(cd "$REPO" && sha256sum -c SHA256SUMS)

echo
echo "==> moss install packages into root tree"
rm -rf "$ROOT" "$CACHE" "$TARGET"
mkdir -p "$ROOT" "$CACHE" "$TARGET"
moss -D "$ROOT" --cache "$CACHE" repo add onix-image "file://$REPO/stone.index" -c "ONIX Phase 201 image assembly repo"
moss -D "$ROOT" --cache "$CACHE" repo update
moss -D "$ROOT" --cache "$CACHE" -y install --to "$TARGET" onix-branding onix-filesystem

echo
echo "==> materialize image-owned root-level glue"
for dir in boot dev efi etc home proc run sys usr var persist; do
    install -dm00755 "$TARGET/$dir"
done
install -dm01777 "$TARGET/tmp"
chmod 01777 "$TARGET/tmp"
install -dm00755 "$TARGET/etc/profile.d"

ln -sfn ../usr/lib/os-release "$TARGET/etc/os-release"
cp "$TARGET/usr/share/defaults/etc/issue" "$TARGET/etc/issue"
cp "$TARGET/usr/share/defaults/etc/motd" "$TARGET/etc/motd"
cp "$TARGET/usr/share/defaults/etc/fstab" "$TARGET/etc/fstab"
cp "$TARGET/usr/share/defaults/etc/profile" "$TARGET/etc/profile"
cp "$TARGET/usr/share/defaults/etc/profile.d/onix-path.sh" "$TARGET/etc/profile.d/onix-path.sh"
cp "$TARGET/usr/share/defaults/etc/profile.d/onix-login.sh" "$TARGET/etc/profile.d/onix-login.sh"
printf 'onix\n' > "$TARGET/etc/hostname"
chmod 0644 \
    "$TARGET/etc/issue" \
    "$TARGET/etc/motd" \
    "$TARGET/etc/fstab" \
    "$TARGET/etc/profile" \
    "$TARGET/etc/profile.d/onix-path.sh" \
    "$TARGET/etc/profile.d/onix-login.sh" \
    "$TARGET/etc/hostname"

echo
echo "==> verify root tree contract"
test -f "$TARGET/usr/lib/os-release"
test -f "$TARGET/usr/lib/os-info.json"
test -f "$TARGET/usr/share/onix/branding/logo.txt"
test -f "$TARGET/usr/share/onix/branding/logo.ansi"
test -f "$TARGET/usr/share/onix/filesystem-layout.md"
test -f "$TARGET/usr/share/defaults/etc/fstab"
test -f "$TARGET/usr/share/defaults/etc/profile"
test -L "$TARGET/etc/os-release"
test "$(readlink "$TARGET/etc/os-release")" = "../usr/lib/os-release"
test -f "$TARGET/etc/issue"
test -f "$TARGET/etc/motd"
test -f "$TARGET/etc/fstab"
test -f "$TARGET/etc/profile"
test -f "$TARGET/etc/profile.d/onix-path.sh"
test -f "$TARGET/etc/profile.d/onix-login.sh"
test -f "$TARGET/etc/hostname"
test -d "$TARGET/tmp"
grep -q '^NAME="ONIX"$' "$TARGET/usr/lib/os-release"
grep -q '^ID="onix"$' "$TARGET/usr/lib/os-release"
grep -q '^ANSI_COLOR="38;2;79;110;145"$' "$TARGET/usr/lib/os-release"
grep -q 'LABEL=onix-root' "$TARGET/etc/fstab"
grep -q 'LABEL=ONIX-PERSIST' "$TARGET/etc/fstab"
grep -q 'moss controls the machine' "$TARGET/etc/motd"
grep -q '▓' "$TARGET/etc/motd"
grep -q '▒' "$TARGET/etc/motd"
grep -q '/etc/profile.d' "$TARGET/etc/profile"
grep -q "alias ll='ls -laF'" "$TARGET/etc/profile.d/onix-path.sh"
grep -q 'logo.ansi' "$TARGET/etc/profile.d/onix-login.sh"
test "$(wc -c < "$TARGET/etc/motd")" -lt 2048
grep -q 'moss owns /usr' "$TARGET/usr/share/onix/filesystem-layout.md"

bad_brand='O''nix'
if grep -RIn "$bad_brand" "$TARGET" >/tmp/onix-root-tree-bad-brand.txt 2>/dev/null; then
    cat /tmp/onix-root-tree-bad-brand.txt >&2
    rm -f /tmp/onix-root-tree-bad-brand.txt
    echo "error: forbidden spelling found in root tree; use ONIX or onix only" >&2
    exit 1
fi
rm -f /tmp/onix-root-tree-bad-brand.txt

echo
echo "==> root tree manifest preview"
find "$TARGET" -maxdepth 4 -mindepth 1 | sort | sed "s#^$TARGET##" | sed -n '1,180p'

echo
echo "==> success"
echo "root tree: $TARGET"
REMOTE

echo "==> exporting root tree back to the host"
"$PHASE0_DIR/ssh.sh" "$user" "test -d '$REMOTE_TARGET' && tar -C '$REMOTE_TARGET' -cf - ." \
  | tar -C "$tmp" -xpf -

echo
echo "==> host-side root tree verification"
test -f "$tmp/usr/lib/os-release"
test -f "$tmp/usr/lib/os-info.json"
test -f "$tmp/usr/share/onix/branding/logo.txt"
test -f "$tmp/usr/share/onix/branding/logo.ansi"
test -f "$tmp/usr/share/onix/filesystem-layout.md"
test -L "$tmp/etc/os-release"
test "$(readlink "$tmp/etc/os-release")" = "../usr/lib/os-release"
test -f "$tmp/etc/issue"
test -f "$tmp/etc/motd"
test -f "$tmp/etc/fstab"
test -f "$tmp/etc/profile"
test -f "$tmp/etc/profile.d/onix-path.sh"
test -f "$tmp/etc/profile.d/onix-login.sh"
test -f "$tmp/etc/hostname"
test "$(stat -c '%a' "$tmp/tmp")" = "1777"
grep -q '^NAME="ONIX"$' "$tmp/usr/lib/os-release"
grep -q '^ID="onix"$' "$tmp/usr/lib/os-release"
grep -q '^ANSI_COLOR="38;2;79;110;145"$' "$tmp/usr/lib/os-release"
grep -q 'LABEL=onix-root' "$tmp/etc/fstab"
grep -q 'LABEL=ONIX-PERSIST' "$tmp/etc/fstab"
grep -q 'moss controls the machine' "$tmp/etc/motd"
grep -q '▓' "$tmp/etc/motd"
grep -q '▒' "$tmp/etc/motd"
grep -q '/etc/profile.d' "$tmp/etc/profile"
grep -q "alias ll='ls -laF'" "$tmp/etc/profile.d/onix-path.sh"
grep -q 'logo.ansi' "$tmp/etc/profile.d/onix-login.sh"
test "$(wc -c < "$tmp/etc/motd")" -lt 2048

if find "$tmp" \( -name '.moss' -o -name 'moss-root' -o -name 'moss-cache' -o -name 'install-target' \) | grep -q .; then
  find "$tmp" \( -name '.moss' -o -name 'moss-root' -o -name 'moss-cache' -o -name 'install-target' \) >&2
  die "root tree export contains Moss assembly state"
fi

rm -rf "$ROOT_TREE_DIR"
mv "$tmp" "$ROOT_TREE_DIR"
trap - EXIT

echo "root tree: ${ROOT_TREE_DIR#$ONIX_ROOT/}"

echo
echo "==> exported root tree preview"
find "$ROOT_TREE_DIR" -maxdepth 4 -mindepth 1 | sort | sed "s#^$ROOT_TREE_DIR##" | sed -n '1,180p'

echo
echo "==> success"
echo "Phase 201 root tree is ready"
echo "artifact: $ROOT_TREE_DIR"
