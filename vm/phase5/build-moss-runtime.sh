#!/usr/bin/env bash
# vm/phase5/build-moss-runtime.sh — Phase 515.
#
# Build moss itself as an ONIX-owned runtime package.
#
# Earlier phases used moss from the host or forge as bootstrap tooling. Phase
# 515 packages moss as a static Rust/musl .stone and proves the packaged binary
# can consume the ONIX repository.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHASE0_DIR="$(cd "$SCRIPT_DIR/../phase0" && pwd)"

# shellcheck source=vm/phase0/config.sh
source "$PHASE0_DIR/config.sh"

user="$BUILD_USER"

MODE="apply"
FORCE_REBUILD="${ONIX_PHASE515_REBUILD:-0}"
MOSS_RELEASE="${ONIX_MOSS_RELEASE:-1}"

STONE_DIR="${ONIX_STONE_DIR:-$ONIX_ROOT/artifacts/onix-stones}"
LOCAL_REPO_DIR="${ONIX_LOCAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-local-repo}"
STONE_WORK_DIR="${ONIX_STONE_WORK_DIR:-$ONIX_ROOT/artifacts/onix-stone-work}"
WORK="${ONIX_PHASE515_WORK_DIR:-$STONE_WORK_DIR/moss-runtime}"
PROOF_DIR="$ONIX_ROOT/artifacts/onix-phase5-work/515"
HOST_MOSS="${ONIX_HOST_MOSS:-$ONIX_ROOT/artifacts/host-tools/bin/moss}"
AUDIT_SCRIPT="$SCRIPT_DIR/audit-stone-payload.sh"

OS_TOOLS_SRC="${ONIX_OS_TOOLS_SRC:-$ONIX_ROOT/artifacts/host-tools/src/os-tools}"
MOSS_RECIPE_TEMPLATE="${ONIX_MOSS_RECIPE_TEMPLATE:-$ONIX_ROOT/packages/core/moss/stone.yaml.in}"

LAB="/home/$user/stone-lab/onix-moss-runtime"

usage() {
  cat <<'EOF'
usage: build-moss-runtime.sh [--apply|--check|--rebuild]

--apply    build missing moss stone, audit it, and refresh the local ONIX repo
--check    verify package metadata and inspect/audit an existing moss stone
--rebuild  force rebuilding/rechecking the Phase 515 moss package

Phase 515 builds:
  - moss
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
  find "$STONE_DIR" -maxdepth 1 -name "$package-[0-9]*.stone" ! -name '*dbginfo*' ! -name '*devel*' | sort | tail -n 1
}

local_stone_for() {
  local package="$1"
  find "$LOCAL_REPO_DIR" -maxdepth 1 -name "$package-[0-9]*.stone" ! -name '*dbginfo*' ! -name '*devel*' | sort | tail -n 1
}

workspace_version() {
  local cargo_toml="$1"
  awk '
    /^\[workspace\.package\]/ { in_workspace=1; next }
    in_workspace && /^\[/ { exit }
    in_workspace && /^version[[:space:]]*=/ {
      gsub(/"/, "", $3)
      print $3
      exit
    }
  ' "$cargo_toml"
}

check_source_files() {
  [[ -f "$ONIX_ROOT/packages/STONES.md" ]] || die "missing packages/STONES.md"
  [[ -f "$ONIX_ROOT/packages/core/moss/PACKAGE.md" ]] || die "missing moss PACKAGE.md"
  [[ -f "$MOSS_RECIPE_TEMPLATE" ]] || die "missing moss recipe template"
  [[ -f "$ONIX_ROOT/vm/phase5/docs/515_moss_runtime_package_and_self_repo_probe.md" ]] \
    || die "missing Phase 515 doc page"
  [[ -d "$OS_TOOLS_SRC/.git" ]] || die "missing pinned os-tools source checkout: ${OS_TOOLS_SRC#$ONIX_ROOT/} (run: make phase 202)"
  [[ -f "$OS_TOOLS_SRC/Cargo.toml" ]] || die "os-tools source is missing Cargo.toml"
  [[ -f "$OS_TOOLS_SRC/moss/Cargo.toml" ]] || die "os-tools source is missing moss/Cargo.toml"

  grep -q 'moss' "$ONIX_ROOT/packages/STONES.md"
  grep -q 'Rust' "$ONIX_ROOT/packages/core/moss/PACKAGE.md"
  grep -q 'static/static-pie' "$ONIX_ROOT/packages/core/moss/PACKAGE.md"
  grep -q 'Phase 515' "$ONIX_ROOT/vm/phase5/docs/515_moss_runtime_package_and_self_repo_probe.md"
}

create_os_tools_archive() {
  need_cmd git
  need_cmd gzip
  need_cmd sha256sum

  local commit version archive tar_path sha
  commit="$(git -C "$OS_TOOLS_SRC" rev-parse HEAD)"
  [[ "$commit" = "$OS_TOOLS_REF" ]] \
    || die "os-tools checkout mismatch: got $commit, expected $OS_TOOLS_REF"

  version="$(workspace_version "$OS_TOOLS_SRC/Cargo.toml")"
  [[ -n "$version" ]] || die "could not read os-tools workspace version"

  archive="$WORK/os-tools-$version-source.tar.gz"
  tar_path="${archive%.gz}"
  rm -f "$archive" "$tar_path"

  git -C "$OS_TOOLS_SRC" archive \
    --format=tar \
    --prefix="os-tools-$version/" \
    -o "$tar_path" \
    HEAD
  gzip -n -f "$tar_path"
  sha="$(sha256sum "$archive" | awk '{print $1}')"

  cat > "$WORK/build.env" <<EOF_ENV
MOSS_VERSION='$version'
MOSS_RELEASE='$MOSS_RELEASE'
OS_TOOLS_REPO='$OS_TOOLS_REPO'
OS_TOOLS_COMMIT='$commit'
OS_TOOLS_SOURCE_ARCHIVE='$(basename "$archive")'
OS_TOOLS_SOURCE_SHA256='$sha'
EOF_ENV

  cat <<EOF_POLICY
==> source policy
os-tools repo      : $OS_TOOLS_REPO
os-tools commit    : $commit
moss version       : $version
source sha256      : $sha
payload rule       : static/static-pie musl; no runtime shared-library surface
EOF_POLICY
}

prove_host_install_and_audit() {
  [[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"
  [[ -x "$AUDIT_SCRIPT" ]] || die "missing payload audit helper: ${AUDIT_SCRIPT#$ONIX_ROOT/}"

  local stone root cache target install_log packaged_root packaged_cache packaged_target info_log list_log
  stone="$(local_stone_for moss)"
  if [[ -z "$stone" ]]; then
    log "stone     : moss not built yet"
    return 0
  fi

  rm -rf "$PROOF_DIR"
  mkdir -p "$PROOF_DIR"
  root="$PROOF_DIR/moss-root"
  cache="$PROOF_DIR/moss-cache"
  target="$PROOF_DIR/install-target"
  install_log="$PROOF_DIR/moss-install.log"
  packaged_root="$PROOF_DIR/packaged-moss-root"
  packaged_cache="$PROOF_DIR/packaged-moss-cache"
  packaged_target="$PROOF_DIR/packaged-moss-target"
  info_log="$PROOF_DIR/packaged-moss-info.log"
  list_log="$PROOF_DIR/packaged-moss-list.log"
  mkdir -p "$root" "$cache" "$target" "$packaged_root" "$packaged_cache" "$packaged_target"

  "$HOST_MOSS" -D "$root" \
    --cache "$cache" \
    repo add onix-moss-runtime \
    "file://$LOCAL_REPO_DIR/stone.index" \
    -c "ONIX Phase 515 moss runtime" >/dev/null
  "$HOST_MOSS" -D "$root" --cache "$cache" repo update >/dev/null

  if ! "$HOST_MOSS" -D "$root" \
      --cache "$cache" \
      -y install --to "$target" \
      moss >"$install_log" 2>&1; then
    cat "$install_log" >&2
    die "Moss could not install the moss stone"
  fi

  if grep -q 'duplicate entry:' "$install_log"; then
    cat "$install_log" >&2
    die "moss install reported package path ownership collisions"
  fi

  [[ -x "$target/usr/bin/moss" ]] || die "missing installed /usr/bin/moss"
  [[ -f "$target/usr/share/onix/packages/moss.md" ]] || die "missing moss package note"
  "$AUDIT_SCRIPT" "$target" >/dev/null
  "$target/usr/bin/moss" version >/dev/null

  "$target/usr/bin/moss" -D "$packaged_root" \
    --cache "$packaged_cache" \
    repo add onix-self \
    "file://$LOCAL_REPO_DIR/stone.index" \
    -c "ONIX packaged moss self-repo proof" >/dev/null
  "$target/usr/bin/moss" -D "$packaged_root" --cache "$packaged_cache" repo update >/dev/null
  "$target/usr/bin/moss" -D "$packaged_root" --cache "$packaged_cache" info moss uutils-coreutils >"$info_log"
  "$target/usr/bin/moss" -D "$packaged_root" --cache "$packaged_cache" list available >"$list_log"
  grep -q 'moss' "$info_log" || die "packaged moss info output did not mention moss"
  grep -q 'uutils-coreutils' "$info_log" || die "packaged moss info output did not mention uutils-coreutils"

  "$target/usr/bin/moss" -D "$packaged_root" \
    --cache "$packaged_cache" \
    -y install --to "$packaged_target" \
    uutils-coreutils >/dev/null
  [[ -x "$packaged_target/usr/bin/coreutils" ]] \
    || die "packaged moss could not install uutils-coreutils into a scratch target"

  log "proof     : host Moss install + packaged moss self-repo proof OK"
}

run_check() {
  check_source_files
  [[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"

  local stone
  stone="$(local_stone_for moss)"
  if [[ -z "$stone" ]]; then
    log "stone     : moss not built yet"
  else
    "$HOST_MOSS" inspect --check "$stone" >/dev/null
    log "stone     : ${stone#$ONIX_ROOT/}"
    prove_host_install_and_audit
  fi

  log "phase515  : check OK"
}

run_apply() {
  need_cmd awk
  need_cmd cp
  need_cmd gzip
  need_cmd sed
  need_cmd sha256sum
  need_cmd tar

  safe_artifact_path "$STONE_DIR"
  safe_artifact_path "$LOCAL_REPO_DIR"
  safe_artifact_path "$STONE_WORK_DIR"
  safe_artifact_path "$WORK"

  check_source_files
  [[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"

  local existing_moss
  existing_moss="$(local_stone_for moss)"
  if [[ "$FORCE_REBUILD" != "1" && -n "$existing_moss" ]]; then
    log "Phase 515 moss runtime stone already exists"
    run_check
    return
  fi

  mkdir -p "$STONE_DIR" "$LOCAL_REPO_DIR" "$STONE_WORK_DIR"
  rm -rf "$WORK"
  mkdir -p "$WORK"

  log "Phase 515 moss runtime package"
  log "build     : Alpine/musl forge VM"
  log "stone out : ${STONE_DIR#$ONIX_ROOT/}"
  log "local repo: ${LOCAL_REPO_DIR#$ONIX_ROOT/}"

  create_os_tools_archive
  cp "$MOSS_RECIPE_TEMPLATE" "$WORK/moss.stone.yaml.in"
  local source_archive_name
  source_archive_name="$(sed -n "s/^OS_TOOLS_SOURCE_ARCHIVE='\\(.*\\)'/\\1/p" "$WORK/build.env")"
  [[ -n "$source_archive_name" && -f "$WORK/$source_archive_name" ]] \
    || die "missing prepared os-tools source archive"

  log "ensuring moss build dependencies in the forge"
  "$PHASE0_DIR/ssh.sh" root \
    "apk add --no-cache build-base cargo rust clang pkgconf file binutils coreutils findutils bash openssl-dev zlib-dev xz-dev"

  log "copying os-tools source archive + moss recipe into the forge"
  tar -cf - \
    -C "$WORK" build.env \
    -C "$WORK" "$source_archive_name" \
    -C "$WORK" moss.stone.yaml.in \
    | "$PHASE0_DIR/ssh.sh" "$user" \
        "rm -rf '$LAB' && mkdir -p '$LAB/src' && tar -C '$LAB' -xf - && mv '$LAB'/*.tar.gz '$LAB/src/'"

  "$PHASE0_DIR/ssh.sh" "$user" /bin/sh -s <<'REMOTE'
set -eu

export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: missing '$1' in the forge. From the host, run: make phase 004" >&2
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

LAB="$HOME/stone-lab/onix-moss-runtime"
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

check_static_binary() {
    bin="$1"
    file "$bin" | tee "$bin.file"
    grep -Eqi 'statically linked|static-pie linked' "$bin.file" || {
        echo "error: $bin is not static/static-pie" >&2
        exit 1
    }
    if readelf -d "$bin" 2>/dev/null | grep -q '(NEEDED)'; then
        echo "error: $bin has shared-library NEEDED entries" >&2
        readelf -d "$bin" | grep '(NEEDED)' >&2 || true
        exit 1
    fi
    if readelf -l "$bin" 2>/dev/null | grep -q 'Requesting program interpreter'; then
        echo "error: $bin has a dynamic interpreter" >&2
        readelf -l "$bin" | grep 'Requesting program interpreter' >&2 || true
        exit 1
    fi
    if grep -a -F '/nix/store' "$bin" >/dev/null 2>&1; then
        echo "error: $bin contains /nix/store reference" >&2
        exit 1
    fi
}

cut_moss_stone() {
    payload_archive="$1"
    payload_hash="$(sha256sum "$payload_archive" | awk '{print $1}')"
    payload_url="file://$payload_archive"

    sed \
      -e "s|@MOSS_VERSION@|$MOSS_VERSION|g" \
      -e "s|@MOSS_RELEASE@|$MOSS_RELEASE|g" \
      -e "s|@OS_TOOLS_COMMIT@|$OS_TOOLS_COMMIT|g" \
      -e "s|@MOSS_PAYLOAD_URL@|$payload_url|g" \
      -e "s|@MOSS_PAYLOAD_SHA256@|$payload_hash|g" \
      "$LAB/moss.stone.yaml.in" > "$LAB/moss.stone.yaml"

    out="$LAB/moss-out"
    rm -rf "$out"
    mkdir -p "$out"
    (
        cd "$LAB"
        boulder build -y --normal-priority -o "$out" moss.stone.yaml
    )

    stone="$(find "$out" -maxdepth 1 -name 'moss-*.stone' ! -name '*dbginfo*' ! -name '*devel*' | sort | head -n 1)"
    test -f "$stone"
    printf '%s\n' "$stone" > "$LAB/moss.stone.path"
    moss inspect --check "$stone"
}

build_moss() {
    echo "==> build moss"

    src_archive="$LAB/src/$OS_TOOLS_SOURCE_ARCHIVE"
    src_hash="$(sha256sum "$src_archive" | awk '{print $1}')"
    if [ "$src_hash" != "$OS_TOOLS_SOURCE_SHA256" ]; then
        echo "error: os-tools source checksum mismatch" >&2
        exit 1
    fi

    build_src="$LAB/os-tools-source"
    payload_name="moss-payload-$MOSS_VERSION"
    payload_root="$LAB/src/$payload_name"
    payload_archive="$LAB/src/$payload_name.tar.gz"

    rm -rf "$build_src" "$payload_root" "$payload_archive" "$LAB/target-moss"
    mkdir -p "$build_src" "$payload_root"
    tar -xzf "$src_archive" -C "$build_src" --strip-components=1

    (
        cd "$build_src"
        CARGO_TARGET_DIR="$LAB/target-moss" \
          cargo rustc \
            --profile onboarding \
            --locked \
            -p moss \
            --bin moss \
            -j "$jobs" \
            -- \
            -C target-feature=+crt-static
    )

    bin="$LAB/target-moss/onboarding/moss"
    test -x "$bin"
    check_static_binary "$bin"
    "$bin" version >/dev/null

    mkdir -p \
        "$payload_root/usr/bin" \
        "$payload_root/usr/share/onix/packages"

    install -m 00755 "$bin" "$payload_root/usr/bin/moss"

    cat > "$payload_root/usr/share/onix/packages/moss.md" <<EOF_DOC
# moss

ONIX runtime package/state manager.

Source:

\`\`\`text
$OS_TOOLS_REPO
$OS_TOOLS_COMMIT
$OS_TOOLS_SOURCE_SHA256
\`\`\`

Build model:

\`\`\`text
Alpine/musl forge cargo rustc --profile onboarding -p moss --bin moss -- -C target-feature=+crt-static
\`\`\`

Installed command:

\`\`\`text
/usr/bin/moss
\`\`\`

Runtime model:

\`\`\`text
static/static-pie musl
no shared runtime surface
\`\`\`
EOF_DOC

    chmod 0644 "$payload_root/usr/share/onix/packages/moss.md"
    chmod g-s \
        "$payload_root/usr" \
        "$payload_root/usr/bin" \
        "$payload_root/usr/share" \
        "$payload_root/usr/share/onix" \
        "$payload_root/usr/share/onix/packages"

    tar -C "$LAB/src" -czf "$payload_archive" "$payload_name"
    cut_moss_stone "$payload_archive"
}

prove_remote_install() {
    echo "==> index local forge repo and prove packaged moss"
    rm -rf "$REPO" "$ROOT" "$CACHE" "$TARGET"
    mkdir -p "$REPO" "$ROOT" "$CACHE" "$TARGET"
    cp "$(cat "$LAB/moss.stone.path")" "$REPO/"
    moss index "$REPO"
    moss -D "$ROOT" --cache "$CACHE" repo add local "file://$REPO/stone.index" -c "local ONIX moss"
    moss -D "$ROOT" --cache "$CACHE" repo update
    moss -D "$ROOT" --cache "$CACHE" -y install --to "$TARGET" moss

    test -x "$TARGET/usr/bin/moss"
    "$TARGET/usr/bin/moss" version

    echo "==> success"
    echo "moss stone: $(cat "$LAB/moss.stone.path")"
}

build_moss
prove_remote_install
REMOTE

  log "copying built moss stone back to host artifacts"
  rm -f \
    "$STONE_DIR"/moss-*.stone \
    "$STONE_DIR"/moss-dbginfo-*.stone \
    "$STONE_DIR"/moss-devel-*.stone

  local remote_stone host_moss_stone
  remote_stone="$("$PHASE0_DIR/ssh.sh" "$user" "cat '$LAB/moss.stone.path'")"
  "$PHASE0_DIR/ssh.sh" "$user" "cd \"\$(dirname '$remote_stone')\" && tar -cf - \"\$(basename '$remote_stone')\"" \
    | tar -C "$STONE_DIR" -xf -

  host_moss_stone="$(host_stone_for moss)"
  [[ -f "$host_moss_stone" ]] || die "failed to copy moss stone into ${STONE_DIR#$ONIX_ROOT/}"

  log "host moss integrity check"
  "$HOST_MOSS" inspect --check "$host_moss_stone" >/dev/null

  log "refreshing local Phase 5 moss repo"
  rm -f \
    "$LOCAL_REPO_DIR"/moss-*.stone \
    "$LOCAL_REPO_DIR"/moss-dbginfo-*.stone \
    "$LOCAL_REPO_DIR"/moss-devel-*.stone
  cp "$host_moss_stone" "$LOCAL_REPO_DIR/"
  "$HOST_MOSS" index "$LOCAL_REPO_DIR"

  prove_host_install_and_audit

  cat <<EOF_SUCCESS

==> success
moss stone     : ${host_moss_stone#$ONIX_ROOT/}
local repo     : ${LOCAL_REPO_DIR#$ONIX_ROOT/}/stone.index

Phase 515 built/audited moss as an ONIX-owned static Rust/musl runtime package.
EOF_SUCCESS
}

case "$MODE" in
  apply) run_apply ;;
  check) run_check ;;
  *) die "unknown mode: $MODE" ;;
esac
