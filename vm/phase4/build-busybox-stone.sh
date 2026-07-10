#!/usr/bin/env bash
# vm/phase4/build-busybox-stone.sh — Phase 409 source-built BusyBox stone.
#
# Runs on the host. The actual package build runs inside the Phase 0 forge VM
# with boulder, so the produced payload is a .stone package, not a Nix payload.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHASE0_DIR="$(cd "$SCRIPT_DIR/../phase0" && pwd)"

# shellcheck source=vm/phase0/config.sh
source "$PHASE0_DIR/config.sh"

user="${1:-$BUILD_USER}"

STONE_DIR="${ONIX_STONE_DIR:-$ONIX_ROOT/artifacts/onix-stones}"
LOCAL_REPO_DIR="${ONIX_LOCAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-local-repo}"
STONE_WORK_DIR="${ONIX_STONE_WORK_DIR:-$ONIX_ROOT/artifacts/onix-stone-work}"
RECIPE_TEMPLATE="${ONIX_BUSYBOX_RECIPE_TEMPLATE:-$ONIX_ROOT/packages/core/onix-busybox/stone.yaml.in}"
HOST_MOSS="${ONIX_HOST_MOSS:-$ONIX_ROOT/artifacts/host-tools/bin/moss}"

LAB="/home/$user/stone-lab/onix-busybox"

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

busybox_source_path() {
  if [[ -n "${ONIX_BUSYBOX_SRC:-}" ]]; then
    printf '%s\n' "$ONIX_BUSYBOX_SRC"
    return
  fi

  local rev
  rev="$(extract_locked_nixpkgs_rev)"
  [[ -n "$rev" ]] || die "could not read pinned nixpkgs_2 rev from flake.lock"

  nix eval --raw "github:NixOS/nixpkgs/${rev}#busybox.src.outPath"
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

BUSYBOX_SRC="$(busybox_source_path)"
[[ -f "$BUSYBOX_SRC" ]] || die "BusyBox source is not a file: $BUSYBOX_SRC"

BUSYBOX_ARCHIVE="$(basename "$BUSYBOX_SRC")"
BUSYBOX_VERSION="$(printf '%s\n' "$BUSYBOX_ARCHIVE" | sed -E 's/^.*busybox-([0-9][0-9.]*)\.tar.*$/\1/')"
[[ "$BUSYBOX_VERSION" != "$BUSYBOX_ARCHIVE" ]] || die "could not infer BusyBox version from $BUSYBOX_ARCHIVE"

BUSYBOX_SHA256="$(sha256sum "$BUSYBOX_SRC" | awk '{print $1}')"
WORK="$STONE_WORK_DIR/onix-busybox"
BUILD_ENV="$WORK/build.env"

log "Phase 409 source-built BusyBox stone"
mkdir -p "$STONE_DIR" "$LOCAL_REPO_DIR" "$WORK"
rm -rf "$WORK"
mkdir -p "$WORK"

log "source policy"
cat <<EOF
source     : $BUSYBOX_SRC
version    : $BUSYBOX_VERSION
sha256     : $BUSYBOX_SHA256
nix role   : source acquisition only
source build: Alpine/musl forge VM
stone cut  : boulder packages the musl-static payload into a .stone
stone out  : ${STONE_DIR#$ONIX_ROOT/}
local repo : ${LOCAL_REPO_DIR#$ONIX_ROOT/}
EOF

cat > "$BUILD_ENV" <<EOF
BUSYBOX_VERSION='$BUSYBOX_VERSION'
BUSYBOX_ARCHIVE='$BUSYBOX_ARCHIVE'
BUSYBOX_SOURCE_SHA256='$BUSYBOX_SHA256'
EOF

log "copying recipe template + source tarball into the forge"
tar -cf - \
  -C "$WORK" build.env \
  -C "$(dirname "$RECIPE_TEMPLATE")" "$(basename "$RECIPE_TEMPLATE")" \
  -C "$(dirname "$BUSYBOX_SRC")" "$BUSYBOX_ARCHIVE" \
  | "$PHASE0_DIR/ssh.sh" "$user" "rm -rf '$LAB' && mkdir -p '$LAB/src' && tar -C '$LAB' -xf - && mv '$LAB/$BUSYBOX_ARCHIVE' '$LAB/src/$BUSYBOX_ARCHIVE' && if [ '$(basename "$RECIPE_TEMPLATE")' != 'stone.yaml.in' ]; then mv '$LAB/$(basename "$RECIPE_TEMPLATE")' '$LAB/stone.yaml.in'; fi"

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

LAB="$HOME/stone-lab/onix-busybox"
BUILD_SRC="$LAB/source-build"
PAYLOAD_ROOT="$LAB/payload-root"
OUT="$LAB/out"
EXTRACT="$LAB/extracted"
REPO="$LAB/repo"
ROOT="$LAB/moss-root"
CACHE="$LAB/moss-cache"
TARGET="$LAB/install-target"
# These commands exist inside the BusyBox binary, but ONIX does not install
# BusyBox applet links for them. Native systemd owns these command names.
SYSTEMD_OWNED_BUSYBOX_APPLETS="
poweroff
reboot
"
BOOTSTRAP_BUSYBOX_APPLETS="
ash
awk
chmod
chown
clear
dmesg
find
getty
grep
id
ifconfig
insmod
ip
less
lsmod
modprobe
mount
nc
netstat
nslookup
ping
ping6
ps
rmmod
route
sed
setsid
sh
stty
tty
udhcpc
umount
vi
wget
cttyhack
"

if [ ! -f "$LAB/build.env" ]; then
    echo "error: missing build environment: $LAB/build.env" >&2
    exit 1
fi

# shellcheck disable=SC1091
. "$LAB/build.env"

SOURCE_ARCHIVE="$LAB/src/$BUSYBOX_ARCHIVE"
SOURCE_HASH="$(sha256sum "$SOURCE_ARCHIVE" | awk '{print $1}')"
if [ "$SOURCE_HASH" != "$BUSYBOX_SOURCE_SHA256" ]; then
    echo "error: BusyBox source checksum mismatch" >&2
    echo "expected: $BUSYBOX_SOURCE_SHA256" >&2
    echo "actual  : $SOURCE_HASH" >&2
    exit 1
fi

echo "==> build musl-static BusyBox in the Alpine forge"
rm -rf "$BUILD_SRC" "$PAYLOAD_ROOT"
mkdir -p "$BUILD_SRC" "$PAYLOAD_ROOT"
tar -xf "$SOURCE_ARCHIVE" -C "$BUILD_SRC" --strip-components=1

jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
case "$jobs" in
    ''|*[!0-9]*) jobs=2 ;;
esac

(
    cd "$BUILD_SRC"
    make defconfig > "$LAB/defconfig.log" 2>&1

    set_config() {
        key="$1"
        value="$2"
        if grep -q "^$key=" .config; then
            sed -i "s/^$key=.*/$key=$value/" .config
        elif grep -q "^# $key is not set" .config; then
            sed -i "s/^# $key is not set/$key=$value/" .config
        else
            printf '%s=%s\n' "$key" "$value" >> .config
        fi
    }

    unset_config() {
        key="$1"
        if grep -q "^$key=" .config; then
            sed -i "s/^$key=.*/# $key is not set/" .config
        elif ! grep -q "^# $key is not set" .config; then
            printf '# %s is not set\n' "$key" >> .config
        fi
    }

    set_config CONFIG_STATIC y

    # Alpine's current kernel headers no longer expose old CBQ traffic-control
    # structs used by the BusyBox tc applet. ONIX does not need tc for the
    # Phase 4 shell/network/SSH proofs, so keep it out of this bootstrap build.
    unset_config CONFIG_TC
    unset_config CONFIG_FEATURE_TC_INGRESS

    # These applets are the contract for replacing the temporary Phase 403-406
    # Nix BusyBox payload. Defconfig usually enables them, but pin them here so
    # a future BusyBox config drift fails in Phase 409 instead of at boot time.
    set_config CONFIG_ASH y
    set_config CONFIG_AWK y
    set_config CONFIG_BASENAME y
    set_config CONFIG_CAT y
    set_config CONFIG_CHMOD y
    set_config CONFIG_CHOWN y
    set_config CONFIG_CLEAR y
    set_config CONFIG_CP y
    set_config CONFIG_CUT y
    set_config CONFIG_DATE y
    set_config CONFIG_DF y
    set_config CONFIG_DMESG y
    set_config CONFIG_DU y
    set_config CONFIG_ECHO y
    set_config CONFIG_ENV y
    set_config CONFIG_FALSE y
    set_config CONFIG_FIND y
    set_config CONFIG_GETTY y
    set_config CONFIG_GREP y
    set_config CONFIG_HEAD y
    set_config CONFIG_HOSTNAME y
    set_config CONFIG_ID y
    set_config CONFIG_IFCONFIG y
    set_config CONFIG_INSMOD y
    set_config CONFIG_IP y
    set_config CONFIG_LESS y
    set_config CONFIG_LN y
    set_config CONFIG_LS y
    set_config CONFIG_LSMOD y
    set_config CONFIG_MKDIR y
    set_config CONFIG_MODPROBE y
    set_config CONFIG_MOUNT y
    set_config CONFIG_MV y
    set_config CONFIG_NC y
    set_config CONFIG_NC_SERVER y
    set_config CONFIG_NC_EXTRA y
    set_config CONFIG_NETSTAT y
    set_config CONFIG_NSLOOKUP y
    set_config CONFIG_PING y
    set_config CONFIG_PING6 y
    set_config CONFIG_POWEROFF y
    set_config CONFIG_PS y
    set_config CONFIG_PWD y
    set_config CONFIG_REBOOT y
    set_config CONFIG_RM y
    set_config CONFIG_RMDIR y
    set_config CONFIG_RMMOD y
    set_config CONFIG_ROUTE y
    set_config CONFIG_SED y
    set_config CONFIG_SETSID y
    set_config CONFIG_SH_IS_ASH y
    set_config CONFIG_SLEEP y
    set_config CONFIG_SORT y
    set_config CONFIG_STTY y
    set_config CONFIG_SYNC y
    set_config CONFIG_TAIL y
    set_config CONFIG_TEE y
    set_config CONFIG_TOUCH y
    set_config CONFIG_TRUE y
    set_config CONFIG_TTY y
    set_config CONFIG_UDHCPC y
    set_config CONFIG_UMOUNT y
    set_config CONFIG_UNAME y
    set_config CONFIG_VI y
    set_config CONFIG_WC y
    set_config CONFIG_WGET y
    set_config CONFIG_WHOAMI y
    set_config CONFIG_CTTYHACK y

    # Keep wget's internal TLS, but do not depend on a separate OpenSSL link in
    # this static bootstrap binary.
    unset_config CONFIG_FEATURE_WGET_OPENSSL

    yes '' | make oldconfig > "$LAB/oldconfig.log" 2>&1
    if ! make -j"$jobs" > "$LAB/build.log" 2>&1; then
        echo "error: BusyBox source build failed; tail of $LAB/build.log:" >&2
        tail -n 140 "$LAB/build.log" >&2
        exit 1
    fi
)

BUSYBOX_BIN="$BUILD_SRC/busybox"
test -x "$BUSYBOX_BIN"
file "$BUSYBOX_BIN" | tee "$LAB/busybox.file"
grep -Eqi 'statically linked|static-pie linked' "$LAB/busybox.file"
"$BUSYBOX_BIN" true
"$BUSYBOX_BIN" sh -c 'echo musl-static busybox shell works'

PAYLOAD_NAME="onix-busybox-payload-$BUSYBOX_VERSION"
PAYLOAD_SRC="$LAB/src/$PAYLOAD_NAME"
PAYLOAD_ARCHIVE="$LAB/src/$PAYLOAD_NAME.tar.gz"

rm -rf "$PAYLOAD_SRC" "$PAYLOAD_ARCHIVE"
mkdir -p "$PAYLOAD_SRC/usr/bin" "$PAYLOAD_SRC/usr/share/onix/packages"
install -m 00755 "$BUSYBOX_BIN" "$PAYLOAD_SRC/usr/bin/busybox"

for applet in $BOOTSTRAP_BUSYBOX_APPLETS; do
    "$BUSYBOX_BIN" --list | grep -qx "$applet" || {
        echo "error: built BusyBox is missing applet: $applet" >&2
        exit 1
    }
    ln -sf busybox "$PAYLOAD_SRC/usr/bin/$applet"
done

for applet in $SYSTEMD_OWNED_BUSYBOX_APPLETS; do
    "$BUSYBOX_BIN" --list | grep -qx "$applet" || {
        echo "error: built BusyBox is missing applet expected to be withheld: $applet" >&2
        exit 1
    }
    if [ -e "$PAYLOAD_SRC/usr/bin/$applet" ]; then
        echo "error: onix-busybox must not own /usr/bin/$applet" >&2
        exit 1
    fi
done

"$BUSYBOX_BIN" --list > "$PAYLOAD_SRC/usr/share/onix/packages/onix-busybox.applets"
printf '%s\n' $BOOTSTRAP_BUSYBOX_APPLETS > "$PAYLOAD_SRC/usr/share/onix/packages/onix-busybox.links"
printf '%s\n' $SYSTEMD_OWNED_BUSYBOX_APPLETS > "$PAYLOAD_SRC/usr/share/onix/packages/onix-busybox.systemd-owned"
cat > "$PAYLOAD_SRC/usr/share/onix/packages/onix-busybox.md" <<EOF_DOC
# onix-busybox

\`onix-busybox\` is the first local machine-plane replacement stone in Phase 4.

Source archive:

\`\`\`text
$BUSYBOX_ARCHIVE
\`\`\`

Source SHA-256:

\`\`\`text
$BUSYBOX_SOURCE_SHA256
\`\`\`

The BusyBox binary was built in the Alpine/musl forge VM and then packaged by
boulder into a moss-installable .stone. This keeps the installed payload static
and musl-based while ONIX is still bootstrapping a proper boulder musl build
environment.

The package owns the applets needed by the Phase 403-406 bootstrap proofs:

\`\`\`text
$BOOTSTRAP_BUSYBOX_APPLETS
\`\`\`

The package deliberately does not own these systemd-owned command names:

\`\`\`text
$SYSTEMD_OWNED_BUSYBOX_APPLETS
\`\`\`
EOF_DOC

chmod 0644 \
    "$PAYLOAD_SRC/usr/share/onix/packages/onix-busybox.applets" \
    "$PAYLOAD_SRC/usr/share/onix/packages/onix-busybox.links" \
    "$PAYLOAD_SRC/usr/share/onix/packages/onix-busybox.systemd-owned" \
    "$PAYLOAD_SRC/usr/share/onix/packages/onix-busybox.md"
chmod g-s \
    "$PAYLOAD_SRC/usr" \
    "$PAYLOAD_SRC/usr/bin" \
    "$PAYLOAD_SRC/usr/share" \
    "$PAYLOAD_SRC/usr/share/onix" \
    "$PAYLOAD_SRC/usr/share/onix/packages"

tar -C "$LAB/src" -czf "$PAYLOAD_ARCHIVE" "$PAYLOAD_NAME"
PAYLOAD_HASH="$(sha256sum "$PAYLOAD_ARCHIVE" | awk '{print $1}')"
PAYLOAD_URL="file://$PAYLOAD_ARCHIVE"

sed \
  -e "s|@BUSYBOX_VERSION@|$BUSYBOX_VERSION|g" \
  -e "s|@BUSYBOX_PAYLOAD_URL@|$PAYLOAD_URL|g" \
  -e "s|@BUSYBOX_PAYLOAD_SHA256@|$PAYLOAD_HASH|g" \
  -e "s|@BUSYBOX_SOURCE_ARCHIVE@|$BUSYBOX_ARCHIVE|g" \
  -e "s|@BUSYBOX_SOURCE_SHA256@|$BUSYBOX_SOURCE_SHA256|g" \
  "$LAB/stone.yaml.in" > "$LAB/stone.yaml"

echo "==> recipe"
sed -n '1,260p' "$LAB/stone.yaml"

echo
echo "==> building onix-busybox stone"
rm -rf "$OUT"
mkdir -p "$OUT"
(
    cd "$LAB"
    boulder build -y --normal-priority -o "$OUT" stone.yaml
)

STONE="$(find "$OUT" -maxdepth 1 -name '*.stone' | sort | head -n 1)"
if [ ! -f "$STONE" ]; then
    echo "error: boulder did not produce a .stone under $OUT" >&2
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
echo "==> extract and verify static BusyBox payload"
rm -rf "$EXTRACT"
mkdir -p "$EXTRACT"
moss extract -o "$EXTRACT" "$STONE"
set -- "$EXTRACT"/*
PAYLOAD="$1"

test -x "$PAYLOAD/usr/bin/busybox"
file "$PAYLOAD/usr/bin/busybox" | tee "$LAB/busybox.file"
grep -Eqi 'statically linked|static-pie linked' "$LAB/busybox.file"
"$PAYLOAD/usr/bin/busybox" true
"$PAYLOAD/usr/bin/busybox" sh -c 'echo busybox shell works'

for applet in $BOOTSTRAP_BUSYBOX_APPLETS; do
    test -e "$PAYLOAD/usr/bin/$applet" || {
        echo "error: missing BusyBox applet link: /usr/bin/$applet" >&2
        exit 1
    }
done

for applet in $SYSTEMD_OWNED_BUSYBOX_APPLETS; do
    if [ -e "$PAYLOAD/usr/bin/$applet" ]; then
        echo "error: onix-busybox must not own /usr/bin/$applet" >&2
        exit 1
    fi
done

test -f "$PAYLOAD/usr/share/onix/packages/onix-busybox.applets"
test -f "$PAYLOAD/usr/share/onix/packages/onix-busybox.links"
test -f "$PAYLOAD/usr/share/onix/packages/onix-busybox.systemd-owned"
grep -qx 'sh' "$PAYLOAD/usr/share/onix/packages/onix-busybox.applets"
grep -qx 'nc' "$PAYLOAD/usr/share/onix/packages/onix-busybox.applets"
grep -qx 'ifconfig' "$PAYLOAD/usr/share/onix/packages/onix-busybox.applets"
grep -qx 'reboot' "$PAYLOAD/usr/share/onix/packages/onix-busybox.systemd-owned"
grep -qx 'poweroff' "$PAYLOAD/usr/share/onix/packages/onix-busybox.systemd-owned"

echo
echo "==> index local repo and install into disposable target"
rm -rf "$REPO" "$ROOT" "$CACHE" "$TARGET"
mkdir -p "$REPO" "$ROOT" "$CACHE" "$TARGET"
cp "$STONE" "$REPO/"
moss index "$REPO"
moss -D "$ROOT" --cache "$CACHE" repo add local "file://$REPO/stone.index" -c "local onix busybox repo"
moss -D "$ROOT" --cache "$CACHE" repo update
moss -D "$ROOT" --cache "$CACHE" -y install --to "$TARGET" onix-busybox

test -x "$TARGET/usr/bin/busybox"
"$TARGET/usr/bin/busybox" true
"$TARGET/usr/bin/sh" -c 'echo installed busybox shell works'
"$TARGET/usr/bin/busybox" uname -s >/dev/null

echo
echo "==> success"
echo "stone : $STONE"
echo "repo  : $REPO/stone.index"
echo "root  : $ROOT"
echo "target: $TARGET"
REMOTE

log "copying built stone back to host artifacts"
rm -f "$STONE_DIR"/onix-busybox-*.stone "$STONE_DIR"/onix-busybox-dbginfo-*.stone
"$PHASE0_DIR/ssh.sh" "$user" "stone=\$(cat '$LAB/stone.path') && cd \"\$(dirname \"\$stone\")\" && tar -cf - \"\$(basename \"\$stone\")\"" \
  | tar -C "$STONE_DIR" -xf -

HOST_STONE="$(find "$STONE_DIR" -maxdepth 1 -name 'onix-busybox-*.stone' ! -name '*dbginfo*' | sort | tail -n 1)"
[[ -f "$HOST_STONE" ]] || die "failed to copy onix-busybox stone into ${STONE_DIR#$ONIX_ROOT/}"

log "host moss integrity check"
"$HOST_MOSS" inspect --check "$HOST_STONE"

log "refreshing local Phase 4 moss repo"
rm -f "$LOCAL_REPO_DIR"/onix-busybox-*.stone "$LOCAL_REPO_DIR"/onix-busybox-dbginfo-*.stone
cp "$HOST_STONE" "$LOCAL_REPO_DIR/"
"$HOST_MOSS" index "$LOCAL_REPO_DIR"

cat <<EOF

==> success
onix-busybox stone: ${HOST_STONE#$ONIX_ROOT/}
local repo index   : ${LOCAL_REPO_DIR#$ONIX_ROOT/}/stone.index

Next:
  make phase 410

EOF
