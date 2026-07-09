#!/usr/bin/env bash
# vm/phase5/audit-stone-payload.sh — runtime-clean ONIX stone payload audit.
#
# This checks a prepared payload directory before ONIX accepts it as a
# canonical system package. It is intentionally strict by default:
#
#   - no /nix/store references
#   - no glibc ELF interpreter
#   - no /nix/store RPATH/RUNPATH
#   - no shared-library NEEDED entries unless explicitly allowed
#
# Nix may build a package during bootstrap. Nix must not own the package at
# runtime.
set -euo pipefail

ALLOW_DYNAMIC_MUSL=0
SELF_TEST=0
PAYLOAD=""
SELF_TEST_TMP=""

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*"
}

usage() {
  cat <<'EOF'
usage: audit-stone-payload.sh [options] PAYLOAD_DIR

Options:
  --allow-dynamic-musl  allow dynamic musl ELF files as a documented exception
  --self-test           run built-in clean/bad fixture tests
  -h, --help

Default ONIX Phase 5 policy is strict:
  Rust-first package choice, musl-only binaries, no runtime /nix/store, and no
  unexpected shared-library dependencies.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-dynamic-musl) ALLOW_DYNAMIC_MUSL=1 ;;
    --self-test) SELF_TEST=1 ;;
    -h|--help) usage; exit 0 ;;
    -*)
      usage >&2
      die "unknown argument: $1"
      ;;
    *)
      [[ -z "$PAYLOAD" ]] || die "only one payload directory may be provided"
      PAYLOAD="$1"
      ;;
  esac
  shift
done

need_tool() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

need_tool find
need_tool grep
need_tool file
need_tool readelf
need_tool sed
need_tool sort
need_tool wc

run_audit() {
  local payload="$1"
  local failures=0
  local file_count=0
  local elf_count=0
  local dynamic_count=0

  [[ -d "$payload" ]] || die "payload directory does not exist: $payload"

  log "ONIX Phase 502 payload audit"
  log "payload   : $payload"
  if [[ "$ALLOW_DYNAMIC_MUSL" -eq 1 ]]; then
    log "mode      : dynamic musl exception allowed"
  else
    log "mode      : strict static/self-contained musl"
  fi

  log "text      : scanning for /nix/store references"
  if grep -R -n -a -F '/nix/store' "$payload" >/tmp/onix-phase502-nix.$$ 2>/dev/null; then
    sed -n '1,80p' /tmp/onix-phase502-nix.$$
    printf 'error: payload contains /nix/store references\n' >&2
    failures=$((failures + 1))
  else
    log "text      : OK, no /nix/store references"
  fi
  rm -f /tmp/onix-phase502-nix.$$

  log "shebang   : scanning executable scripts"
  while IFS= read -r -d '' path; do
    file_count=$((file_count + 1))
    if [[ -f "$path" ]] && head -c 2 "$path" 2>/dev/null | grep -q '^#!'; then
      first_line="$(sed -n '1p' "$path")"
      case "$first_line" in
        *'/nix/store'*)
          printf 'error: Nix shebang: %s: %s\n' "$path" "$first_line" >&2
          failures=$((failures + 1))
          ;;
      esac
    fi
  done < <(find "$payload" -type f -print0)
  log "shebang   : scanned $file_count files"

  log "units     : scanning service units for /nix/store"
  unit_hits=0
  while IFS= read -r -d '' unit; do
    if grep -n -a -F '/nix/store' "$unit" >/tmp/onix-phase502-unit.$$ 2>/dev/null; then
      sed "s|^|$unit:|" /tmp/onix-phase502-unit.$$
      unit_hits=$((unit_hits + 1))
    fi
  done < <(find "$payload" -type f \( -name '*.service' -o -name '*.socket' -o -name '*.timer' -o -name '*.mount' -o -name '*.path' \) -print0)
  rm -f /tmp/onix-phase502-unit.$$
  if [[ "$unit_hits" -gt 0 ]]; then
    printf 'error: systemd unit files mention /nix/store\n' >&2
    failures=$((failures + 1))
  else
    log "units     : OK, no /nix/store in unit files"
  fi

  log "elf       : scanning ELF interpreters and dynamic tags"
  while IFS= read -r -d '' path; do
    file_desc="$(file -b "$path" 2>/dev/null || true)"
    case "$file_desc" in
      ELF*)
        elf_count=$((elf_count + 1))
        program_headers="$(readelf -l "$path" 2>/dev/null || true)"
        dynamic_section="$(readelf -d "$path" 2>/dev/null || true)"

        interp="$(printf '%s\n' "$program_headers" | sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p')"
        if [[ -n "$interp" ]]; then
          case "$interp" in
            /lib/ld-musl-*.so.1|/usr/lib/ld-musl-*.so.1)
              ;;
            /nix/store/*)
              printf 'error: Nix ELF interpreter: %s -> %s\n' "$path" "$interp" >&2
              failures=$((failures + 1))
              ;;
            *ld-linux*|*glibc*)
              printf 'error: glibc ELF interpreter: %s -> %s\n' "$path" "$interp" >&2
              failures=$((failures + 1))
              ;;
            *)
              printf 'error: unknown ELF interpreter: %s -> %s\n' "$path" "$interp" >&2
              failures=$((failures + 1))
              ;;
          esac
        fi

        if printf '%s\n' "$dynamic_section" | grep -E 'RPATH|RUNPATH' >/tmp/onix-phase502-rpath.$$ 2>/dev/null; then
          if grep -F '/nix/store' /tmp/onix-phase502-rpath.$$ >/dev/null 2>&1; then
            sed "s|^|error: Nix RPATH/RUNPATH in $path: |" /tmp/onix-phase502-rpath.$$ >&2
            failures=$((failures + 1))
          fi
        fi
        rm -f /tmp/onix-phase502-rpath.$$

        needed_count="$(printf '%s\n' "$dynamic_section" | grep -c '(NEEDED)' || true)"
        if [[ "$needed_count" -gt 0 ]]; then
          dynamic_count=$((dynamic_count + 1))
          if [[ "$ALLOW_DYNAMIC_MUSL" -eq 0 ]]; then
            printf 'error: dynamic shared-library dependency in strict mode: %s\n' "$path" >&2
            printf '%s\n' "$dynamic_section" | grep '(NEEDED)' >&2 || true
            failures=$((failures + 1))
          fi
        fi
        ;;
    esac
  done < <(find "$payload" -type f -print0)

  log "elf       : scanned $elf_count ELF file(s)"
  log "dynamic   : $dynamic_count ELF file(s) with NEEDED entries"

  if [[ "$failures" -gt 0 ]]; then
    printf 'error: payload audit failed with %s issue(s)\n' "$failures" >&2
    return 1
  fi

  cat <<EOF

==> success
payload audit passed

Summary:
  files scanned : $file_count
  ELF files     : $elf_count
  dynamic ELF   : $dynamic_count
  /nix/store    : none
EOF
}

run_self_test() {
  local clean bad
  SELF_TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/onix-phase502.XXXXXX")"
  trap 'rm -rf "$SELF_TEST_TMP"' EXIT

  clean="$SELF_TEST_TMP/clean"
  bad="$SELF_TEST_TMP/bad"

  mkdir -p "$clean/usr/bin" "$clean/usr/lib/systemd/system"
  cat > "$clean/usr/bin/hello" <<'EOF_CLEAN'
#!/bin/sh
printf 'hello from clean ONIX payload\n'
EOF_CLEAN
  chmod 0755 "$clean/usr/bin/hello"
  cat > "$clean/usr/lib/systemd/system/hello.service" <<'EOF_UNIT'
[Service]
ExecStart=/usr/bin/hello
EOF_UNIT

  mkdir -p "$bad/usr/bin"
  cat > "$bad/usr/bin/bad" <<'EOF_BAD'
#!/nix/store/bad/bin/bash
echo bad
EOF_BAD
  chmod 0755 "$bad/usr/bin/bad"

  log "self-test : clean payload should pass"
  "$0" "$clean" >/dev/null
  log "self-test : bad payload should fail"
  if "$0" "$bad" >/dev/null 2>&1; then
    die "self-test bad payload unexpectedly passed"
  fi
  log "self-test : OK"
}

if [[ "$SELF_TEST" -eq 1 ]]; then
  [[ -z "$PAYLOAD" ]] || die "--self-test does not accept a payload argument"
  run_self_test
  exit 0
fi

[[ -n "$PAYLOAD" ]] || { usage >&2; die "missing payload directory"; }
run_audit "$PAYLOAD"
