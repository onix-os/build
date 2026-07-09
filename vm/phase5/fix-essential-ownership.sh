#!/usr/bin/env bash
# vm/phase5/fix-essential-ownership.sh — Phase 506 ownership collision gate.
#
# Phase 506 removes the current onix-busybox/onix-systemd overlap for
# /usr/bin/reboot and /usr/bin/poweroff, then proves the canonical repo can be
# installed in strict ownership mode.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PHASE4_DIR="$ONIX_ROOT/vm/phase4"
HOST_MOSS="${ONIX_HOST_MOSS:-$ONIX_ROOT/artifacts/host-tools/bin/moss}"
LOCAL_REPO_DIR="${ONIX_LOCAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-local-repo}"

MODE="check"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*"
}

rel() {
  local path="$1"
  case "$path" in
    "$ONIX_ROOT") printf '.' ;;
    "$ONIX_ROOT"/*) printf '%s' "${path#$ONIX_ROOT/}" ;;
    *) printf '%s' "$path" ;;
  esac
}

usage() {
  cat <<'EOF'
usage: fix-essential-ownership.sh [--check|--rebuild]

--check    verify source policy, rebuilt onix-busybox payload, and strict
           canonical repo install proof
--rebuild  rebuild onix-busybox from the patched package rules, reassemble the
           canonical local repo, and run the same strict checks
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE="check" ;;
    --rebuild) MODE="rebuild" ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
  shift
done

cd "$ONIX_ROOT"

need_file() {
  [[ -f "$1" ]] || die "missing expected file: $(rel "$1")"
}

need_host_moss() {
  [[ -x "$HOST_MOSS" ]] || die "missing host moss: $(rel "$HOST_MOSS") (run: make phase 202)"
}

bootstrap_list_from_build_script() {
  awk '
    /^BOOTSTRAP_BUSYBOX_APPLETS="/ { in_list=1; next }
    in_list && /^"$/ { in_list=0; next }
    in_list { print }
  ' vm/phase4/build-busybox-stone.sh
}

bootstrap_list_from_materializer() {
  awk '
    /^bootstrap_busybox_applets\(\) \{/ { in_func=1; next }
    in_func && /^EOF$/ { in_func=0; next }
    in_func && /^[[:alnum:]_-]+$/ { print }
  ' vm/phase4/materialize-etc.sh
}

reject_systemd_owned_busybox_link() {
  local source_name="$1"
  local list="$2"

  if printf '%s\n' "$list" | grep -Eq '^(reboot|poweroff)$'; then
    printf '%s\n' "$list" >&2
    die "$source_name still asks onix-busybox to own reboot/poweroff"
  fi
}

check_source_policy() {
  log "source    : checking BusyBox/systemd ownership policy"

  need_file "vm/phase4/build-busybox-stone.sh"
  need_file "vm/phase4/materialize-etc.sh"
  need_file "packages/core/onix-busybox/stone.yaml.in"
  need_file "vm/phase4/stone-recipes/onix-busybox/stone.yaml.in"
  need_file "packages/core/onix-busybox/PACKAGE.md"

  reject_systemd_owned_busybox_link \
    "build-busybox-stone.sh" \
    "$(bootstrap_list_from_build_script)"
  reject_systemd_owned_busybox_link \
    "materialize-etc.sh" \
    "$(bootstrap_list_from_materializer)"

  grep -q '^release     : 2$' packages/core/onix-busybox/stone.yaml.in \
    || die "canonical onix-busybox recipe must bump release to 2"
  cmp -s \
    vm/phase4/stone-recipes/onix-busybox/stone.yaml.in \
    packages/core/onix-busybox/stone.yaml.in \
    || die "old and canonical onix-busybox recipe templates must stay byte-for-byte equal during migration"
  grep -q 'must not own `/usr/bin/reboot` or `/usr/bin/poweroff`' \
    packages/core/onix-busybox/PACKAGE.md \
    || die "onix-busybox PACKAGE.md must document systemd-owned command names"
}

select_busybox_stone() {
  local matches=("$LOCAL_REPO_DIR"/onix-busybox-*.stone)
  [[ "${#matches[@]}" -eq 1 ]] || die "expected exactly one onix-busybox stone in $(rel "$LOCAL_REPO_DIR"), found ${#matches[@]}"
  printf '%s\n' "${matches[0]}"
}

check_busybox_artifact() {
  need_host_moss

  local stone tmp payload
  stone="$(select_busybox_stone)"
  log "stone     : checking $(rel "$stone")"

  mkdir -p "$ONIX_ROOT/artifacts"
  tmp="$(mktemp -d "$ONIX_ROOT/artifacts/.phase506-extract.XXXXXX")"
  cleanup() {
    rm -rf "$tmp"
  }
  trap cleanup RETURN

  "$HOST_MOSS" inspect --check "$stone" >/dev/null
  "$HOST_MOSS" extract -o "$tmp" "$stone" >/dev/null

  payload="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | sort | sed -n '1p')"
  [[ -n "$payload" ]] || die "could not find extracted onix-busybox payload"

  need_file "$payload/usr/bin/busybox"
  need_file "$payload/usr/share/onix/packages/onix-busybox.links"
  need_file "$payload/usr/share/onix/packages/onix-busybox.systemd-owned"

  [[ ! -e "$payload/usr/bin/reboot" ]] \
    || die "rebuilt onix-busybox still owns /usr/bin/reboot"
  [[ ! -e "$payload/usr/bin/poweroff" ]] \
    || die "rebuilt onix-busybox still owns /usr/bin/poweroff"

  grep -qx 'reboot' "$payload/usr/share/onix/packages/onix-busybox.systemd-owned" \
    || die "onix-busybox.systemd-owned must list reboot"
  grep -qx 'poweroff' "$payload/usr/share/onix/packages/onix-busybox.systemd-owned" \
    || die "onix-busybox.systemd-owned must list poweroff"

  reject_systemd_owned_busybox_link \
    "onix-busybox.links" \
    "$(cat "$payload/usr/share/onix/packages/onix-busybox.links")"

  rm -rf "$tmp"
  trap - RETURN
}

strict_repo_proof() {
  log "repo      : strict canonical local repo install proof"
  ONIX_REPO_STRICT_OWNERSHIP=1 "$SCRIPT_DIR/assemble-canonical-local-repo.sh" --check >/dev/null
}

run_check() {
  log "Phase 506 essential package ownership collision fix"
  log "mode      : check"
  check_source_policy
  check_busybox_artifact
  strict_repo_proof

  cat <<'EOF'

==> success
Phase 506 proved the essential package set has no reboot/poweroff ownership
collision in the canonical local repo.
EOF
}

run_rebuild() {
  log "Phase 506 essential package ownership collision fix"
  log "mode      : rebuild onix-busybox, then prove strict repo ownership"
  check_source_policy

  "$(command -v make)" --no-print-directory -C "$PHASE4_DIR" busybox-stone
  check_busybox_artifact
  ONIX_REPO_STRICT_OWNERSHIP=1 "$SCRIPT_DIR/assemble-canonical-local-repo.sh" --assemble
  strict_repo_proof
}

case "$MODE" in
  check) run_check ;;
  rebuild) run_rebuild ;;
  *) die "unknown mode: $MODE" ;;
esac
