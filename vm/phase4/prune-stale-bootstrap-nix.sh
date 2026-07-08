#!/usr/bin/env bash
# vm/phase4/prune-stale-bootstrap-nix.sh — Phase 420 stale payload cleanup.
#
# This wrapper intentionally does not become a new sudoers entrypoint. The
# mounted-image mutation is handled by materialize-etc.sh, the existing
# passwordless Phase 4 rootful script.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

exec "$SCRIPT_DIR/materialize-etc.sh" --prune-stale-bootstrap-nix
