#!/usr/bin/env bash
# vm/phase5/wire-uutils-coreutils.sh — Phase 513.
#
# Move normal coreutils command-name ownership from busybox to
# uutils-coreutils while keeping BusyBox as bootstrap/recovery shell.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHASE4_DIR="$(cd "$SCRIPT_DIR/../phase4" && pwd)"
PHASE0_DIR="$(cd "$SCRIPT_DIR/../phase0" && pwd)"

# shellcheck source=vm/phase0/config.sh
source "$PHASE0_DIR/config.sh"

MODE="apply"
FORCE_REBUILD="${ONIX_PHASE513_REBUILD:-0}"

STONE_DIR="${ONIX_STONE_DIR:-$ONIX_ROOT/artifacts/onix-stones}"
LOCAL_REPO_DIR="${ONIX_LOCAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-local-repo}"
HOST_MOSS="${ONIX_HOST_MOSS:-$ONIX_ROOT/artifacts/host-tools/bin/moss}"
PROOF_DIR="$ONIX_ROOT/artifacts/onix-phase5-work/513"

usage() {
  cat <<'EOF'
usage: wire-uutils-coreutils.sh [--apply|--check|--rebuild]

--apply    rebuild busybox with reduced command links, rebuild
           uutils-coreutils with command-name links, and prove they install
           together without path collisions
--check    verify existing stones and docs
--rebuild  force rebuilding/rechecking Phase 513
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

local_stone_for() {
  local package="$1"
  find "$LOCAL_REPO_DIR" -maxdepth 1 -name "$package-*.stone" ! -name '*dbginfo*' ! -name '*devel*' | sort | tail -n 1
}

check_source_files() {
  [[ -f "$ONIX_ROOT/vm/phase5/docs/513_uutils_command_ownership.md" ]] || die "missing Phase 513 doc page"
  [[ -f "$ONIX_ROOT/packages/core/uutils-coreutils/PACKAGE.md" ]] || die "missing uutils package contract"
  [[ -f "$ONIX_ROOT/packages/core/busybox/PACKAGE.md" ]] || die "missing busybox package contract"
  grep -q 'Phase 513' "$ONIX_ROOT/packages/core/uutils-coreutils/PACKAGE.md"
  grep -q 'uutils-coreutils' "$ONIX_ROOT/packages/core/busybox/PACKAGE.md"
  grep -q 'uutils-coreutils' "$ONIX_ROOT/packages/STONES.md"
}

prove_install() {
  [[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"

  local busybox_stone uutils_stone
  busybox_stone="$(local_stone_for busybox)"
  uutils_stone="$(local_stone_for uutils-coreutils)"
  [[ -n "$busybox_stone" ]] || die "missing busybox stone in ${LOCAL_REPO_DIR#$ONIX_ROOT/}"
  [[ -n "$uutils_stone" ]] || die "missing uutils-coreutils stone in ${LOCAL_REPO_DIR#$ONIX_ROOT/}"

  "$HOST_MOSS" inspect --check "$busybox_stone" >/dev/null
  "$HOST_MOSS" inspect --check "$uutils_stone" >/dev/null

  local root="$PROOF_DIR/moss-root"
  local cache="$PROOF_DIR/moss-cache"
  local target="$PROOF_DIR/install-target"
  local install_log="$PROOF_DIR/moss-install.log"

  rm -rf "$PROOF_DIR"
  mkdir -p "$root" "$cache" "$target"

  "$HOST_MOSS" -D "$root" \
    --cache "$cache" \
    repo add onix-uutils-wiring \
    "file://$LOCAL_REPO_DIR/stone.index" \
    -c "ONIX Phase 513 uutils wiring" >/dev/null

  "$HOST_MOSS" -D "$root" --cache "$cache" repo update >/dev/null

  if ! "$HOST_MOSS" -D "$root" \
      --cache "$cache" \
      -y install --to "$target" \
      busybox uutils-coreutils >"$install_log" 2>&1; then
    cat "$install_log" >&2
    die "Moss could not install busybox + uutils-coreutils"
  fi

  if grep -q 'duplicate entry:' "$install_log"; then
    cat "$install_log" >&2
    die "BusyBox/uutils install has package path ownership collisions"
  fi

  [[ -x "$target/usr/bin/busybox" ]] || die "missing /usr/bin/busybox"
  [[ -x "$target/usr/bin/coreutils" ]] || die "missing /usr/bin/coreutils"
  [[ -f "$target/usr/share/onix/packages/uutils-coreutils.commands" ]] \
    || die "missing uutils command manifest"

  local command_name command_count
  command_count=0
  while IFS= read -r command_name; do
    [[ -n "$command_name" ]] || continue
    command_count=$((command_count + 1))
    [[ -L "$target/usr/bin/$command_name" ]] \
      || die "uutils did not own /usr/bin/$command_name"
    [[ "$(readlink "$target/usr/bin/$command_name")" = "coreutils" ]] \
      || die "/usr/bin/$command_name does not point at coreutils"
  done < "$target/usr/share/onix/packages/uutils-coreutils.commands"

  [[ "$command_count" -gt 0 ]] || die "uutils command manifest is empty"
  [[ -L "$target/usr/bin/ls" ]] || die "uutils did not own /usr/bin/ls"
  [[ "$(readlink "$target/usr/bin/ls")" = "coreutils" ]] \
    || die "/usr/bin/ls does not point at coreutils"
  [[ -L "$target/usr/bin/cp" ]] || die "uutils did not own /usr/bin/cp"
  [[ -L "$target/usr/bin/[" ]] || die "uutils did not own /usr/bin/["
  [[ -L "$target/usr/bin/sh" ]] || die "busybox did not keep /usr/bin/sh"
  [[ "$(readlink "$target/usr/bin/sh")" = "busybox" ]] \
    || die "/usr/bin/sh does not point at busybox"

  "$target/usr/bin/ls" --version >/dev/null
  "$target/usr/bin/[" 1 = 1 ]
  "$target/usr/bin/busybox" sh -c 'echo busybox recovery shell OK' >/dev/null

  log "proof     : BusyBox recovery + all uutils command links OK ($command_count commands)"
}

run_check() {
  check_source_files
  if [[ -z "$(local_stone_for busybox)" || -z "$(local_stone_for uutils-coreutils)" ]]; then
    log "stone     : Phase 513 stones not both built yet"
    log "phase513  : check OK"
    return
  fi
  prove_install
  log "phase513  : check OK"
}

run_apply() {
  check_source_files

  log "Phase 513 uutils command wiring"
  log "step 1/3 : rebuild busybox without uutils-overlapping command links"
  "$PHASE4_DIR/build-busybox-stone.sh"

  log "step 2/3 : rebuild uutils-coreutils with command-name links"
  ONIX_UUTILS_LINK_COMMANDS=1 \
  ONIX_UUTILS_RELEASE=2 \
  ONIX_PHASE509_REBUILD=1 \
    "$SCRIPT_DIR/build-rust-essential-stones.sh" --rebuild

  log "step 3/3 : prove combined package ownership"
  prove_install

  cat <<EOF_SUCCESS

==> success
busybox     : $(local_stone_for busybox | sed "s|^$ONIX_ROOT/||")
uutils-coreutils : $(local_stone_for uutils-coreutils | sed "s|^$ONIX_ROOT/||")

Phase 513 moved normal coreutils command-name ownership to uutils while keeping
BusyBox as the bootstrap/recovery shell provider.
EOF_SUCCESS
}

case "$MODE" in
  apply) run_apply ;;
  check) run_check ;;
  *) die "unknown mode: $MODE" ;;
esac
