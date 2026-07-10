#!/usr/bin/env bash
# vm/phase5/build-rootasrole-policy.sh — Phase 512.
#
# Builds the first live ONIX RootAsRole policy stone.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHASE0_DIR="$(cd "$SCRIPT_DIR/../phase0" && pwd)"

# shellcheck source=vm/phase0/config.sh
source "$PHASE0_DIR/config.sh"

user="$BUILD_USER"

MODE="apply"
FORCE_REBUILD="${ONIX_PHASE512_REBUILD:-0}"

STONE_DIR="${ONIX_STONE_DIR:-$ONIX_ROOT/artifacts/onix-stones}"
LOCAL_REPO_DIR="${ONIX_LOCAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-local-repo}"
STONE_WORK_DIR="${ONIX_STONE_WORK_DIR:-$ONIX_ROOT/artifacts/onix-stone-work}"
WORK="${ONIX_PHASE512_WORK_DIR:-$STONE_WORK_DIR/onix-rootasrole-policy}"
HOST_MOSS="${ONIX_HOST_MOSS:-$ONIX_ROOT/artifacts/host-tools/bin/moss}"
RECIPE_TEMPLATE="${ONIX_ROOTASROLE_POLICY_RECIPE_TEMPLATE:-$ONIX_ROOT/packages/services/onix-rootasrole-policy/stone.yaml.in}"
PROOF_DIR="$ONIX_ROOT/artifacts/onix-phase5-work/512"
POLICY_VERSION="${ONIX_ROOTASROLE_POLICY_VERSION:-0.1.0}"

LAB="/home/$user/stone-lab/onix-rootasrole-policy"

usage() {
  cat <<'EOF'
usage: build-rootasrole-policy.sh [--apply|--check|--rebuild]

--apply    build missing onix-rootasrole-policy stone, audit it, and refresh
           the local ONIX repo
--check    verify metadata and inspect/audit the existing policy stone
--rebuild  force rebuilding/rechecking the Phase 512 policy stone
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

host_stone_for() {
  local package="$1"
  find "$STONE_DIR" -maxdepth 1 -name "$package-*.stone" ! -name '*dbginfo*' ! -name '*devel*' | sort | tail -n 1
}

local_stone_for() {
  local package="$1"
  find "$LOCAL_REPO_DIR" -maxdepth 1 -name "$package-*.stone" ! -name '*dbginfo*' ! -name '*devel*' | sort | tail -n 1
}

check_source_files() {
  [[ -f "$RECIPE_TEMPLATE" ]] || die "missing recipe template: ${RECIPE_TEMPLATE#$ONIX_ROOT/}"
  [[ -f "$ONIX_ROOT/packages/services/onix-rootasrole-policy/PACKAGE.md" ]] \
    || die "missing onix-rootasrole-policy PACKAGE.md"
  [[ -f "$ONIX_ROOT/vm/phase5/docs/512_rootasrole_policy_stone.md" ]] || die "missing Phase 512 doc page"
  grep -q 'onix-rootasrole-policy' "$ONIX_ROOT/packages/STONES.md"
  grep -q '/etc/security/rootasrole.json' "$ONIX_ROOT/packages/services/onix-rootasrole-policy/PACKAGE.md"
}

require_dependency_stones() {
  local package
  for package in rootasrole linux-pam musl libseccomp libgcc-runtime; do
    [[ -n "$(local_stone_for "$package")" ]] \
      || die "missing $package in ${LOCAL_REPO_DIR#$ONIX_ROOT/}; run previous phases first"
  done
}

write_payload() {
  local payload_root="$1"

  install -dm00755 \
    "$payload_root/usr/share/factory/etc/security" \
    "$payload_root/usr/share/factory/etc/pam.d" \
    "$payload_root/usr/share/onix/packages"

  cat > "$payload_root/usr/share/factory/etc/security/rootasrole.json" <<'EOF_JSON'
{
    "version": "4.0.0",
    "roles": [
        {
            "name": "r_onix_root_bootstrap",
            "actors": [
                {
                    "type": "user",
                    "name": "root"
                }
            ],
            "tasks": [
                {
                    "options": {
                        "workdir": {
                            "default": "all"
                        },
                        "env": {
                            "override_behavior": true
                        }
                    },
                    "name": "t_root",
                    "purpose": "bootstrap root-only administrative access",
                    "cred": {
                        "setuid": {
                            "fallback": "root",
                            "default": "all"
                        },
                        "setgid": {
                            "fallback": "root",
                            "default": "all"
                        },
                        "capabilities": {
                            "default": "all",
                            "sub": ["CAP_LINUX_IMMUTABLE"]
                        }
                    },
                    "commands": "all"
                },
                {
                    "name": "t_chsr",
                    "purpose": "root-only RootAsRole policy editing",
                    "cred": {
                        "setuid": "root",
                        "setgid": "root",
                        "capabilities": ["CAP_LINUX_IMMUTABLE"]
                    },
                    "commands": ["/usr/bin/chsr ^.*$"]
                }
            ]
        }
    ]
}
EOF_JSON

  cat > "$payload_root/usr/share/factory/etc/pam.d/dosr" <<'EOF_PAM'
#%PAM-1.0
# ONIX Phase 512 bootstrap policy.
#
# PAM is permissive here because RootAsRole policy is the real authorization
# gate and currently contains only the root actor. Do not add normal users to
# /etc/security/rootasrole.json casually.
auth      required   pam_permit.so
account   required   pam_permit.so
session   required   pam_permit.so
EOF_PAM

  cat > "$payload_root/usr/share/onix/packages/onix-rootasrole-policy.md" <<EOF_DOC
# onix-rootasrole-policy

Phase 512 live RootAsRole policy package.

Installed factory policy:

\`\`\`text
/usr/share/factory/etc/security/rootasrole.json
/usr/share/factory/etc/pam.d/dosr
\`\`\`

Bootstrap rule:

\`\`\`text
Only root is a RootAsRole actor.
\`\`\`

This package intentionally does not grant the default ONIX login user full
administrative rights yet.
EOF_DOC

  chmod 00600 "$payload_root/usr/share/factory/etc/security/rootasrole.json"
  chmod 00644 "$payload_root/usr/share/factory/etc/pam.d/dosr"
  chmod 00644 "$payload_root/usr/share/onix/packages/onix-rootasrole-policy.md"
}

prove_host_install_and_audit() {
  [[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"

  local root="$PROOF_DIR/moss-root"
  local cache="$PROOF_DIR/moss-cache"
  local target="$PROOF_DIR/install-target"
  local install_log="$PROOF_DIR/moss-install.log"

  rm -rf "$PROOF_DIR"
  mkdir -p "$root" "$cache" "$target"

  "$HOST_MOSS" -D "$root" \
    --cache "$cache" \
    repo add onix-rootasrole-policy \
    "file://$LOCAL_REPO_DIR/stone.index" \
    -c "ONIX Phase 512 RootAsRole policy" >/dev/null

  "$HOST_MOSS" -D "$root" --cache "$cache" repo update >/dev/null

  if ! "$HOST_MOSS" -D "$root" \
      --cache "$cache" \
      -y install --to "$target" \
      onix-rootasrole-policy >"$install_log" 2>&1; then
    cat "$install_log" >&2
    die "Moss could not install onix-rootasrole-policy and dependencies"
  fi

  if grep -q 'duplicate entry:' "$install_log"; then
    cat "$install_log" >&2
    die "RootAsRole policy install reported package path ownership collisions"
  fi

  [[ -x "$target/usr/bin/dosr" ]] || die "policy did not pull rootasrole/dosr"
  local factory_policy="$target/usr/share/factory/etc/security/rootasrole.json"
  local factory_pam="$target/usr/share/factory/etc/pam.d/dosr"

  [[ -f "$factory_policy" ]] || die "missing factory rootasrole.json"
  [[ -f "$factory_pam" ]] || die "missing factory PAM policy"
  [[ "$(stat -c '%a' "$factory_policy")" = "600" ]] \
    || die "rootasrole.json must be mode 600"

  grep -q '"name": "root"' "$factory_policy"
  if grep -q 'ROOTADMINISTRATOR\|"name": "onix"' "$factory_policy"; then
    die "bootstrap RootAsRole policy must not grant ROOTADMINISTRATOR/onix"
  fi
  grep -q 'pam_permit.so' "$factory_pam"

  if grep -R -F /nix/store \
      "$factory_policy" \
      "$factory_pam" \
      "$target/usr/share/onix/packages/onix-rootasrole-policy.md" >/dev/null 2>&1; then
    die "policy payload contains /nix/store reference"
  fi

  log "proof     : host Moss install + live RootAsRole policy audit OK"
}

run_check() {
  check_source_files
  require_dependency_stones
  [[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"

  local stone
  stone="$(local_stone_for onix-rootasrole-policy)"
  if [[ -z "$stone" ]]; then
    log "stone     : onix-rootasrole-policy not built yet"
    log "phase512  : check OK"
    return
  fi

  "$HOST_MOSS" inspect --check "$stone" >/dev/null
  log "stone     : ${stone#$ONIX_ROOT/}"
  prove_host_install_and_audit
  log "phase512  : check OK"
}

run_apply() {
  need_cmd cp
  need_cmd install
  need_cmd sed
  need_cmd sha256sum
  need_cmd tar

  safe_artifact_path "$STONE_DIR"
  safe_artifact_path "$LOCAL_REPO_DIR"
  safe_artifact_path "$STONE_WORK_DIR"
  safe_artifact_path "$WORK"

  check_source_files
  require_dependency_stones
  [[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"

  local existing
  existing="$(local_stone_for onix-rootasrole-policy)"
  if [[ "$FORCE_REBUILD" != "1" && -n "$existing" ]]; then
    log "Phase 512 RootAsRole policy stone already exists"
    run_check
    return
  fi

  mkdir -p "$STONE_DIR" "$LOCAL_REPO_DIR" "$STONE_WORK_DIR"
  rm -rf "$WORK"
  mkdir -p "$WORK"

  local payload_name payload_root payload_archive payload_sha payload_url
  payload_name="onix-rootasrole-policy-payload-$POLICY_VERSION"
  payload_root="$WORK/$payload_name"
  payload_archive="$WORK/$payload_name.tar.gz"

  log "Phase 512 RootAsRole live policy"
  log "policy    : root actor only"
  log "stone out : ${STONE_DIR#$ONIX_ROOT/}"
  log "local repo: ${LOCAL_REPO_DIR#$ONIX_ROOT/}"

  write_payload "$payload_root"
  tar -C "$WORK" -czf "$payload_archive" "$payload_name"
  payload_sha="$(sha256sum "$payload_archive" | awk '{print $1}')"
  payload_url="file://$LAB/$(basename "$payload_archive")"

  sed \
    -e "s|@ONIX_ROOTASROLE_POLICY_VERSION@|$POLICY_VERSION|g" \
    -e "s|@ONIX_ROOTASROLE_POLICY_PAYLOAD_URL@|$payload_url|g" \
    -e "s|@ONIX_ROOTASROLE_POLICY_PAYLOAD_SHA256@|$payload_sha|g" \
    "$RECIPE_TEMPLATE" > "$WORK/stone.yaml"

  log "copying policy payload + recipe into the forge"
  tar -cf - \
    -C "$WORK" "$(basename "$payload_archive")" stone.yaml \
    | "$PHASE0_DIR/ssh.sh" "$user" "rm -rf '$LAB' && mkdir -p '$LAB' && tar -C '$LAB' -xf -"

  "$PHASE0_DIR/ssh.sh" "$user" /bin/sh -s <<'REMOTE'
set -eu

export PATH="$HOME/.local/bin:$PATH"

need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: missing '$1' in the forge" >&2
        exit 1
    fi
}

need_tool boulder
need_tool moss
need_tool tar

LAB="$HOME/stone-lab/onix-rootasrole-policy"
OUT="$LAB/out"

rm -rf "$OUT"
mkdir -p "$OUT"
(
    cd "$LAB"
    boulder build -y --normal-priority -o "$OUT" stone.yaml
)

stone="$(find "$OUT" -maxdepth 1 -name 'onix-rootasrole-policy-*.stone' ! -name '*dbginfo*' ! -name '*devel*' | sort | head -n 1)"
test -f "$stone"
printf '%s\n' "$stone" > "$LAB/stone.path"
moss inspect --check "$stone"

echo "==> success"
echo "onix-rootasrole-policy stone: $stone"
REMOTE

  log "copying built stone back to host artifacts"
  rm -f \
    "$STONE_DIR"/onix-rootasrole-policy-*.stone \
    "$STONE_DIR"/onix-rootasrole-policy-dbginfo-*.stone \
    "$STONE_DIR"/onix-rootasrole-policy-devel-*.stone

  local remote_stone host_stone
  remote_stone="$("$PHASE0_DIR/ssh.sh" "$user" "cat '$LAB/stone.path'")"
  "$PHASE0_DIR/ssh.sh" "$user" "cd \"\$(dirname '$remote_stone')\" && tar -cf - \"\$(basename '$remote_stone')\"" \
    | tar -C "$STONE_DIR" -xf -

  host_stone="$(host_stone_for onix-rootasrole-policy)"
  [[ -f "$host_stone" ]] || die "failed to copy onix-rootasrole-policy stone into ${STONE_DIR#$ONIX_ROOT/}"

  "$HOST_MOSS" inspect --check "$host_stone" >/dev/null

  log "refreshing local Phase 5 moss repo"
  rm -f \
    "$LOCAL_REPO_DIR"/onix-rootasrole-policy-*.stone \
    "$LOCAL_REPO_DIR"/onix-rootasrole-policy-dbginfo-*.stone \
    "$LOCAL_REPO_DIR"/onix-rootasrole-policy-devel-*.stone
  cp "$host_stone" "$LOCAL_REPO_DIR/"
  "$HOST_MOSS" index "$LOCAL_REPO_DIR"

  prove_host_install_and_audit

  cat <<EOF_SUCCESS

==> success
onix-rootasrole-policy stone: ${host_stone#$ONIX_ROOT/}
local repo index             : ${LOCAL_REPO_DIR#$ONIX_ROOT/}/stone.index

Phase 512 packaged the first RootAsRole policy source as a package-owned
/usr/share/factory/etc payload. Normal users are not granted privilege yet.
EOF_SUCCESS
}

case "$MODE" in
  apply) run_apply ;;
  check) run_check ;;
  *) die "unknown mode: $MODE" ;;
esac
