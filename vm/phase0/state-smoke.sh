#!/usr/bin/env bash
# vm/phase0/state-smoke.sh — final Phase 0 gate: real moss state transactions.
#
# Runs on the host, but all state work happens inside the running forge VM as the
# build user. It uses the hello .stone produced by vm/phase0/build-hello-stone.sh and
# writes only under:
#
#   /home/<build-user>/stone-lab/onix-hello/state-*
#
# This differs from `moss install --to`: here we install into a disposable Moss
# root with `-D`, so Moss creates/activates real states in `.moss`.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=vm/phase0/config.sh
source "$SCRIPT_DIR/config.sh"

user="${1:-$BUILD_USER}"

"$SCRIPT_DIR/ssh.sh" "$user" /bin/sh -s <<'REMOTE'
set -eu

export PATH="$HOME/.local/bin:$PATH"

need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: missing '$1' in the forge. From the host, run: make phase 004" >&2
        exit 1
    fi
}

need_tool moss

LAB="$HOME/stone-lab/onix-hello"
OUT="$LAB/out"
ROOT="$LAB/state-root"
CACHE="$LAB/state-cache"
REPO="$LAB/state-repo"

STONE="$(ls "$OUT"/*.stone 2>/dev/null | head -n 1 || true)"
if [ -z "$STONE" ]; then
    echo "error: no hello .stone found under $OUT" >&2
    echo "hint : from the host, run make phase 005 first" >&2
    exit 1
fi

echo "==> using stone"
echo "$STONE"

echo
echo "==> preparing disposable moss state root"
rm -rf "$ROOT" "$CACHE" "$REPO"
mkdir -p "$ROOT" "$CACHE" "$REPO"
cp "$STONE" "$REPO/"

echo
echo "==> local repo"
moss index "$REPO"
moss -D "$ROOT" --cache "$CACHE" repo add local "file://$REPO/stone.index" -c "local state smoke repo"
moss -D "$ROOT" --cache "$CACHE" repo update
moss -D "$ROOT" --cache "$CACHE" search onix-hello

echo
echo "==> state before install"
moss -D "$ROOT" --cache "$CACHE" state list || true

echo
echo "==> install onix-hello as a real moss state"
moss -D "$ROOT" --cache "$CACHE" -y install onix-hello

echo
echo "==> state after install"
moss -D "$ROOT" --cache "$CACHE" state list
moss -D "$ROOT" --cache "$CACHE" state active | tee "$LAB/state-active-after-install.txt"
grep -q 'State #1 - Install' "$LAB/state-active-after-install.txt"
moss -D "$ROOT" --cache "$CACHE" list installed | tee "$LAB/state-installed-after-install.txt"
grep -q '^onix-hello' "$LAB/state-installed-after-install.txt"
"$ROOT/usr/bin/onix-hello"

echo
echo "==> remove onix-hello as a second moss state"
moss -D "$ROOT" --cache "$CACHE" -y remove onix-hello

echo
echo "==> state after remove"
moss -D "$ROOT" --cache "$CACHE" state list
moss -D "$ROOT" --cache "$CACHE" state active | tee "$LAB/state-active-after-remove.txt"
grep -q 'State #2 - Remove' "$LAB/state-active-after-remove.txt"
if moss -D "$ROOT" --cache "$CACHE" list installed > "$LAB/state-installed-after-remove.txt" 2>&1; then
    echo "error: expected no installed packages after remove" >&2
    cat "$LAB/state-installed-after-remove.txt" >&2
    exit 1
fi
grep -q 'No packages found' "$LAB/state-installed-after-remove.txt"
test ! -e "$ROOT/usr/bin/onix-hello"

echo
echo "==> rollback by activating State #1"
moss -D "$ROOT" --cache "$CACHE" -y state activate 1 --skip-triggers --skip-boot

echo
echo "==> state after rollback"
moss -D "$ROOT" --cache "$CACHE" state active | tee "$LAB/state-active-after-rollback.txt"
grep -q 'State #1 - Install' "$LAB/state-active-after-rollback.txt"
moss -D "$ROOT" --cache "$CACHE" list installed | tee "$LAB/state-installed-after-rollback.txt"
grep -q '^onix-hello' "$LAB/state-installed-after-rollback.txt"
"$ROOT/usr/bin/onix-hello"

echo
echo "==> success"
echo "root : $ROOT"
echo "cache: $CACHE"
echo "repo : $REPO/stone.index"
echo "proof: install -> State #1, remove -> State #2, activate 1 -> rollback"
REMOTE
