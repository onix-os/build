#!/bin/sh
# vm/phase0/provision.sh — runs INSIDE the forge VM (as the build user) to build the
# AerynOS tooling: moss (package/state manager) + boulder (.stone builder).
#
# Baked into the image at /home/<user>/provision.sh. Run it after first boot:
#     ssh -p 6649 mason@127.0.0.1 ./provision.sh      (or: make provision)
# Idempotent-ish: re-running updates the checkout and rebuilds.
set -e

[ -f /etc/onix-forge.env ] && . /etc/onix-forge.env

REPO_URL="${OS_TOOLS_REPO:-https://github.com/AerynOS/os-tools.git}"
REF="${OS_TOOLS_REF:-36f78e5bcfa9d594d65d1c6d2e332e950f3e4d0e}"
SRC="$HOME/src/os-tools"

echo "==> toolchain versions"
rustc --version
cargo --version
just --version || { echo "just missing"; exit 1; }

echo "==> clone/update os-tools"
mkdir -p "$HOME/src"
if [ -d "$SRC/.git" ]; then
    git -C "$SRC" remote set-url origin "$REPO_URL"
    git -C "$SRC" fetch --tags --prune origin
else
    git clone "$REPO_URL" "$SRC"
fi
cd "$SRC"
if ! git rev-parse --verify --quiet "$REF^{commit}" >/dev/null; then
    git fetch origin "$REF"
fi
git checkout --detach "$REF"
echo "==> os-tools pinned at $(git rev-parse --short HEAD)"

echo "==> subuid/subgid (needed for boulder/moss rootless sandbox)"
grep "^$(id -un):" /etc/subuid || echo "  (warning: no subuid entry — rootless builds may fail)"

echo "==> build moss + boulder"
# Prefer the project's own bootstrap; fall back to a plain cargo build.
if just get-started; then
    :
else
    echo "!! 'just get-started' failed — falling back to cargo build --release"
    cargo build --release -p moss -p boulder
    mkdir -p "$HOME/.local/bin"
    cp target/release/moss target/release/boulder "$HOME/.local/bin/"
fi

export PATH="$HOME/.local/bin:$PATH"
echo "==> installed:"
command -v moss    && moss --version    || echo "  moss not on PATH yet (re-login or: export PATH=\$HOME/.local/bin:\$PATH)"
command -v boulder && boulder --version || echo "  boulder not on PATH yet"

echo "==> done. moss + boulder are built. Next: cut a first musl .stone with boulder."
