#!/usr/bin/env bash
# vm/phase2/build-host-moss.sh — build host-side moss from the pinned source.
#
# Runs on the host. This is the first step toward removing the forge from root
# tree/image assembly. It intentionally reuses the same OS_TOOLS_REPO and
# OS_TOOLS_REF that Phase 0 uses, so host moss and forge moss stay aligned.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHASE0_DIR="$(cd "$SCRIPT_DIR/../phase0" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=vm/phase0/config.sh
source "$PHASE0_DIR/config.sh"

HOST_TOOLS_DIR="${ONIX_HOST_TOOLS_DIR:-$ONIX_ROOT/artifacts/host-tools}"
SRC_DIR="$HOST_TOOLS_DIR/src/os-tools"
BIN_DIR="$HOST_TOOLS_DIR/bin"
CARGO_HOME_DIR="${ONIX_HOST_CARGO_HOME:-$HOST_TOOLS_DIR/cargo-home}"
CARGO_TARGET_DIR="${ONIX_HOST_CARGO_TARGET_DIR:-$HOST_TOOLS_DIR/target}"
PIN_FILE="$HOST_TOOLS_DIR/os-tools.source"
GIT_DEPS_FILE="$HOST_TOOLS_DIR/os-tools.git-deps"

need_cmd git
need_cmd cargo
need_cmd rustc
need_cmd pkg-config

require_rust() {
  local version major minor
  version="$(rustc --version | awk '{print $2}')"
  major="${version%%.*}"
  minor="${version#*.}"
  minor="${minor%%.*}"

  if (( major < 1 || (major == 1 && minor < 91) )); then
    cat >&2 <<EOF
error: host moss requires rustc >= 1.91, but this shell has:

  $(rustc --version)

The ONIX flake provides a new enough Rust toolchain. Reload it, then retry:

  direnv reload
  make phase 202

or run directly through Nix:

  nix develop --impure -c make phase 202
EOF
    exit 1
  fi
}

mkdir -p "$HOST_TOOLS_DIR/src" "$BIN_DIR" "$CARGO_HOME_DIR" "$CARGO_TARGET_DIR"

echo "==> Phase 202 source policy"
echo "repo: $OS_TOOLS_REPO"
echo "ref : $OS_TOOLS_REF"
echo
cat <<'EOF'
ONIX currently treats AerynOS os-tools as pinned bootstrap tooling.

The pin protects us from upstream changes, but the URL is still an availability
dependency. When the ONIX mirror exists, switch OS_TOOLS_REPO to:

  https://github.com/onix-os/os-tools.git

while keeping the same commit first. Do not diverge until ONIX needs patches.
EOF

echo
echo "==> host Rust toolchain"
rustc --version
cargo --version
require_rust

echo
echo "==> fetching pinned os-tools source"
if [[ ! -d "$SRC_DIR/.git" ]]; then
  git clone "$OS_TOOLS_REPO" "$SRC_DIR"
else
  git -C "$SRC_DIR" remote set-url origin "$OS_TOOLS_REPO"
fi

git -C "$SRC_DIR" fetch --tags --prune origin
git -C "$SRC_DIR" checkout --detach "$OS_TOOLS_REF"
actual_ref="$(git -C "$SRC_DIR" rev-parse HEAD)"
[[ "$actual_ref" == "$OS_TOOLS_REF" ]] || die "os-tools checkout mismatch: got $actual_ref, expected $OS_TOOLS_REF"

grep '^source = "git+' "$SRC_DIR/Cargo.lock" \
  | sed -e 's/^source = "//' -e 's/"$//' \
  | sort -u > "$GIT_DEPS_FILE"

cat > "$PIN_FILE" <<EOF
repo=$OS_TOOLS_REPO
ref=$OS_TOOLS_REF
commit=$actual_ref
source_dir=$SRC_DIR
cargo_home=$CARGO_HOME_DIR
cargo_target_dir=$CARGO_TARGET_DIR
git_deps_file=$GIT_DEPS_FILE
EOF

echo "source: ${SRC_DIR#$ONIX_ROOT/}"
echo "pin   : ${PIN_FILE#$ONIX_ROOT/}"
echo "deps  : ${GIT_DEPS_FILE#$ONIX_ROOT/}"
sed -n '1,80p' "$GIT_DEPS_FILE"

echo
echo "==> building host moss"
(
  cd "$SRC_DIR"
  CARGO_HOME="$CARGO_HOME_DIR" \
  CARGO_TARGET_DIR="$CARGO_TARGET_DIR" \
    cargo build --profile onboarding -p moss
)

MOSS_BIN="$CARGO_TARGET_DIR/onboarding/moss"
[[ -x "$MOSS_BIN" ]] || die "missing built moss binary: $MOSS_BIN"

install -m 0755 "$MOSS_BIN" "$BIN_DIR/moss"

echo
echo "==> installed host moss"
"$BIN_DIR/moss" --version
test -x "$BIN_DIR/moss"
"$BIN_DIR/moss" --version | grep -q '^moss version '

echo
echo "==> success"
echo "host moss: $BIN_DIR/moss"
echo "source   : $SRC_DIR @ $actual_ref"
