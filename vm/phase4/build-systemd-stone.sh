#!/usr/bin/env bash
# vm/phase4/build-systemd-stone.sh — Phase 415 bootstrap systemd stone.
#
# This is intentionally not the final native ONIX systemd recipe. It packages
# the exact musl systemd payload proved in Phase 213/414 into a .stone so the
# machine-plane owner exists before Phase 416 switches the image to consume it.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHASE0_DIR="$(cd "$SCRIPT_DIR/../phase0" && pwd)"

# shellcheck source=vm/phase0/config.sh
source "$PHASE0_DIR/config.sh"

user="${1:-$BUILD_USER}"

STONE_DIR="${ONIX_STONE_DIR:-$ONIX_ROOT/artifacts/onix-stones}"
LOCAL_REPO_DIR="${ONIX_LOCAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-local-repo}"
STONE_WORK_DIR="${ONIX_STONE_WORK_DIR:-$ONIX_ROOT/artifacts/onix-stone-work}"
RECIPE_TEMPLATE="${ONIX_SYSTEMD_RECIPE_TEMPLATE:-$SCRIPT_DIR/stone-recipes/systemd/stone.yaml.in}"
HOST_MOSS="${ONIX_HOST_MOSS:-$ONIX_ROOT/artifacts/host-tools/bin/moss}"
SYSTEMD_PAYLOAD_OUT_FILE="${ONIX_SYSTEMD_PAYLOAD_OUT_FILE:-$ONIX_ROOT/artifacts/onix-image/systemd-payload.out}"
SYSTEMD_CLOSURE_LIST="${ONIX_SYSTEMD_CLOSURE_LIST:-$ONIX_ROOT/artifacts/onix-image/systemd-payload.closure}"

LAB="/home/$user/stone-lab/systemd"

need_cmd awk
need_cmd file
need_cmd find
need_cmd grep
need_cmd install
need_cmd readelf
need_cmd sed
need_cmd sha256sum
need_cmd sort
need_cmd tar
need_cmd wc

[[ -f "$RECIPE_TEMPLATE" ]] || die "missing recipe template: ${RECIPE_TEMPLATE#$ONIX_ROOT/}"
[[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"
[[ -f "$SYSTEMD_PAYLOAD_OUT_FILE" ]] || die "missing systemd payload path: ${SYSTEMD_PAYLOAD_OUT_FILE#$ONIX_ROOT/} (run: make phase 213)"
[[ -s "$SYSTEMD_CLOSURE_LIST" ]] || die "missing systemd closure list: ${SYSTEMD_CLOSURE_LIST#$ONIX_ROOT/} (run: make phase 213)"

safe_artifact_path() {
  local path="$1"
  case "$path" in
    "$ONIX_ROOT"/artifacts/*) ;;
    *) die "refusing artifact path outside artifacts/: $path" ;;
  esac
}

safe_artifact_path "$STONE_DIR"
safe_artifact_path "$LOCAL_REPO_DIR"
safe_artifact_path "$STONE_WORK_DIR"

SYSTEMD_PAYLOAD_OUT="$(< "$SYSTEMD_PAYLOAD_OUT_FILE")"
[[ "$SYSTEMD_PAYLOAD_OUT" == /nix/store/*-systemd-* ]] \
  || die "systemd payload is not a Nix systemd output: $SYSTEMD_PAYLOAD_OUT"
[[ -x "$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd" ]] \
  || die "missing systemd binary: $SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd"
[[ -f "$SYSTEMD_PAYLOAD_OUT/example/systemd/system/multi-user.target" ]] \
  || die "missing systemd system unit tree: $SYSTEMD_PAYLOAD_OUT/example/systemd/system"

SYSTEMD_VERSION="$(basename "$SYSTEMD_PAYLOAD_OUT" | sed -E 's/^[^-]+-systemd-([0-9][0-9.]*).*$/\1/')"
[[ -n "$SYSTEMD_VERSION" && "$SYSTEMD_VERSION" != "$(basename "$SYSTEMD_PAYLOAD_OUT")" ]] \
  || die "could not infer systemd version from $SYSTEMD_PAYLOAD_OUT"

WORK="$STONE_WORK_DIR/systemd"
PAYLOAD_NAME="systemd-payload-$SYSTEMD_VERSION"
PAYLOAD_ROOT="$WORK/$PAYLOAD_NAME"
BOOTSTRAP_PREFIX="/usr/lib/onix/bootstrap"
BOOTSTRAP_ROOT="$PAYLOAD_ROOT$BOOTSTRAP_PREFIX"
PAYLOAD_ARCHIVE="$WORK/$PAYLOAD_NAME.tar.gz"
BUILD_ENV="$WORK/build.env"
CLOSURE_REL="$WORK/systemd-closure.rel"
CLOSURE_COUNT="$(wc -l < "$SYSTEMD_CLOSURE_LIST" | tr -d '[:space:]')"

cleanup_work_dir() {
  case "$WORK" in
    "$ONIX_ROOT"/artifacts/onix-stone-work/systemd) ;;
    *) die "refusing unsafe work cleanup path: $WORK" ;;
  esac

  if [[ -d "$WORK" ]]; then
    chmod -R u+rwX "$WORK" 2>/dev/null || true
    rm -rf "$WORK"
  fi
}

mkdir -p "$STONE_DIR" "$LOCAL_REPO_DIR" "$STONE_WORK_DIR"
cleanup_work_dir
mkdir -p "$PAYLOAD_ROOT"

log "Phase 415 bootstrap systemd stone"
cat <<EOF
systemd out : $SYSTEMD_PAYLOAD_OUT
version     : $SYSTEMD_VERSION
closure     : ${SYSTEMD_CLOSURE_LIST#$ONIX_ROOT/}
entries     : $CLOSURE_COUNT
nix role    : bootstrap build provenance for this first ownership stone
stone cut   : boulder packages the proven systemd closure into a .stone
stone out   : ${STONE_DIR#$ONIX_ROOT/}
local repo  : ${LOCAL_REPO_DIR#$ONIX_ROOT/}
EOF

log "verifying current systemd payload shape"
file "$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd"
readelf -l "$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd" |
  grep -q 'Requesting program interpreter: /nix/store/.*/ld-musl-x86_64\.so\.1' \
  || die "systemd is not using the expected musl loader path"

while IFS= read -r store_path; do
  [[ -n "$store_path" ]] || continue
  [[ -e "$store_path" ]] || die "closure path is missing on host: $store_path"
done < "$SYSTEMD_CLOSURE_LIST"

sed 's#^/##' "$SYSTEMD_CLOSURE_LIST" > "$CLOSURE_REL"

log "staging systemd closure into package payload"
install -dm0755 "$BOOTSTRAP_ROOT"
tar --numeric-owner -C / -cpf - -T "$CLOSURE_REL" |
  tar --no-same-owner --no-same-permissions -C "$BOOTSTRAP_ROOT" -xpf -
find "$BOOTSTRAP_ROOT/nix/store" -type d -exec chmod 0755 {} +

log "staging /usr activation symlinks"
install -dm0755 \
  "$PAYLOAD_ROOT/usr/bin" \
  "$PAYLOAD_ROOT/usr/lib/onix/bootstrap" \
  "$PAYLOAD_ROOT/usr/lib/systemd" \
  "$PAYLOAD_ROOT/usr/share/onix/packages"

find "$SYSTEMD_PAYLOAD_OUT/lib/systemd" -maxdepth 1 -mindepth 1 | sort |
  while IFS= read -r entry; do
    ln -sfn "$entry" "$PAYLOAD_ROOT/usr/lib/systemd/$(basename "$entry")"
  done
ln -sfn "$SYSTEMD_PAYLOAD_OUT/example/systemd/system" "$PAYLOAD_ROOT/usr/lib/systemd/system"
ln -sfn "$SYSTEMD_PAYLOAD_OUT/example/systemd/user" "$PAYLOAD_ROOT/usr/lib/systemd/user"

for bin in systemctl journalctl loginctl machinectl networkctl systemd-analyze systemd-tmpfiles systemd-sysusers udevadm; do
  if [[ -e "$SYSTEMD_PAYLOAD_OUT/bin/$bin" ]]; then
    ln -sfn "$SYSTEMD_PAYLOAD_OUT/bin/$bin" "$PAYLOAD_ROOT/usr/bin/$bin"
  fi
done

{
  echo "# systemd"
  echo
  echo "\`systemd\` is the Phase 415 bootstrap ownership stone for the"
  echo "currently proven musl systemd userspace payload."
  echo
  echo "Systemd output:"
  echo
  echo "\`\`\`text"
  echo "$SYSTEMD_PAYLOAD_OUT"
  echo "\`\`\`"
  echo
  echo "Important paths installed by this package:"
  echo
  echo "\`\`\`text"
  echo "/nix/store/... systemd runtime closure"
  echo "/usr/lib/onix/bootstrap/nix/store/... packaged bootstrap copy"
  echo "/usr/lib/systemd/systemd"
  echo "/usr/lib/systemd/system"
  echo "/usr/lib/systemd/user"
  echo "/usr/bin/systemctl"
  echo "/usr/bin/journalctl"
  echo "/usr/bin/systemd-tmpfiles"
  echo "/usr/bin/systemd-sysusers"
  echo "/usr/bin/udevadm"
  echo "\`\`\`"
  echo
  echo "This first package is intentionally a bootstrap ownership package."
  echo "The payload was built by pinned nixpkgs pkgsMusl.systemd and then packaged"
  echo "as a moss-installable .stone. Later ONIX should replace this with a native"
  echo "source recipe and split dependency ownership more cleanly."
  echo
  echo "Moss packages /usr payloads, so this stone carries the Nix closure under:"
  echo
  echo "\`\`\`text"
  echo "/usr/lib/onix/bootstrap/nix/store"
  echo "\`\`\`"
  echo
  echo "Phase 416 materializes that bootstrap copy to /nix/store inside the image"
  echo "so the absolute musl loader and runtime dependency paths resolve at boot."
} > "$PAYLOAD_ROOT/usr/share/onix/packages/systemd.md"

cp "$SYSTEMD_CLOSURE_LIST" "$PAYLOAD_ROOT/usr/share/onix/packages/systemd.closure"
{
  echo "/usr/lib/onix/bootstrap/nix/store -> packaged copy of runtime closure"
  echo "/usr/lib/systemd/systemd -> $SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd"
  echo "/usr/lib/systemd/system -> $SYSTEMD_PAYLOAD_OUT/example/systemd/system"
  echo "/usr/lib/systemd/user -> $SYSTEMD_PAYLOAD_OUT/example/systemd/user"
  for link in "$PAYLOAD_ROOT"/usr/bin/*; do
    [[ -e "$link" ]] || continue
    printf '/usr/bin/%s -> %s\n' "$(basename "$link")" "$(readlink "$link")"
  done
} > "$PAYLOAD_ROOT/usr/share/onix/packages/systemd.links"

chmod 0644 \
  "$PAYLOAD_ROOT/usr/share/onix/packages/systemd.md" \
  "$PAYLOAD_ROOT/usr/share/onix/packages/systemd.closure" \
  "$PAYLOAD_ROOT/usr/share/onix/packages/systemd.links"

log "verifying staged payload"
[[ -x "$BOOTSTRAP_ROOT$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd" ]]
[[ "$(readlink "$PAYLOAD_ROOT/usr/lib/systemd/systemd")" == "$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd" ]]
[[ "$(readlink "$PAYLOAD_ROOT/usr/lib/systemd/system")" == "$SYSTEMD_PAYLOAD_OUT/example/systemd/system" ]]
[[ -L "$PAYLOAD_ROOT/usr/bin/systemctl" ]]
[[ -d "$PAYLOAD_ROOT/usr/lib/onix/bootstrap/nix/store" ]]
[[ -f "$PAYLOAD_ROOT/usr/share/onix/packages/systemd.closure" ]]
grep -q "$SYSTEMD_PAYLOAD_OUT" "$PAYLOAD_ROOT/usr/share/onix/packages/systemd.closure"

log "creating prepared payload archive"
tar --numeric-owner -C "$WORK" -czf "$PAYLOAD_ARCHIVE" "$PAYLOAD_NAME"
PAYLOAD_HASH="$(sha256sum "$PAYLOAD_ARCHIVE" | awk '{print $1}')"
PAYLOAD_URL="file://$LAB/src/$(basename "$PAYLOAD_ARCHIVE")"

cat > "$BUILD_ENV" <<EOF
SYSTEMD_VERSION='$SYSTEMD_VERSION'
SYSTEMD_PAYLOAD_OUT='$SYSTEMD_PAYLOAD_OUT'
SYSTEMD_CLOSURE_COUNT='$CLOSURE_COUNT'
SYSTEMD_PAYLOAD_ARCHIVE='$(basename "$PAYLOAD_ARCHIVE")'
SYSTEMD_PAYLOAD_SHA256='$PAYLOAD_HASH'
EOF

log "copying recipe template + prepared payload into the forge"
tar -cf - \
  -C "$WORK" build.env "$(basename "$PAYLOAD_ARCHIVE")" \
  -C "$(dirname "$RECIPE_TEMPLATE")" "$(basename "$RECIPE_TEMPLATE")" \
  | "$PHASE0_DIR/ssh.sh" "$user" "if [ -d '$LAB' ]; then chmod -R u+rwX '$LAB' 2>/dev/null || true; rm -rf '$LAB'; fi && mkdir -p '$LAB/src' && tar -C '$LAB' -xf - && mv '$LAB/$(basename "$PAYLOAD_ARCHIVE")' '$LAB/src/$(basename "$PAYLOAD_ARCHIVE")' && if [ '$(basename "$RECIPE_TEMPLATE")' != 'stone.yaml.in' ]; then mv '$LAB/$(basename "$RECIPE_TEMPLATE")' '$LAB/stone.yaml.in'; fi"

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
need_tool tar
need_tool gzip
need_tool sha256sum
need_tool sed
need_tool grep
need_tool awk
need_tool install
need_tool file
need_tool readelf

LAB="$HOME/stone-lab/systemd"
OUT="$LAB/out"
EXTRACT="$LAB/extracted"
REPO="$LAB/repo"
ROOT="$LAB/moss-root"
CACHE="$LAB/moss-cache"
TARGET="$LAB/install-target"

safe_rm_rf() {
    for path in "$@"; do
        if [ -e "$path" ]; then
            chmod -R u+rwX "$path" 2>/dev/null || true
            rm -rf "$path"
        fi
    done
}

if [ ! -f "$LAB/build.env" ]; then
    echo "error: missing build environment: $LAB/build.env" >&2
    exit 1
fi

# shellcheck disable=SC1091
. "$LAB/build.env"

PAYLOAD_ARCHIVE="$LAB/src/$SYSTEMD_PAYLOAD_ARCHIVE"
PAYLOAD_HASH="$(sha256sum "$PAYLOAD_ARCHIVE" | awk '{print $1}')"
if [ "$PAYLOAD_HASH" != "$SYSTEMD_PAYLOAD_SHA256" ]; then
    echo "error: systemd payload checksum mismatch" >&2
    echo "expected: $SYSTEMD_PAYLOAD_SHA256" >&2
    echo "actual  : $PAYLOAD_HASH" >&2
    exit 1
fi

sed \
  -e "s|@SYSTEMD_VERSION@|$SYSTEMD_VERSION|g" \
  -e "s|@SYSTEMD_PAYLOAD_URL@|file://$PAYLOAD_ARCHIVE|g" \
  -e "s|@SYSTEMD_PAYLOAD_SHA256@|$SYSTEMD_PAYLOAD_SHA256|g" \
  -e "s|@SYSTEMD_PAYLOAD_OUT@|$SYSTEMD_PAYLOAD_OUT|g" \
  -e "s|@SYSTEMD_CLOSURE_COUNT@|$SYSTEMD_CLOSURE_COUNT|g" \
  "$LAB/stone.yaml.in" > "$LAB/stone.yaml"

echo "==> recipe"
sed -n '1,260p' "$LAB/stone.yaml"

echo
echo "==> building systemd stone"
safe_rm_rf "$OUT"
mkdir -p "$OUT"
(
    cd "$LAB"
    boulder build -y --normal-priority -o "$OUT" stone.yaml
)

STONE="$(find "$OUT" -maxdepth 1 -name 'systemd-*.stone' ! -name '*dbginfo*' | sort | head -n 1)"
if [ ! -f "$STONE" ]; then
    echo "error: boulder did not produce an systemd .stone under $OUT" >&2
    exit 1
fi
printf '%s\n' "$STONE" > "$LAB/stone.path"

echo
echo "==> built artifact"
ls -lh "$OUT"
file "$STONE"

echo
echo "==> moss integrity check"
moss inspect --check "$STONE"

echo
echo "==> moss layout"
moss inspect "$STONE" | sed -n '1,260p'

echo
echo "==> extract and verify systemd payload"
safe_rm_rf "$EXTRACT"
mkdir -p "$EXTRACT"
moss extract -o "$EXTRACT" "$STONE"
set -- "$EXTRACT"/*
PAYLOAD="$1"

test -x "$PAYLOAD/usr/lib/onix/bootstrap$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd"
test -f "$PAYLOAD/usr/lib/onix/bootstrap$SYSTEMD_PAYLOAD_OUT/example/systemd/system/multi-user.target"
test -d "$PAYLOAD/usr/lib/onix/bootstrap/nix/store"
test "$(readlink "$PAYLOAD/usr/lib/systemd/systemd")" = "$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd"
test "$(readlink "$PAYLOAD/usr/lib/systemd/system")" = "$SYSTEMD_PAYLOAD_OUT/example/systemd/system"
test -L "$PAYLOAD/usr/bin/systemctl"
test -f "$PAYLOAD/usr/share/onix/packages/systemd.md"
test -f "$PAYLOAD/usr/share/onix/packages/systemd.closure"
grep -q "$SYSTEMD_PAYLOAD_OUT" "$PAYLOAD/usr/share/onix/packages/systemd.closure"
file "$PAYLOAD/usr/lib/onix/bootstrap$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd" | tee "$LAB/systemd.extracted.file"
readelf -l "$PAYLOAD/usr/lib/onix/bootstrap$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd" |
    grep -q 'Requesting program interpreter: /nix/store/.*/ld-musl-x86_64\.so\.1'

echo
echo "==> index local repo and install into disposable target"
safe_rm_rf "$REPO" "$ROOT" "$CACHE" "$TARGET"
mkdir -p "$REPO" "$ROOT" "$CACHE" "$TARGET"
cp "$STONE" "$REPO/"
moss index "$REPO"
moss -D "$ROOT" --cache "$CACHE" repo add local "file://$REPO/stone.index" -c "local onix systemd repo"
moss -D "$ROOT" --cache "$CACHE" repo update
moss -D "$ROOT" --cache "$CACHE" -y install --to "$TARGET" systemd

test -x "$TARGET/usr/lib/onix/bootstrap$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd"
test -d "$TARGET/usr/lib/onix/bootstrap/nix/store"
test "$(readlink "$TARGET/usr/lib/systemd/systemd")" = "$SYSTEMD_PAYLOAD_OUT/lib/systemd/systemd"
test "$(readlink "$TARGET/usr/bin/systemctl")" = "$SYSTEMD_PAYLOAD_OUT/bin/systemctl"
test -f "$TARGET/usr/share/onix/packages/systemd.md"

echo
echo "==> success"
echo "stone : $STONE"
echo "repo  : $REPO/stone.index"
echo "root  : $ROOT"
echo "target: $TARGET"
REMOTE

log "copying built stone back to host artifacts"
rm -f "$STONE_DIR"/systemd-*.stone "$STONE_DIR"/systemd-dbginfo-*.stone
"$PHASE0_DIR/ssh.sh" "$user" "stone=\$(cat '$LAB/stone.path') && cd \"\$(dirname \"\$stone\")\" && tar -cf - \"\$(basename \"\$stone\")\"" \
  | tar -C "$STONE_DIR" -xf -

HOST_STONE="$(find "$STONE_DIR" -maxdepth 1 -name 'systemd-*.stone' ! -name '*dbginfo*' | sort | tail -n 1)"
[[ -f "$HOST_STONE" ]] || die "failed to copy systemd stone into ${STONE_DIR#$ONIX_ROOT/}"

log "host moss integrity check"
"$HOST_MOSS" inspect --check "$HOST_STONE"

log "refreshing local Phase 4 moss repo"
rm -f "$LOCAL_REPO_DIR"/systemd-*.stone "$LOCAL_REPO_DIR"/systemd-dbginfo-*.stone
cp "$HOST_STONE" "$LOCAL_REPO_DIR/"
"$HOST_MOSS" index "$LOCAL_REPO_DIR"

cat <<EOF

==> success
systemd stone: ${HOST_STONE#$ONIX_ROOT/}
local repo index  : ${LOCAL_REPO_DIR#$ONIX_ROOT/}/stone.index

Next:
  make phase 416

EOF
