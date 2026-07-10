#!/usr/bin/env bash
# vm/phase5/build-rust-essential-stones.sh — Phase 509 Rust essential stones.
#
# Phase 509 accepts the first built Rust essential stone:
#
#   - uutils-coreutils
#
# It also records the selected sudo-class direction:
#
#   - rootasrole
#
# RootAsRole is selected here. Phase 510 builds the small shared-library surface
# RootAsRole needs: linux-pam and libseccomp.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHASE0_DIR="$(cd "$SCRIPT_DIR/../phase0" && pwd)"

# shellcheck source=vm/phase0/config.sh
source "$PHASE0_DIR/config.sh"

user="$BUILD_USER"

MODE="apply"
FORCE_REBUILD="${ONIX_PHASE509_REBUILD:-0}"
UUTILS_LINK_COMMANDS="${ONIX_UUTILS_LINK_COMMANDS:-0}"
UUTILS_RELEASE="${ONIX_UUTILS_RELEASE:-1}"

STONE_DIR="${ONIX_STONE_DIR:-$ONIX_ROOT/artifacts/onix-stones}"
LOCAL_REPO_DIR="${ONIX_LOCAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-local-repo}"
STONE_WORK_DIR="${ONIX_STONE_WORK_DIR:-$ONIX_ROOT/artifacts/onix-stone-work}"
WORK="${ONIX_PHASE509_WORK_DIR:-$STONE_WORK_DIR/rust-essentials}"
HOST_MOSS="${ONIX_HOST_MOSS:-$ONIX_ROOT/artifacts/host-tools/bin/moss}"
AUDIT_SCRIPT="$SCRIPT_DIR/audit-stone-payload.sh"
PHASE509_PROOF_DIR="$ONIX_ROOT/artifacts/onix-phase5-work/509"
ROOTASROLE_GATE="$PHASE509_PROOF_DIR/rootasrole.gate.md"

UUTILS_RECIPE_TEMPLATE="${ONIX_UUTILS_RECIPE_TEMPLATE:-$ONIX_ROOT/packages/core/uutils-coreutils/stone.yaml.in}"
ROOTASROLE_RECIPE_TEMPLATE="${ONIX_ROOTASROLE_RECIPE_TEMPLATE:-$ONIX_ROOT/packages/core/rootasrole/stone.yaml.in}"

LAB="/home/$user/stone-lab/onix-rust-essentials"

usage() {
  cat <<'EOF'
usage: build-rust-essential-stones.sh [--apply|--check|--rebuild]

--apply    build missing Phase 509 Rust essential stones, audit them, and refresh
           the local Phase 4/5 repo
--check    verify source files and, when present, inspect/audit existing stones
--rebuild  force rebuilding/rechecking the Phase 509 Rust essential lane

Phase 509:
  - builds/audits uutils-coreutils as the first accepted Rust essential stone
  - records rootasrole as ONIX's selected sudo-class direction
  - Phase 510 builds the ONIX-owned linux-pam/libseccomp surface it needs

Optional environment:
  ONIX_UUTILS_LINK_COMMANDS=1  also install command-name symlinks
  ONIX_UUTILS_RELEASE=N        set the uutils stone release number
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

  nix build --no-link --print-out-paths "github:NixOS/nixpkgs/${rev}#${attr}.src" | tail -n 1
}

toml_workspace_version() {
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
  find "$STONE_DIR" -maxdepth 1 -name "$package-[0-9]*.stone" ! -name '*dbginfo*' | sort | tail -n 1
}

local_stone_for() {
  local package="$1"
  find "$LOCAL_REPO_DIR" -maxdepth 1 -name "$package-[0-9]*.stone" ! -name '*dbginfo*' | sort | tail -n 1
}

copy_template_to_work() {
  local template="$1"
  local target="$2"
  [[ -f "$template" ]] || die "missing recipe template: ${template#$ONIX_ROOT/}"
  cp "$template" "$WORK/$target"
}

check_source_files() {
  [[ -f "$ONIX_ROOT/packages/STONES.md" ]] || die "missing packages/STONES.md"
  [[ -f "$ONIX_ROOT/packages/core/uutils-coreutils/PACKAGE.md" ]] || die "missing uutils-coreutils PACKAGE.md"
  [[ -f "$ONIX_ROOT/packages/core/rootasrole/PACKAGE.md" ]] || die "missing rootasrole PACKAGE.md"
  [[ -f "$UUTILS_RECIPE_TEMPLATE" ]] || die "missing uutils-coreutils recipe template"
  [[ -f "$ROOTASROLE_RECIPE_TEMPLATE" ]] || die "missing rootasrole recipe template"

  grep -q 'uutils-coreutils' "$ONIX_ROOT/packages/STONES.md"
  grep -q 'rootasrole' "$ONIX_ROOT/packages/STONES.md"
  grep -q 'Rust implementation' "$ONIX_ROOT/packages/core/uutils-coreutils/PACKAGE.md"
  grep -q 'RootAsRole' "$ONIX_ROOT/packages/core/rootasrole/PACKAGE.md"
  grep -q 'minimal shared-library surface' "$ONIX_ROOT/packages/core/rootasrole/PACKAGE.md"
}

phase509_packages_for_proof() {
  local packages=(uutils-coreutils)
  if [[ -n "$(local_stone_for rootasrole)" ]]; then
    packages+=(rootasrole)
  fi
  printf '%s\n' "${packages[@]}"
}

preserve_rootasrole_gate() {
  local gate_tmp=""

  if [[ -f "$ROOTASROLE_GATE" ]]; then
    gate_tmp="$(mktemp "${TMPDIR:-/tmp}/onix-rootasrole-gate.XXXXXX")"
    cp "$ROOTASROLE_GATE" "$gate_tmp"
  fi

  rm -rf "$PHASE509_PROOF_DIR"
  mkdir -p "$PHASE509_PROOF_DIR"

  if [[ -n "$gate_tmp" ]]; then
    cp "$gate_tmp" "$ROOTASROLE_GATE"
    rm -f "$gate_tmp"
  fi
}

write_host_rootasrole_gate() {
  mkdir -p "$PHASE509_PROOF_DIR"
  cat > "$ROOTASROLE_GATE" <<'EOF_GATE'
# rootasrole Phase 509 gate

RootAsRole is ONIX's selected sudo-class privilege delegation path.

Phase 509 does not accept a finished RootAsRole stone yet. It records the
selected package direction. Phase 510 builds the minimal shared-library surface
RootAsRole needs:

```text
linux-pam
libseccomp
musl
toolchain runtime, only if libgcc_s is still needed
```

The rule is static/static-PIE first by default, with a minimal ONIX-owned shared
surface only when static is not the right model.
EOF_GATE
}

prove_host_install_and_audit() {
  need_cmd stat
  [[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"
  [[ -x "$AUDIT_SCRIPT" ]] || die "missing payload audit helper: ${AUDIT_SCRIPT#$ONIX_ROOT/}"

  local proof="$PHASE509_PROOF_DIR"
  local root="$proof/moss-root"
  local cache="$proof/moss-cache"
  local target="$proof/install-target"
  local install_log="$proof/moss-install.log"
  local packages=()
  local package
  local has_rootasrole=0

  preserve_rootasrole_gate
  mkdir -p "$root" "$cache" "$target"

  while IFS= read -r package; do
    packages+=("$package")
    [[ "$package" = "rootasrole" ]] && has_rootasrole=1
  done < <(phase509_packages_for_proof)

  "$HOST_MOSS" -D "$root" \
    --cache "$cache" \
    repo add onix-rust-essentials \
    "file://$LOCAL_REPO_DIR/stone.index" \
    -c "ONIX Phase 509 Rust essentials" >/dev/null

  "$HOST_MOSS" -D "$root" --cache "$cache" repo update >/dev/null

  if ! "$HOST_MOSS" -D "$root" \
      --cache "$cache" \
      -y install --to "$target" \
      "${packages[@]}" >"$install_log" 2>&1; then
    cat "$install_log" >&2
    die "Moss could not install Phase 509 Rust essential stones"
  fi

  if grep -q 'duplicate entry:' "$install_log"; then
    cat "$install_log" >&2
    die "Phase 509 Rust essential stones reported package path ownership collisions"
  fi

  [[ -x "$target/usr/bin/coreutils" ]] || die "missing installed /usr/bin/coreutils"
  if [[ "$has_rootasrole" -eq 1 ]]; then
    [[ -x "$target/usr/bin/dosr" ]] || die "missing installed /usr/bin/dosr"
    [[ -x "$target/usr/bin/chsr" ]] || die "missing installed /usr/bin/chsr"
    [[ -f "$target/usr/share/onix/packages/rootasrole.md" ]] \
      || die "missing packaged rootasrole metadata"
    "$AUDIT_SCRIPT" --allow-dynamic-musl "$target" >/dev/null
  else
    [[ -f "$ROOTASROLE_GATE" ]] || write_host_rootasrole_gate
    log "rootasrole: selected; build package after Phase 510 shared-surface stones"
    "$AUDIT_SCRIPT" "$target" >/dev/null
  fi

  log "proof     : host Moss install + runtime-clean audit OK"
}

run_check() {
  check_source_files

  [[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"

  local missing_uutils=0
  local package stone
  for package in uutils-coreutils rootasrole; do
    stone="$(local_stone_for "$package")"
    if [[ -z "$stone" ]]; then
      if [[ "$package" = "rootasrole" && -f "$ROOTASROLE_GATE" ]]; then
        log "rootasrole: selected; dependency-surface note at ${ROOTASROLE_GATE#$ONIX_ROOT/}"
      else
        log "stone     : $package not built yet"
        [[ "$package" = "uutils-coreutils" ]] && missing_uutils=1
      fi
      continue
    fi
    "$HOST_MOSS" inspect --check "$stone" >/dev/null
    log "stone     : ${stone#$ONIX_ROOT/}"
  done

  if [[ "$missing_uutils" -eq 0 && -n "$(local_stone_for uutils-coreutils)" ]]; then
    prove_host_install_and_audit
  fi

  log "phase509  : check OK"
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

  local existing_uutils existing_rootasrole
  existing_uutils="$(local_stone_for uutils-coreutils)"
  existing_rootasrole="$(local_stone_for rootasrole)"

  if [[ "$FORCE_REBUILD" != "1" && -n "$existing_uutils" && ( -n "$existing_rootasrole" || -f "$ROOTASROLE_GATE" ) ]]; then
    log "Phase 509 Rust essential lane already exists"
    run_check
    return
  fi

  mkdir -p "$STONE_DIR" "$LOCAL_REPO_DIR" "$STONE_WORK_DIR"
  rm -rf "$WORK"
  mkdir -p "$WORK"

  log "Phase 509 Rust essential stones"
  log "source    : pinned nixpkgs_2 source trees for built packages"
  log "build     : Alpine/musl forge VM"
  log "policy    : static first; minimal ONIX-owned shared surface by exception"
  log "stone out : ${STONE_DIR#$ONIX_ROOT/}"
  log "local repo: ${LOCAL_REPO_DIR#$ONIX_ROOT/}"

  local uutils_src uutils_version
  uutils_src="$(realize_source uutils-coreutils "${ONIX_UUTILS_SRC:-}")"
  uutils_version="$(toml_workspace_version "$uutils_src/Cargo.toml")"
  [[ -n "$uutils_version" ]] || die "could not read uutils version"

  local uutils_archive uutils_sha
  uutils_archive="$(create_source_archive "$uutils_src" uutils-coreutils "$uutils_version")"
  uutils_sha="$(sha256sum "$uutils_archive" | awk '{print $1}')"

  cat > "$WORK/build.env" <<EOF_ENV
UUTILS_VERSION='$uutils_version'
UUTILS_SOURCE_ARCHIVE='$(basename "$uutils_archive")'
UUTILS_SOURCE_SHA256='$uutils_sha'
UUTILS_LINK_COMMANDS='$UUTILS_LINK_COMMANDS'
UUTILS_RELEASE='$UUTILS_RELEASE'
EOF_ENV

  copy_template_to_work "$UUTILS_RECIPE_TEMPLATE" "uutils-coreutils.stone.yaml.in"

  cat <<EOF_POLICY
==> source policy
uutils version     : $uutils_version
uutils sha256      : $uutils_sha
rootasrole status  : selected; linux-pam + libseccomp are built by Phase 510
nix role           : pinned source acquisition only
payload rule       : static first; shared libraries only when ONIX-owned and documented
uutils links       : $UUTILS_LINK_COMMANDS
uutils release     : $UUTILS_RELEASE
EOF_POLICY

  log "copying source archive + recipe template into the forge"
  tar -cf - \
    -C "$WORK" build.env \
    -C "$WORK" "$(basename "$uutils_archive")" \
    -C "$WORK" uutils-coreutils.stone.yaml.in \
    | "$PHASE0_DIR/ssh.sh" "$user" "rm -rf '$LAB' && mkdir -p '$LAB/src' && tar -C '$LAB' -xf - && mv '$LAB/$(basename "$uutils_archive")' '$LAB/src/$(basename "$uutils_archive")'"

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

LAB="$HOME/stone-lab/onix-rust-essentials"
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
    grep -Eqi 'statically linked|static-pie linked' "$bin.file"
    if readelf -d "$bin" 2>/dev/null | grep -q '(NEEDED)'; then
        echo "error: $bin has shared-library NEEDED entries" >&2
        readelf -d "$bin" | grep '(NEEDED)' >&2 || true
        exit 1
    fi
    if grep -a -F '/nix/store' "$bin" >/dev/null 2>&1; then
        echo "error: $bin contains /nix/store reference" >&2
        exit 1
    fi
}

build_uutils() {
    echo "==> build uutils-coreutils"

    src_archive="$LAB/src/$UUTILS_SOURCE_ARCHIVE"
    src_hash="$(sha256sum "$src_archive" | awk '{print $1}')"
    if [ "$src_hash" != "$UUTILS_SOURCE_SHA256" ]; then
        echo "error: uutils source checksum mismatch" >&2
        exit 1
    fi

    build_src="$LAB/uutils-source"
    payload_name="uutils-coreutils-payload-$UUTILS_VERSION"
    payload_root="$LAB/src/$payload_name"
    payload_archive="$LAB/src/$payload_name.tar.gz"
    out="$LAB/uutils-out"
    extract="$LAB/uutils-extracted"

    rm -rf "$build_src" "$payload_root" "$payload_archive" "$out" "$extract" "$LAB/target-uutils"
    mkdir -p "$build_src" "$payload_root"
    tar -xzf "$src_archive" -C "$build_src"

    (
        cd "$build_src"
        CARGO_TARGET_DIR="$LAB/target-uutils" \
          cargo rustc \
            --release \
            --locked \
            --no-default-features \
            --features feat_Tier1 \
            --bin coreutils \
            -j "$jobs" \
            -- \
            -C target-feature=+crt-static
    )

    bin="$LAB/target-uutils/release/coreutils"
    test -x "$bin"
    check_static_binary "$bin"
    "$bin" --help >/dev/null

    mkdir -p \
        "$payload_root/usr/bin" \
        "$payload_root/usr/share/onix/packages"

    install -m 00755 "$bin" "$payload_root/usr/bin/coreutils"

    "$bin" --list | sed '/^$/d' > "$payload_root/usr/share/onix/packages/uutils-coreutils.commands"

    if [ ! -s "$payload_root/usr/share/onix/packages/uutils-coreutils.commands" ]; then
        echo "error: uutils coreutils --list produced no command names" >&2
        exit 1
    fi
    if grep -Eq '/|[[:space:]]' "$payload_root/usr/share/onix/packages/uutils-coreutils.commands"; then
        echo "error: uutils command list contains unsafe command names" >&2
        cat "$payload_root/usr/share/onix/packages/uutils-coreutils.commands" >&2
        exit 1
    fi
    grep -Fx '[' "$payload_root/usr/share/onix/packages/uutils-coreutils.commands" >/dev/null \
        || { echo "error: uutils command list is missing [" >&2; exit 1; }
    grep -Fx 'ls' "$payload_root/usr/share/onix/packages/uutils-coreutils.commands" >/dev/null \
        || { echo "error: uutils command list is missing ls" >&2; exit 1; }
    grep -Fx 'cp' "$payload_root/usr/share/onix/packages/uutils-coreutils.commands" >/dev/null \
        || { echo "error: uutils command list is missing cp" >&2; exit 1; }

    if [ "${UUTILS_LINK_COMMANDS:-0}" = "1" ]; then
        while IFS= read -r command_name; do
            [ -n "$command_name" ] || continue
            ln -sf coreutils "$payload_root/usr/bin/$command_name"
        done < "$payload_root/usr/share/onix/packages/uutils-coreutils.commands"

        cat > "$payload_root/usr/share/onix/packages/uutils-coreutils.pending-links" <<'EOF_PENDING'
Phase 513 installs every uutils command-name link reported by
`/usr/bin/coreutils --list`.

This file remains as a migration note for older Phase 509 documentation. The
The current package owns the command names listed in
uutils-coreutils.commands, including special applets such as `[`.
EOF_PENDING
    else
        cat > "$payload_root/usr/share/onix/packages/uutils-coreutils.pending-links" <<'EOF_PENDING'
Phase 509 installs only /usr/bin/coreutils.

The command-name links are intentionally deferred because busybox currently
owns the bootstrap command paths under /usr/bin.
EOF_PENDING
    fi

    cat > "$payload_root/usr/share/onix/packages/uutils-coreutils.md" <<EOF_DOC
# uutils-coreutils

Rust-first coreutils payload for ONIX.

Source archive:

\`\`\`text
$UUTILS_SOURCE_ARCHIVE
\`\`\`

Source SHA-256:

\`\`\`text
$UUTILS_SOURCE_SHA256
\`\`\`

Build model:

\`\`\`text
Alpine/musl forge cargo build --release --locked --no-default-features --features feat_Tier1 --bin coreutils
\`\`\`

Installed binary:

\`\`\`text
/usr/bin/coreutils
\`\`\`

Command-name link mode:

\`\`\`text
UUTILS_LINK_COMMANDS=${UUTILS_LINK_COMMANDS:-0}
\`\`\`

When this value is 1, the package also owns every command name reported by:

\`\`\`text
/usr/bin/coreutils --list
\`\`\`

Examples:

\`\`\`text
/usr/bin/[ -> coreutils
/usr/bin/ls -> coreutils
/usr/bin/cp -> coreutils
/usr/bin/mv -> coreutils
\`\`\`
EOF_DOC

    chmod 00755 "$payload_root/usr/bin/coreutils"
    chmod 0644 \
        "$payload_root/usr/share/onix/packages/uutils-coreutils.commands" \
        "$payload_root/usr/share/onix/packages/uutils-coreutils.pending-links" \
        "$payload_root/usr/share/onix/packages/uutils-coreutils.md"
    chmod g-s \
        "$payload_root/usr" \
        "$payload_root/usr/bin" \
        "$payload_root/usr/share" \
        "$payload_root/usr/share/onix" \
        "$payload_root/usr/share/onix/packages"

    tar -C "$LAB/src" -czf "$payload_archive" "$payload_name"
    payload_hash="$(sha256sum "$payload_archive" | awk '{print $1}')"
    payload_url="file://$payload_archive"

    sed \
      -e "s|@UUTILS_VERSION@|$UUTILS_VERSION|g" \
      -e "s|@UUTILS_RELEASE@|${UUTILS_RELEASE:-1}|g" \
      -e "s|@UUTILS_PAYLOAD_URL@|$payload_url|g" \
      -e "s|@UUTILS_PAYLOAD_SHA256@|$payload_hash|g" \
      -e "s|@UUTILS_SOURCE_ARCHIVE@|$UUTILS_SOURCE_ARCHIVE|g" \
      -e "s|@UUTILS_SOURCE_SHA256@|$UUTILS_SOURCE_SHA256|g" \
      "$LAB/uutils-coreutils.stone.yaml.in" > "$LAB/uutils-coreutils.stone.yaml"

    mkdir -p "$out"
    (
        cd "$LAB"
        boulder build -y --normal-priority -o "$out" uutils-coreutils.stone.yaml
    )

    stone="$(find "$out" -maxdepth 1 -name 'uutils-coreutils-*.stone' ! -name '*dbginfo*' | sort | head -n 1)"
    test -f "$stone"
    printf '%s\n' "$stone" > "$LAB/uutils-coreutils.stone.path"

    moss inspect --check "$stone"
    rm -rf "$extract"
    mkdir -p "$extract"
    moss extract -o "$extract" "$stone"
    set -- "$extract"/*
    payload="$1"
    test -x "$payload/usr/bin/coreutils"
    check_static_binary "$payload/usr/bin/coreutils"
    if [ "${UUTILS_LINK_COMMANDS:-0}" = "1" ]; then
        while IFS= read -r command_name; do
            [ -n "$command_name" ] || continue
            test -L "$payload/usr/bin/$command_name"
            test "$(readlink "$payload/usr/bin/$command_name")" = "coreutils"
        done < "$payload/usr/share/onix/packages/uutils-coreutils.commands"
        test -L "$payload/usr/bin/ls"
        test "$(readlink "$payload/usr/bin/ls")" = "coreutils"
        "$payload/usr/bin/ls" --version >/dev/null
        "$payload/usr/bin/[" 1 = 1 ]
        "$payload/usr/bin/true"
    elif [ -e "$payload/usr/bin/ls" ]; then
        echo "error: uutils-coreutils must not own /usr/bin/ls in Phase 509" >&2
        exit 1
    fi
}

record_rootasrole_gate() {
    cat > "$LAB/rootasrole.gate.md" <<'EOF_GATE'
# rootasrole Phase 509 gate

RootAsRole is ONIX's selected sudo-class privilege delegation path.

The user-facing command is `dosr`. In ONIX language, `dosr` is the command that
fills the "run this task with controlled privilege" role. A future compatibility
command named `sudo` may point into this model, but the canonical privilege
implementation is RootAsRole.

## Why it is not built in Phase 509

RootAsRole was investigated as a Rust privilege package. The static-first probe
found that its useful binaries are not currently pure static musl outputs:

```text
dosr -> needs PAM at runtime
chsr -> needs libseccomp at runtime
```

ONIX no longer says "shared libraries are impossible." The current rule is:

```text
try static/static-PIE first by default
allow the smallest ONIX-owned shared-library surface when static is not the
right model
```

That means RootAsRole can be accepted as a dynamic-musl exception after ONIX
owns and audits the required shared-library stones:

```text
linux-pam
libseccomp
musl
toolchain runtime, if libgcc_s is still needed
```

## Decision

Do not package RootAsRole as a host-leaking or half-owned binary.

Keep RootAsRole selected. Build the dependency surface as ONIX stones first, then
build RootAsRole against that surface.

## What unblocks it

1. Phase 510 adds ONIX stones for `linux-pam` and `libseccomp`.
2. Phase 511 builds RootAsRole in the forge against those ONIX-owned libraries.
3. Audit the payload with dynamic musl allowed only for the documented sonames.
4. Install `/usr/bin/dosr`, `/usr/bin/chsr`, defaults under `/usr/share/defaults`,
   and `/usr/share/onix/packages/rootasrole.md`.
EOF_GATE
    echo "==> rootasrole selected: Phase 510 owns linux-pam + libseccomp"
}

build_uutils
record_rootasrole_gate

echo "==> index local forge repo and install built Rust essentials"
rm -rf "$REPO" "$ROOT" "$CACHE" "$TARGET"
mkdir -p "$REPO" "$ROOT" "$CACHE" "$TARGET"
cp "$(cat "$LAB/uutils-coreutils.stone.path")" "$REPO/"
moss index "$REPO"
moss -D "$ROOT" --cache "$CACHE" repo add local "file://$REPO/stone.index" -c "local ONIX Rust essentials repo"
moss -D "$ROOT" --cache "$CACHE" repo update
moss -D "$ROOT" --cache "$CACHE" -y install --to "$TARGET" uutils-coreutils

test -x "$TARGET/usr/bin/coreutils"
if [ "${UUTILS_LINK_COMMANDS:-0}" = "1" ]; then
    test -L "$TARGET/usr/bin/ls"
    test "$(readlink "$TARGET/usr/bin/ls")" = "coreutils"
    "$TARGET/usr/bin/ls" --version >/dev/null
fi
test -f "$LAB/rootasrole.gate.md"

echo "==> success"
echo "uutils-coreutils stone: $(cat "$LAB/uutils-coreutils.stone.path")"
echo "rootasrole gate       : $LAB/rootasrole.gate.md"
REMOTE

  log "copying built stones back to host artifacts"
  rm -f \
    "$STONE_DIR"/uutils-coreutils-*.stone \
    "$STONE_DIR"/uutils-coreutils-dbginfo-*.stone

  local remote_stone
  remote_stone="$("$PHASE0_DIR/ssh.sh" "$user" "cat '$LAB/uutils-coreutils.stone.path'")"
  "$PHASE0_DIR/ssh.sh" "$user" "cd \"\$(dirname '$remote_stone')\" && tar -cf - \"\$(basename '$remote_stone')\"" \
    | tar -C "$STONE_DIR" -xf -

  mkdir -p "$PHASE509_PROOF_DIR"
  "$PHASE0_DIR/ssh.sh" "$user" "cat '$LAB/rootasrole.gate.md'" > "$ROOTASROLE_GATE"
  log "rootasrole: copied selection/dependency note to ${ROOTASROLE_GATE#$ONIX_ROOT/}"

  local host_uutils host_rootasrole
  host_uutils="$(host_stone_for uutils-coreutils)"
  host_rootasrole="$(host_stone_for rootasrole)"
  [[ -f "$host_uutils" ]] || die "failed to copy uutils-coreutils stone into ${STONE_DIR#$ONIX_ROOT/}"

  log "host moss integrity checks"
  "$HOST_MOSS" inspect --check "$host_uutils" >/dev/null
  if [[ -f "$host_rootasrole" ]]; then
    "$HOST_MOSS" inspect --check "$host_rootasrole" >/dev/null
  fi

  log "refreshing local Phase 4/5 moss repo"
  rm -f \
    "$LOCAL_REPO_DIR"/uutils-coreutils-*.stone \
    "$LOCAL_REPO_DIR"/uutils-coreutils-dbginfo-*.stone
  cp "$host_uutils" "$LOCAL_REPO_DIR/"
  if [[ -f "$host_rootasrole" ]]; then
    cp "$host_rootasrole" "$LOCAL_REPO_DIR/"
  fi
  "$HOST_MOSS" index "$LOCAL_REPO_DIR"

  prove_host_install_and_audit

  cat <<EOF_SUCCESS

==> success
uutils-coreutils stone: ${host_uutils#$ONIX_ROOT/}
rootasrole status     : $(if [[ -f "$host_rootasrole" ]]; then printf '%s' "${host_rootasrole#$ONIX_ROOT/}"; else printf 'gated (%s)' "${ROOTASROLE_GATE#$ONIX_ROOT/}"; fi)
local repo index      : ${LOCAL_REPO_DIR#$ONIX_ROOT/}/stone.index
stone catalog         : packages/STONES.md

Phase 509 built/audited uutils-coreutils and recorded RootAsRole as the selected
sudo-class path. Phase 510 owns linux-pam + libseccomp.
EOF_SUCCESS
}

case "$MODE" in
  apply) run_apply ;;
  check) run_check ;;
  *) die "unknown mode: $MODE" ;;
esac
