#!/usr/bin/env bash
# vm/phase4/bootstrap-debt-audit.sh — guard known bootstrap-only OS debt.
#
# This is not a new public phase. It is a doctor/check guard so we do not forget
# which pieces are temporary while Phase 5 starts adding more real packages.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

MODE="${1:---check}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*"
}

usage() {
  cat <<'EOF'
usage: bootstrap-debt-audit.sh [--check]

--check  verify bootstrap-only machine debt is explicitly packaged, documented,
         and checked by the live Phase 5 proof
EOF
}

case "$MODE" in
  --check) ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; die "unknown argument: $MODE" ;;
esac

cd "$ONIX_ROOT"

need_grep() {
  local pattern="$1"
  local file="$2"
  local message="$3"

  grep -q -- "$pattern" "$file" || die "$message"
}

log "guard: bootstrap networking is marked transitional"
need_grep '-Dnetworkd=false' \
  "$ONIX_ROOT/vm/phase4/build-native-systemd-stone.sh" \
  "native systemd build no longer documents the current networkd=false boundary"
need_grep 'static-qemu-network' \
  "$ONIX_ROOT/vm/phase4/build-bootstrap-stone.sh" \
  "bootstrap payload does not list static-qemu-network debt"
need_grep 'replace after native systemd grows networkd' \
  "$ONIX_ROOT/vm/phase4/build-bootstrap-stone.sh" \
  "bootstrap payload does not explain the networkd next step"

log "guard: temporary access paths are named as debt"
for item in \
  serial-root-shell \
  remote-inspection-listener \
  dropbear-ssh-bootstrap \
  active-unit-copy-glue
do
  need_grep "$item" \
    "$ONIX_ROOT/vm/phase4/build-bootstrap-stone.sh" \
    "bootstrap payload does not list $item debt"
done

log "guard: package recipe installs the debt ledger"
need_grep 'bootstrap-debt.tsv' \
  "$ONIX_ROOT/packages/services/bootstrap/stone.yaml.in" \
  "canonical bootstrap recipe does not install bootstrap-debt.tsv"
need_grep 'bootstrap-debt.tsv' \
  "$ONIX_ROOT/vm/phase4/stone-recipes/bootstrap/stone.yaml.in" \
  "Phase 4 bootstrap recipe copy does not install bootstrap-debt.tsv"

log "guard: image materializer verifies the debt ledger"
need_grep 'bootstrap debt ledger' \
  "$ONIX_ROOT/vm/phase4/materialize-etc.sh" \
  "materialize-etc does not verify bootstrap-debt.tsv"

log "guard: booted Phase 5 proof verifies the debt ledger"
need_grep '/usr/share/onix/bootstrap/bootstrap-debt.tsv' \
  "$ONIX_ROOT/vm/phase5/phase5-runtime-proof.sh" \
  "Phase 514 runtime proof does not check bootstrap-debt.tsv"

log "guard: educational docs explain the debt ledger"
need_grep 'bootstrap-debt.tsv' \
  "$ONIX_ROOT/vm/phase4/docs/418_package_prove_bootstrap.md" \
  "Phase 418 docs do not explain bootstrap-debt.tsv"
need_grep 'bootstrap-debt.tsv' \
  "$ONIX_ROOT/vm/phase5/docs/514_booted_phase_5_runtime_proof.md" \
  "Phase 514 docs do not mention bootstrap-debt.tsv"

log "bootstrap debt: guard OK"
