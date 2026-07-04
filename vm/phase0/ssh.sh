#!/usr/bin/env bash
# vm/phase0/ssh.sh — SSH into the running forge via the forwarded port + generated key.
#   ./ssh.sh                 shell as the build user (mason)
#   ./ssh.sh root            shell as root
#   ./ssh.sh mason ./provision.sh   run a command instead of a shell
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

need_cmd ssh
user="${1:-$BUILD_USER}"; shift || true

key_args=()
[[ -f "$SSH_KEY" ]] && key_args=(-i "$SSH_KEY" -o IdentitiesOnly=yes)

# Disposable guest: don't pin/patch host keys (they change on every rebuild).
exec ssh \
  -F /dev/null \
  -p "$SSH_PORT" \
  "${key_args[@]}" \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR \
  "$user@127.0.0.1" "$@"
