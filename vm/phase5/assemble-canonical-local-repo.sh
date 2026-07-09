#!/usr/bin/env bash
# vm/phase5/assemble-canonical-local-repo.sh — Phase 505 canonical local repo.
#
# Phase 505 collects the current canonical essential ONIX stones into one local
# repository layout. It does not upload anything. It is the local shape that a
# later publishing phase can rsync/sync to repo.onix-os.com.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOST_MOSS="${ONIX_HOST_MOSS:-$ONIX_ROOT/artifacts/host-tools/bin/moss}"

CHANNEL="${ONIX_REPO_CHANNEL:-unstable}"
ARCH="${ONIX_REPO_ARCH:-x86_64}"

REPO_ROOT="${ONIX_CANONICAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-repo}"
REPO_DIR="$REPO_ROOT/$CHANNEL/$ARCH"
WORK_ROOT="${ONIX_CANONICAL_REPO_WORK_DIR:-$ONIX_ROOT/artifacts/onix-repo-work}"
STRICT_OWNERSHIP="${ONIX_REPO_STRICT_OWNERSHIP:-0}"

BASE_SOURCE_DIR="${ONIX_PHASE505_BASE_REPO:-$ONIX_ROOT/artifacts/onix-publish/$CHANNEL/$ARCH}"
RUNTIME_SOURCE_DIR="${ONIX_PHASE505_RUNTIME_REPO:-$ONIX_ROOT/artifacts/onix-local-repo}"

MODE="assemble"

REQUIRED_PACKAGES=(
  onix-branding
  onix-filesystem
  onix-busybox
  onix-dropbear
  onix-systemd
  onix-bootstrap-policy
)

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
usage: assemble-canonical-local-repo.sh [--assemble|--check]

--assemble  copy canonical essential stones into artifacts/onix-repo, index
            them, write metadata/checksums, and prove installability
--check     verify an existing artifacts/onix-repo tree

The repo is local only. A later phase will define publication/hosting.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --assemble) MODE="assemble" ;;
    --check) MODE="check" ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
  shift
done

cd "$ONIX_ROOT"
shopt -s nullglob

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

need_file() {
  [[ -f "$1" ]] || die "missing expected file: $(rel "$1")"
}

need_dir() {
  [[ -d "$1" ]] || die "missing expected directory: $(rel "$1")"
}

need_host_moss() {
  [[ -x "$HOST_MOSS" ]] || die "missing host moss: $(rel "$HOST_MOSS") (run: make phase 202)"
}

package_contract_path() {
  case "$1" in
    onix-branding) printf '%s\n' "packages/base/onix-branding/PACKAGE.md" ;;
    onix-filesystem) printf '%s\n' "packages/base/onix-filesystem/PACKAGE.md" ;;
    onix-busybox) printf '%s\n' "packages/core/onix-busybox/PACKAGE.md" ;;
    onix-dropbear) printf '%s\n' "packages/services/onix-dropbear/PACKAGE.md" ;;
    onix-systemd) printf '%s\n' "packages/services/onix-systemd/PACKAGE.md" ;;
    onix-bootstrap-policy) printf '%s\n' "packages/services/onix-bootstrap-policy/PACKAGE.md" ;;
    *) die "unknown package contract mapping: $1" ;;
  esac
}

package_source_dir() {
  case "$1" in
    onix-branding|onix-filesystem) printf '%s\n' "$BASE_SOURCE_DIR" ;;
    onix-busybox|onix-dropbear|onix-systemd|onix-bootstrap-policy) printf '%s\n' "$RUNTIME_SOURCE_DIR" ;;
    *) die "unknown package source mapping: $1" ;;
  esac
}

select_one_stone() {
  local package="$1"
  local source_dir="$2"
  local matches=("$source_dir/$package"-*.stone)

  if [[ "${#matches[@]}" -ne 1 ]]; then
    printf 'searched: %s/%s-*.stone\n' "$(rel "$source_dir")" "$package" >&2
    printf 'found   : %s\n' "${#matches[@]}" >&2
    if [[ "${#matches[@]}" -gt 0 ]]; then
      printf 'matches :\n' >&2
      printf '  %s\n' "${matches[@]#$ONIX_ROOT/}" >&2
    fi
    die "expected exactly one stone for $package"
  fi

  printf '%s\n' "${matches[0]}"
}

check_inputs() {
  log "Phase 505 canonical local repo inputs"
  log "base repo : $(rel "$BASE_SOURCE_DIR")"
  log "local repo: $(rel "$RUNTIME_SOURCE_DIR")"

  need_dir "$BASE_SOURCE_DIR"
  need_dir "$RUNTIME_SOURCE_DIR"
  need_file "$BASE_SOURCE_DIR/stone.index"
  need_file "$RUNTIME_SOURCE_DIR/stone.index"

  local package contract source stone
  for package in "${REQUIRED_PACKAGES[@]}"; do
    contract="$(package_contract_path "$package")"
    source="$(package_source_dir "$package")"
    need_file "$contract"
    stone="$(select_one_stone "$package" "$source")"
    "$HOST_MOSS" inspect --check "$stone" >/dev/null
    log "stone     : $(rel "$stone")"
  done
}

write_metadata() {
  local root="$1"
  local repo="$2"

  cat > "$root/repo.json" <<EOF_JSON
{
  "name": "ONIX",
  "id": "onix",
  "channel": "$CHANNEL",
  "architecture": "$ARCH",
  "phase": "505",
  "homepage": "https://onix-os.com",
  "source": "https://github.com/onix-os",
  "repo_url_hint": "https://repo.onix-os.com/$CHANNEL/$ARCH/stone.index",
  "local_index": "$REPO_DIR/stone.index",
  "package_root": "packages/"
}
EOF_JSON

  cat > "$root/README.txt" <<EOF_README
ONIX canonical local package repo

Phase: 505
Channel: $CHANNEL
Architecture: $ARCH

Local test index:
  file://$REPO_DIR/stone.index

Future public index:
  https://repo.onix-os.com/$CHANNEL/$ARCH/stone.index

Purpose:
  This tree collects the current canonical essential ONIX stones into one
  local Moss repository. It is not uploaded by Phase 505.

Files:
  repo.json                         repo metadata for humans/tools
  $CHANNEL/$ARCH/stone.index        Moss index
  $CHANNEL/$ARCH/SHA256SUMS         checksums for stones, index, and manifest
  $CHANNEL/$ARCH/MANIFEST.tsv       package-to-stone source manifest
  $CHANNEL/$ARCH/*.stone            package payloads
EOF_README

  if grep -n 'O[n]ix' "$root/repo.json" "$root/README.txt" "$repo/MANIFEST.tsv"; then
    die "forbidden mixed-case branding found in generated repo metadata"
  fi
}

assemble_repo() {
  need_cmd sha256sum
  need_cmd sort
  need_cmd find
  need_cmd grep
  need_cmd awk
  need_cmd cp
  need_host_moss

  check_inputs

  local parent tmp tmp_repo manifest package source contract stone stone_name
  parent="$(dirname "$REPO_ROOT")"
  mkdir -p "$parent"
  tmp="$(mktemp -d "$parent/.onix-repo.XXXXXX")"
  tmp_repo="$tmp/$CHANNEL/$ARCH"
  manifest="$tmp_repo/MANIFEST.tsv"

  cleanup() {
    rm -rf "$tmp"
  }
  trap cleanup EXIT

  mkdir -p "$tmp_repo"
  printf 'package\tstone\tsource_repo\tpackage_contract\n' > "$manifest"

  log "assembling: $(rel "$REPO_ROOT")"
  for package in "${REQUIRED_PACKAGES[@]}"; do
    source="$(package_source_dir "$package")"
    contract="$(package_contract_path "$package")"
    stone="$(select_one_stone "$package" "$source")"
    stone_name="$(basename "$stone")"
    cp "$stone" "$tmp_repo/$stone_name"
    printf '%s\t%s\t%s\t%s\n' \
      "$package" \
      "$stone_name" \
      "$(rel "$source")" \
      "$contract" >> "$manifest"
  done

  "$HOST_MOSS" index "$tmp_repo"
  need_file "$tmp_repo/stone.index"

  write_metadata "$tmp" "$tmp_repo"

  (
    cd "$tmp_repo"
    sha256sum *.stone stone.index MANIFEST.tsv > SHA256SUMS
    sha256sum -c SHA256SUMS >/dev/null
  )

  rm -rf "$REPO_ROOT"
  mv "$tmp" "$REPO_ROOT"
  trap - EXIT

  verify_repo
  prove_install

  cat <<EOF_SUCCESS

==> success
canonical repo root : $(rel "$REPO_ROOT")
canonical repo index: $(rel "$REPO_DIR")/stone.index
manifest            : $(rel "$REPO_DIR")/MANIFEST.tsv
future public index : https://repo.onix-os.com/$CHANNEL/$ARCH/stone.index

Phase 505 assembled one local ONIX repo from the canonical essential package set.
EOF_SUCCESS
}

verify_manifest() {
  local manifest="$REPO_DIR/MANIFEST.tsv"
  need_file "$manifest"

  local package count stone_name
  for package in "${REQUIRED_PACKAGES[@]}"; do
    count="$(awk -F '\t' -v package="$package" '$1 == package { count++ } END { print count + 0 }' "$manifest")"
    [[ "$count" -eq 1 ]] || die "manifest must contain exactly one row for $package, found $count"

    stone_name="$(awk -F '\t' -v package="$package" '$1 == package { print $2 }' "$manifest")"
    need_file "$REPO_DIR/$stone_name"
  done
}

verify_repo() {
  need_cmd sha256sum
  need_cmd find
  need_cmd grep
  need_cmd awk
  need_host_moss

  log "verifying : $(rel "$REPO_ROOT")"
  need_file "$REPO_ROOT/README.txt"
  need_file "$REPO_ROOT/repo.json"
  need_file "$REPO_DIR/stone.index"
  need_file "$REPO_DIR/SHA256SUMS"
  need_file "$REPO_DIR/MANIFEST.tsv"

  grep -q '"name": "ONIX"' "$REPO_ROOT/repo.json"
  grep -q '"id": "onix"' "$REPO_ROOT/repo.json"
  grep -q '"phase": "505"' "$REPO_ROOT/repo.json"
  grep -q '"package_root": "packages/"' "$REPO_ROOT/repo.json"

  if grep -n 'O[n]ix' "$REPO_ROOT/README.txt" "$REPO_ROOT/repo.json" "$REPO_DIR/MANIFEST.tsv"; then
    die "forbidden mixed-case branding found in canonical repo metadata"
  fi

  local stone_count
  stone_count="$(find "$REPO_DIR" -maxdepth 1 -type f -name '*.stone' | wc -l)"
  [[ "$stone_count" -eq "${#REQUIRED_PACKAGES[@]}" ]] \
    || die "expected ${#REQUIRED_PACKAGES[@]} stones, found $stone_count"

  verify_manifest

  (
    cd "$REPO_DIR"
    sha256sum -c SHA256SUMS >/dev/null
  )

  local package stone
  for package in "${REQUIRED_PACKAGES[@]}"; do
    stone="$(select_one_stone "$package" "$REPO_DIR")"
    "$HOST_MOSS" inspect --check "$stone" >/dev/null
  done

  log "repo      : checksum + moss integrity OK"
}

prove_install() {
  need_host_moss

  log "proof     : installing all essential packages from canonical local repo"
  rm -rf "$WORK_ROOT"
  mkdir -p "$WORK_ROOT/moss-root" "$WORK_ROOT/moss-cache" "$WORK_ROOT/install-target"

  "$HOST_MOSS" -D "$WORK_ROOT/moss-root" \
    --cache "$WORK_ROOT/moss-cache" \
    repo add onix-canonical-local \
    "file://$REPO_DIR/stone.index" \
    -c "ONIX Phase 505 canonical local repo" >/dev/null

  "$HOST_MOSS" -D "$WORK_ROOT/moss-root" \
    --cache "$WORK_ROOT/moss-cache" \
    repo update >/dev/null

  local install_log="$WORK_ROOT/moss-install.log"
  if ! "$HOST_MOSS" -D "$WORK_ROOT/moss-root" \
      --cache "$WORK_ROOT/moss-cache" \
      -y install --to "$WORK_ROOT/install-target" \
      "${REQUIRED_PACKAGES[@]}" >"$install_log" 2>&1; then
    cat "$install_log" >&2
    die "Moss could not install the essential package set from the canonical repo"
  fi

  if grep -q 'duplicate entry:' "$install_log"; then
    if [[ "$STRICT_OWNERSHIP" = "1" ]]; then
      cat "$install_log" >&2
      die "Moss reported package path collisions in strict ownership mode"
    else
      log "ownership : Moss reported current package path collisions"
      grep 'duplicate entry:' "$install_log" | sed 's/^error: /    /'
      log "ownership : repo is usable; a later package phase must remove these overlaps"
    fi
  fi

  need_file "$WORK_ROOT/install-target/usr/lib/os-release"
  need_file "$WORK_ROOT/install-target/usr/share/onix/filesystem-layout.md"
  need_file "$WORK_ROOT/install-target/usr/bin/busybox"
  need_file "$WORK_ROOT/install-target/usr/sbin/dropbear"
  need_file "$WORK_ROOT/install-target/usr/lib/systemd/systemd"
  need_file "$WORK_ROOT/install-target/usr/share/onix/packages/onix-bootstrap-policy.md"

  grep -q '^NAME="ONIX"$' "$WORK_ROOT/install-target/usr/lib/os-release"
  grep -q '^ID="onix"$' "$WORK_ROOT/install-target/usr/lib/os-release"

  log "proof     : install target OK ($(rel "$WORK_ROOT/install-target"))"
}

case "$MODE" in
  assemble) assemble_repo ;;
  check)
    verify_repo
    prove_install
    ;;
  *) die "unknown mode: $MODE" ;;
esac
