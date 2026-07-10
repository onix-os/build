#!/usr/bin/env bash
# vm/phase5/check-rootasrole-integration.sh — Phase 512.
#
# Proves that RootAsRole's bootstrap policy is integrated into the rootasrole
# stone instead of living in a separate rootasrole-policy package.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHASE0_DIR="$(cd "$SCRIPT_DIR/../phase0" && pwd)"

# shellcheck source=vm/phase0/config.sh
source "$PHASE0_DIR/config.sh"

MODE="apply"

STONE_DIR="${ONIX_STONE_DIR:-$ONIX_ROOT/artifacts/onix-stones}"
LOCAL_REPO_DIR="${ONIX_LOCAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-local-repo}"
HOST_MOSS="${ONIX_HOST_MOSS:-$ONIX_ROOT/artifacts/host-tools/bin/moss}"
PROOF_DIR="$ONIX_ROOT/artifacts/onix-phase5-work/512"
ROOTASROLE_RELEASE="${ONIX_ROOTASROLE_RELEASE:-4}"

usage() {
  cat <<'EOF'
usage: check-rootasrole-integration.sh [--apply|--check|--rebuild]

--apply    remove stale rootasrole-policy artifacts, reindex the local repo,
           and prove rootasrole owns the bootstrap factory policy
--check    verify metadata and the current local repo without mutating artifacts
--rebuild  rebuild rootasrole first, then run the integrated-policy proof
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) MODE="apply" ;;
    --check) MODE="check" ;;
    --rebuild) MODE="rebuild" ;;
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

local_stone_for() {
  local package="$1"
  find "$LOCAL_REPO_DIR" -maxdepth 1 -name "$package-[0-9]*.stone" ! -name '*dbginfo*' ! -name '*devel*' | sort | tail -n 1
}

local_current_rootasrole_stone() {
  find "$LOCAL_REPO_DIR" -maxdepth 1 \
    -name "rootasrole-[0-9]*-$ROOTASROLE_RELEASE-*.stone" \
    ! -name '*dbginfo*' ! -name '*devel*' | sort | tail -n 1
}

check_no_stale_policy_package() {
  if find "$STONE_DIR" "$LOCAL_REPO_DIR" -maxdepth 1 -name 'rootasrole-policy-*.stone' | grep -q .; then
    die "stale rootasrole-policy stone remains; run: make phase 512"
  fi

  if [[ -f "$LOCAL_REPO_DIR/stone.index" ]] &&
      grep -a 'rootasrole-policy' "$LOCAL_REPO_DIR/stone.index" >/dev/null 2>&1; then
    die "local repo index still mentions rootasrole-policy; run: make phase 512"
  fi
}

cleanup_stale_policy_package() {
  safe_artifact_path "$STONE_DIR"
  safe_artifact_path "$LOCAL_REPO_DIR"

  rm -f \
    "$STONE_DIR"/rootasrole-policy-*.stone \
    "$STONE_DIR"/rootasrole-policy-dbginfo-*.stone \
    "$STONE_DIR"/rootasrole-policy-devel-*.stone \
    "$LOCAL_REPO_DIR"/rootasrole-policy-*.stone \
    "$LOCAL_REPO_DIR"/rootasrole-policy-dbginfo-*.stone \
    "$LOCAL_REPO_DIR"/rootasrole-policy-devel-*.stone

  if [[ -d "$LOCAL_REPO_DIR" ]]; then
    "$HOST_MOSS" index "$LOCAL_REPO_DIR" >/dev/null
  fi
}

check_source_files() {
  [[ -f "$ONIX_ROOT/packages/core/rootasrole/PACKAGE.md" ]] \
    || die "missing rootasrole package contract"
  [[ -f "$ONIX_ROOT/packages/core/rootasrole/stone.yaml.in" ]] \
    || die "missing rootasrole recipe"
  [[ -f "$ONIX_ROOT/vm/phase5/docs/512_rootasrole_integrated_policy.md" ]] \
    || die "missing Phase 512 doc page"

  grep -q '/usr/share/factory/etc/security/rootasrole.json' \
    "$ONIX_ROOT/packages/core/rootasrole/PACKAGE.md" \
    || die "rootasrole package doc does not describe integrated factory policy"
  grep -q '/usr/share/factory/etc/security/rootasrole.json' \
    "$ONIX_ROOT/packages/core/rootasrole/stone.yaml.in" \
    || die "rootasrole recipe does not install integrated factory policy"
  grep -q 'rootasrole' "$ONIX_ROOT/packages/STONES.md" \
    || die "packages/STONES.md does not list rootasrole"

  if grep -q 'rootasrole-policy' "$ONIX_ROOT/packages/STONES.md"; then
    die "packages/STONES.md still lists rootasrole-policy"
  fi
  if [[ -e "$ONIX_ROOT/packages/services/rootasrole-policy" ]]; then
    die "rootasrole-policy package directory still exists"
  fi
}

prove_installed_policy() {
  [[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"
  [[ -f "$LOCAL_REPO_DIR/stone.index" ]] \
    || die "missing local repo index: ${LOCAL_REPO_DIR#$ONIX_ROOT/}/stone.index (run: make phase 505)"

  local stone
  stone="$(local_current_rootasrole_stone)"
  [[ -n "$stone" ]] || die "missing rootasrole release $ROOTASROLE_RELEASE stone; run: make phase 511"
  "$HOST_MOSS" inspect --check "$stone" >/dev/null

  local root="$PROOF_DIR/moss-root"
  local cache="$PROOF_DIR/moss-cache"
  local target="$PROOF_DIR/install-target"
  local install_log="$PROOF_DIR/moss-install.log"

  rm -rf "$PROOF_DIR"
  mkdir -p "$root" "$cache" "$target"

  "$HOST_MOSS" -D "$root" \
    --cache "$cache" \
    repo add rootasrole \
    "file://$LOCAL_REPO_DIR/stone.index" \
    -c "ONIX Phase 512 integrated RootAsRole policy" >/dev/null
  "$HOST_MOSS" -D "$root" --cache "$cache" repo update >/dev/null

  if ! "$HOST_MOSS" -D "$root" \
      --cache "$cache" \
      -y install --to "$target" \
      rootasrole >"$install_log" 2>&1; then
    cat "$install_log" >&2
    die "Moss could not install rootasrole for integrated policy proof"
  fi

  if grep -q 'duplicate entry:' "$install_log"; then
    cat "$install_log" >&2
    die "rootasrole integrated policy install reported ownership collisions"
  fi

  local root_config="$target/usr/share/factory/etc/security/rootasrole.json"
  local policy="$target/usr/share/factory/etc/security/rootasrole.d/policy.json"
  local pam_sr="$target/usr/share/factory/etc/pam.d/sr"
  local pam_dosr="$target/usr/share/factory/etc/pam.d/dosr"
  local note="$target/usr/share/onix/packages/rootasrole.md"

  [[ -x "$target/usr/bin/dosr" ]] || die "missing dosr from rootasrole install"
  [[ -x "$target/usr/bin/chsr" ]] || die "missing chsr from rootasrole install"
  [[ -f "$root_config" ]] || die "missing integrated rootasrole.json"
  [[ -f "$policy" ]] || die "missing integrated policy.json"
  [[ -f "$pam_sr" ]] || die "missing integrated PAM sr"
  [[ -f "$pam_dosr" ]] || die "missing integrated PAM dosr"
  [[ -f "$note" ]] || die "missing rootasrole package note"

  [[ "$(stat -c '%a' "$root_config")" = "600" ]] \
    || die "rootasrole.json mode is not 600"
  [[ "$(stat -c '%a' "$policy")" = "600" ]] \
    || die "policy.json mode is not 600"

  grep -q '"id": 0' "$policy" || die "integrated policy is missing root actor"
  grep -q '"id": 1000' "$policy" || die "integrated policy is missing onix actor"
  grep -q 'pam_permit.so' "$pam_sr" || die "integrated PAM sr is missing bootstrap PAM rule"
  grep -q '/usr/share/factory/etc/security/rootasrole.json' "$note" \
    || die "rootasrole package note does not describe integrated policy"

  log "proof     : rootasrole owns bootstrap factory policy"
}

run_check() {
  check_source_files
  check_no_stale_policy_package
  prove_installed_policy
  log "phase512  : check OK"
}

run_apply() {
  cleanup_stale_policy_package
  run_check
}

case "$MODE" in
  apply) run_apply ;;
  check) run_check ;;
  rebuild)
    "$SCRIPT_DIR/build-rootasrole.sh" --rebuild
    run_apply
    ;;
  *) die "unknown mode: $MODE" ;;
esac
