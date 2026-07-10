#!/usr/bin/env bash
# vm/phase4/build-dropbear-stone.sh — Phase 412 source-built Dropbear stone.
#
# Runs on the host. The actual source build runs inside the Phase 0 forge VM so
# the produced payload is a musl-built .stone package, not a Nix payload.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHASE0_DIR="$(cd "$SCRIPT_DIR/../phase0" && pwd)"

# shellcheck source=vm/phase0/config.sh
source "$PHASE0_DIR/config.sh"

user="${1:-$BUILD_USER}"

STONE_DIR="${ONIX_STONE_DIR:-$ONIX_ROOT/artifacts/onix-stones}"
LOCAL_REPO_DIR="${ONIX_LOCAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-local-repo}"
STONE_WORK_DIR="${ONIX_STONE_WORK_DIR:-$ONIX_ROOT/artifacts/onix-stone-work}"
RECIPE_TEMPLATE="${ONIX_DROPBEAR_RECIPE_TEMPLATE:-$ONIX_ROOT/packages/services/dropbear/stone.yaml.in}"
HOST_MOSS="${ONIX_HOST_MOSS:-$ONIX_ROOT/artifacts/host-tools/bin/moss}"

LAB="/home/$user/stone-lab/dropbear"

need_cmd nix
need_cmd awk
need_cmd sed
need_cmd sha256sum
need_cmd tar

[[ -f "$RECIPE_TEMPLATE" ]] || die "missing recipe template: ${RECIPE_TEMPLATE#$ONIX_ROOT/}"
[[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"

extract_locked_nixpkgs_rev() {
  awk '
    /"nixpkgs_2"[[:space:]]*:/ { in_node=1 }
    in_node && /"rev"[[:space:]]*:/ {
      gsub(/[",]/, "", $2)
      print $2
      exit
    }
  ' "$ONIX_ROOT/flake.lock"
}

dropbear_source_path() {
  if [[ -n "${ONIX_DROPBEAR_SRC:-}" ]]; then
    printf '%s\n' "$ONIX_DROPBEAR_SRC"
    return
  fi

  local rev
  rev="$(extract_locked_nixpkgs_rev)"
  [[ -n "$rev" ]] || die "could not read pinned nixpkgs_2 rev from flake.lock"

  nix eval --raw "github:NixOS/nixpkgs/${rev}#dropbear.src.outPath"
}

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

DROPBEAR_SRC="$(dropbear_source_path)"
[[ -f "$DROPBEAR_SRC" ]] || die "Dropbear source is not a file: $DROPBEAR_SRC"

DROPBEAR_ARCHIVE="$(basename "$DROPBEAR_SRC")"
DROPBEAR_VERSION="$(printf '%s\n' "$DROPBEAR_ARCHIVE" | sed -E 's/^.*dropbear-([0-9][0-9.]*)\.tar.*$/\1/')"
[[ "$DROPBEAR_VERSION" != "$DROPBEAR_ARCHIVE" ]] || die "could not infer Dropbear version from $DROPBEAR_ARCHIVE"

DROPBEAR_SHA256="$(sha256sum "$DROPBEAR_SRC" | awk '{print $1}')"
WORK="$STONE_WORK_DIR/dropbear"
BUILD_ENV="$WORK/build.env"

log "Phase 412 source-built Dropbear stone"
mkdir -p "$STONE_DIR" "$LOCAL_REPO_DIR" "$WORK"
rm -rf "$WORK"
mkdir -p "$WORK"

log "source policy"
cat <<EOF
source      : $DROPBEAR_SRC
version     : $DROPBEAR_VERSION
sha256      : $DROPBEAR_SHA256
nix role    : source acquisition only
source build: Alpine/musl forge VM
stone cut   : boulder packages the musl-static payload into a .stone
stone out   : ${STONE_DIR#$ONIX_ROOT/}
local repo  : ${LOCAL_REPO_DIR#$ONIX_ROOT/}
EOF

cat > "$BUILD_ENV" <<EOF
DROPBEAR_VERSION='$DROPBEAR_VERSION'
DROPBEAR_ARCHIVE='$DROPBEAR_ARCHIVE'
DROPBEAR_SOURCE_SHA256='$DROPBEAR_SHA256'
EOF

log "copying recipe template + source tarball into the forge"
tar -cf - \
  -C "$WORK" build.env \
  -C "$(dirname "$RECIPE_TEMPLATE")" "$(basename "$RECIPE_TEMPLATE")" \
  -C "$(dirname "$DROPBEAR_SRC")" "$DROPBEAR_ARCHIVE" \
  | "$PHASE0_DIR/ssh.sh" "$user" "rm -rf '$LAB' && mkdir -p '$LAB/src' && tar -C '$LAB' -xf - && mv '$LAB/$DROPBEAR_ARCHIVE' '$LAB/src/$DROPBEAR_ARCHIVE' && if [ '$LAB/$(basename "$RECIPE_TEMPLATE")' != '$LAB/stone.yaml.in' ]; then mv '$LAB/$(basename "$RECIPE_TEMPLATE")' '$LAB/stone.yaml.in'; fi"

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
need_tool gcc
need_tool make
need_tool tar
need_tool bzip2
need_tool sha256sum
need_tool sed
need_tool grep
need_tool awk
need_tool install
need_tool file

LAB="$HOME/stone-lab/dropbear"
BUILD_SRC="$LAB/source-build"
PAYLOAD_SRC="$LAB/payload-src"
OUT="$LAB/out"
EXTRACT="$LAB/extracted"
REPO="$LAB/repo"
ROOT="$LAB/moss-root"
CACHE="$LAB/moss-cache"
TARGET="$LAB/install-target"

if [ ! -f "$LAB/build.env" ]; then
    echo "error: missing build environment: $LAB/build.env" >&2
    exit 1
fi

# shellcheck disable=SC1091
. "$LAB/build.env"

SOURCE_ARCHIVE="$LAB/src/$DROPBEAR_ARCHIVE"
SOURCE_HASH="$(sha256sum "$SOURCE_ARCHIVE" | awk '{print $1}')"
if [ "$SOURCE_HASH" != "$DROPBEAR_SOURCE_SHA256" ]; then
    echo "error: Dropbear source checksum mismatch" >&2
    echo "expected: $DROPBEAR_SOURCE_SHA256" >&2
    echo "actual  : $SOURCE_HASH" >&2
    exit 1
fi

echo "==> build musl-static Dropbear in the Alpine forge"
rm -rf "$BUILD_SRC" "$PAYLOAD_SRC"
mkdir -p "$BUILD_SRC" "$PAYLOAD_SRC"
tar -xf "$SOURCE_ARCHIVE" -C "$BUILD_SRC" --strip-components=1

jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
case "$jobs" in
    ''|*[!0-9]*) jobs=2 ;;
esac

(
    cd "$BUILD_SRC"
    ./configure \
        --prefix=/usr \
        --bindir=/usr/bin \
        --sbindir=/usr/sbin \
        --enable-static \
        --enable-bundled-libtom \
        --disable-zlib \
        --disable-pam \
        --disable-lastlog \
        --disable-utmp \
        --disable-utmpx \
        --disable-wtmp \
        --disable-wtmpx \
        --disable-loginfunc \
        --disable-pututline \
        --disable-pututxline \
        CFLAGS="-Os" \
        LDFLAGS="-static" \
        > "$LAB/configure.log" 2>&1

    if ! make -j"$jobs" PROGRAMS="dropbear dropbearkey" > "$LAB/build.log" 2>&1; then
        echo "error: Dropbear source build failed; tail of $LAB/build.log:" >&2
        tail -n 160 "$LAB/build.log" >&2
        exit 1
    fi
)

DROPBEAR_BIN="$BUILD_SRC/dropbear"
DROPBEARKEY_BIN="$BUILD_SRC/dropbearkey"
test -x "$DROPBEAR_BIN"
test -x "$DROPBEARKEY_BIN"
file "$DROPBEAR_BIN" | tee "$LAB/dropbear.file"
file "$DROPBEARKEY_BIN" | tee "$LAB/dropbearkey.file"
grep -Eqi 'statically linked|static-pie linked' "$LAB/dropbear.file"
grep -Eqi 'statically linked|static-pie linked' "$LAB/dropbearkey.file"
"$DROPBEARKEY_BIN" -t ed25519 -f "$LAB/test_ed25519_host_key" >/dev/null
test -s "$LAB/test_ed25519_host_key"
rm -f "$LAB/test_ed25519_host_key"

PAYLOAD_NAME="dropbear-payload-$DROPBEAR_VERSION"
PAYLOAD_ROOT="$LAB/src/$PAYLOAD_NAME"
PAYLOAD_ARCHIVE="$LAB/src/$PAYLOAD_NAME.tar.gz"

rm -rf "$PAYLOAD_ROOT" "$PAYLOAD_ARCHIVE"
mkdir -p \
    "$PAYLOAD_ROOT/usr/bin" \
    "$PAYLOAD_ROOT/usr/sbin" \
    "$PAYLOAD_ROOT/usr/share/onix/packages"

install -m 00755 "$DROPBEAR_BIN" "$PAYLOAD_ROOT/usr/sbin/dropbear"
install -m 00755 "$DROPBEARKEY_BIN" "$PAYLOAD_ROOT/usr/bin/dropbearkey"

cat > "$PAYLOAD_ROOT/usr/share/onix/packages/dropbear.md" <<EOF_DOC
# dropbear

\`dropbear\` is the ONIX bootstrap SSH server stone in Phase 4.

Source archive:

\`\`\`text
$DROPBEAR_ARCHIVE
\`\`\`

Source SHA-256:

\`\`\`text
$DROPBEAR_SOURCE_SHA256
\`\`\`

The Dropbear binaries were built in the Alpine/musl forge VM and then packaged
by boulder into a moss-installable .stone.

Installed commands:

\`\`\`text
/usr/sbin/dropbear
/usr/bin/dropbearkey
\`\`\`

Bootstrap build choices:

- static musl binaries
- bundled libtomcrypt/libtommath
- no PAM
- no zlib compression
- no utmp/wtmp/lastlog login accounting

Those choices keep the Phase 4 SSH proof small. Later ONIX can decide whether
to expand the SSH package or replace Dropbear with another server.
EOF_DOC

chmod 0644 "$PAYLOAD_ROOT/usr/share/onix/packages/dropbear.md"
chmod g-s \
    "$PAYLOAD_ROOT/usr" \
    "$PAYLOAD_ROOT/usr/bin" \
    "$PAYLOAD_ROOT/usr/sbin" \
    "$PAYLOAD_ROOT/usr/share" \
    "$PAYLOAD_ROOT/usr/share/onix" \
    "$PAYLOAD_ROOT/usr/share/onix/packages"

tar -C "$LAB/src" -czf "$PAYLOAD_ARCHIVE" "$PAYLOAD_NAME"
PAYLOAD_HASH="$(sha256sum "$PAYLOAD_ARCHIVE" | awk '{print $1}')"
PAYLOAD_URL="file://$PAYLOAD_ARCHIVE"

sed \
  -e "s|@DROPBEAR_VERSION@|$DROPBEAR_VERSION|g" \
  -e "s|@DROPBEAR_PAYLOAD_URL@|$PAYLOAD_URL|g" \
  -e "s|@DROPBEAR_PAYLOAD_SHA256@|$PAYLOAD_HASH|g" \
  -e "s|@DROPBEAR_SOURCE_ARCHIVE@|$DROPBEAR_ARCHIVE|g" \
  -e "s|@DROPBEAR_SOURCE_SHA256@|$DROPBEAR_SOURCE_SHA256|g" \
  "$LAB/stone.yaml.in" > "$LAB/stone.yaml"

echo "==> recipe"
sed -n '1,260p' "$LAB/stone.yaml"

echo
echo "==> building dropbear stone"
rm -rf "$OUT"
mkdir -p "$OUT"
(
    cd "$LAB"
    boulder build -y --normal-priority -o "$OUT" stone.yaml
)

STONE="$(find "$OUT" -maxdepth 1 -name 'dropbear-*.stone' ! -name '*dbginfo*' | sort | head -n 1)"
if [ ! -f "$STONE" ]; then
    echo "error: boulder did not produce an dropbear .stone under $OUT" >&2
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
moss inspect "$STONE" | sed -n '1,220p'

echo
echo "==> extract and verify static Dropbear payload"
rm -rf "$EXTRACT"
mkdir -p "$EXTRACT"
moss extract -o "$EXTRACT" "$STONE"
set -- "$EXTRACT"/*
PAYLOAD="$1"

test -x "$PAYLOAD/usr/sbin/dropbear"
test -x "$PAYLOAD/usr/bin/dropbearkey"
file "$PAYLOAD/usr/sbin/dropbear" | tee "$LAB/dropbear.extracted.file"
file "$PAYLOAD/usr/bin/dropbearkey" | tee "$LAB/dropbearkey.extracted.file"
grep -Eqi 'statically linked|static-pie linked' "$LAB/dropbear.extracted.file"
grep -Eqi 'statically linked|static-pie linked' "$LAB/dropbearkey.extracted.file"
"$PAYLOAD/usr/bin/dropbearkey" -t ed25519 -f "$LAB/test_extracted_ed25519_host_key" >/dev/null
test -s "$LAB/test_extracted_ed25519_host_key"
rm -f "$LAB/test_extracted_ed25519_host_key"
test -f "$PAYLOAD/usr/share/onix/packages/dropbear.md"

echo
echo "==> index local repo and install into disposable target"
rm -rf "$REPO" "$ROOT" "$CACHE" "$TARGET"
mkdir -p "$REPO" "$ROOT" "$CACHE" "$TARGET"
cp "$STONE" "$REPO/"
moss index "$REPO"
moss -D "$ROOT" --cache "$CACHE" repo add local "file://$REPO/stone.index" -c "local onix dropbear repo"
moss -D "$ROOT" --cache "$CACHE" repo update
moss -D "$ROOT" --cache "$CACHE" -y install --to "$TARGET" dropbear

test -x "$TARGET/usr/sbin/dropbear"
test -x "$TARGET/usr/bin/dropbearkey"
"$TARGET/usr/bin/dropbearkey" -t ed25519 -f "$LAB/test_installed_ed25519_host_key" >/dev/null
test -s "$LAB/test_installed_ed25519_host_key"
rm -f "$LAB/test_installed_ed25519_host_key"

echo
echo "==> success"
echo "stone : $STONE"
echo "repo  : $REPO/stone.index"
echo "root  : $ROOT"
echo "target: $TARGET"
REMOTE

log "copying built stone back to host artifacts"
rm -f "$STONE_DIR"/dropbear-*.stone "$STONE_DIR"/dropbear-dbginfo-*.stone
"$PHASE0_DIR/ssh.sh" "$user" "stone=\$(cat '$LAB/stone.path') && cd \"\$(dirname \"\$stone\")\" && tar -cf - \"\$(basename \"\$stone\")\"" \
  | tar -C "$STONE_DIR" -xf -

HOST_STONE="$(find "$STONE_DIR" -maxdepth 1 -name 'dropbear-*.stone' ! -name '*dbginfo*' | sort | tail -n 1)"
[[ -f "$HOST_STONE" ]] || die "failed to copy dropbear stone into ${STONE_DIR#$ONIX_ROOT/}"

log "host moss integrity check"
"$HOST_MOSS" inspect --check "$HOST_STONE"

log "refreshing local Phase 4 moss repo"
rm -f "$LOCAL_REPO_DIR"/dropbear-*.stone "$LOCAL_REPO_DIR"/dropbear-dbginfo-*.stone
cp "$HOST_STONE" "$LOCAL_REPO_DIR/"
"$HOST_MOSS" index "$LOCAL_REPO_DIR"

cat <<EOF

==> success
dropbear stone: ${HOST_STONE#$ONIX_ROOT/}
local repo index    : ${LOCAL_REPO_DIR#$ONIX_ROOT/}/stone.index

Next:
  make phase 413

EOF
