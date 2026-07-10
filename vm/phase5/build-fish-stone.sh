#!/usr/bin/env bash
# vm/phase5/build-fish-stone.sh — Phase 517.
#
# Build fish as an ONIX-owned Rust/musl interactive shell stone.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHASE0_DIR="$(cd "$SCRIPT_DIR/../phase0" && pwd)"

# shellcheck source=vm/phase0/config.sh
source "$PHASE0_DIR/config.sh"

user="$BUILD_USER"

MODE="apply"
FORCE_REBUILD="${ONIX_PHASE517_REBUILD:-0}"
FISH_RELEASE="${ONIX_FISH_RELEASE:-1}"

STONE_DIR="${ONIX_STONE_DIR:-$ONIX_ROOT/artifacts/onix-stones}"
LOCAL_REPO_DIR="${ONIX_LOCAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-local-repo}"
CHANNEL="${ONIX_REPO_CHANNEL:-unstable}"
ARCH="${ONIX_REPO_ARCH:-x86_64}"
CANONICAL_REPO_ROOT="${ONIX_CANONICAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-repo}"
CANONICAL_IMAGE_REPO_DIR="${ONIX_PHASE517_IMAGE_REPO_DIR:-$CANONICAL_REPO_ROOT/$CHANNEL/$ARCH}"
STONE_WORK_DIR="${ONIX_STONE_WORK_DIR:-$ONIX_ROOT/artifacts/onix-stone-work}"
WORK="${ONIX_PHASE517_WORK_DIR:-$STONE_WORK_DIR/fish-shell}"
PROOF_DIR="$ONIX_ROOT/artifacts/onix-phase5-work/517"
HOST_MOSS="${ONIX_HOST_MOSS:-$ONIX_ROOT/artifacts/host-tools/bin/moss}"
AUDIT_SCRIPT="$ONIX_ROOT/vm/phase5/audit-stone-payload.sh"
FISH_RECIPE_TEMPLATE="${ONIX_FISH_RECIPE_TEMPLATE:-$ONIX_ROOT/packages/core/fish/stone.yaml.in}"

LAB="/home/$user/stone-lab/onix-fish-shell"

usage() {
  cat <<'EOF'
usage: build-fish-stone.sh [--apply|--check|--rebuild]

--apply    build missing fish stone, audit it, and refresh the local ONIX repo
--check    verify package metadata and inspect/audit an existing fish stone
--rebuild  force rebuilding/rechecking the fish stone

Phase 517 builds:
  - fish

Optional environment:
  ONIX_FISH_RELEASE=N
  ONIX_FISH_SRC=/path/to/fish/source
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

realize_fish_source() {
  if [[ -n "${ONIX_FISH_SRC:-}" ]]; then
    printf '%s\n' "$ONIX_FISH_SRC"
    return
  fi

  local rev
  rev="$(extract_locked_nixpkgs_rev)"
  [[ -n "$rev" ]] || die "could not read pinned nixpkgs_2 rev from flake.lock"

  nix build --no-link --print-out-paths "github:NixOS/nixpkgs/${rev}#fish.src" | tail -n 1
}

cargo_package_version() {
  local cargo_toml="$1"
  awk '
    /^\[package\]/ { in_package=1; next }
    in_package && /^\[/ { exit }
    in_package && /^version[[:space:]]*=/ {
      gsub(/"/, "", $3)
      print $3
      exit
    }
  ' "$cargo_toml"
}

create_source_archive() {
  local source_dir="$1"
  local package="$2"
  local version="$3"
  local archive="$WORK/${package}-${version}-source.tar.gz"
  local tar_path="${archive%.gz}"

  [[ -d "$source_dir" ]] || die "source path is not a directory: $source_dir"
  [[ -f "$source_dir/Cargo.toml" ]] || die "source path is missing Cargo.toml: $source_dir"

  rm -f "$archive" "$tar_path"
  tar \
    --mode='u+rwX,go+rX' \
    --exclude='./.git' \
    --exclude='./target' \
    -C "$source_dir" \
    -cf "$tar_path" .
  gzip -n -f "$tar_path"

  printf '%s\n' "$archive"
}

host_stone_for() {
  local package="$1"
  find "$STONE_DIR" -maxdepth 1 -name "$package-[0-9]*.stone" ! -name '*dbginfo*' ! -name '*devel*' | sort | tail -n 1
}

local_stone_for() {
  local package="$1"
  find "$LOCAL_REPO_DIR" -maxdepth 1 -name "$package-[0-9]*.stone" ! -name '*dbginfo*' ! -name '*devel*' | sort | tail -n 1
}

sync_fish_to_canonical_image_repo() {
  local fish_stone="$1"

  [[ -f "$fish_stone" ]] || die "missing fish stone to sync: $fish_stone"
  if [[ ! -d "$CANONICAL_IMAGE_REPO_DIR" ]]; then
    log "canonical : ${CANONICAL_IMAGE_REPO_DIR#$ONIX_ROOT/} absent; skipping fish sync"
    return 0
  fi

  rm -f \
    "$CANONICAL_IMAGE_REPO_DIR"/fish-*.stone \
    "$CANONICAL_IMAGE_REPO_DIR"/fish-dbginfo-*.stone \
    "$CANONICAL_IMAGE_REPO_DIR"/fish-devel-*.stone
  cp "$fish_stone" "$CANONICAL_IMAGE_REPO_DIR/"
  "$HOST_MOSS" index "$CANONICAL_IMAGE_REPO_DIR" >/dev/null
  log "canonical : synced fish into ${CANONICAL_IMAGE_REPO_DIR#$ONIX_ROOT/}"
}

check_source_files() {
  [[ -f "$ONIX_ROOT/packages/STONES.md" ]] || die "missing packages/STONES.md"
  [[ -f "$ONIX_ROOT/packages/core/fish/PACKAGE.md" ]] || die "missing fish PACKAGE.md"
  [[ -f "$FISH_RECIPE_TEMPLATE" ]] || die "missing fish recipe template"
  [[ -f "$SCRIPT_DIR/docs/517_fish_shell_stone.md" ]] \
    || die "missing Phase 517 doc page"
  [[ -x "$AUDIT_SCRIPT" ]] || die "missing payload audit helper: ${AUDIT_SCRIPT#$ONIX_ROOT/}"

  grep -q 'fish' "$ONIX_ROOT/packages/STONES.md"
  grep -q 'Rust' "$ONIX_ROOT/packages/core/fish/PACKAGE.md"
  grep -q 'BusyBox' "$ONIX_ROOT/packages/core/fish/PACKAGE.md"
  grep -q 'static musl' "$ONIX_ROOT/packages/core/fish/PACKAGE.md"
  grep -q 'branding.fish' "$ONIX_ROOT/packages/core/fish/PACKAGE.md"
  grep -q 'Phase 517' "$SCRIPT_DIR/docs/517_fish_shell_stone.md"
  grep -q 'ONIX-branded fish greeting' "$SCRIPT_DIR/docs/517_fish_shell_stone.md"
}

prove_host_install_and_audit() {
  [[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"

  local stone root cache target install_log
  stone="$(local_stone_for fish)"
  if [[ -z "$stone" ]]; then
    log "stone     : fish not built yet"
    return 0
  fi

  rm -rf "$PROOF_DIR"
  mkdir -p "$PROOF_DIR"
  root="$PROOF_DIR/moss-root"
  cache="$PROOF_DIR/moss-cache"
  target="$PROOF_DIR/install-target"
  install_log="$PROOF_DIR/moss-install.log"
  mkdir -p "$root" "$cache" "$target"

  "$HOST_MOSS" -D "$root" \
    --cache "$cache" \
    repo add onix-fish-shell \
    "file://$LOCAL_REPO_DIR/stone.index" \
    -c "ONIX Phase 517 fish shell" >/dev/null
  "$HOST_MOSS" -D "$root" --cache "$cache" repo update >/dev/null

  if ! "$HOST_MOSS" -D "$root" \
      --cache "$cache" \
      -y install --to "$target" \
      fish >"$install_log" 2>&1; then
    cat "$install_log" >&2
    die "Moss could not install the fish stone"
  fi

  if grep -q 'duplicate entry:' "$install_log"; then
    cat "$install_log" >&2
    die "fish install reported package path ownership collisions"
  fi

  [[ -x "$target/usr/bin/fish" ]] || die "missing installed /usr/bin/fish"
  [[ -x "$target/usr/bin/fish_indent" ]] || die "missing installed /usr/bin/fish_indent"
  [[ -x "$target/usr/bin/fish_key_reader" ]] || die "missing installed /usr/bin/fish_key_reader"
  [[ -d "$target/usr/share/fish" ]] || die "missing installed /usr/share/fish"
  [[ -f "$target/usr/share/onix/defaults/etc/fish/conf.d/branding.fish" ]] \
    || die "missing ONIX fish branding config"
  [[ -f "$target/usr/share/onix/packages/fish.md" ]] || die "missing fish package note"
  [[ -f "$target/usr/share/onix/shells/fish-policy.txt" ]] || die "missing fish shell policy note"
  grep -q 'Welcome to ONIX' "$target/usr/share/onix/defaults/etc/fish/conf.d/branding.fish" \
    || die "fish branding config does not contain ONIX greeting"

  "$AUDIT_SCRIPT" "$target" >/dev/null
  HOME="$PROOF_DIR/home" XDG_CONFIG_HOME="$PROOF_DIR/config" \
    "$target/usr/bin/fish" --version >/dev/null
  HOME="$PROOF_DIR/home" XDG_CONFIG_HOME="$PROOF_DIR/config" \
    "$target/usr/bin/fish" -c 'echo ONIX_FISH_OK' | grep -qx 'ONIX_FISH_OK'

  log "proof     : host Moss install + fish runtime-clean audit OK"
}

run_check() {
  check_source_files
  [[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"

  local stone
  stone="$(local_stone_for fish)"
  if [[ -z "$stone" ]]; then
    log "stone     : fish not built yet"
  else
    "$HOST_MOSS" inspect --check "$stone" >/dev/null
    log "stone     : ${stone#$ONIX_ROOT/}"
    prove_host_install_and_audit
  fi

  log "phase517  : check OK"
}

run_apply() {
  need_cmd awk
  need_cmd cp
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

  local existing_fish
  existing_fish="$(local_stone_for fish)"
  if [[ "$FORCE_REBUILD" != "1" && -n "$existing_fish" ]]; then
    log "Phase 517 fish shell stone already exists"
    sync_fish_to_canonical_image_repo "$existing_fish"
    run_check
    return
  fi

  mkdir -p "$STONE_DIR" "$LOCAL_REPO_DIR" "$STONE_WORK_DIR"
  rm -rf "$WORK"
  mkdir -p "$WORK"

  log "Phase 517 fish shell stone"
  log "source    : pinned nixpkgs_2 fish source"
  log "build     : Alpine/musl forge VM"
  log "policy    : fish for interactive users; BusyBox remains sh"
  log "stone out : ${STONE_DIR#$ONIX_ROOT/}"
  log "local repo: ${LOCAL_REPO_DIR#$ONIX_ROOT/}"

  local fish_src fish_version fish_archive fish_sha
  fish_src="$(realize_fish_source)"
  fish_version="$(cargo_package_version "$fish_src/Cargo.toml")"
  [[ -n "$fish_version" ]] || die "could not read fish version"

  fish_archive="$(create_source_archive "$fish_src" fish "$fish_version")"
  fish_sha="$(sha256sum "$fish_archive" | awk '{print $1}')"

  cat > "$WORK/build.env" <<EOF_ENV
FISH_VERSION='$fish_version'
FISH_RELEASE='$FISH_RELEASE'
FISH_SOURCE_ARCHIVE='$(basename "$fish_archive")'
FISH_SOURCE_SHA256='$fish_sha'
EOF_ENV

  cp "$FISH_RECIPE_TEMPLATE" "$WORK/fish.stone.yaml.in"

  cat <<EOF_POLICY
==> source policy
fish version      : $fish_version
fish sha256       : $fish_sha
nix role          : pinned source acquisition only
payload rule      : static musl; no runtime /nix/store
shell policy      : fish interactive, BusyBox sh system scripts
EOF_POLICY

  log "ensuring fish build dependencies in the forge"
  "$PHASE0_DIR/ssh.sh" root \
    "apk add --no-cache build-base cargo rust clang pkgconf file binutils coreutils findutils bash pcre2-dev; if apk search -qe pcre2-static >/dev/null 2>&1; then apk add --no-cache pcre2-static; fi"

  log "copying fish source archive + recipe into the forge"
  tar -cf - \
    -C "$WORK" build.env \
    -C "$WORK" "$(basename "$fish_archive")" \
    -C "$WORK" fish.stone.yaml.in \
    | "$PHASE0_DIR/ssh.sh" "$user" \
        "rm -rf '$LAB' && mkdir -p '$LAB/src' && tar -C '$LAB' -xf - && mv '$LAB/$(basename "$fish_archive")' '$LAB/src/$(basename "$fish_archive")'"

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
need_tool tar
need_tool gzip
need_tool sha256sum
need_tool sed
need_tool grep
need_tool awk
need_tool install
need_tool file
need_tool readelf

LAB="$HOME/stone-lab/onix-fish-shell"
REPO="$LAB/repo"
ROOT="$LAB/moss-root"
CACHE="$LAB/moss-cache"
TARGET="$LAB/install-target"
CARGO_HOME="$HOME/.cargo-onix"
export CARGO_HOME
mkdir -p "$CARGO_HOME"

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

cut_fish_stone() {
    payload_archive="$1"
    payload_hash="$(sha256sum "$payload_archive" | awk '{print $1}')"
    payload_url="file://$payload_archive"

    sed \
      -e "s|@FISH_VERSION@|$FISH_VERSION|g" \
      -e "s|@FISH_RELEASE@|$FISH_RELEASE|g" \
      -e "s|@FISH_PAYLOAD_URL@|$payload_url|g" \
      -e "s|@FISH_PAYLOAD_SHA256@|$payload_hash|g" \
      -e "s|@FISH_SOURCE_SHA256@|$FISH_SOURCE_SHA256|g" \
      "$LAB/fish.stone.yaml.in" > "$LAB/fish.stone.yaml"

    out="$LAB/fish-out"
    rm -rf "$out"
    mkdir -p "$out"
    (
        cd "$LAB"
        boulder build -y --normal-priority -o "$out" fish.stone.yaml
    )

    stone="$(find "$out" -maxdepth 1 -name 'fish-*.stone' ! -name '*dbginfo*' ! -name '*devel*' | sort | head -n 1)"
    test -f "$stone"
    printf '%s\n' "$stone" > "$LAB/fish.stone.path"
    moss inspect --check "$stone"
}

build_fish() {
    echo "==> build fish"

    src_archive="$LAB/src/$FISH_SOURCE_ARCHIVE"
    src_hash="$(sha256sum "$src_archive" | awk '{print $1}')"
    if [ "$src_hash" != "$FISH_SOURCE_SHA256" ]; then
        echo "error: fish source checksum mismatch" >&2
        exit 1
    fi

    build_src="$LAB/fish-source"
    payload_name="fish-payload-$FISH_VERSION"
    payload_root="$LAB/src/$payload_name"
    payload_archive="$LAB/src/$payload_name.tar.gz"
    out_extract="$LAB/fish-extracted"

    rm -rf "$build_src" "$payload_root" "$payload_archive" "$LAB/target-fish" "$out_extract"
    mkdir -p "$build_src" "$payload_root"
    tar -xzf "$src_archive" -C "$build_src"

    for bin in fish fish_indent fish_key_reader; do
        (
            cd "$build_src"
            PREFIX=/usr \
            DATADIR=/usr/share \
            PCRE2_SYS_STATIC=1 \
            PKG_CONFIG_ALL_STATIC=1 \
            CARGO_TARGET_DIR="$LAB/target-fish" \
              cargo rustc \
                --release \
                --locked \
                --bin "$bin" \
                --no-default-features \
                --features embed-manpages \
                -j "$jobs" \
                -- \
                -C target-feature=+crt-static
        )
    done

    mkdir -p "$payload_root/usr/bin"
    for bin in fish fish_indent fish_key_reader; do
        install -m 00755 "$LAB/target-fish/release/$bin" "$payload_root/usr/bin/$bin"
    done

    for bin in fish fish_indent fish_key_reader; do
        test -x "$payload_root/usr/bin/$bin"
        check_static_binary "$payload_root/usr/bin/$bin"
    done

    mkdir -p "$payload_root/usr/share/fish"
    cp -a "$build_src/share/." "$payload_root/usr/share/fish/"
    mkdir -p "$payload_root/usr/share/onix/defaults/etc/fish/conf.d"

    cat > "$payload_root/usr/share/onix/defaults/etc/fish/conf.d/branding.fish" <<'EOF_FISH_BRANDING'
# ONIX fish login branding.
#
# fish does not read POSIX /etc/profile.d scripts, so ONIX ships a native fish
# greeting here. The full logo is owned by the branding stone when present; this
# fish package provides the shell hook and a small fallback.
#
# fish autoloads its built-in fish_greeting function. That function respects a
# global fish_greeting variable, so set the variable instead of trying to replace
# the function from vendor_conf.d.
function __onix_configure_fish_greeting --description 'Configure ONIX fish greeting'
    if set -q ONIX_LOGIN_BANNER
        if test "$ONIX_LOGIN_BANNER" = 0
            set -g fish_greeting
            return 0
        end
    end

    if set -q ONIX_LOGIN_BANNER_SHOWN
        set -g fish_greeting
        return 0
    end

    if set -q TERM
        if test "$TERM" = dumb
            set -g fish_greeting
            return 0
        end
    end

    set -gx ONIX_LOGIN_BANNER_SHOWN 1

    if test -r /usr/share/onix/branding/logo.ansi
        set -g fish_greeting (begin
            command cat /usr/share/onix/branding/logo.ansi
            echo
            printf '\033[1mWelcome to ONIX.\033[0m\n'
            echo 'moss controls the machine. nix controls the toolbox.'
        end | string collect)
    else
        set -g fish_greeting (begin
            printf '\033[38;2;231;89;15mON\033[38;2;79;110;145mIX\033[0m\n'
            printf '\033[1mWelcome to ONIX.\033[0m\n'
            echo 'moss controls the machine. nix controls the toolbox.'
        end | string collect)
    end

    return 0
end

__onix_configure_fish_greeting
functions -e __onix_configure_fish_greeting
EOF_FISH_BRANDING

    mkdir -p \
        "$payload_root/usr/share/onix/packages" \
        "$payload_root/usr/share/onix/shells"

    cat > "$payload_root/usr/share/onix/packages/fish.md" <<EOF_DOC
# fish

ONIX interactive user shell.

Source archive:

\`\`\`text
$FISH_SOURCE_ARCHIVE
\`\`\`

Source SHA-256:

\`\`\`text
$FISH_SOURCE_SHA256
\`\`\`

Build model:

\`\`\`text
Alpine/musl forge per-binary cargo rustc --release --locked --bin NAME --no-default-features --features embed-manpages -- -C target-feature=+crt-static
PCRE2_SYS_STATIC=1
\`\`\`

Installed commands:

\`\`\`text
/usr/bin/fish
/usr/bin/fish_indent
/usr/bin/fish_key_reader
/usr/share/onix/defaults/etc/fish/conf.d/branding.fish
\`\`\`

Runtime model:

\`\`\`text
static/static-pie musl
BusyBox remains /bin/sh and /usr/bin/sh
Interactive fish sessions show the ONIX login banner when branding assets exist
\`\`\`
EOF_DOC

    cat > "$payload_root/usr/share/onix/shells/fish-policy.txt" <<'EOF_POLICY'
ONIX fish shell policy

- /usr/bin/fish is the normal user's interactive login shell.
- fish is not /bin/sh.
- /bin/sh and /usr/bin/sh remain BusyBox for system scripts and recovery.
- System scripts should keep using #!/bin/sh or an explicit BusyBox sh command.
EOF_POLICY

    chmod 0755 \
        "$payload_root/usr/bin/fish" \
        "$payload_root/usr/bin/fish_indent" \
        "$payload_root/usr/bin/fish_key_reader"
    chmod 0644 \
        "$payload_root/usr/share/onix/defaults/etc/fish/conf.d/branding.fish" \
        "$payload_root/usr/share/onix/packages/fish.md" \
        "$payload_root/usr/share/onix/shells/fish-policy.txt"
    find "$payload_root/usr/share/fish" -type d -exec chmod 0755 {} +
    find "$payload_root/usr/share/fish" -type f -exec chmod 0644 {} +
    find "$payload_root/usr/share/fish" -type d -exec chmod g-s {} +
    chmod g-s \
        "$payload_root/usr" \
        "$payload_root/usr/bin" \
        "$payload_root/usr/share" \
        "$payload_root/usr/share/fish" \
        "$payload_root/usr/share/onix" \
        "$payload_root/usr/share/onix/defaults" \
        "$payload_root/usr/share/onix/defaults/etc" \
        "$payload_root/usr/share/onix/defaults/etc/fish" \
        "$payload_root/usr/share/onix/defaults/etc/fish/conf.d" \
        "$payload_root/usr/share/onix/packages" \
        "$payload_root/usr/share/onix/shells"

    HOME="$LAB/fish-home" XDG_CONFIG_HOME="$LAB/fish-config" \
        "$payload_root/usr/bin/fish" --version
    HOME="$LAB/fish-home" XDG_CONFIG_HOME="$LAB/fish-config" \
        "$payload_root/usr/bin/fish" -c 'echo ONIX_FISH_OK' | grep -qx 'ONIX_FISH_OK'

    tar -C "$LAB/src" -czf "$payload_archive" "$payload_name"
    cut_fish_stone "$payload_archive"

    rm -rf "$out_extract"
    mkdir -p "$out_extract"
    moss extract -o "$out_extract" "$(cat "$LAB/fish.stone.path")"
    set -- "$out_extract"/*
    extracted="$1"
    test -x "$extracted/usr/bin/fish"
    test -d "$extracted/usr/share/fish"
    test -f "$extracted/usr/share/onix/defaults/etc/fish/conf.d/branding.fish"
    grep -q 'Welcome to ONIX' "$extracted/usr/share/onix/defaults/etc/fish/conf.d/branding.fish"
    check_static_binary "$extracted/usr/bin/fish"
}

prove_remote_install() {
    echo "==> index local forge repo and prove packaged fish"
    rm -rf "$REPO" "$ROOT" "$CACHE" "$TARGET"
    mkdir -p "$REPO" "$ROOT" "$CACHE" "$TARGET"
    cp "$(cat "$LAB/fish.stone.path")" "$REPO/"
    moss index "$REPO"
    moss -D "$ROOT" --cache "$CACHE" repo add local "file://$REPO/stone.index" -c "local ONIX fish"
    moss -D "$ROOT" --cache "$CACHE" repo update
    moss -D "$ROOT" --cache "$CACHE" -y install --to "$TARGET" fish

    test -x "$TARGET/usr/bin/fish"
    test -f "$TARGET/usr/share/onix/defaults/etc/fish/conf.d/branding.fish"
    test -f "$TARGET/usr/share/onix/packages/fish.md"
    test -f "$TARGET/usr/share/onix/shells/fish-policy.txt"
    HOME="$LAB/proof-home" XDG_CONFIG_HOME="$LAB/proof-config" \
        "$TARGET/usr/bin/fish" --version
    HOME="$LAB/proof-home" XDG_CONFIG_HOME="$LAB/proof-config" \
        "$TARGET/usr/bin/fish" -c 'echo ONIX_FISH_PACKAGE_OK' | grep -qx 'ONIX_FISH_PACKAGE_OK'

    echo "==> success"
    echo "fish stone: $(cat "$LAB/fish.stone.path")"
}

build_fish
prove_remote_install
REMOTE

  log "copying built fish stone back to host artifacts"
  rm -f \
    "$STONE_DIR"/fish-*.stone \
    "$STONE_DIR"/fish-dbginfo-*.stone \
    "$STONE_DIR"/fish-devel-*.stone

  local remote_stone host_fish_stone
  remote_stone="$("$PHASE0_DIR/ssh.sh" "$user" "cat '$LAB/fish.stone.path'")"
  "$PHASE0_DIR/ssh.sh" "$user" "cd \"\$(dirname '$remote_stone')\" && tar -cf - \"\$(basename '$remote_stone')\"" \
    | tar -C "$STONE_DIR" -xf -

  host_fish_stone="$(host_stone_for fish)"
  [[ -f "$host_fish_stone" ]] || die "failed to copy fish stone into ${STONE_DIR#$ONIX_ROOT/}"

  log "host moss integrity check"
  "$HOST_MOSS" inspect --check "$host_fish_stone" >/dev/null

  log "refreshing local Phase 5 fish repo"
  rm -f \
    "$LOCAL_REPO_DIR"/fish-*.stone \
    "$LOCAL_REPO_DIR"/fish-dbginfo-*.stone \
    "$LOCAL_REPO_DIR"/fish-devel-*.stone
  cp "$host_fish_stone" "$LOCAL_REPO_DIR/"
  "$HOST_MOSS" index "$LOCAL_REPO_DIR"
  sync_fish_to_canonical_image_repo "$host_fish_stone"

  prove_host_install_and_audit

  cat <<EOF_SUCCESS

==> success
fish stone     : ${host_fish_stone#$ONIX_ROOT/}
local repo     : ${LOCAL_REPO_DIR#$ONIX_ROOT/}/stone.index

Phase 517 built/audited fish as an ONIX-owned Rust/musl interactive shell
package. BusyBox still owns the system sh contract.
EOF_SUCCESS
}

case "$MODE" in
  apply) run_apply ;;
  check) run_check ;;
  *) die "unknown mode: $MODE" ;;
esac
