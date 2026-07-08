#!/usr/bin/env bash
# vm/phase4/booted-base-ownership-audit.sh — Phase 419 ownership report.
#
# This wrapper intentionally does not become a new sudoers entrypoint. The
# mounted-image inspection is handled by materialize-etc.sh, the existing
# passwordless Phase 4 rootful script.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

exec "$SCRIPT_DIR/materialize-etc.sh" --booted-base-audit
