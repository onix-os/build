#!/usr/bin/env bash
# vm/phase4/build-native-systemd-stone.sh — Phase 422 native onix-systemd.
#
# This is the first real native systemd step for ONIX:
#
#   host Nix/dev shell: source acquisition + orchestration only
#   Alpine forge VM  : actual musl source build + boulder packaging
#   moss repo        : refreshed local Phase 4 package index
#
# The result must not install or reference /nix/store runtime paths.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHASE0_DIR="$(cd "$SCRIPT_DIR/../phase0" && pwd)"

# shellcheck source=vm/phase0/config.sh
source "$PHASE0_DIR/config.sh"

user="${1:-$BUILD_USER}"

STONE_DIR="${ONIX_STONE_DIR:-$ONIX_ROOT/artifacts/onix-stones}"
LOCAL_REPO_DIR="${ONIX_LOCAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-local-repo}"
STONE_WORK_DIR="${ONIX_STONE_WORK_DIR:-$ONIX_ROOT/artifacts/onix-stone-work}"
PLAN_DIR="${ONIX_NATIVE_SYSTEMD_PLAN_DIR:-$ONIX_ROOT/artifacts/onix-native-systemd-plan}"
SOURCE_POLICY="${ONIX_NATIVE_SYSTEMD_SOURCE_POLICY:-$PLAN_DIR/source-policy.txt}"
RECIPE_TEMPLATE="${ONIX_SYSTEMD_NATIVE_RECIPE_TEMPLATE:-$ONIX_ROOT/packages/services/onix-systemd/stone.yaml.in}"
HOST_MOSS="${ONIX_HOST_MOSS:-$ONIX_ROOT/artifacts/host-tools/bin/moss}"

LAB="/home/$user/stone-lab/onix-systemd-native"

need_cmd awk
need_cmd grep
need_cmd install
need_cmd sed
need_cmd sha256sum
need_cmd tar

[[ -f "$RECIPE_TEMPLATE" ]] || die "missing recipe template: ${RECIPE_TEMPLATE#$ONIX_ROOT/}"
[[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"
[[ -f "$SOURCE_POLICY" ]] || die "missing Phase 421 source policy: ${SOURCE_POLICY#$ONIX_ROOT/} (run: make phase 421)"

safe_artifact_path() {
  local path="$1"
  case "$path" in
    "$ONIX_ROOT"/artifacts/*) ;;
    *) die "refusing artifact path outside artifacts/: $path" ;;
  esac
}

policy_block_value() {
  local key="$1"
  awk -v key="$key:" '
    $0 == key {
      getline
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      print
      exit
    }
  ' "$SOURCE_POLICY"
}

policy_inline_value() {
  local key="$1"
  awk -v key="$key" '
    $0 ~ "^[[:space:]]*" key "[[:space:]]*:" {
      sub("^[[:space:]]*" key "[[:space:]]*:[[:space:]]*", "")
      print
      exit
    }
  ' "$SOURCE_POLICY"
}

safe_artifact_path "$STONE_DIR"
safe_artifact_path "$LOCAL_REPO_DIR"
safe_artifact_path "$STONE_WORK_DIR"

SYSTEMD_VERSION="${ONIX_SYSTEMD_NATIVE_VERSION:-$(policy_block_value "Systemd version")}"
SYSTEMD_SRC="${ONIX_SYSTEMD_NATIVE_SRC:-$(policy_block_value "Current pkgsMusl.systemd source path")}"
SYSTEMD_UPSTREAM_REV="${ONIX_SYSTEMD_NATIVE_UPSTREAM_REV:-$(policy_inline_value "rev")}"

[[ -n "$SYSTEMD_VERSION" ]] || die "could not read systemd version from ${SOURCE_POLICY#$ONIX_ROOT/}"
[[ -n "$SYSTEMD_SRC" ]] || die "could not read systemd source path from ${SOURCE_POLICY#$ONIX_ROOT/}"
[[ -d "$SYSTEMD_SRC" ]] || die "systemd source path is not a directory: $SYSTEMD_SRC"
[[ -f "$SYSTEMD_SRC/meson.build" ]] || die "systemd source path is missing meson.build: $SYSTEMD_SRC"
[[ -n "$SYSTEMD_UPSTREAM_REV" ]] || SYSTEMD_UPSTREAM_REV="v$SYSTEMD_VERSION"

WORK="$STONE_WORK_DIR/onix-systemd-native"
BUILD_ENV="$WORK/build.env"
SOURCE_BASENAME="systemd-$SYSTEMD_VERSION-source.tar"
SOURCE_TAR="$WORK/$SOURCE_BASENAME"
SOURCE_ARCHIVE="$SOURCE_TAR.gz"

cleanup_work_dir() {
  case "$WORK" in
    "$ONIX_ROOT"/artifacts/onix-stone-work/onix-systemd-native) ;;
    *) die "refusing unsafe work cleanup path: $WORK" ;;
  esac

  if [[ -d "$WORK" ]]; then
    chmod -R u+rwX "$WORK" 2>/dev/null || true
    rm -rf "$WORK"
  fi
}

mkdir -p "$STONE_DIR" "$LOCAL_REPO_DIR" "$STONE_WORK_DIR"
cleanup_work_dir
mkdir -p "$WORK"

log "Phase 422 native source-built onix-systemd stone"
cat <<EOF
source      : $SYSTEMD_SRC
version     : $SYSTEMD_VERSION
upstream    : $SYSTEMD_UPSTREAM_REV
nix role    : source acquisition/reference only
source build: Alpine/musl forge VM
stone cut   : boulder packages the native payload into a .stone
stone out   : ${STONE_DIR#$ONIX_ROOT/}
local repo  : ${LOCAL_REPO_DIR#$ONIX_ROOT/}
EOF

log "creating writable source archive for the forge"
tar \
  --mode='u+rwX,go+rX' \
  --exclude='./.git' \
  --exclude='./build' \
  -C "$SYSTEMD_SRC" \
  -cf "$SOURCE_TAR" .
gzip -n -f "$SOURCE_TAR"
SYSTEMD_SOURCE_SHA256="$(sha256sum "$SOURCE_ARCHIVE" | awk '{print $1}')"

cat > "$BUILD_ENV" <<EOF
SYSTEMD_VERSION='$SYSTEMD_VERSION'
SYSTEMD_UPSTREAM_REV='$SYSTEMD_UPSTREAM_REV'
SYSTEMD_SOURCE_ARCHIVE='$(basename "$SOURCE_ARCHIVE")'
SYSTEMD_SOURCE_SHA256='$SYSTEMD_SOURCE_SHA256'
EOF

log "ensuring native systemd build dependencies in the forge"
"$PHASE0_DIR/ssh.sh" root \
  "apk add --no-cache build-base meson samurai gperf m4 coreutils findutils py3-jinja2 file binutils pkgconf linux-headers libcap-dev util-linux-dev kmod-dev acl-dev xz-dev zstd-dev pcre2-dev gettext-dev bash"

log "copying source archive + recipe template into the forge"
RECIPE_BASENAME="$(basename "$RECIPE_TEMPLATE")"
tar -cf - \
  -C "$WORK" build.env "$(basename "$SOURCE_ARCHIVE")" \
  -C "$(dirname "$RECIPE_TEMPLATE")" "$RECIPE_BASENAME" \
  | "$PHASE0_DIR/ssh.sh" "$user" "if [ -d '$LAB' ]; then chmod -R u+rwX '$LAB' 2>/dev/null || true; rm -rf '$LAB'; fi && mkdir -p '$LAB/src' && tar -C '$LAB' -xf - && mv '$LAB/$(basename "$SOURCE_ARCHIVE")' '$LAB/src/$(basename "$SOURCE_ARCHIVE")' && if [ '$RECIPE_BASENAME' != 'stone.yaml.in' ]; then mv '$LAB/$RECIPE_BASENAME' '$LAB/stone.yaml.in'; fi"

"$PHASE0_DIR/ssh.sh" "$user" /bin/sh -s <<'REMOTE'
set -eu

export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: missing '$1' in the forge" >&2
        exit 1
    fi
}

need_tool boulder
need_tool moss
need_tool meson
need_tool ninja
need_tool gcc
need_tool gperf
need_tool m4
need_tool tar
need_tool gzip
need_tool sha256sum
need_tool sed
need_tool grep
need_tool awk
need_tool install
need_tool readelf
need_tool file
need_tool ldd

LAB="$HOME/stone-lab/onix-systemd-native"
BUILD_SRC="$LAB/source"
BUILD_DIR="$LAB/build"
DEST="$LAB/dest"
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

SOURCE_ARCHIVE="$LAB/src/$SYSTEMD_SOURCE_ARCHIVE"
SOURCE_HASH="$(sha256sum "$SOURCE_ARCHIVE" | awk '{print $1}')"
if [ "$SOURCE_HASH" != "$SYSTEMD_SOURCE_SHA256" ]; then
    echo "error: systemd source checksum mismatch" >&2
    echo "expected: $SYSTEMD_SOURCE_SHA256" >&2
    echo "actual  : $SOURCE_HASH" >&2
    exit 1
fi

echo "==> build native musl systemd in the Alpine forge"
rm -rf "$BUILD_SRC" "$BUILD_DIR" "$DEST"
mkdir -p "$BUILD_SRC" "$DEST"
tar -xzf "$SOURCE_ARCHIVE" -C "$BUILD_SRC"

jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
case "$jobs" in
    ''|*[!0-9]*) jobs=2 ;;
esac

meson setup "$BUILD_DIR" "$BUILD_SRC" \
    --prefix=/usr \
    --libdir=lib \
    --buildtype=release \
    -Dlibc=musl \
    -Dmode=release \
    -Dsplit-bin=false \
    -Dtests=false \
    -Dman=disabled \
    -Dhtml=disabled \
    -Dtranslations=false \
    -Dfirstboot=false \
    -Dhomed=disabled \
    -Dnetworkd=false \
    -Dresolve=false \
    -Dtimesyncd=false \
    -Dremote=disabled \
    -Dimportd=disabled \
    -Dnspawn=disabled \
    -Dmachined=false \
    -Dportabled=false \
    -Doomd=false \
    -Dcoredump=false \
    -Drepart=disabled \
    -Dsysupdate=disabled \
    -Dsysupdated=disabled \
    -Dukify=disabled \
    -Defi=false \
    -Dbootloader=disabled \
    -Dtpm=false \
    -Dqrencode=disabled \
    -Dpam=disabled \
    -Dpolkit=disabled \
    -Dselinux=disabled \
    -Dapparmor=disabled \
    -Daudit=disabled \
    -Dlibcryptsetup=disabled \
    -Dlibcryptsetup-plugins=disabled \
    -Dlibidn2=disabled \
    -Dlibidn=disabled \
    -Dlibcurl=disabled \
    -Dmicrohttpd=disabled \
    -Dopenssl=disabled \
    -Dgcrypt=disabled \
    -Dp11kit=disabled \
    -Dlibfido2=disabled \
    -Dpwquality=disabled \
    -Dseccomp=disabled \
    -Dpcre2=enabled \
    -Dbzip2=disabled \
    -Dlz4=disabled \
    -Dxz=enabled \
    -Dzstd=enabled \
    -Dzlib=disabled \
    -Dkmod=enabled \
    -Dacl=enabled \
    -Dutmp=false \
    -Dgshadow=false \
    -Didn=false \
    -Ddebug-shell=/bin/sh \
    -Ddefault-user-shell=/bin/sh \
    -Dmount-path=/bin/mount \
    -Dumount-path=/bin/umount \
    -Dsulogin-path=/sbin/sulogin \
    -Dnologin-path=/sbin/nologin \
    -Dswapon-path=/sbin/swapon \
    -Dswapoff-path=/sbin/swapoff \
    -Dkmod-path=/bin/kmod \
    -Dsysvinit-path= \
    -Dsysvrcnd-path= \
    -Drpmmacrosdir=no \
    > "$LAB/meson-setup.log" 2>&1 || {
        echo "error: meson setup failed; tail of $LAB/meson-setup.log:" >&2
        tail -n 220 "$LAB/meson-setup.log" >&2
        exit 1
    }

if ! meson compile -C "$BUILD_DIR" -j "$jobs" > "$LAB/build.log" 2>&1; then
    echo "error: native systemd build failed; tail of $LAB/build.log:" >&2
    tail -n 220 "$LAB/build.log" >&2
    exit 1
fi

if ! meson install -C "$BUILD_DIR" --destdir "$DEST" > "$LAB/install.log" 2>&1; then
    echo "error: native systemd install failed; tail of $LAB/install.log:" >&2
    tail -n 220 "$LAB/install.log" >&2
    exit 1
fi

SYSTEMD_BIN="$DEST/usr/lib/systemd/systemd"
SYSTEMCTL_BIN="$DEST/usr/bin/systemctl"
test -x "$SYSTEMD_BIN"
test -x "$SYSTEMCTL_BIN"
file "$SYSTEMD_BIN" | tee "$LAB/systemd.file"
interp="$(readelf -l "$SYSTEMD_BIN" | sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p' | head -n1)"
if [ "$interp" != "/lib/ld-musl-x86_64.so.1" ]; then
    echo "error: native systemd has wrong interpreter: $interp" >&2
    exit 1
fi
readelf -d "$SYSTEMD_BIN" | grep -q 'RUNPATH.*\[/usr/lib/systemd\]' \
    || { echo "error: native systemd is missing /usr/lib/systemd RUNPATH" >&2; exit 1; }

PAYLOAD_NAME="onix-systemd-native-payload-$SYSTEMD_VERSION"
PAYLOAD_ROOT="$LAB/src/$PAYLOAD_NAME"
PAYLOAD_ARCHIVE="$LAB/src/$PAYLOAD_NAME.tar.gz"

rm -rf "$PAYLOAD_ROOT" "$PAYLOAD_ARCHIVE"
mkdir -p "$PAYLOAD_ROOT/usr"
cp -a "$DEST/usr/bin" "$PAYLOAD_ROOT/usr/"
cp -a "$DEST/usr/lib" "$PAYLOAD_ROOT/usr/"
cp -a "$DEST/usr/share" "$PAYLOAD_ROOT/usr/"
mkdir -p "$PAYLOAD_ROOT/usr/sbin" "$PAYLOAD_ROOT/usr/share/onix/packages"

copy_one_lib() {
    src="$1"
    [ -e "$src" ] || return 0
    base="$(basename "$src")"
    cp -a "$src" "$PAYLOAD_ROOT/usr/lib/$base"
    if [ -L "$src" ]; then
        target="$(readlink "$src")"
        case "$target" in
            /*) real="$target" ;;
            *) real="$(dirname "$src")/$target" ;;
        esac
        [ -e "$real" ] && cp -a "$real" "$PAYLOAD_ROOT/usr/lib/$(basename "$real")"
    fi
}

copy_elf_closure() {
    elf="$1"
    ldd "$elf" 2>/dev/null | while read -r a b c rest; do
        case "$a" in
            /lib/*|/usr/lib/*) copy_one_lib "$a" ;;
        esac
        case "$c" in
            /lib/*|/usr/lib/*) copy_one_lib "$c" ;;
        esac
    done
}

install_runtime_library_family() {
    pattern="$1"
    matched=0
    for lib in /lib/$pattern /usr/lib/$pattern; do
        [ -e "$lib" ] || continue
        matched=1
        copy_one_lib "$lib"
        copy_elf_closure "$lib"
        printf '%s -> /usr/lib/%s\n' "$lib" "$(basename "$lib")" >> "$PAYLOAD_ROOT/usr/share/onix/packages/onix-systemd.helpers"
    done
    if [ "$matched" -eq 0 ]; then
        echo "warn: runtime library family not found in forge: $pattern" >&2
    fi
}

find_host_command() {
    name="$1"
    for p in "/usr/bin/$name" "/bin/$name" "/usr/sbin/$name" "/sbin/$name"; do
        if [ -x "$p" ]; then
            printf '%s\n' "$p"
            return 0
        fi
    done
    return 1
}

install_helper_command() {
    name="$1"
    dest_dir="$2"
    src="$(find_host_command "$name" || true)"
    if [ -z "$src" ]; then
        echo "warn: helper command not found in forge: $name" >&2
        return 0
    fi
    if [ ! -r "$src" ]; then
        echo "warn: helper command is not readable by the forge build user; skipping: $src" >&2
        return 0
    fi
    install -m 00755 "$src" "$PAYLOAD_ROOT/$dest_dir/$name"
    copy_elf_closure "$src"
    printf '%s -> /%s/%s\n' "$src" "$dest_dir" "$name" >> "$PAYLOAD_ROOT/usr/share/onix/packages/onix-systemd.helpers"
}

# Bootstrap-native helper/library manifest. Runtime-library families and helper
# commands append to this file while we assemble the monolithic Phase 422 stone.
: > "$PAYLOAD_ROOT/usr/share/onix/packages/onix-systemd.helpers"

# The interpreter path is /lib/ld-musl-x86_64.so.1. ONIX uses merged-/usr, so
# installing it under /usr/lib makes /lib/ld-musl-x86_64.so.1 resolve.
copy_one_lib /lib/ld-musl-x86_64.so.1

# systemd uses some libraries through dynamic loading instead of normal ELF
# NEEDED entries. If these are absent, PID 1 may start but freeze while mounting
# API filesystems or initializing kmod support.
install_runtime_library_family 'libmount.so*'
install_runtime_library_family 'libblkid.so*'
install_runtime_library_family 'libuuid.so*'
install_runtime_library_family 'libkmod.so*'
install_runtime_library_family 'libcap.so*'
install_runtime_library_family 'libacl.so*'
install_runtime_library_family 'libpcre2-8.so*'
install_runtime_library_family 'libfdisk.so*'
install_runtime_library_family 'libsmartcols.so*'

# Bootstrap-native helper bundle. These are not final dependency splits; they
# are the minimum pragmatic helper commands that keep PID 1 bootable while we
# replace the old /nix/store systemd payload.
install_helper_command kmod usr/bin
install_helper_command mount usr/bin
install_helper_command umount usr/bin
install_helper_command swapon usr/sbin
install_helper_command swapoff usr/sbin
install_helper_command sulogin usr/sbin
install_helper_command nologin usr/sbin

cat > "$PAYLOAD_ROOT/usr/sbin/nologin" <<'EOF_NOLOGIN'
#!/bin/sh
echo "This account is currently not available." >&2
exit 1
EOF_NOLOGIN
chmod 00755 "$PAYLOAD_ROOT/usr/sbin/nologin"
printf 'ONIX generated nologin script -> /usr/sbin/nologin\n' >> "$PAYLOAD_ROOT/usr/share/onix/packages/onix-systemd.helpers"

find "$PAYLOAD_ROOT/usr/bin" "$PAYLOAD_ROOT/usr/sbin" "$PAYLOAD_ROOT/usr/lib/systemd" \
    -type f -perm -0100 -exec readelf -d {} \; 2>/dev/null |
    sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' |
    sort -u > "$PAYLOAD_ROOT/usr/share/onix/packages/onix-systemd.needed"

cat > "$PAYLOAD_ROOT/usr/share/onix/packages/onix-systemd.md" <<EOF_DOC
# onix-systemd

\`onix-systemd\` is the Phase 422 native systemd userspace package.

Source identity:

\`\`\`text
systemd $SYSTEMD_VERSION
upstream tag/ref: $SYSTEMD_UPSTREAM_REV
source archive: $SYSTEMD_SOURCE_ARCHIVE
source SHA-256: $SYSTEMD_SOURCE_SHA256
\`\`\`

Build identity:

\`\`\`text
build host: ONIX Alpine/musl forge VM
build system: meson + ninja
libc mode: musl
ELF interpreter: /lib/ld-musl-x86_64.so.1
private library RUNPATH: /usr/lib/systemd
\`\`\`

Installed native payload:

\`\`\`text
/usr/lib/systemd/systemd
/usr/lib/systemd/system
/usr/lib/systemd/user
/usr/bin/systemctl
/usr/bin/journalctl
/usr/bin/systemd-tmpfiles
/usr/bin/systemd-sysusers
/usr/bin/udevadm
/usr/lib/ld-musl-x86_64.so.1
\`\`\`

Bootstrap-native policy:

- this package is source-built in the forge,
- it does not install symlinks into the old bootstrap store,
- it may temporarily bundle immediate musl runtime/helper files,
- later phases may split those bundled helpers into smaller dependency stones.
EOF_DOC

chmod 0644 \
    "$PAYLOAD_ROOT/usr/share/onix/packages/onix-systemd.md" \
    "$PAYLOAD_ROOT/usr/share/onix/packages/onix-systemd.helpers" \
    "$PAYLOAD_ROOT/usr/share/onix/packages/onix-systemd.needed"

if grep -R -I -F '/nix/store' "$PAYLOAD_ROOT/usr/share/onix" >/dev/null 2>&1; then
    echo "error: native package notes must not mention /nix/store" >&2
    exit 1
fi

find "$PAYLOAD_ROOT" -type l | while read -r link; do
    target="$(readlink "$link")"
    case "$target" in
        /nix/store/*)
            echo "error: native payload symlink points into /nix/store: $link -> $target" >&2
            exit 1
            ;;
    esac
done

if find "$PAYLOAD_ROOT" -type l | grep -q .; then
    find "$PAYLOAD_ROOT" -type l | while read -r link; do
        printf '%s -> %s\n' "${link#$PAYLOAD_ROOT}" "$(readlink "$link")"
    done > "$LAB/payload-symlinks.txt"
fi

test -x "$PAYLOAD_ROOT/usr/lib/systemd/systemd"
test ! -L "$PAYLOAD_ROOT/usr/lib/systemd/systemd"
test -f "$PAYLOAD_ROOT/usr/lib/systemd/system/multi-user.target"
test -x "$PAYLOAD_ROOT/usr/bin/systemctl"
test -x "$PAYLOAD_ROOT/usr/bin/journalctl"
test -x "$PAYLOAD_ROOT/usr/bin/udevadm"
test -e "$PAYLOAD_ROOT/usr/lib/ld-musl-x86_64.so.1"

LD_LIBRARY_PATH="$PAYLOAD_ROOT/usr/lib:$PAYLOAD_ROOT/usr/lib/systemd" \
    "$PAYLOAD_ROOT/usr/bin/systemctl" --version | tee "$LAB/systemctl.version"

tar -C "$LAB/src" -czf "$PAYLOAD_ARCHIVE" "$PAYLOAD_NAME"
PAYLOAD_HASH="$(sha256sum "$PAYLOAD_ARCHIVE" | awk '{print $1}')"
PAYLOAD_URL="file://$PAYLOAD_ARCHIVE"

sed \
  -e "s|@SYSTEMD_VERSION@|$SYSTEMD_VERSION|g" \
  -e "s|@SYSTEMD_NATIVE_PAYLOAD_URL@|$PAYLOAD_URL|g" \
  -e "s|@SYSTEMD_NATIVE_PAYLOAD_SHA256@|$PAYLOAD_HASH|g" \
  "$LAB/stone.yaml.in" > "$LAB/stone.yaml"

echo "==> recipe"
sed -n '1,260p' "$LAB/stone.yaml"

echo
echo "==> building native onix-systemd stone"
rm -rf "$OUT"
mkdir -p "$OUT"
(
    cd "$LAB"
    boulder build -y --normal-priority -o "$OUT" stone.yaml
)

STONE="$(find "$OUT" -maxdepth 1 -name 'onix-systemd-*.stone' ! -name '*dbginfo*' | sort | head -n 1)"
if [ ! -f "$STONE" ]; then
    echo "error: boulder did not produce an onix-systemd .stone under $OUT" >&2
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
echo "==> extract and verify native systemd payload"
rm -rf "$EXTRACT"
mkdir -p "$EXTRACT"
moss extract -o "$EXTRACT" "$STONE"
set -- "$EXTRACT"/*
PAYLOAD="$1"

test -x "$PAYLOAD/usr/lib/systemd/systemd"
test ! -L "$PAYLOAD/usr/lib/systemd/systemd"
test -f "$PAYLOAD/usr/lib/systemd/system/multi-user.target"
test -x "$PAYLOAD/usr/bin/systemctl"
test -x "$PAYLOAD/usr/bin/journalctl"
test -x "$PAYLOAD/usr/bin/udevadm"
test -e "$PAYLOAD/usr/lib/ld-musl-x86_64.so.1"
interp="$(readelf -l "$PAYLOAD/usr/lib/systemd/systemd" | sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p' | head -n1)"
test "$interp" = "/lib/ld-musl-x86_64.so.1"
readelf -d "$PAYLOAD/usr/lib/systemd/systemd" | grep -q 'RUNPATH.*\[/usr/lib/systemd\]'
LD_LIBRARY_PATH="$PAYLOAD/usr/lib:$PAYLOAD/usr/lib/systemd" "$PAYLOAD/usr/bin/systemctl" --version | sed -n '1,3p'

if grep -R -I -F '/nix/store' "$PAYLOAD/usr/share/onix" >/dev/null 2>&1; then
    echo "error: extracted package notes mention /nix/store" >&2
    exit 1
fi

find "$PAYLOAD" -type l | while read -r link; do
    target="$(readlink "$link")"
    case "$target" in
        /nix/store/*)
            echo "error: extracted native payload symlink points into /nix/store: $link -> $target" >&2
            exit 1
            ;;
    esac
done

echo
echo "==> index local repo and install into disposable target"
rm -rf "$REPO" "$ROOT" "$CACHE" "$TARGET"
mkdir -p "$REPO" "$ROOT" "$CACHE" "$TARGET"
cp "$STONE" "$REPO/"
moss index "$REPO"
moss -D "$ROOT" --cache "$CACHE" repo add local "file://$REPO/stone.index" -c "local native onix-systemd repo"
moss -D "$ROOT" --cache "$CACHE" repo update
moss -D "$ROOT" --cache "$CACHE" -y install --to "$TARGET" onix-systemd

test -x "$TARGET/usr/lib/systemd/systemd"
test ! -L "$TARGET/usr/lib/systemd/systemd"
test -x "$TARGET/usr/bin/systemctl"
test -e "$TARGET/usr/lib/ld-musl-x86_64.so.1"
find "$TARGET" -type l | while read -r link; do
    target="$(readlink "$link")"
    case "$target" in
        /nix/store/*)
            echo "error: installed native target contains a /nix/store symlink: $link -> $target" >&2
            exit 1
            ;;
    esac
done

echo
echo "==> success"
echo "stone : $STONE"
echo "repo  : $REPO/stone.index"
echo "root  : $ROOT"
echo "target: $TARGET"
REMOTE

log "copying built native onix-systemd stone back to host artifacts"
rm -f "$STONE_DIR"/onix-systemd-*.stone "$STONE_DIR"/onix-systemd-dbginfo-*.stone
"$PHASE0_DIR/ssh.sh" "$user" "stone=\$(cat '$LAB/stone.path') && cd \"\$(dirname \"\$stone\")\" && tar -cf - \"\$(basename \"\$stone\")\"" \
  | tar -C "$STONE_DIR" -xf -

HOST_STONE="$(find "$STONE_DIR" -maxdepth 1 -name 'onix-systemd-*.stone' ! -name '*dbginfo*' | sort | tail -n 1)"
[[ -f "$HOST_STONE" ]] || die "failed to copy native onix-systemd stone into ${STONE_DIR#$ONIX_ROOT/}"

log "host moss integrity check"
"$HOST_MOSS" inspect --check "$HOST_STONE"

log "refreshing local Phase 4 moss repo"
rm -f "$LOCAL_REPO_DIR"/onix-systemd-*.stone "$LOCAL_REPO_DIR"/onix-systemd-dbginfo-*.stone
cp "$HOST_STONE" "$LOCAL_REPO_DIR/"
"$HOST_MOSS" index "$LOCAL_REPO_DIR"

cat <<EOF

==> success
native onix-systemd stone: ${HOST_STONE#$ONIX_ROOT/}
local repo index          : ${LOCAL_REPO_DIR#$ONIX_ROOT/}/stone.index

Next:
  make phase 422 will now install and boot-prove it.

EOF
