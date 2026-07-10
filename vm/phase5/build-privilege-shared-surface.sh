#!/usr/bin/env bash
# vm/phase5/build-privilege-shared-surface.sh — Phase 510.
#
# Builds the ONIX-owned shared-library surface needed before RootAsRole can stop
# depending on forge/host libraries:
#
#   - linux-pam
#   - libseccomp
#   - musl
#
# These are intentional dynamic-musl exceptions. Static/static-PIE is still the
# default for ordinary system binaries, but PAM/seccomp are library surfaces and
# musl is the runtime provider those dynamic-musl packages need.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHASE0_DIR="$(cd "$SCRIPT_DIR/../phase0" && pwd)"

# shellcheck source=vm/phase0/config.sh
source "$PHASE0_DIR/config.sh"

user="$BUILD_USER"

MODE="apply"
FORCE_REBUILD="${ONIX_PHASE510_REBUILD:-0}"

DEFAULT_MUSL_VERSION="${ONIX_MUSL_VERSION:-1.2.6}"
DEFAULT_MUSL_SOURCE_URL="${ONIX_MUSL_SOURCE_URL:-https://musl.libc.org/releases/musl-$DEFAULT_MUSL_VERSION.tar.gz}"
DEFAULT_MUSL_SOURCE_SHA256="${ONIX_MUSL_SOURCE_SHA256:-d585fd3b613c66151fc3249e8ed44f77020cb5e6c1e635a616d3f9f82460512a}"

STONE_DIR="${ONIX_STONE_DIR:-$ONIX_ROOT/artifacts/onix-stones}"
LOCAL_REPO_DIR="${ONIX_LOCAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-local-repo}"
STONE_WORK_DIR="${ONIX_STONE_WORK_DIR:-$ONIX_ROOT/artifacts/onix-stone-work}"
WORK="${ONIX_PHASE510_WORK_DIR:-$STONE_WORK_DIR/privilege-shared-surface}"
HOST_MOSS="${ONIX_HOST_MOSS:-$ONIX_ROOT/artifacts/host-tools/bin/moss}"
AUDIT_SCRIPT="$SCRIPT_DIR/audit-stone-payload.sh"
PROOF_DIR="$ONIX_ROOT/artifacts/onix-phase5-work/510"

MUSL_RECIPE_TEMPLATE="${ONIX_MUSL_RECIPE_TEMPLATE:-$ONIX_ROOT/packages/libs/musl/stone.yaml.in}"
LINUX_PAM_RECIPE_TEMPLATE="${ONIX_LINUX_PAM_RECIPE_TEMPLATE:-$ONIX_ROOT/packages/libs/linux-pam/stone.yaml.in}"
LIBSECCOMP_RECIPE_TEMPLATE="${ONIX_LIBSECCOMP_RECIPE_TEMPLATE:-$ONIX_ROOT/packages/libs/libseccomp/stone.yaml.in}"

LAB="/home/$user/stone-lab/onix-privilege-shared-surface"

usage() {
  cat <<'EOF'
usage: build-privilege-shared-surface.sh [--apply|--check|--rebuild]

--apply    build missing musl/linux-pam/libseccomp stones, audit them, and refresh
           the local ONIX repo
--check    verify package metadata and inspect/audit existing stones when present
--rebuild  force rebuilding/rechecking the Phase 510 shared-library surface

Phase 510 builds:
  - musl
  - linux-pam
  - libseccomp
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

realize_source() {
  local attr="$1"
  local override="$2"

  if [[ -n "$override" ]]; then
    printf '%s\n' "$override"
    return
  fi

  local rev
  rev="$(extract_locked_nixpkgs_rev)"
  [[ -n "$rev" ]] || die "could not read pinned nixpkgs_2 rev from flake.lock"

  nix eval --raw "github:NixOS/nixpkgs/${rev}#${attr}.src.outPath"
}

realize_musl_source() {
  local override="$1"
  local source_dir archive actual_sha

  if [[ -n "$override" ]]; then
    printf '%s\n' "$override"
    return
  fi

  source_dir="$WORK/sources"
  archive="$source_dir/musl-$DEFAULT_MUSL_VERSION.tar.gz"
  mkdir -p "$source_dir"

  if [[ -f "$archive" ]]; then
    actual_sha="$(sha256sum "$archive" | awk '{print $1}')"
    if [[ "$actual_sha" != "$DEFAULT_MUSL_SOURCE_SHA256" ]]; then
      rm -f "$archive"
    fi
  fi

  if [[ ! -f "$archive" ]]; then
    curl -L --fail --retry 3 -o "$archive" "$DEFAULT_MUSL_SOURCE_URL"
  fi

  actual_sha="$(sha256sum "$archive" | awk '{print $1}')"
  [[ "$actual_sha" == "$DEFAULT_MUSL_SOURCE_SHA256" ]] \
    || die "musl source checksum mismatch for $archive: expected $DEFAULT_MUSL_SOURCE_SHA256, got $actual_sha"

  printf '%s\n' "$archive"
}

meson_project_version() {
  local meson_file="$1"
  sed -n "s/.*version:[[:space:]]*'\\([^']*\\)'.*/\\1/p" "$meson_file" | head -n 1
}

archive_dir_source() {
  local source_dir="$1"
  local package="$2"
  local version="$3"
  local archive="$WORK/${package}-${version}-source.tar.gz"
  local tar_path="${archive%.gz}"

  [[ -d "$source_dir" ]] || die "source path is not a directory: $source_dir"
  rm -f "$archive" "$tar_path"
  tar \
    --mode='u+rwX,go+rX' \
    --exclude='./.git' \
    --exclude='./build' \
    -C "$source_dir" \
    -cf "$tar_path" .
  gzip -n -f "$tar_path"

  printf '%s\n' "$archive"
}

host_stone_for() {
  local package="$1"
  find "$STONE_DIR" -maxdepth 1 -name "$package-[0-9]*.stone" ! -name '*dbginfo*' | sort | tail -n 1
}

elf_has_symbol() {
  local elf="$1"
  local symbol="$2"
  readelf -Ws "$elf" |
    awk -v symbol="$symbol" '$8 == symbol { found=1 } END { exit found ? 0 : 1 }'
}

local_stone_for() {
  local package="$1"
  find "$LOCAL_REPO_DIR" -maxdepth 1 -name "$package-[0-9]*.stone" ! -name '*dbginfo*' | sort | tail -n 1
}

check_source_files() {
  [[ -f "$ONIX_ROOT/packages/STONES.md" ]] || die "missing packages/STONES.md"
  [[ -f "$ONIX_ROOT/packages/libs/musl/PACKAGE.md" ]] || die "missing musl PACKAGE.md"
  [[ -f "$ONIX_ROOT/packages/libs/linux-pam/PACKAGE.md" ]] || die "missing linux-pam PACKAGE.md"
  [[ -f "$ONIX_ROOT/packages/libs/libseccomp/PACKAGE.md" ]] || die "missing libseccomp PACKAGE.md"
  [[ -f "$MUSL_RECIPE_TEMPLATE" ]] || die "missing musl recipe template"
  [[ -f "$LINUX_PAM_RECIPE_TEMPLATE" ]] || die "missing linux-pam recipe template"
  [[ -f "$LIBSECCOMP_RECIPE_TEMPLATE" ]] || die "missing libseccomp recipe template"

  grep -q 'musl' "$ONIX_ROOT/packages/STONES.md"
  grep -q 'linux-pam' "$ONIX_ROOT/packages/STONES.md"
  grep -q 'libseccomp' "$ONIX_ROOT/packages/STONES.md"
  grep -q 'runtime provider' "$ONIX_ROOT/packages/libs/musl/PACKAGE.md"
  grep -q 'dynamic-musl exception' "$ONIX_ROOT/packages/libs/linux-pam/PACKAGE.md"
  grep -q 'dynamic-musl exception' "$ONIX_ROOT/packages/libs/libseccomp/PACKAGE.md"
}

phase510_packages_for_proof() {
  local packages=()
  [[ -n "$(local_stone_for musl)" ]] && packages+=(musl)
  [[ -n "$(local_stone_for linux-pam)" ]] && packages+=(linux-pam)
  [[ -n "$(local_stone_for libseccomp)" ]] && packages+=(libseccomp)
  printf '%s\n' "${packages[@]}"
}

prove_host_install_and_audit() {
  [[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"
  [[ -x "$AUDIT_SCRIPT" ]] || die "missing payload audit helper: ${AUDIT_SCRIPT#$ONIX_ROOT/}"
  command -v readelf >/dev/null 2>&1 || die "missing required command: readelf"

  local root="$PROOF_DIR/moss-root"
  local cache="$PROOF_DIR/moss-cache"
  local target="$PROOF_DIR/install-target"
  local install_log="$PROOF_DIR/moss-install.log"
  local packages=()
  local package

  rm -rf "$PROOF_DIR"
  mkdir -p "$root" "$cache" "$target"

  while IFS= read -r package; do
    [[ -n "$package" ]] && packages+=("$package")
  done < <(phase510_packages_for_proof)

  if [[ "${#packages[@]}" -ne 3 ]]; then
    log "stone     : musl/linux-pam/libseccomp not all built yet"
    return 0
  fi

  "$HOST_MOSS" -D "$root" \
    --cache "$cache" \
    repo add onix-privilege-shared-surface \
    "file://$LOCAL_REPO_DIR/stone.index" \
    -c "ONIX Phase 510 privilege shared surface" >/dev/null

  "$HOST_MOSS" -D "$root" --cache "$cache" repo update >/dev/null

  if ! "$HOST_MOSS" -D "$root" \
      --cache "$cache" \
      -y install --to "$target" \
      "${packages[@]}" >"$install_log" 2>&1; then
    cat "$install_log" >&2
    die "Moss could not install Phase 510 shared-surface stones"
  fi

  if grep -q 'duplicate entry:' "$install_log"; then
    cat "$install_log" >&2
    die "Phase 510 shared-surface stones reported package path ownership collisions"
  fi

  [[ -e "$target/usr/lib/ld-musl-x86_64.so.1" ]] || die "missing installed musl loader"
  elf_has_symbol "$target/usr/lib/ld-musl-x86_64.so.1" renameat2 \
    || die "installed musl loader is missing renameat2; rebuild Phase 510 musl"
  [[ -e "$target/usr/lib/libpam.so.0" ]] || die "missing installed libpam.so.0"
  [[ -e "$target/usr/lib/libseccomp.so.2" ]] || die "missing installed libseccomp.so.2"
  [[ -f "$target/usr/share/onix/packages/musl.md" ]] || die "missing musl package note"
  [[ -f "$target/usr/share/onix/packages/linux-pam.md" ]] || die "missing linux-pam package note"
  [[ -f "$target/usr/share/onix/packages/libseccomp.md" ]] || die "missing libseccomp package note"

  "$AUDIT_SCRIPT" --allow-dynamic-musl "$target" >/dev/null

  log "proof     : host Moss install + dynamic-musl audit OK"
}

run_check() {
  check_source_files
  [[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"

  local package stone
  for package in musl linux-pam libseccomp; do
    stone="$(local_stone_for "$package")"
    if [[ -z "$stone" ]]; then
      log "stone     : $package not built yet"
      continue
    fi
    "$HOST_MOSS" inspect --check "$stone" >/dev/null
    log "stone     : ${stone#$ONIX_ROOT/}"
  done

  prove_host_install_and_audit
  log "phase510  : check OK"
}

run_apply() {
  need_cmd awk
  need_cmd cp
  need_cmd curl
  need_cmd gzip
  need_cmd nix
  need_cmd sed
  need_cmd sha256sum
  need_cmd tar

  safe_artifact_path "$STONE_DIR"
  safe_artifact_path "$LOCAL_REPO_DIR"
  safe_artifact_path "$STONE_WORK_DIR"
  safe_artifact_path "$WORK"

  check_source_files
  [[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"

  local existing_musl existing_pam existing_seccomp
  existing_musl="$(local_stone_for musl)"
  existing_pam="$(local_stone_for linux-pam)"
  existing_seccomp="$(local_stone_for libseccomp)"

  if [[ "$FORCE_REBUILD" != "1" && -n "$existing_musl" && -n "$existing_pam" && -n "$existing_seccomp" ]]; then
    log "Phase 510 shared-library surface already exists"
    run_check
    return
  fi

  mkdir -p "$STONE_DIR" "$LOCAL_REPO_DIR" "$STONE_WORK_DIR"
  rm -rf "$WORK"
  mkdir -p "$WORK"

  log "Phase 510 privilege shared-library surface"
  log "source    : pinned nixpkgs_2 source trees"
  log "build     : Alpine/musl forge VM"
  log "policy    : intentional dynamic-musl exceptions, ONIX-owned"
  log "stone out : ${STONE_DIR#$ONIX_ROOT/}"
  log "local repo: ${LOCAL_REPO_DIR#$ONIX_ROOT/}"

  local musl_src pam_src seccomp_src musl_version pam_version seccomp_version
  musl_src="$(realize_musl_source "${ONIX_MUSL_SRC:-}")"
  pam_src="$(realize_source linux-pam "${ONIX_LINUX_PAM_SRC:-}")"
  seccomp_src="$(realize_source libseccomp "${ONIX_LIBSECCOMP_SRC:-}")"

  [[ -f "$musl_src" ]] || die "musl source is not a file: $musl_src"
  [[ -d "$pam_src" ]] || die "linux-pam source is not a directory: $pam_src"
  [[ -f "$seccomp_src" ]] || die "libseccomp source is not a file: $seccomp_src"

  musl_version="$(basename "$musl_src" | sed -E 's/^.*musl-([0-9][0-9.]*)\.tar.*$/\1/')"
  pam_version="$(meson_project_version "$pam_src/meson.build")"
  seccomp_version="$(basename "$seccomp_src" | sed -E 's/^.*libseccomp-([0-9][0-9.]*)\.tar.*$/\1/')"
  [[ "$musl_version" != "$(basename "$musl_src")" ]] || die "could not infer musl version"
  [[ -n "$pam_version" ]] || die "could not read linux-pam version"
  [[ "$seccomp_version" != "$(basename "$seccomp_src")" ]] || die "could not infer libseccomp version"

  local musl_archive pam_archive seccomp_archive musl_sha pam_sha seccomp_sha
  musl_archive="$musl_src"
  pam_archive="$(archive_dir_source "$pam_src" linux-pam "$pam_version")"
  seccomp_archive="$seccomp_src"
  musl_sha="$(sha256sum "$musl_archive" | awk '{print $1}')"
  pam_sha="$(sha256sum "$pam_archive" | awk '{print $1}')"
  seccomp_sha="$(sha256sum "$seccomp_archive" | awk '{print $1}')"

  cat > "$WORK/build.env" <<EOF_ENV
MUSL_VERSION='$musl_version'
MUSL_SOURCE_ARCHIVE='$(basename "$musl_archive")'
MUSL_SOURCE_SHA256='$musl_sha'
LINUX_PAM_VERSION='$pam_version'
LINUX_PAM_SOURCE_ARCHIVE='$(basename "$pam_archive")'
LINUX_PAM_SOURCE_SHA256='$pam_sha'
LIBSECCOMP_VERSION='$seccomp_version'
LIBSECCOMP_SOURCE_ARCHIVE='$(basename "$seccomp_archive")'
LIBSECCOMP_SOURCE_SHA256='$seccomp_sha'
EOF_ENV

  cp "$MUSL_RECIPE_TEMPLATE" "$WORK/musl.stone.yaml.in"
  cp "$LINUX_PAM_RECIPE_TEMPLATE" "$WORK/linux-pam.stone.yaml.in"
  cp "$LIBSECCOMP_RECIPE_TEMPLATE" "$WORK/libseccomp.stone.yaml.in"

  cat <<EOF_POLICY
==> source policy
musl version      : $musl_version
musl sha256       : $musl_sha
linux-pam version  : $pam_version
linux-pam sha256   : $pam_sha
libseccomp version : $seccomp_version
libseccomp sha256  : $seccomp_sha
nix role           : pinned source acquisition only
payload rule       : dynamic-musl allowed here because these stones own the shared surface
EOF_POLICY

  log "ensuring shared-surface build dependencies in the forge"
  "$PHASE0_DIR/ssh.sh" root \
    "apk add --no-cache build-base meson samurai pkgconf coreutils findutils file binutils linux-headers gettext-dev autoconf automake libtool m4 gperf bash"

  log "copying source archives + recipe templates into the forge"
  tar -cf - \
    -C "$WORK" build.env \
    -C "$(dirname "$musl_archive")" "$(basename "$musl_archive")" \
    -C "$WORK" "$(basename "$pam_archive")" \
    -C "$(dirname "$seccomp_archive")" "$(basename "$seccomp_archive")" \
    -C "$WORK" musl.stone.yaml.in \
    -C "$WORK" linux-pam.stone.yaml.in \
    -C "$WORK" libseccomp.stone.yaml.in \
    | "$PHASE0_DIR/ssh.sh" "$user" "rm -rf '$LAB' && mkdir -p '$LAB/src' && tar -C '$LAB' -xf - && mv '$LAB/$(basename "$musl_archive")' '$LAB/src/$(basename "$musl_archive")' && mv '$LAB/$(basename "$pam_archive")' '$LAB/src/$(basename "$pam_archive")' && mv '$LAB/$(basename "$seccomp_archive")' '$LAB/src/$(basename "$seccomp_archive")'"

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
need_tool make
need_tool tar
need_tool gzip
need_tool sha256sum
need_tool sed
need_tool grep
need_tool awk
need_tool install
need_tool readelf
need_tool file

LAB="$HOME/stone-lab/onix-privilege-shared-surface"
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

elf_has_symbol() {
    elf="$1"
    symbol="$2"
    readelf -Ws "$elf" |
        awk -v symbol="$symbol" '$8 == symbol { found=1 } END { exit found ? 0 : 1 }'
}

check_musl_soname() {
    so="$1"
    check_shared_object "$so"
    if ! readelf -d "$so" 2>/dev/null | grep -q 'Library soname: \[libc.musl-x86_64.so.1\]'; then
        echo "error: $so does not provide libc.musl-x86_64.so.1" >&2
        readelf -d "$so" >&2 || true
        exit 1
    fi
    if ! elf_has_symbol "$so" renameat2; then
        echo "error: $so does not export renameat2" >&2
        exit 1
    fi
}

cut_stone() {
    package="$1"
    version="$2"
    payload_archive="$3"
    payload_hash="$(sha256sum "$payload_archive" | awk '{print $1}')"
    payload_url="file://$payload_archive"

    case "$package" in
      musl)
        sed \
          -e "s|@MUSL_VERSION@|$version|g" \
          -e "s|@MUSL_PAYLOAD_URL@|$payload_url|g" \
          -e "s|@MUSL_PAYLOAD_SHA256@|$payload_hash|g" \
          -e "s|@MUSL_PAYLOAD_ARCHIVE@|$(basename "$payload_archive")|g" \
          -e "s|@MUSL_SOURCE_ARCHIVE@|$MUSL_SOURCE_ARCHIVE|g" \
          -e "s|@MUSL_SOURCE_SHA256@|$MUSL_SOURCE_SHA256|g" \
          "$LAB/musl.stone.yaml.in" > "$LAB/musl.stone.yaml"
        recipe="$LAB/musl.stone.yaml"
        ;;
      linux-pam)
        sed \
          -e "s|@LINUX_PAM_VERSION@|$version|g" \
          -e "s|@LINUX_PAM_PAYLOAD_URL@|$payload_url|g" \
          -e "s|@LINUX_PAM_PAYLOAD_SHA256@|$payload_hash|g" \
          -e "s|@LINUX_PAM_PAYLOAD_ARCHIVE@|$(basename "$payload_archive")|g" \
          -e "s|@LINUX_PAM_SOURCE_ARCHIVE@|$LINUX_PAM_SOURCE_ARCHIVE|g" \
          -e "s|@LINUX_PAM_SOURCE_SHA256@|$LINUX_PAM_SOURCE_SHA256|g" \
          "$LAB/linux-pam.stone.yaml.in" > "$LAB/linux-pam.stone.yaml"
        recipe="$LAB/linux-pam.stone.yaml"
        ;;
      libseccomp)
        sed \
          -e "s|@LIBSECCOMP_VERSION@|$version|g" \
          -e "s|@LIBSECCOMP_PAYLOAD_URL@|$payload_url|g" \
          -e "s|@LIBSECCOMP_PAYLOAD_SHA256@|$payload_hash|g" \
          -e "s|@LIBSECCOMP_PAYLOAD_ARCHIVE@|$(basename "$payload_archive")|g" \
          -e "s|@LIBSECCOMP_SOURCE_ARCHIVE@|$LIBSECCOMP_SOURCE_ARCHIVE|g" \
          -e "s|@LIBSECCOMP_SOURCE_SHA256@|$LIBSECCOMP_SOURCE_SHA256|g" \
          "$LAB/libseccomp.stone.yaml.in" > "$LAB/libseccomp.stone.yaml"
        recipe="$LAB/libseccomp.stone.yaml"
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

    stone="$(find "$out" -maxdepth 1 -name "$package-[0-9]*.stone" ! -name '*dbginfo*' | sort | head -n 1)"
    test -f "$stone"
    printf '%s\n' "$stone" > "$LAB/$package.stone.path"
    moss inspect --check "$stone"
}

build_musl() {
    echo "==> build musl runtime provider"

    src_archive="$LAB/src/$MUSL_SOURCE_ARCHIVE"
    src_hash="$(sha256sum "$src_archive" | awk '{print $1}')"
    if [ "$src_hash" != "$MUSL_SOURCE_SHA256" ]; then
        echo "error: musl source checksum mismatch" >&2
        exit 1
    fi

    build_src="$LAB/musl-source"
    dest="$LAB/musl-dest"
    payload_name="musl-payload-$MUSL_VERSION"
    payload_root="$LAB/src/$payload_name"
    payload_archive="$LAB/src/$payload_name.tar.gz"

    rm -rf "$build_src" "$dest" "$payload_root" "$payload_archive"
    mkdir -p "$build_src" "$dest" "$payload_root"
    tar -xzf "$src_archive" -C "$build_src" --strip-components=1

    (
        cd "$build_src"
        LDFLAGS="${LDFLAGS:-} -Wl,-soname,libc.musl-x86_64.so.1" \
        ./configure \
          --prefix=/usr \
          --syslibdir=/lib \
          --enable-shared \
          > "$LAB/musl-configure.log" 2>&1

        if ! make -j"$jobs" > "$LAB/musl-build.log" 2>&1; then
            echo "error: musl build failed; tail:" >&2
            tail -n 160 "$LAB/musl-build.log" >&2
            exit 1
        fi
        make DESTDIR="$dest" install > "$LAB/musl-install.log" 2>&1
    )

    mkdir -p \
      "$payload_root/usr/include" \
      "$payload_root/usr/lib" \
      "$payload_root/usr/share/onix/packages"

    cp -a "$dest/usr/include"/* "$payload_root/usr/include/"
    cp -a "$dest/usr/lib"/* "$payload_root/usr/lib/"

    # Upstream musl installs /lib/ld-musl-*.so.1 as a symlink to
    # /usr/lib/libc.so. Boulder classifies the package through /usr/lib, and
    # ONIX image roots are usr-merged (/lib -> /usr/lib), so package the
    # SONAME-carrying ELF at /usr/lib/ld-musl-x86_64.so.1. Keep libc.so and
    # libc.musl-x86_64.so.1 as relative symlinks for link/runtime lookup.
    rm -f \
      "$payload_root/usr/lib/ld-musl-x86_64.so.1" \
      "$payload_root/usr/lib/libc.so" \
      "$payload_root/usr/lib/libc.musl-x86_64.so.1"
    install -m 00755 "$dest/usr/lib/libc.so" "$payload_root/usr/lib/ld-musl-x86_64.so.1"
    ln -s ld-musl-x86_64.so.1 "$payload_root/usr/lib/libc.so"
    ln -s ld-musl-x86_64.so.1 "$payload_root/usr/lib/libc.musl-x86_64.so.1"

    check_musl_soname "$payload_root/usr/lib/ld-musl-x86_64.so.1"
    check_musl_soname "$payload_root/usr/lib/libc.so"
    check_musl_soname "$payload_root/usr/lib/libc.musl-x86_64.so.1"

    cat > "$payload_root/usr/share/onix/packages/musl.md" <<EOF_DOC
# musl

ONIX-owned musl runtime provider.

Source archive:

\`\`\`text
$MUSL_SOURCE_ARCHIVE
\`\`\`

Source SHA-256:

\`\`\`text
$MUSL_SOURCE_SHA256
\`\`\`

Installed runtime provider:

\`\`\`text
/usr/lib/ld-musl-x86_64.so.1
\`\`\`

Required ABI proof:

\`\`\`text
exports renameat2
\`\`\`
EOF_DOC

    chmod 0644 "$payload_root/usr/share/onix/packages/musl.md"
    tar -C "$LAB/src" -czf "$payload_archive" "$payload_name"
    cut_stone musl "$MUSL_VERSION" "$payload_archive"
}

build_libseccomp() {
    echo "==> build libseccomp"

    src_archive="$LAB/src/$LIBSECCOMP_SOURCE_ARCHIVE"
    src_hash="$(sha256sum "$src_archive" | awk '{print $1}')"
    if [ "$src_hash" != "$LIBSECCOMP_SOURCE_SHA256" ]; then
        echo "error: libseccomp source checksum mismatch" >&2
        exit 1
    fi

    build_src="$LAB/libseccomp-source"
    dest="$LAB/libseccomp-dest"
    payload_name="libseccomp-payload-$LIBSECCOMP_VERSION"
    payload_root="$LAB/src/$payload_name"
    payload_archive="$LAB/src/$payload_name.tar.gz"

    rm -rf "$build_src" "$dest" "$payload_root" "$payload_archive"
    mkdir -p "$build_src" "$dest" "$payload_root"
    tar -xzf "$src_archive" -C "$build_src" --strip-components=1

    (
        cd "$build_src"
        ./configure \
          --prefix=/usr \
          --libdir=/usr/lib \
          --enable-shared \
          --disable-static \
          --disable-python \
          > "$LAB/libseccomp-configure.log" 2>&1

        if ! make -j"$jobs" > "$LAB/libseccomp-build.log" 2>&1; then
            echo "error: libseccomp build failed; tail:" >&2
            tail -n 160 "$LAB/libseccomp-build.log" >&2
            exit 1
        fi
        make DESTDIR="$dest" install > "$LAB/libseccomp-install.log" 2>&1
    )

    mkdir -p \
      "$payload_root/usr/lib" \
      "$payload_root/usr/include" \
      "$payload_root/usr/lib/pkgconfig" \
      "$payload_root/usr/share/onix/packages"

    cp -a "$dest/usr/lib"/libseccomp.so* "$payload_root/usr/lib/"
    cp -a "$dest/usr/include"/seccomp.h "$payload_root/usr/include/"
    cp -a "$dest/usr/lib/pkgconfig"/libseccomp.pc "$payload_root/usr/lib/pkgconfig/"

    check_shared_object "$payload_root/usr/lib/libseccomp.so.2"

    cat > "$payload_root/usr/share/onix/packages/libseccomp.md" <<EOF_DOC
# libseccomp

ONIX-owned libseccomp shared-library surface.

Source archive:

\`\`\`text
$LIBSECCOMP_SOURCE_ARCHIVE
\`\`\`

Source SHA-256:

\`\`\`text
$LIBSECCOMP_SOURCE_SHA256
\`\`\`

Installed shared object:

\`\`\`text
/usr/lib/libseccomp.so.2
\`\`\`
EOF_DOC

    chmod 0644 "$payload_root/usr/share/onix/packages/libseccomp.md"
    tar -C "$LAB/src" -czf "$payload_archive" "$payload_name"
    cut_stone libseccomp "$LIBSECCOMP_VERSION" "$payload_archive"
}

build_linux_pam() {
    echo "==> build linux-pam"

    src_archive="$LAB/src/$LINUX_PAM_SOURCE_ARCHIVE"
    src_hash="$(sha256sum "$src_archive" | awk '{print $1}')"
    if [ "$src_hash" != "$LINUX_PAM_SOURCE_SHA256" ]; then
        echo "error: linux-pam source checksum mismatch" >&2
        exit 1
    fi

    build_src="$LAB/linux-pam-source"
    build_dir="$LAB/linux-pam-build"
    dest="$LAB/linux-pam-dest"
    payload_name="linux-pam-payload-$LINUX_PAM_VERSION"
    payload_root="$LAB/src/$payload_name"
    payload_archive="$LAB/src/$payload_name.tar.gz"

    rm -rf "$build_src" "$build_dir" "$dest" "$payload_root" "$payload_archive"
    mkdir -p "$build_src" "$dest" "$payload_root"
    tar -xzf "$src_archive" -C "$build_src"

    meson setup "$build_dir" "$build_src" \
      --prefix=/usr \
      --libdir=lib \
      --buildtype=release \
      -Di18n=disabled \
      -Ddocs=disabled \
      -Daudit=disabled \
      -Deconf=disabled \
      -Dlogind=disabled \
      -Delogind=disabled \
      -Dopenssl=disabled \
      -Dselinux=disabled \
      -Dnis=disabled \
      -Dexamples=false \
      -Dxtests=false \
      -Dpam_userdb=disabled \
      -Dpam_lastlog=disabled \
      -Dpam_unix=disabled \
      -Dsecuredir=/usr/lib/security \
      -Dsconfigdir=/etc/security \
      > "$LAB/linux-pam-meson-setup.log" 2>&1 || {
        echo "error: linux-pam meson setup failed; tail:" >&2
        tail -n 200 "$LAB/linux-pam-meson-setup.log" >&2
        exit 1
      }

    if ! meson compile -C "$build_dir" -j "$jobs" > "$LAB/linux-pam-build.log" 2>&1; then
        echo "error: linux-pam build failed; tail:" >&2
        tail -n 200 "$LAB/linux-pam-build.log" >&2
        exit 1
    fi

    meson install -C "$build_dir" --destdir "$dest" > "$LAB/linux-pam-install.log" 2>&1

    mkdir -p \
      "$payload_root/usr/lib" \
      "$payload_root/usr/include" \
      "$payload_root/usr/lib/pkgconfig" \
      "$payload_root/usr/share/onix/packages"

    cp -a "$dest/usr/lib"/libpam.so* "$payload_root/usr/lib/"
    cp -a "$dest/usr/lib"/libpam_misc.so* "$payload_root/usr/lib/"
    cp -a "$dest/usr/lib"/libpamc.so* "$payload_root/usr/lib/"
    if [ -d "$dest/usr/lib/security" ]; then
        mkdir -p "$payload_root/usr/lib/security"
        cp -a "$dest/usr/lib/security"/*.so "$payload_root/usr/lib/security/" 2>/dev/null || true
    fi
    if [ -d "$dest/usr/include/security" ]; then
        mkdir -p "$payload_root/usr/include/security"
        cp -a "$dest/usr/include/security"/*.h "$payload_root/usr/include/security/"
    fi
    cp -a "$dest/usr/lib/pkgconfig"/pam*.pc "$payload_root/usr/lib/pkgconfig/" 2>/dev/null || true

    check_shared_object "$payload_root/usr/lib/libpam.so.0"
    check_shared_object "$payload_root/usr/lib/libpam_misc.so.0"
    check_shared_object "$payload_root/usr/lib/libpamc.so.0"

    cat > "$payload_root/usr/share/onix/packages/linux-pam.md" <<EOF_DOC
# linux-pam

ONIX-owned Linux-PAM shared-library and module surface.

Source archive:

\`\`\`text
$LINUX_PAM_SOURCE_ARCHIVE
\`\`\`

Source SHA-256:

\`\`\`text
$LINUX_PAM_SOURCE_SHA256
\`\`\`

Installed shared objects:

\`\`\`text
/usr/lib/libpam.so.0
/usr/lib/libpam_misc.so.0
/usr/lib/libpamc.so.0
\`\`\`

This first ONIX PAM surface disables pam_unix while we package the privilege
path. Secure live PAM policy is a later materialization decision.
EOF_DOC

    chmod 0644 "$payload_root/usr/share/onix/packages/linux-pam.md"
    tar -C "$LAB/src" -czf "$payload_archive" "$payload_name"
    cut_stone linux-pam "$LINUX_PAM_VERSION" "$payload_archive"
}

build_musl
build_libseccomp
build_linux_pam

echo "==> index local forge repo and install shared-surface stones"
rm -rf "$REPO" "$ROOT" "$CACHE" "$TARGET"
mkdir -p "$REPO" "$ROOT" "$CACHE" "$TARGET"
cp "$(cat "$LAB/musl.stone.path")" "$REPO/"
cp "$(cat "$LAB/libseccomp.stone.path")" "$REPO/"
cp "$(cat "$LAB/linux-pam.stone.path")" "$REPO/"
moss index "$REPO"
moss -D "$ROOT" --cache "$CACHE" repo add local "file://$REPO/stone.index" -c "local ONIX privilege shared surface"
moss -D "$ROOT" --cache "$CACHE" repo update
moss -D "$ROOT" --cache "$CACHE" -y install --to "$TARGET" musl linux-pam libseccomp

test -e "$TARGET/usr/lib/ld-musl-x86_64.so.1"
elf_has_symbol "$TARGET/usr/lib/ld-musl-x86_64.so.1" renameat2
test -e "$TARGET/usr/lib/libpam.so.0"
test -e "$TARGET/usr/lib/libseccomp.so.2"

echo "==> success"
echo "musl stone     : $(cat "$LAB/musl.stone.path")"
echo "linux-pam stone : $(cat "$LAB/linux-pam.stone.path")"
echo "libseccomp stone: $(cat "$LAB/libseccomp.stone.path")"
REMOTE

  log "copying built stones back to host artifacts"
  rm -f \
    "$STONE_DIR"/musl-*.stone \
    "$STONE_DIR"/musl-dbginfo-*.stone \
    "$STONE_DIR"/musl-devel-*.stone \
    "$STONE_DIR"/linux-pam-*.stone \
    "$STONE_DIR"/linux-pam-dbginfo-*.stone \
    "$STONE_DIR"/libseccomp-*.stone \
    "$STONE_DIR"/libseccomp-dbginfo-*.stone

  local package path_file remote_stone
  for package in musl linux-pam libseccomp; do
    path_file="$LAB/$package.stone.path"
    remote_stone="$("$PHASE0_DIR/ssh.sh" "$user" "cat '$path_file'")"
    "$PHASE0_DIR/ssh.sh" "$user" "cd \"\$(dirname '$remote_stone')\" && tar -cf - \"\$(basename '$remote_stone')\"" \
      | tar -C "$STONE_DIR" -xf -
  done

  local host_musl host_pam host_seccomp
  host_musl="$(host_stone_for musl)"
  host_pam="$(host_stone_for linux-pam)"
  host_seccomp="$(host_stone_for libseccomp)"
  [[ -f "$host_musl" ]] || die "failed to copy musl stone into ${STONE_DIR#$ONIX_ROOT/}"
  [[ -f "$host_pam" ]] || die "failed to copy linux-pam stone into ${STONE_DIR#$ONIX_ROOT/}"
  [[ -f "$host_seccomp" ]] || die "failed to copy libseccomp stone into ${STONE_DIR#$ONIX_ROOT/}"

  log "host moss integrity checks"
  "$HOST_MOSS" inspect --check "$host_musl" >/dev/null
  "$HOST_MOSS" inspect --check "$host_pam" >/dev/null
  "$HOST_MOSS" inspect --check "$host_seccomp" >/dev/null

  log "refreshing local Phase 4/5 moss repo"
  rm -f \
    "$LOCAL_REPO_DIR"/musl-*.stone \
    "$LOCAL_REPO_DIR"/musl-dbginfo-*.stone \
    "$LOCAL_REPO_DIR"/musl-devel-*.stone \
    "$LOCAL_REPO_DIR"/linux-pam-*.stone \
    "$LOCAL_REPO_DIR"/linux-pam-dbginfo-*.stone \
    "$LOCAL_REPO_DIR"/libseccomp-*.stone \
    "$LOCAL_REPO_DIR"/libseccomp-dbginfo-*.stone
  cp "$host_musl" "$LOCAL_REPO_DIR/"
  cp "$host_pam" "$LOCAL_REPO_DIR/"
  cp "$host_seccomp" "$LOCAL_REPO_DIR/"
  "$HOST_MOSS" index "$LOCAL_REPO_DIR"

  prove_host_install_and_audit

  cat <<EOF_SUCCESS

==> success
musl stone     : ${host_musl#$ONIX_ROOT/}
linux-pam stone : ${host_pam#$ONIX_ROOT/}
libseccomp stone: ${host_seccomp#$ONIX_ROOT/}
local repo index: ${LOCAL_REPO_DIR#$ONIX_ROOT/}/stone.index

Phase 510 built/audited the ONIX-owned musl + PAM + seccomp shared-library surface.
RootAsRole is no longer blocked on missing dependency stones; next is building
RootAsRole itself against this surface.
EOF_SUCCESS
}

case "$MODE" in
  apply) run_apply ;;
  check) run_check ;;
  *) die "unknown mode: $MODE" ;;
esac
