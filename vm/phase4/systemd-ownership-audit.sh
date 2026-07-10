#!/usr/bin/env bash
# vm/phase4/systemd-ownership-audit.sh — Phase 414 pre-systemd-stone audit.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SYSTEMD_OUT_FILE="$ONIX_ROOT/artifacts/onix-image/systemd-payload.out"
SYSTEMD_CLOSURE="$ONIX_ROOT/artifacts/onix-image/systemd-payload.closure"
LOCAL_REPO="$ONIX_ROOT/artifacts/onix-local-repo"
BOOK_PAGE="$ONIX_ROOT/vm/phase4/docs/414_systemd_ownership_audit.md"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*"
}

need_file() {
  [[ -f "$1" ]] || die "missing expected file: ${1#$ONIX_ROOT/}"
}

need_text() {
  local pattern="$1"
  local file="$2"

  grep -qE "$pattern" "$file" \
    || die "missing required text in ${file#$ONIX_ROOT/}: $pattern"
}

need_repo_stone() {
  local name="$1"
  local matches

  matches=("$LOCAL_REPO"/"$name"-*.stone)
  [[ -e "${matches[0]}" ]] || die "local Phase 4 repo is missing $name stone"
}

log "Phase 414 systemd ownership audit"
cat <<'EOF'

Phase 414 question:

  What still depends on the temporary Nix systemd payload now that BusyBox and
  Dropbear have ONIX stones?

Expected state before Phase 415:

  - /usr/bin/busybox is active from busybox.
  - /usr/sbin/dropbear is active from dropbear.
  - /usr/lib/systemd/systemd still points into the copied Nix systemd payload.
  - /usr/bin/systemctl still points into the copied Nix systemd payload.
  - the next package target is systemd, not another runtime shortcut.

EOF

log "checking host artifacts"
need_file "$SYSTEMD_OUT_FILE"
need_file "$SYSTEMD_CLOSURE"
need_file "$LOCAL_REPO/stone.index"

grep -Eq '/nix/store/.+-systemd-' "$SYSTEMD_OUT_FILE" \
  || die "systemd payload out file is not a Nix systemd path"
grep -Eq '/nix/store/.+-systemd-' "$SYSTEMD_CLOSURE" \
  || die "systemd closure does not contain systemd"
grep -Eq '/nix/store/.+-kmod-' "$SYSTEMD_CLOSURE" \
  || die "systemd closure does not contain kmod/libkmod"
grep -Eq '/nix/store/.+-util-linux-minimal-' "$SYSTEMD_CLOSURE" \
  || die "systemd closure does not contain util-linux helpers"
grep -Eq '/nix/store/.+-musl-' "$SYSTEMD_CLOSURE" \
  || die "systemd closure does not contain musl runtime support"

need_repo_stone busybox
need_repo_stone dropbear

log "checking Phase 414 book page"
need_file "$BOOK_PAGE"
need_text 'systemd' "$BOOK_PAGE"
need_text '/usr/lib/systemd/systemd' "$BOOK_PAGE"
need_text '/usr/bin/busybox' "$BOOK_PAGE"
need_text '/usr/sbin/dropbear' "$BOOK_PAGE"
need_text 'Nix systemd payload' "$BOOK_PAGE"

log "checking mounted image ownership"
"$SCRIPT_DIR/materialize-etc.sh" --systemd-audit

cat <<EOF

==> success
Phase 414 audited the current systemd boundary.

Next:
  make phase 415

EOF
