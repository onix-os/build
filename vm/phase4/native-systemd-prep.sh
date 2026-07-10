#!/usr/bin/env bash
# vm/phase4/native-systemd-prep.sh — Phase 421 native systemd prep.
#
# This phase does not build systemd yet. It turns the current Nix-wrapped
# systemd truth into a compact Phase 422 contract: build one native
# source-owned systemd stone, with dependencies bundled for the first
# proof and split into separate stones later.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHASE0_DIR="$(cd "$SCRIPT_DIR/../phase0" && pwd)"

# shellcheck source=vm/phase0/config.sh
source "$PHASE0_DIR/config.sh"

PLAN_DIR="${ONIX_NATIVE_SYSTEMD_PLAN_DIR:-$ONIX_ROOT/artifacts/onix-native-systemd-plan}"
SYSTEMD_PAYLOAD_OUT_FILE="${ONIX_SYSTEMD_PAYLOAD_OUT_FILE:-$ONIX_ROOT/artifacts/onix-image/systemd-payload.out}"
SYSTEMD_CLOSURE_LIST="${ONIX_SYSTEMD_CLOSURE_LIST:-$ONIX_ROOT/artifacts/onix-image/systemd-payload.closure}"
NATIVE_RECIPE_DRAFT="${ONIX_NATIVE_SYSTEMD_RECIPE_DRAFT:-$ONIX_ROOT/packages/services/systemd/stone.yaml.in}"

need_cmd awk
need_cmd basename
need_cmd cat
need_cmd chmod
need_cmd cp
need_cmd date
need_cmd find
need_cmd grep
need_cmd install
need_cmd mkdir
need_cmd nix
need_cmd sed
need_cmd sort
need_cmd wc

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

locked_nixpkgs_path() {
  nix eval --raw --impure --expr "
let
  lock = builtins.fromJSON (builtins.readFile \"$ONIX_ROOT/flake.lock\");
  node = lock.nodes.nixpkgs_2.locked;
  src = builtins.fetchTree {
    type = node.type;
    owner = node.owner;
    repo = node.repo;
    rev = node.rev;
    narHash = node.narHash;
  };
in src.outPath
" 2>/dev/null || true
}

systemd_source_path() {
  nix eval --raw --impure --expr "
let
  lock = builtins.fromJSON (builtins.readFile \"$ONIX_ROOT/flake.lock\");
  node = lock.nodes.nixpkgs_2.locked;
  src = builtins.fetchTree {
    type = node.type;
    owner = node.owner;
    repo = node.repo;
    rev = node.rev;
    narHash = node.narHash;
  };
  pkgs = import src {
    system = builtins.currentSystem;
    config.allowUnfree = true;
  };
in pkgs.pkgsMusl.systemd.src.outPath
" 2>/dev/null || true
}

systemd_source_hash() {
  local path="$1"

  [[ -n "$path" && -e "$path" ]] || return 0
  nix hash path "$path" 2>/dev/null || true
}

extract_nixpkgs_fetch_hash() {
  local nixpkgs="$1"
  local expr="$nixpkgs/pkgs/os-specific/linux/systemd/default.nix"

  [[ -f "$expr" ]] || return 0
  awk '
    /src = fetchFromGitHub/ { in_src=1 }
    in_src && /hash =/ {
      gsub(/[;" ]/, "", $3)
      print $3
      exit
    }
  ' "$expr"
}

count_nixpkgs_systemd_patches() {
  local nixpkgs="$1"
  local patch_dir="$nixpkgs/pkgs/os-specific/linux/systemd"

  [[ -d "$patch_dir" ]] || {
    printf '0\n'
    return 0
  }
  find "$patch_dir" -maxdepth 1 -name '00*.patch' -type f | wc -l | sed 's/[[:space:]]//g'
}

write_closure_buckets() {
  awk '
    BEGIN {
      print "store_path\tbucket\treason"
    }
    {
      store = $0
      base = store
      sub("^.*/", "", base)
      name = base
      sub("^[^-]+-", "", name)

      bucket = "phase422-inspect"
      reason = "not yet classified"

      if (name ~ /^systemd-/) {
        bucket = "native-systemd-core"
        reason = "the package we replace with a source-built stone"
      } else if (name ~ /^musl-/ || name ~ /^gcc-.*-lib/ || name ~ /^libxcrypt-/) {
        bucket = "phase422-runtime-bundle"
        reason = "needed so native systemd has a non-Nix musl runtime path"
      } else if (name ~ /^util-linux-/ || name ~ /^kmod-/ || name ~ /^coreutils-/) {
        bucket = "phase422-helper-bundle"
        reason = "runtime/helper command or library used by current systemd closure"
      } else if (name ~ /^acl-/ || name ~ /^attr-/ || name ~ /^xz-/ || name ~ /^zstd-/ || name ~ /^gmp-/) {
        bucket = "phase422-library-bundle"
        reason = "runtime library in current systemd closure; bundle now, split later"
      }

      print store "\t" bucket "\t" reason
    }
  ' "$SYSTEMD_CLOSURE_LIST"
}

safe_artifact_path "$PLAN_DIR"

[[ -f "$SYSTEMD_PAYLOAD_OUT_FILE" ]] \
  || die "missing systemd payload path: ${SYSTEMD_PAYLOAD_OUT_FILE#$ONIX_ROOT/} (run make phase 213)"
[[ -s "$SYSTEMD_CLOSURE_LIST" ]] \
  || die "missing systemd closure list: ${SYSTEMD_CLOSURE_LIST#$ONIX_ROOT/} (run make phase 213)"
[[ -f "$NATIVE_RECIPE_DRAFT" ]] \
  || die "missing native recipe draft: ${NATIVE_RECIPE_DRAFT#$ONIX_ROOT/}"

SYSTEMD_PAYLOAD_OUT="$(< "$SYSTEMD_PAYLOAD_OUT_FILE")"
[[ "$SYSTEMD_PAYLOAD_OUT" == /nix/store/*-systemd-* ]] \
  || die "current systemd payload is not the expected bootstrap Nix systemd output: $SYSTEMD_PAYLOAD_OUT"

SYSTEMD_VERSION="$(basename "$SYSTEMD_PAYLOAD_OUT" | sed -E 's/^[^-]+-systemd-([0-9][0-9.]*).*$/\1/')"
[[ -n "$SYSTEMD_VERSION" && "$SYSTEMD_VERSION" != "$(basename "$SYSTEMD_PAYLOAD_OUT")" ]] \
  || die "could not infer systemd version from $SYSTEMD_PAYLOAD_OUT"

CLOSURE_COUNT="$(wc -l < "$SYSTEMD_CLOSURE_LIST" | tr -d '[:space:]')"
NIXPKGS_REV="$(extract_locked_nixpkgs_rev)"
SYSTEMD_SRC="$(systemd_source_path)"
SYSTEMD_SRC_HASH="$(systemd_source_hash "$SYSTEMD_SRC")"
NIXPKGS_SRC="$(locked_nixpkgs_path)"
NIXPKGS_SYSTEMD_FETCH_HASH="$(extract_nixpkgs_fetch_hash "$NIXPKGS_SRC")"
NIXPKGS_SYSTEMD_PATCH_COUNT="$(count_nixpkgs_systemd_patches "$NIXPKGS_SRC")"

rm -rf "$PLAN_DIR"
install -dm0755 "$PLAN_DIR"

write_closure_buckets > "$PLAN_DIR/current-systemd-closure-buckets.tsv"
cp "$NATIVE_RECIPE_DRAFT" "$PLAN_DIR/systemd-native.stone.yaml.in"

cat > "$PLAN_DIR/current-wrapper.txt" <<EOF
ONIX Phase 421 current systemd wrapper truth

Current package name:
  systemd

Current package kind:
  bootstrap ownership stone wrapping a Nix-built musl systemd payload

Current payload:
  $SYSTEMD_PAYLOAD_OUT

Current version:
  $SYSTEMD_VERSION

Current closure list:
  ${SYSTEMD_CLOSURE_LIST#$ONIX_ROOT/}

Current closure entries:
  $CLOSURE_COUNT

Current problem:
  The machine-plane package boundary exists, but the systemd bytes are still
  built by pinned nixpkgs and still execute through absolute /nix/store paths.
EOF

cat > "$PLAN_DIR/source-policy.txt" <<EOF
ONIX Phase 421 native systemd source policy

Goal:
  Phase 422 replaces the Nix-wrapped systemd payload with a source-built
  systemd stone.

Systemd version:
  $SYSTEMD_VERSION

Upstream source identity:
  owner: systemd
  repo : systemd
  rev  : v$SYSTEMD_VERSION

Locked nixpkgs revision used as current source/build research:
  $NIXPKGS_REV

Locked nixpkgs source path:
  ${NIXPKGS_SRC:-unavailable in this shell}

Current pkgsMusl.systemd source path:
  ${SYSTEMD_SRC:-unavailable in this shell}

Current source path hash:
  ${SYSTEMD_SRC_HASH:-unavailable in this shell}

Nixpkgs fetchFromGitHub hash:
  ${NIXPKGS_SYSTEMD_FETCH_HASH:-unavailable in this shell}

Nixpkgs systemd patch count:
  $NIXPKGS_SYSTEMD_PATCH_COUNT

Policy:
  Nix may remain a source-acquisition/reference tool during Phase 421.
  Nix must not provide runtime ownership for the Phase 422 native systemd stone.
  The Phase 422 installed runtime must not require /nix/store.
EOF

cat > "$PLAN_DIR/phase422-build-contract.txt" <<'EOF'
ONIX Phase 422 native systemd build contract

User-facing phase budget:
  Keep this compressed. Phase 422 should build/install/boot-prove one native
  systemd stone. Do not create one public phase per dependency.

Initial packaging shape:
  Build a monolithic bootstrap-native systemd stone first.

Why monolithic first:
  systemd has many runtime libraries/helpers. Splitting every dependency into
  separate stones first would explode the learning flow and delay the boot
  proof. The first native package may bundle its immediate runtime closure; a
  later cleanup can split musl, kmod, util-linux, compression libraries, and
  other libraries into their own stones.

Required runtime rule:
  No installed systemd binary, symlink, unit source, package note, or runtime
  materialization may point to /nix/store.

Interpreter rule:
  The native systemd binary should use the normal ONIX/musl interpreter path,
  expected through merged-/usr as /lib/ld-musl-x86_64.so.1.

Minimum install shape:
  /usr/lib/systemd/systemd
  /usr/lib/systemd/system
  /usr/lib/systemd/user
  /usr/bin/systemctl
  /usr/bin/journalctl
  /usr/bin/systemd-tmpfiles
  /usr/bin/systemd-sysusers
  /usr/bin/udevadm
  /usr/share/onix/packages/systemd.md

Minimum boot proof:
  PID 1 is systemd.
  /usr/lib/systemd/systemd is not a symlink into /nix/store.
  systemctl --version works.
  bootstrap network still comes up.
  bootstrap SSH still works.
  Phase 419 audit reports no Nix-built systemd runtime debt.

Deferred split:
  After the native boot proof, split bundled runtime pieces into smaller stones
  only when doing so is safer than keeping the bootstrap bundle.
EOF

cat > "$PLAN_DIR/README.md" <<EOF
# Phase 421 native systemd prep artifact

Generated by:

\`\`\`sh
make phase 421
\`\`\`

Generated at:

\`\`\`text
$(date -u '+%Y-%m-%dT%H:%M:%SZ')
\`\`\`

Files:

- \`current-wrapper.txt\` — what the current Nix-wrapped \`systemd\` is.
- \`source-policy.txt\` — source identity and Nix-as-source-reference policy.
- \`current-systemd-closure-buckets.tsv\` — current closure split into compressed Phase 422 buckets.
- \`phase422-build-contract.txt\` — what the next phase must build and prove.
- \`systemd-native.stone.yaml.in\` — tracked native recipe draft copied from \`${NATIVE_RECIPE_DRAFT#$ONIX_ROOT/}\`.

This artifact is generated output. The educational explanation lives in the
mdBook page for Phase 421.
EOF

grep -q '^name[[:space:]]*: systemd$' "$NATIVE_RECIPE_DRAFT" \
  || die "native recipe draft must keep the package name systemd"
grep -q '@SYSTEMD_VERSION@' "$NATIVE_RECIPE_DRAFT" \
  || die "native recipe draft must expose @SYSTEMD_VERSION@"
grep -q '@SYSTEMD_NATIVE_PAYLOAD_URL@' "$NATIVE_RECIPE_DRAFT" \
  || die "native recipe draft must use a prepared native payload URL placeholder"
if grep -q '/nix/store' "$NATIVE_RECIPE_DRAFT"; then
  die "native recipe draft must not install or reference /nix/store runtime paths"
fi

log "Phase 421 native systemd prep"
cat <<EOF
current    : $SYSTEMD_PAYLOAD_OUT
version    : $SYSTEMD_VERSION
closure    : $CLOSURE_COUNT entries
source     : ${SYSTEMD_SRC:-unavailable in this shell}
fetch hash : ${NIXPKGS_SYSTEMD_FETCH_HASH:-unavailable in this shell}
patches    : $NIXPKGS_SYSTEMD_PATCH_COUNT Nixpkgs systemd patch hints
recipe     : ${NATIVE_RECIPE_DRAFT#$ONIX_ROOT/}
artifact   : ${PLAN_DIR#$ONIX_ROOT/}

Phase 422 contract:
  build one source-built native systemd stone
  bundle immediate runtime deps for the first boot proof
  install/prove it without any /nix/store systemd runtime path
EOF

log "success"
