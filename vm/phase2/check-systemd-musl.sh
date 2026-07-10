#!/usr/bin/env bash
# vm/phase2/check-systemd-musl.sh — Phase 209 systemd-on-musl feasibility gate.
#
# Host-only check. It does not build systemd, mount the image, use sudo, or boot
# QEMU. It asks the pinned nixpkgs whether a musl-targeted systemd derivation is
# present and whether Nix can plan its build graph.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOC="$ONIX_ROOT/vm/phase2/docs/209_systemd_on_musl_feasibility_gate.md"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

need_file() {
  [[ -f "$1" ]] || die "missing expected file: ${1#$ONIX_ROOT/}"
}

need_text() {
  local file="$1"
  local text="$2"
  grep -Fq -- "$text" "$file" || die "missing required text in ${file#$ONIX_ROOT/}: $text"
}

need_cmd grep
need_cmd nix
need_cmd sed
need_file "$ONIX_ROOT/flake.lock"
need_file "$DOC"

echo "==> Phase 209 systemd-on-musl feasibility"

for text in \
  "# Phase 209" \
  "systemd-on-musl" \
  "glibc is not a hard requirement" \
  "musl is still a risk" \
  "-Dlibc=musl" \
  "pkgsMusl.systemd" \
  "systemd-259.3" \
  "musl 1.2.5" \
  "musl >= 1.2.6" \
  "continue systemd-on-musl" \
  "Phase 209 does not build systemd"
do
  need_text "$DOC" "$text"
done
echo "contract : OK (documented in ${DOC#$ONIX_ROOT/})"

read -r -d '' NIX_EXPR <<EOF_NIX || true
let
  lock = builtins.fromJSON (builtins.readFile "$ONIX_ROOT/flake.lock");
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
  flags = pkgs.pkgsMusl.systemd.mesonFlags or [];
in {
  name = pkgs.pkgsMusl.systemd.name;
  version = pkgs.pkgsMusl.systemd.version or "unknown";
  hostLibc = pkgs.pkgsMusl.stdenv.hostPlatform.libc or "unknown";
  muslVersion = pkgs.pkgsMusl.musl.version or "unknown";
  broken = pkgs.pkgsMusl.systemd.meta.broken or false;
  muslFlag = builtins.elem "-Dlibc=musl" flags;
  utmpDisabled = builtins.elem "-Dutmp=false" flags;
  nssSystemdDisabled = builtins.elem "-Dnss-systemd=false" flags;
}
EOF_NIX

read -r -d '' NIX_PKG_EXPR <<EOF_NIX || true
let
  lock = builtins.fromJSON (builtins.readFile "$ONIX_ROOT/flake.lock");
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
in pkgs.pkgsMusl.systemd
EOF_NIX

echo
echo "==> pinned nixpkgs pkgsMusl.systemd metadata"
meta="$(nix eval --impure --json --expr "$NIX_EXPR")"
printf '%s\n' "$meta"

printf '%s\n' "$meta" | grep -q '"hostLibc":"musl"' || die "pkgsMusl.systemd is not targeting musl"
printf '%s\n' "$meta" | grep -q '"muslFlag":true' || die "pkgsMusl.systemd meson flags do not include -Dlibc=musl"
printf '%s\n' "$meta" | grep -q '"broken":false' || die "pkgsMusl.systemd is marked broken"
printf '%s\n' "$meta" | grep -q '"name":"systemd-' || die "pkgsMusl.systemd name was not reported"

echo "metadata : OK (musl-targeted systemd derivation exists and is not marked broken)"

echo
echo "==> dry-run build graph"
dry_log="$(mktemp "${TMPDIR:-/tmp}/onix-systemd-musl-dry.XXXXXX")"
trap 'rm -f "$dry_log"' EXIT
if timeout 60s nix build --dry-run --impure --expr "$NIX_PKG_EXPR" >"$dry_log" 2>&1; then
  if grep -E 'derivations? will be built|path will be fetched|will be fetched' "$dry_log" | sed -n '1,3p'; then
    :
  else
    sed -n '1,3p' "$dry_log"
  fi
else
  sed -n '1,120p' "$dry_log" >&2
  die "Nix could not plan pkgsMusl.systemd build graph"
fi

echo "dry-run  : OK (Nix can plan pkgsMusl.systemd; no build was performed)"

echo
echo "==> result"
echo "systemd-on-musl is feasible enough to keep probing, but not proven boot-ready."
