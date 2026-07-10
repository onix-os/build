#!/usr/bin/env bash
# vm/phase2/build-root-tree-host.sh — assemble ONIX root tree with host moss.
#
# Runs on the host only. This is the host-native successor to Phase 201:
#
#   artifacts/onix-publish -> artifacts/host-tools/bin/moss -> artifacts/onix-root-tree
#
# It does not SSH into the forge, create a disk image, partition anything,
# mount anything, or boot.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHASE0_DIR="$(cd "$SCRIPT_DIR/../phase0" && pwd)"
PHASE1_DIR="$(cd "$SCRIPT_DIR/../phase1" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=vm/phase0/config.sh
source "$PHASE0_DIR/config.sh"

CHANNEL="${ONIX_REPO_CHANNEL:-unstable}"
ARCH="${ONIX_REPO_ARCH:-x86_64}"
EXPORT_ROOT="${ONIX_PUBLISH_EXPORT_DIR:-$ONIX_ROOT/artifacts/onix-publish}"
REPO_DIR="$EXPORT_ROOT/$CHANNEL/$ARCH"
HOST_TOOLS_DIR="${ONIX_HOST_TOOLS_DIR:-$ONIX_ROOT/artifacts/host-tools}"
HOST_MOSS="${ONIX_HOST_MOSS:-$HOST_TOOLS_DIR/bin/moss}"
ROOT_TREE_DIR="${ONIX_ROOT_TREE_DIR:-$ONIX_ROOT/artifacts/onix-root-tree}"
WORK_DIR="${ONIX_ROOT_TREE_WORK_DIR:-$ONIX_ROOT/artifacts/onix-root-tree-work}"
MOSS_ROOT="$WORK_DIR/moss-root"
MOSS_CACHE="$WORK_DIR/moss-cache"
TARGET_TMP="$WORK_DIR/root-tree"

need_cmd find
need_cmd grep
need_cmd readlink
need_cmd rm
need_cmd sed
need_cmd sha256sum
need_cmd sort
need_cmd stat

[[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/}; run make phase 202"
[[ -d "$EXPORT_ROOT" ]] || die "missing exported repo artifact: ${EXPORT_ROOT#$ONIX_ROOT/}; run make phase 105"
[[ -f "$REPO_DIR/stone.index" ]] || die "missing repo index: ${REPO_DIR#$ONIX_ROOT/}/stone.index; run make phase 106"
[[ -f "$REPO_DIR/SHA256SUMS" ]] || die "missing checksums: ${REPO_DIR#$ONIX_ROOT/}/SHA256SUMS; run make phase 106"

echo "==> Phase 203 input check: Phase 2 readiness"
"$SCRIPT_DIR/check-readiness.sh"

echo "==> Phase 203 input check: exported repo artifact"
"$PHASE1_DIR/verify-exported-repo.sh" >/dev/null
echo "artifact: ${EXPORT_ROOT#$ONIX_ROOT/}"
echo "index   : ${REPO_DIR#$ONIX_ROOT/}/stone.index"

echo
echo "==> Phase 203 input check: host moss"
"$HOST_MOSS" --version
"$HOST_MOSS" --version | grep -q "$OS_TOOLS_REF" \
  || die "host moss is not built from expected os-tools ref $OS_TOOLS_REF"

echo
echo "==> checksum input stones"
(
  cd "$REPO_DIR"
  sha256sum -c SHA256SUMS
)

echo
echo "==> moss install packages into host root tree"
rm -rf "$WORK_DIR"
mkdir -p "$MOSS_ROOT" "$MOSS_CACHE" "$TARGET_TMP"

"$HOST_MOSS" -D "$MOSS_ROOT" --cache "$MOSS_CACHE" repo add onix-image \
  "file://$REPO_DIR/stone.index" \
  -c "ONIX Phase 203 host image assembly repo"
"$HOST_MOSS" -D "$MOSS_ROOT" --cache "$MOSS_CACHE" repo update
"$HOST_MOSS" -D "$MOSS_ROOT" --cache "$MOSS_CACHE" -y install --to "$TARGET_TMP" \
  branding \
  filesystem

echo
echo "==> materialize image-owned root-level glue"
for dir in boot dev efi etc home proc run sys usr var persist; do
  install -dm00755 "$TARGET_TMP/$dir"
done
install -dm01777 "$TARGET_TMP/tmp"
chmod 01777 "$TARGET_TMP/tmp"
install -dm00755 "$TARGET_TMP/etc/profile.d"

ln -sfn ../usr/lib/os-release "$TARGET_TMP/etc/os-release"
cp "$TARGET_TMP/usr/share/defaults/etc/issue" "$TARGET_TMP/etc/issue"
cp "$TARGET_TMP/usr/share/defaults/etc/motd" "$TARGET_TMP/etc/motd"
cp "$TARGET_TMP/usr/share/defaults/etc/fstab" "$TARGET_TMP/etc/fstab"
cp "$TARGET_TMP/usr/share/defaults/etc/profile" "$TARGET_TMP/etc/profile"
cp "$TARGET_TMP/usr/share/defaults/etc/profile.d/onix-path.sh" "$TARGET_TMP/etc/profile.d/onix-path.sh"
cp "$TARGET_TMP/usr/share/defaults/etc/profile.d/onix-login.sh" "$TARGET_TMP/etc/profile.d/onix-login.sh"
printf 'onix\n' > "$TARGET_TMP/etc/hostname"
chmod 0644 \
  "$TARGET_TMP/etc/issue" \
  "$TARGET_TMP/etc/motd" \
  "$TARGET_TMP/etc/fstab" \
  "$TARGET_TMP/etc/profile" \
  "$TARGET_TMP/etc/profile.d/onix-path.sh" \
  "$TARGET_TMP/etc/profile.d/onix-login.sh" \
  "$TARGET_TMP/etc/hostname"

echo
echo "==> verify host root tree contract"
test -f "$TARGET_TMP/usr/lib/os-release"
test -f "$TARGET_TMP/usr/lib/os-info.json"
test -f "$TARGET_TMP/usr/lib/system-model.kdl"
test -f "$TARGET_TMP/usr/share/onix/branding/logo.txt"
test -f "$TARGET_TMP/usr/share/onix/branding/logo.ansi"
test -f "$TARGET_TMP/usr/share/onix/filesystem-layout.md"
test -f "$TARGET_TMP/usr/share/defaults/etc/fstab"
test -f "$TARGET_TMP/usr/share/defaults/etc/profile"
test -L "$TARGET_TMP/etc/os-release"
test "$(readlink "$TARGET_TMP/etc/os-release")" = "../usr/lib/os-release"
test -f "$TARGET_TMP/etc/issue"
test -f "$TARGET_TMP/etc/motd"
test -f "$TARGET_TMP/etc/fstab"
test -f "$TARGET_TMP/etc/profile"
test -f "$TARGET_TMP/etc/profile.d/onix-path.sh"
test -f "$TARGET_TMP/etc/profile.d/onix-login.sh"
test -f "$TARGET_TMP/etc/hostname"
test "$(stat -c '%a' "$TARGET_TMP/tmp")" = "1777"
grep -q '^NAME="ONIX"$' "$TARGET_TMP/usr/lib/os-release"
grep -q '^ID="onix"$' "$TARGET_TMP/usr/lib/os-release"
grep -q '^ANSI_COLOR="38;2;79;110;145"$' "$TARGET_TMP/usr/lib/os-release"
grep -q 'LABEL=onix-root' "$TARGET_TMP/etc/fstab"
grep -q 'LABEL=ONIX-PERSIST' "$TARGET_TMP/etc/fstab"
grep -q 'moss controls the machine' "$TARGET_TMP/etc/motd"
grep -q '▓' "$TARGET_TMP/etc/motd"
grep -q '▒' "$TARGET_TMP/etc/motd"
grep -q '/etc/profile.d' "$TARGET_TMP/etc/profile"
grep -q "alias ll='ls -laF'" "$TARGET_TMP/etc/profile.d/onix-path.sh"
grep -q 'logo.ansi' "$TARGET_TMP/etc/profile.d/onix-login.sh"
test "$(wc -c < "$TARGET_TMP/etc/motd")" -lt 2048
grep -q 'moss owns /usr' "$TARGET_TMP/usr/share/onix/filesystem-layout.md"
grep -q 'branding' "$TARGET_TMP/usr/lib/system-model.kdl"
grep -q 'filesystem' "$TARGET_TMP/usr/lib/system-model.kdl"
grep -q 'ONIX Phase 203 host image assembly repo' "$TARGET_TMP/usr/lib/system-model.kdl"

bad_brand='O''nix'
if grep -RIn "$bad_brand" "$TARGET_TMP" >/tmp/onix-root-tree-host-bad-brand.txt 2>/dev/null; then
  cat /tmp/onix-root-tree-host-bad-brand.txt >&2
  rm -f /tmp/onix-root-tree-host-bad-brand.txt
  die "forbidden spelling found in root tree; use ONIX or onix only"
fi
rm -f /tmp/onix-root-tree-host-bad-brand.txt

if find "$TARGET_TMP" \( -name '.moss' -o -name 'moss-root' -o -name 'moss-cache' -o -name 'install-target' \) | grep -q .; then
  find "$TARGET_TMP" \( -name '.moss' -o -name 'moss-root' -o -name 'moss-cache' -o -name 'install-target' \) >&2
  die "root tree contains Moss assembly state"
fi

echo
echo "==> publish host-built root tree artifact"
rm -rf "$ROOT_TREE_DIR"
mv "$TARGET_TMP" "$ROOT_TREE_DIR"

echo "root tree: ${ROOT_TREE_DIR#$ONIX_ROOT/}"

echo
echo "==> exported root tree preview"
find "$ROOT_TREE_DIR" -maxdepth 4 -mindepth 1 | sort | sed "s#^$ROOT_TREE_DIR##" | sed -n '1,180p'

echo
echo "==> generated system model"
cat "$ROOT_TREE_DIR/usr/lib/system-model.kdl"

echo
echo "==> success"
echo "Phase 203 host-native root tree is ready"
echo "artifact : $ROOT_TREE_DIR"
echo "host moss: $HOST_MOSS"
