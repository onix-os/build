#!/usr/bin/env bash
# vm/phase4/remote-inspection-host-check.sh — host side of Phase 405 proof.
set -euo pipefail

HOST="${ONIX_REMOTE_INSPECTION_HOST:-127.0.0.1}"
PORT="${ONIX_REMOTE_INSPECTION_HOST_PORT:-7665}"
MARKER="${ONIX_REMOTE_INSPECTION_MARKER:-ONIX_REMOTE_INSPECTION_OK name=ONIX phase=405}"
ATTEMPTS="${ONIX_REMOTE_INSPECTION_ATTEMPTS:-30}"

last_output=""

for _ in $(seq 1 "$ATTEMPTS"); do
  last_output="$(printf 'ONIX_PHASE405_HOST_CHECK\n' | nc -w 2 "$HOST" "$PORT" 2>/dev/null || true)"
  if printf '%s\n' "$last_output" | grep -qaE "$MARKER"; then
    printf '%s\n' "$last_output"
    exit 0
  fi
  sleep 1
done

printf '%s\n' "$last_output"
printf 'error: remote inspection marker not observed on %s:%s: %s\n' "$HOST" "$PORT" "$MARKER" >&2
exit 1
