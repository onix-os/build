#!/usr/bin/env bash
# vm/phase4/ssh-host-check.sh — host side of Phase 406 SSH proof.
set -euo pipefail

HOST="${ONIX_SSH_HOST:-127.0.0.1}"
PORT="${ONIX_SSH_HOST_PORT:-7626}"
USER="${ONIX_SSH_USER:-onix}"
KEY="${ONIX_SSH_CLIENT_KEY:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/vm/state/id_ed25519}"
MARKER="${ONIX_SSH_MARKER:-ONIX_SSH_OK user=${USER} uid=1000}"
ATTEMPTS="${ONIX_SSH_ATTEMPTS:-30}"

last_output=""

for _ in $(seq 1 "$ATTEMPTS"); do
  last_output="$(
    ssh \
      -i "$KEY" \
      -p "$PORT" \
      -o BatchMode=yes \
      -o PasswordAuthentication=no \
      -o PreferredAuthentications=publickey \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o GlobalKnownHostsFile=/dev/null \
      -o ConnectTimeout=2 \
      -o LogLevel=ERROR \
      "$USER@$HOST" \
      'printf "ONIX_SSH_OK user=$(/bin/id -un) uid=$(/bin/id -u) home=$HOME shell=$SHELL host=$(/bin/hostname) kernel=$(/bin/uname -s)\n"' \
      2>&1 || true
  )"

  if printf '%s\n' "$last_output" | grep -qaE "$MARKER"; then
    printf '%s\n' "$last_output"
    exit 0
  fi

  sleep 1
done

printf '%s\n' "$last_output"
printf 'error: SSH proof marker not observed on %s@%s:%s: %s\n' "$USER" "$HOST" "$PORT" "$MARKER" >&2
exit 1
