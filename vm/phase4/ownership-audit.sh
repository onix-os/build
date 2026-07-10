#!/usr/bin/env bash
# vm/phase4/ownership-audit.sh — Phase 407 machine-plane ownership audit.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*"
}

need_doc_text() {
  local pattern="$1"
  local file="$2"

  grep -qE "$pattern" "$ONIX_ROOT/$file" \
    || die "missing ownership wording in $file: $pattern"
}

log "Phase 407 machine-plane ownership audit"
cat <<'EOF'

ONIX ownership rule:

  moss/.stone owns the machine plane.
  Nix owns the user toolbox plane.

Temporary bootstrap payloads currently copied from pinned Nix or Alpine are
allowed only as proofs. They must not become the final package story.

Temporary payload                         Final machine-plane owner
---------------------------------------------------------------------------
Alpine virt kernel/initramfs/modules      onix-kernel + onix-initramfs stones
pkgsMusl.systemd                          systemd stone
pkgsMusl.busybox                          busybox / onix-base stone
pkgsMusl.dropbear                         dropbear / onix-ssh stone
Nix-store util-linux nologin              onix-util-linux or onix-base stone

EOF

log "checking architecture/book wording"
need_doc_text 'Nix-sourced system payloads are bootstrap-only' "vm/phase4/docs/407_machine_plane_ownership_audit.md"
need_doc_text 'systemd' "vm/phase4/docs/407_machine_plane_ownership_audit.md"
need_doc_text 'busybox' "vm/phase4/docs/407_machine_plane_ownership_audit.md"
need_doc_text 'dropbear' "vm/phase4/docs/407_machine_plane_ownership_audit.md"
need_doc_text 'onix-kernel' "vm/phase4/docs/407_machine_plane_ownership_audit.md"
need_doc_text 'Nix controls the toolbox' "ARCHITECTURE.md"
need_doc_text 'Nix-sourced system payloads are bootstrap-only' "ARCHITECTURE.md"

echo
echo "==> success"
echo "Phase 407 confirms temporary Nix-sourced system payloads have named future .stone owners."
