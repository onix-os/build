#!/usr/bin/env bash
# vm/phase5/build-rootasrole.sh — Phase 511.
#
# Builds RootAsRole as ONIX's sudo-class privilege package.
#
# Phase 510 made PAM/seccomp/musl package-owned. Phase 511 consumes that owned
# surface, adds the tiny libgcc runtime surface required by the current forge
# Rust toolchain, and cuts the rootasrole stone.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHASE0_DIR="$(cd "$SCRIPT_DIR/../phase0" && pwd)"

# shellcheck source=vm/phase0/config.sh
source "$PHASE0_DIR/config.sh"

user="$BUILD_USER"

MODE="apply"
FORCE_REBUILD="${ONIX_PHASE511_REBUILD:-0}"

STONE_DIR="${ONIX_STONE_DIR:-$ONIX_ROOT/artifacts/onix-stones}"
LOCAL_REPO_DIR="${ONIX_LOCAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-local-repo}"
STONE_WORK_DIR="${ONIX_STONE_WORK_DIR:-$ONIX_ROOT/artifacts/onix-stone-work}"
WORK="${ONIX_PHASE511_WORK_DIR:-$STONE_WORK_DIR/rootasrole}"
HOST_MOSS="${ONIX_HOST_MOSS:-$ONIX_ROOT/artifacts/host-tools/bin/moss}"
AUDIT_SCRIPT="$SCRIPT_DIR/audit-stone-payload.sh"
PROOF_DIR="$ONIX_ROOT/artifacts/onix-phase5-work/511"

ROOTASROLE_RECIPE_TEMPLATE="${ONIX_ROOTASROLE_RECIPE_TEMPLATE:-$ONIX_ROOT/packages/core/rootasrole/stone.yaml.in}"
LIBGCC_RUNTIME_RECIPE_TEMPLATE="${ONIX_LIBGCC_RUNTIME_RECIPE_TEMPLATE:-$ONIX_ROOT/packages/libs/libgcc-runtime/stone.yaml.in}"

ROOTASROLE_REPO="${ONIX_ROOTASROLE_REPO:-https://github.com/LeChatP/RootAsRole.git}"
ROOTASROLE_REF="${ONIX_ROOTASROLE_REF:-v4.0.0}"
ROOTASROLE_EXPECTED_COMMIT="${ONIX_ROOTASROLE_COMMIT:-1bd1924fde43c8a209dee102b026c622bb407d04}"

LAB="/home/$user/stone-lab/onix-rootasrole"

usage() {
  cat <<'EOF'
usage: build-rootasrole.sh [--apply|--check|--rebuild]

--apply    build missing libgcc-runtime/rootasrole stones, audit them, and
           refresh the local ONIX repo
--check    verify package metadata and inspect/audit existing stones when present
--rebuild  force rebuilding/rechecking the Phase 511 RootAsRole package

Phase 511 builds:
  - libgcc-runtime
  - rootasrole
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) MODE="apply" ;;
    --check) MODE="check" ;;
    --rebuild) MODE="apply"; FORCE_REBUILD=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
  shift
done

cd "$ONIX_ROOT"

safe_artifact_path() {
  local path="$1"
  case "$path" in
    "$ONIX_ROOT"/artifacts/*) ;;
    *) die "refusing artifact path outside artifacts/: $path" ;;
  esac
}

host_stone_for() {
  local package="$1"
  find "$STONE_DIR" -maxdepth 1 -name "$package-*.stone" ! -name '*dbginfo*' ! -name '*devel*' | sort | tail -n 1
}

local_stone_for() {
  local package="$1"
  find "$LOCAL_REPO_DIR" -maxdepth 1 -name "$package-*.stone" ! -name '*dbginfo*' ! -name '*devel*' | sort | tail -n 1
}

check_source_files() {
  [[ -f "$ONIX_ROOT/packages/STONES.md" ]] || die "missing packages/STONES.md"
  [[ -f "$ONIX_ROOT/packages/core/rootasrole/PACKAGE.md" ]] || die "missing rootasrole PACKAGE.md"
  [[ -f "$ONIX_ROOT/packages/libs/libgcc-runtime/PACKAGE.md" ]] || die "missing libgcc-runtime PACKAGE.md"
  [[ -f "$ROOTASROLE_RECIPE_TEMPLATE" ]] || die "missing rootasrole recipe template"
  [[ -f "$LIBGCC_RUNTIME_RECIPE_TEMPLATE" ]] || die "missing libgcc-runtime recipe template"
  [[ -f "$ONIX_ROOT/book/src/phases/511.md" ]] || die "missing Phase 511 book page"

  grep -q 'rootasrole' "$ONIX_ROOT/packages/STONES.md"
  grep -q 'libgcc-runtime' "$ONIX_ROOT/packages/STONES.md"
  grep -q 'libgcc-runtime' "$ONIX_ROOT/packages/core/rootasrole/PACKAGE.md"
  grep -q 'RootAsRole' "$ONIX_ROOT/book/src/phases/511.md"
}

require_phase510_stones() {
  local package
  for package in musl linux-pam libseccomp; do
    [[ -n "$(local_stone_for "$package")" ]] || die "missing $package in ${LOCAL_REPO_DIR#$ONIX_ROOT/}; run: make phase 510"
  done
}

rootasrole_packages_for_proof() {
  local packages=()
  [[ -n "$(local_stone_for rootasrole)" ]] && packages+=(rootasrole)
  printf '%s\n' "${packages[@]}"
}

check_allowed_needed_file() {
  local path="$1"
  local kind="$2"
  local needed bad=0

  while IFS= read -r needed; do
    case "$kind:$needed" in
      dosr:libpam.so.0|dosr:libgcc_s.so.1|dosr:libc.musl-x86_64.so.1) ;;
      chsr:libseccomp.so.2|chsr:libgcc_s.so.1|chsr:libc.musl-x86_64.so.1) ;;
      *)
        printf 'error: unexpected NEEDED in %s: %s\n' "$path" "$needed" >&2
        bad=1
        ;;
    esac
  done < <(readelf -d "$path" 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p')

  [[ "$bad" -eq 0 ]] || return 1
}

prove_host_install_and_audit() {
  [[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"
  [[ -x "$AUDIT_SCRIPT" ]] || die "missing payload audit helper: ${AUDIT_SCRIPT#$ONIX_ROOT/}"

  local root="$PROOF_DIR/moss-root"
  local cache="$PROOF_DIR/moss-cache"
  local target="$PROOF_DIR/install-target"
  local install_log="$PROOF_DIR/moss-install.log"
  local packages=()
  local package mode

  rm -rf "$PROOF_DIR"
  mkdir -p "$root" "$cache" "$target"

  while IFS= read -r package; do
    [[ -n "$package" ]] && packages+=("$package")
  done < <(rootasrole_packages_for_proof)

  if [[ "${#packages[@]}" -ne 1 ]]; then
    log "stone     : rootasrole not built yet"
    return 0
  fi

  "$HOST_MOSS" -D "$root" \
    --cache "$cache" \
    repo add onix-rootasrole \
    "file://$LOCAL_REPO_DIR/stone.index" \
    -c "ONIX Phase 511 RootAsRole" >/dev/null

  "$HOST_MOSS" -D "$root" --cache "$cache" repo update >/dev/null

  if ! "$HOST_MOSS" -D "$root" \
      --cache "$cache" \
      -y install --to "$target" \
      "${packages[@]}" >"$install_log" 2>&1; then
    cat "$install_log" >&2
    die "Moss could not install rootasrole and its owned dependency surface"
  fi

  if grep -q 'duplicate entry:' "$install_log"; then
    cat "$install_log" >&2
    die "rootasrole install reported package path ownership collisions"
  fi

  [[ -x "$target/usr/bin/dosr" ]] || die "missing installed dosr"
  [[ -x "$target/usr/bin/chsr" ]] || die "missing installed chsr"
  [[ -e "$target/usr/lib/libpam.so.0" ]] || die "missing installed libpam.so.0"
  [[ -e "$target/usr/lib/libseccomp.so.2" ]] || die "missing installed libseccomp.so.2"
  [[ -e "$target/usr/lib/libgcc_s.so.1" ]] || die "missing installed libgcc_s.so.1"
  [[ -e "$target/usr/lib/ld-musl-x86_64.so.1" ]] || die "missing installed musl loader"

  mode="$(stat -c '%a' "$target/usr/bin/dosr")"
  [[ "$mode" = "4755" ]] || die "dosr mode is $mode, expected 4755"

  check_allowed_needed_file "$target/usr/bin/dosr" dosr
  check_allowed_needed_file "$target/usr/bin/chsr" chsr
  "$AUDIT_SCRIPT" --allow-dynamic-musl "$target" >/dev/null

  log "proof     : host Moss install + RootAsRole dependency audit OK"
}

run_check() {
  check_source_files
  require_phase510_stones
  [[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"

  local package stone
  for package in libgcc-runtime rootasrole; do
    stone="$(local_stone_for "$package")"
    if [[ -z "$stone" ]]; then
      log "stone     : $package not built yet"
      continue
    fi
    "$HOST_MOSS" inspect --check "$stone" >/dev/null
    log "stone     : ${stone#$ONIX_ROOT/}"
  done

  prove_host_install_and_audit
  log "phase511  : check OK"
}

prepare_rootasrole_source() {
  need_cmd git
  need_cmd gzip
  need_cmd sed
  need_cmd sha256sum
  need_cmd tar

  local source_dir="$WORK/src/rootasrole"
  local archive="$WORK/rootasrole-source.tar.gz"
  local tar_path="${archive%.gz}"

  rm -rf "$source_dir" "$archive" "$tar_path"
  mkdir -p "$(dirname "$source_dir")"

  git clone --no-checkout "$ROOTASROLE_REPO" "$source_dir" >/dev/null
  git -C "$source_dir" fetch --depth 1 origin "$ROOTASROLE_REF" >/dev/null
  git -C "$source_dir" checkout --detach FETCH_HEAD >/dev/null

  local commit version sha
  commit="$(git -C "$source_dir" rev-parse HEAD)"
  if [[ -n "$ROOTASROLE_EXPECTED_COMMIT" && "$commit" != "$ROOTASROLE_EXPECTED_COMMIT" ]]; then
    die "RootAsRole ref $ROOTASROLE_REF resolved to $commit, expected $ROOTASROLE_EXPECTED_COMMIT"
  fi

  version="$(sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$source_dir/Cargo.toml" | head -n 1)"
  [[ -n "$version" ]] || die "could not read RootAsRole version"

  git -C "$source_dir" archive \
    --format=tar \
    --prefix="rootasrole-$version/" \
    -o "$tar_path" \
    HEAD
  gzip -n -f "$tar_path"

  sha="$(sha256sum "$archive" | awk '{print $1}')"

  cat > "$WORK/build.env" <<EOF_ENV
ROOTASROLE_VERSION='$version'
ROOTASROLE_REF='$ROOTASROLE_REF'
ROOTASROLE_COMMIT='$commit'
ROOTASROLE_SOURCE_ARCHIVE='$(basename "$archive")'
ROOTASROLE_SOURCE_SHA256='$sha'
EOF_ENV

  cat <<EOF_POLICY
==> source policy
rootasrole repo    : $ROOTASROLE_REPO
rootasrole ref     : $ROOTASROLE_REF
rootasrole commit  : $commit
rootasrole version : $version
rootasrole sha256  : $sha
payload rule       : dynamic-musl allowed only for owned PAM/seccomp/libgcc/musl surface
EOF_POLICY
}

run_apply() {
  need_cmd awk
  need_cmd cp
  need_cmd git
  need_cmd gzip
  need_cmd sed
  need_cmd sha256sum
  need_cmd tar

  safe_artifact_path "$STONE_DIR"
  safe_artifact_path "$LOCAL_REPO_DIR"
  safe_artifact_path "$STONE_WORK_DIR"
  safe_artifact_path "$WORK"

  check_source_files
  require_phase510_stones
  [[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"

  local existing_gcc existing_rootasrole
  existing_gcc="$(local_stone_for libgcc-runtime)"
  existing_rootasrole="$(local_stone_for rootasrole)"

  if [[ "$FORCE_REBUILD" != "1" && -n "$existing_gcc" && -n "$existing_rootasrole" ]]; then
    log "Phase 511 RootAsRole stones already exist"
    run_check
    return
  fi

  mkdir -p "$STONE_DIR" "$LOCAL_REPO_DIR" "$STONE_WORK_DIR"
  rm -rf "$WORK"
  mkdir -p "$WORK"

  log "Phase 511 RootAsRole package"
  log "build     : Alpine/musl forge VM"
  log "stone out : ${STONE_DIR#$ONIX_ROOT/}"
  log "local repo: ${LOCAL_REPO_DIR#$ONIX_ROOT/}"

  prepare_rootasrole_source

  cp "$ROOTASROLE_RECIPE_TEMPLATE" "$WORK/rootasrole.stone.yaml.in"
  cp "$LIBGCC_RUNTIME_RECIPE_TEMPLATE" "$WORK/libgcc-runtime.stone.yaml.in"

  local musl_stone pam_stone seccomp_stone
  musl_stone="$(local_stone_for musl)"
  pam_stone="$(local_stone_for linux-pam)"
  seccomp_stone="$(local_stone_for libseccomp)"

  log "ensuring RootAsRole build dependencies in the forge"
  "$PHASE0_DIR/ssh.sh" root \
    "apk add --no-cache build-base cargo rust clang pkgconf file binutils coreutils findutils bash"

  log "copying RootAsRole source + owned dependency stones into the forge"
  tar -cf - \
    -C "$WORK" build.env rootasrole-source.tar.gz rootasrole.stone.yaml.in libgcc-runtime.stone.yaml.in \
    -C "$(dirname "$musl_stone")" "$(basename "$musl_stone")" \
    -C "$(dirname "$pam_stone")" "$(basename "$pam_stone")" \
    -C "$(dirname "$seccomp_stone")" "$(basename "$seccomp_stone")" \
    | "$PHASE0_DIR/ssh.sh" "$user" "rm -rf '$LAB' && mkdir -p '$LAB/src' '$LAB/phase510' && tar -C '$LAB' -xf - && mv '$LAB'/*.stone '$LAB/phase510/'"

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
need_tool cargo
need_tool rustc
need_tool readelf
need_tool file
need_tool tar
need_tool gzip
need_tool sha256sum
need_tool sed
need_tool grep
need_tool awk
need_tool install
need_tool pkg-config

LAB="$HOME/stone-lab/onix-rootasrole"
BUILD_REPO="$LAB/build-repo"
FINAL_REPO="$LAB/repo"
SYSROOT="$LAB/sysroot"
ROOT="$LAB/moss-root"
CACHE="$LAB/moss-cache"
TARGET="$LAB/install-target"

if [ ! -f "$LAB/build.env" ]; then
    echo "error: missing build environment: $LAB/build.env" >&2
    exit 1
fi

# shellcheck disable=SC1091
. "$LAB/build.env"

jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
case "$jobs" in
    ''|*[!0-9]*) jobs=2 ;;
esac

check_no_nix_reference() {
    path="$1"
    if grep -a -F '/nix/store' "$path" >/dev/null 2>&1; then
        echo "error: $path contains /nix/store reference" >&2
        exit 1
    fi
}

check_shared_object() {
    so="$1"
    test -e "$so"
    file "$so"
    check_no_nix_reference "$so"
    if readelf -d "$so" 2>/dev/null | grep -E 'RPATH|RUNPATH' >/dev/null; then
        echo "error: $so has RPATH/RUNPATH" >&2
        readelf -d "$so" | grep -E 'RPATH|RUNPATH' >&2 || true
        exit 1
    fi
}

check_soname() {
    so="$1"
    soname="$2"
    check_shared_object "$so"
    if ! readelf -d "$so" 2>/dev/null | grep -q "Library soname: \\[$soname\\]"; then
        echo "error: $so does not provide $soname" >&2
        readelf -d "$so" >&2 || true
        exit 1
    fi
}

check_allowed_needed() {
    bin="$1"
    kind="$2"
    bad=0
    while IFS= read -r needed; do
        case "$kind:$needed" in
          dosr:libpam.so.0|dosr:libgcc_s.so.1|dosr:libc.musl-x86_64.so.1) ;;
          chsr:libseccomp.so.2|chsr:libgcc_s.so.1|chsr:libc.musl-x86_64.so.1) ;;
          *)
            echo "error: unexpected NEEDED in $bin: $needed" >&2
            bad=1
            ;;
        esac
    done <<EOF_NEEDED
$(readelf -d "$bin" 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p')
EOF_NEEDED
    test "$bad" -eq 0
}

cut_stone() {
    package="$1"
    version="$2"
    payload_archive="$3"
    payload_hash="$(sha256sum "$payload_archive" | awk '{print $1}')"
    payload_url="file://$payload_archive"

    case "$package" in
      libgcc-runtime)
        source_note="Alpine forge /usr/lib/libgcc_s.so.1, packaged as ONIX bootstrap compiler runtime"
        sed \
          -e "s|@LIBGCC_RUNTIME_VERSION@|$version|g" \
          -e "s|@LIBGCC_RUNTIME_PAYLOAD_URL@|$payload_url|g" \
          -e "s|@LIBGCC_RUNTIME_PAYLOAD_SHA256@|$payload_hash|g" \
          -e "s|@LIBGCC_RUNTIME_SOURCE_NOTE@|$source_note|g" \
          "$LAB/libgcc-runtime.stone.yaml.in" > "$LAB/libgcc-runtime.stone.yaml"
        recipe="$LAB/libgcc-runtime.stone.yaml"
        ;;
      rootasrole)
        sed \
          -e "s|@ROOTASROLE_VERSION@|$version|g" \
          -e "s|@ROOTASROLE_PAYLOAD_URL@|$payload_url|g" \
          -e "s|@ROOTASROLE_PAYLOAD_SHA256@|$payload_hash|g" \
          "$LAB/rootasrole.stone.yaml.in" > "$LAB/rootasrole.stone.yaml"
        recipe="$LAB/rootasrole.stone.yaml"
        ;;
      *) echo "error: unknown package $package" >&2; exit 1 ;;
    esac

    out="$LAB/$package-out"
    rm -rf "$out"
    mkdir -p "$out"
    (
        cd "$LAB"
        boulder build -y --normal-priority -o "$out" "$recipe"
    )

    stone="$(find "$out" -maxdepth 1 -name "$package-*.stone" ! -name '*dbginfo*' ! -name '*devel*' | sort | head -n 1)"
    test -f "$stone"
    printf '%s\n' "$stone" > "$LAB/$package.stone.path"
    moss inspect --check "$stone"
}

build_libgcc_runtime() {
    echo "==> build libgcc-runtime"

    apk_id="$(apk list --installed libgcc 2>/dev/null | awk 'NR == 1 { print $1 }')"
    version="$(printf '%s\n' "$apk_id" | sed -E 's/^libgcc-([0-9][0-9.]*)-r[0-9]+$/\1/')"
    test -n "$apk_id"
    test -n "$version"
    if [ "$version" = "$apk_id" ]; then
        echo "error: could not parse libgcc version from apk id: $apk_id" >&2
        exit 1
    fi

    payload_name="libgcc-runtime-payload-$version"
    payload_root="$LAB/src/$payload_name"
    payload_archive="$LAB/src/$payload_name.tar.gz"

    rm -rf "$payload_root" "$payload_archive"
    mkdir -p "$payload_root/usr/lib" "$payload_root/usr/share/onix/packages"

    install -m 00755 /usr/lib/libgcc_s.so.1 "$payload_root/usr/lib/libgcc_s.so.1"
    cp -a /usr/lib/libgcc_s.so "$payload_root/usr/lib/libgcc_s.so"

    check_soname "$payload_root/usr/lib/libgcc_s.so.1" "libgcc_s.so.1"

    cat > "$payload_root/usr/share/onix/packages/libgcc-runtime.md" <<EOF_DOC
# libgcc-runtime

ONIX-owned bootstrap compiler runtime surface for RootAsRole.

Forge package:

\`\`\`text
$apk_id
\`\`\`

Installed shared object:

\`\`\`text
/usr/lib/libgcc_s.so.1
\`\`\`
EOF_DOC

    chmod 0644 "$payload_root/usr/share/onix/packages/libgcc-runtime.md"
    tar -C "$LAB/src" -czf "$payload_archive" "$payload_name"
    cut_stone libgcc-runtime "$version" "$payload_archive"
}

install_build_sysroot() {
    echo "==> install ONIX-owned build sysroot"
    rm -rf "$BUILD_REPO" "$SYSROOT" "$ROOT" "$CACHE"
    mkdir -p "$BUILD_REPO" "$SYSROOT" "$ROOT" "$CACHE"
    cp "$LAB/phase510"/*.stone "$BUILD_REPO/"
    cp "$(cat "$LAB/libgcc-runtime.stone.path")" "$BUILD_REPO/"
    moss index "$BUILD_REPO"
    moss -D "$ROOT" --cache "$CACHE" repo add build "file://$BUILD_REPO/stone.index" -c "ONIX RootAsRole build sysroot" >/dev/null
    moss -D "$ROOT" --cache "$CACHE" repo update >/dev/null
    moss -D "$ROOT" --cache "$CACHE" -y install --to "$SYSROOT" musl linux-pam libseccomp libgcc-runtime >/dev/null
}

build_rootasrole() {
    echo "==> build rootasrole"

    src_archive="$LAB/$ROOTASROLE_SOURCE_ARCHIVE"
    src_hash="$(sha256sum "$src_archive" | awk '{print $1}')"
    if [ "$src_hash" != "$ROOTASROLE_SOURCE_SHA256" ]; then
        echo "error: RootAsRole source checksum mismatch" >&2
        exit 1
    fi

    build_src="$LAB/rootasrole-source"
    payload_name="rootasrole-payload-$ROOTASROLE_VERSION"
    payload_root="$LAB/src/$payload_name"
    payload_archive="$LAB/src/$payload_name.tar.gz"

    rm -rf "$build_src" "$payload_root" "$payload_archive"
    mkdir -p "$build_src" "$payload_root"
    tar -xzf "$src_archive" -C "$build_src" --strip-components=1

    (
        cd "$build_src"
        export PKG_CONFIG_PATH="$SYSROOT/usr/lib/pkgconfig"
        export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig"
        export LIBRARY_PATH="$SYSROOT/usr/lib"
        export C_INCLUDE_PATH="$SYSROOT/usr/include"
        export RUSTFLAGS="-L native=$SYSROOT/usr/lib ${RUSTFLAGS:-}"
        cargo build --locked --release --bins --no-default-features --features finder,editor
    )

    mkdir -p \
      "$payload_root/usr/bin" \
      "$payload_root/usr/share/defaults/rootasrole" \
      "$payload_root/usr/share/defaults/pam.d" \
      "$payload_root/usr/share/onix/packages"

    install -m 04755 "$build_src/target/release/dosr" "$payload_root/usr/bin/dosr"
    install -m 00755 "$build_src/target/release/chsr" "$payload_root/usr/bin/chsr"
    install -m 00644 "$build_src/resources/rootasrole.json" "$payload_root/usr/share/defaults/rootasrole/rootasrole.json"

    cat > "$payload_root/usr/share/defaults/pam.d/dosr" <<'EOF_PAM'
#%PAM-1.0
# ONIX packaged default for RootAsRole.
#
# This file is documentation/default policy, not live machine policy. Copy and
# adapt it deliberately into /etc/pam.d/dosr in a later integration phase.
auth     required   pam_deny.so
account  required   pam_permit.so
session  required   pam_permit.so
EOF_PAM

    check_shared_object "$payload_root/usr/bin/dosr"
    check_shared_object "$payload_root/usr/bin/chsr"
    check_allowed_needed "$payload_root/usr/bin/dosr" dosr
    check_allowed_needed "$payload_root/usr/bin/chsr" chsr

    cat > "$payload_root/usr/share/onix/packages/rootasrole.md" <<EOF_DOC
# rootasrole

ONIX sudo-class privilege delegation package.

Source:

\`\`\`text
$ROOTASROLE_REF
$ROOTASROLE_COMMIT
$ROOTASROLE_SOURCE_SHA256
\`\`\`

Installed commands:

\`\`\`text
/usr/bin/dosr
/usr/bin/chsr
\`\`\`

Allowed runtime shared surface:

\`\`\`text
dosr -> libpam.so.0, libgcc_s.so.1, libc.musl-x86_64.so.1
chsr -> libseccomp.so.2, libgcc_s.so.1, libc.musl-x86_64.so.1
\`\`\`
EOF_DOC

    chmod 0644 "$payload_root/usr/share/defaults/pam.d/dosr"
    chmod 0644 "$payload_root/usr/share/onix/packages/rootasrole.md"
    tar -C "$LAB/src" -czf "$payload_archive" "$payload_name"
    cut_stone rootasrole "$ROOTASROLE_VERSION" "$payload_archive"
}

prove_remote_install() {
    echo "==> index local forge repo and install RootAsRole"
    rm -rf "$FINAL_REPO" "$ROOT" "$CACHE" "$TARGET"
    mkdir -p "$FINAL_REPO" "$ROOT" "$CACHE" "$TARGET"
    cp "$LAB/phase510"/*.stone "$FINAL_REPO/"
    cp "$(cat "$LAB/libgcc-runtime.stone.path")" "$FINAL_REPO/"
    cp "$(cat "$LAB/rootasrole.stone.path")" "$FINAL_REPO/"
    moss index "$FINAL_REPO"
    moss -D "$ROOT" --cache "$CACHE" repo add local "file://$FINAL_REPO/stone.index" -c "local ONIX RootAsRole"
    moss -D "$ROOT" --cache "$CACHE" repo update
    moss -D "$ROOT" --cache "$CACHE" -y install --to "$TARGET" rootasrole

    test -x "$TARGET/usr/bin/dosr"
    test -x "$TARGET/usr/bin/chsr"
    test -e "$TARGET/usr/lib/libpam.so.0"
    test -e "$TARGET/usr/lib/libseccomp.so.2"
    test -e "$TARGET/usr/lib/libgcc_s.so.1"
    test "$(stat -c '%a' "$TARGET/usr/bin/dosr")" = "4755"
    check_allowed_needed "$TARGET/usr/bin/dosr" dosr
    check_allowed_needed "$TARGET/usr/bin/chsr" chsr

    # Do not execute dosr in this scratch install target. RootAsRole expects
    # live machine policy/config paths, and Phase 511 deliberately installs only
    # package defaults under /usr/share/defaults. The live-policy execution proof
    # belongs to the next integration phase.

    echo "==> success"
    echo "libgcc-runtime stone: $(cat "$LAB/libgcc-runtime.stone.path")"
    echo "rootasrole stone     : $(cat "$LAB/rootasrole.stone.path")"
}

build_libgcc_runtime
install_build_sysroot
build_rootasrole
prove_remote_install
REMOTE

  log "copying built stones back to host artifacts"
  rm -f \
    "$STONE_DIR"/libgcc-runtime-*.stone \
    "$STONE_DIR"/libgcc-runtime-dbginfo-*.stone \
    "$STONE_DIR"/libgcc-runtime-devel-*.stone \
    "$STONE_DIR"/rootasrole-*.stone \
    "$STONE_DIR"/rootasrole-dbginfo-*.stone \
    "$STONE_DIR"/rootasrole-devel-*.stone

  local package path_file remote_stone
  for package in libgcc-runtime rootasrole; do
    path_file="$LAB/$package.stone.path"
    remote_stone="$("$PHASE0_DIR/ssh.sh" "$user" "cat '$path_file'")"
    "$PHASE0_DIR/ssh.sh" "$user" "cd \"\$(dirname '$remote_stone')\" && tar -cf - \"\$(basename '$remote_stone')\"" \
      | tar -C "$STONE_DIR" -xf -
  done

  local host_gcc host_rootasrole
  host_gcc="$(host_stone_for libgcc-runtime)"
  host_rootasrole="$(host_stone_for rootasrole)"
  [[ -f "$host_gcc" ]] || die "failed to copy libgcc-runtime stone into ${STONE_DIR#$ONIX_ROOT/}"
  [[ -f "$host_rootasrole" ]] || die "failed to copy rootasrole stone into ${STONE_DIR#$ONIX_ROOT/}"

  log "host moss integrity checks"
  "$HOST_MOSS" inspect --check "$host_gcc" >/dev/null
  "$HOST_MOSS" inspect --check "$host_rootasrole" >/dev/null

  log "refreshing local Phase 5 moss repo"
  rm -f \
    "$LOCAL_REPO_DIR"/libgcc-runtime-*.stone \
    "$LOCAL_REPO_DIR"/libgcc-runtime-dbginfo-*.stone \
    "$LOCAL_REPO_DIR"/libgcc-runtime-devel-*.stone \
    "$LOCAL_REPO_DIR"/rootasrole-*.stone \
    "$LOCAL_REPO_DIR"/rootasrole-dbginfo-*.stone \
    "$LOCAL_REPO_DIR"/rootasrole-devel-*.stone
  cp "$host_gcc" "$LOCAL_REPO_DIR/"
  cp "$host_rootasrole" "$LOCAL_REPO_DIR/"
  "$HOST_MOSS" index "$LOCAL_REPO_DIR"

  prove_host_install_and_audit

  cat <<EOF_SUCCESS

==> success
libgcc-runtime stone: ${host_gcc#$ONIX_ROOT/}
rootasrole stone     : ${host_rootasrole#$ONIX_ROOT/}
local repo index     : ${LOCAL_REPO_DIR#$ONIX_ROOT/}/stone.index

Phase 511 built/audited RootAsRole against ONIX-owned musl + PAM + seccomp +
libgcc-runtime. The next step is policy integration: deciding how ONIX
materializes live /etc/security/rootasrole.json and /etc/pam.d/dosr.
EOF_SUCCESS
}

case "$MODE" in
  apply) run_apply ;;
  check) run_check ;;
  *) die "unknown mode: $MODE" ;;
esac
