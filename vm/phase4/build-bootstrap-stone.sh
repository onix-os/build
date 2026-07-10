#!/usr/bin/env bash
# vm/phase4/build-bootstrap-stone.sh — Phase 418 bootstrap stone.
#
# This package is deliberately data/policy, not compiled software. It moves the
# bootstrap helper scripts, proof notes, and source copies of bootstrap systemd
# units out of image-assembly heredocs and into a moss-installable .stone.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHASE0_DIR="$(cd "$SCRIPT_DIR/../phase0" && pwd)"

# shellcheck source=vm/phase0/config.sh
source "$PHASE0_DIR/config.sh"

user="${1:-$BUILD_USER}"

STONE_DIR="${ONIX_STONE_DIR:-$ONIX_ROOT/artifacts/onix-stones}"
LOCAL_REPO_DIR="${ONIX_LOCAL_REPO_DIR:-$ONIX_ROOT/artifacts/onix-local-repo}"
STONE_WORK_DIR="${ONIX_STONE_WORK_DIR:-$ONIX_ROOT/artifacts/onix-stone-work}"
RECIPE_TEMPLATE="${ONIX_BOOTSTRAP_RECIPE_TEMPLATE:-${ONIX_BOOTSTRAP_POLICY_RECIPE_TEMPLATE:-}}"
RECIPE_TEMPLATE="${RECIPE_TEMPLATE:-$ONIX_ROOT/packages/services/bootstrap/stone.yaml.in}"
HOST_MOSS="${ONIX_HOST_MOSS:-$ONIX_ROOT/artifacts/host-tools/bin/moss}"
BOOTSTRAP_POLICY_VERSION="${ONIX_BOOTSTRAP_POLICY_VERSION:-0.1.0}"
SERIAL_CONSOLE_TTY="${ONIX_SERIAL_CONSOLE_TTY:-ttyS1}"
SSH_USER="${ONIX_SSH_USER:-onix}"

LAB="/home/$user/stone-lab/bootstrap"

need_cmd awk
need_cmd install
need_cmd sed
need_cmd sha256sum
need_cmd tar

[[ -f "$RECIPE_TEMPLATE" ]] || die "missing recipe template: ${RECIPE_TEMPLATE#$ONIX_ROOT/}"
[[ -x "$HOST_MOSS" ]] || die "missing host moss: ${HOST_MOSS#$ONIX_ROOT/} (run: make phase 202)"

case "$SERIAL_CONSOLE_TTY" in
  ttyS[0-9]*) ;;
  *) die "refusing unsafe serial console tty name: $SERIAL_CONSOLE_TTY" ;;
esac

safe_artifact_path() {
  local path="$1"
  case "$path" in
    "$ONIX_ROOT"/artifacts/*) ;;
    *) die "refusing artifact path outside artifacts/: $path" ;;
  esac
}

safe_artifact_path "$STONE_DIR"
safe_artifact_path "$LOCAL_REPO_DIR"
safe_artifact_path "$STONE_WORK_DIR"

WORK="$STONE_WORK_DIR/bootstrap"
PAYLOAD_NAME="bootstrap-payload-$BOOTSTRAP_POLICY_VERSION"
PAYLOAD_ROOT="$WORK/$PAYLOAD_NAME"
PAYLOAD_ARCHIVE="$WORK/$PAYLOAD_NAME.tar.gz"
BUILD_ENV="$WORK/build.env"

cleanup_work_dir() {
  case "$WORK" in
    "$ONIX_ROOT"/artifacts/onix-stone-work/bootstrap) ;;
    *) die "refusing unsafe work cleanup path: $WORK" ;;
  esac

  if [[ -d "$WORK" ]]; then
    chmod -R u+rwX "$WORK" 2>/dev/null || true
    rm -rf "$WORK"
  fi
}

write_payload() {
  install -dm0755 \
    "$PAYLOAD_ROOT/usr/lib/onix/systemd/system" \
    "$PAYLOAD_ROOT/usr/share/onix/bootstrap" \
    "$PAYLOAD_ROOT/usr/share/onix/packages"

  cat > "$PAYLOAD_ROOT/usr/lib/onix/bootstrap-serial-shell" <<EOF
#!/bin/sh
export PATH=/bin:/usr/bin:/sbin:/usr/sbin
echo
echo "ONIX_BOOTSTRAP_SERIAL_CONSOLE_READY tty=/dev/$SERIAL_CONSOLE_TTY uid=\$(/bin/id -u) shell=/bin/sh"
echo "WARNING: Phase 418 bootstrap console is unauthenticated and temporary."
echo "Type commands here. This is not the final ONIX login design."
echo
exec /bin/sh -l
EOF
  chmod 0755 "$PAYLOAD_ROOT/usr/lib/onix/bootstrap-serial-shell"

  cat > "$PAYLOAD_ROOT/usr/lib/onix/bootstrap-network-up" <<'EOF'
#!/bin/sh
set -eu

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

find_iface() {
  for path in /sys/class/net/*; do
    iface="${path##*/}"
    [ "$iface" = "lo" ] && continue
    [ -e "$path" ] || continue
    printf '%s\n' "$iface"
    return 0
  done
  return 1
}

iface="${ONIX_BOOTSTRAP_NET_IFACE:-}"
if [ -z "$iface" ]; then
  i=0
  while [ "$i" -lt 30 ]; do
    iface="$(find_iface 2>/dev/null || true)"
    [ -n "$iface" ] && break
    i=$((i + 1))
    sleep 1
  done
  if [ -z "$iface" ]; then
    echo "ONIX_NETWORK_ERROR no-non-loopback-interface"
    exit 1
  fi
fi

ip="${ONIX_BOOTSTRAP_NET_IP:-10.0.2.15}"
netmask="${ONIX_BOOTSTRAP_NET_NETMASK:-255.255.255.0}"
router="${ONIX_BOOTSTRAP_NET_ROUTER:-10.0.2.2}"
dns="${ONIX_BOOTSTRAP_NET_DNS:-10.0.2.3}"

mkdir -p /run/onix

/bin/ifconfig lo 127.0.0.1 up || true
/bin/ifconfig "$iface" "$ip" netmask "$netmask" up
/bin/route del default 2>/dev/null || true
/bin/route add default gw "$router" dev "$iface"
rm -f /run/onix/network.env

if [ -n "$dns" ]; then
  : > /run/onix/resolv.conf
  for server in $dns; do
    echo "nameserver $server" >> /run/onix/resolv.conf
  done
fi

{
  echo "method=static-qemu-user"
  echo "interface=$iface"
  echo "ip=$ip"
  echo "subnet=$netmask"
  echo "router=$router"
  echo "dns=$dns"
} > /run/onix/network.env

if [ -s /run/onix/network.env ]; then
  # shellcheck source=/dev/null
  . /run/onix/network.env
  echo "ONIX_BOOTSTRAP_NETWORK_READY iface=$interface ip=$ip router=${router:-none}"
  exit 0
fi

echo "ONIX_NETWORK_ERROR no-runtime-network-state"
exit 1
EOF

  cat > "$PAYLOAD_ROOT/usr/lib/onix/bootstrap-network-status" <<'EOF'
#!/bin/sh
set -eu

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

if [ ! -s /run/onix/network.env ]; then
  echo "ONIX_NETWORK_WAIT no-/run/onix/network.env"
  exit 1
fi

# shellcheck source=/dev/null
. /run/onix/network.env

if [ -z "${interface:-}" ] || [ -z "${ip:-}" ] || [ -z "${router:-}" ]; then
  echo "ONIX_NETWORK_WAIT incomplete-network.env"
  exit 1
fi

if ! /bin/ifconfig "$interface" | /bin/grep -F "$ip" >/dev/null 2>&1; then
  echo "ONIX_NETWORK_WAIT address-not-visible iface=$interface ip=$ip"
  exit 1
fi

if ! /bin/route -n | /bin/awk -v gw="$router" '$1 == "0.0.0.0" && $2 == gw { found=1 } END { exit found ? 0 : 1 }'; then
  echo "ONIX_NETWORK_WAIT default-route-missing router=$router"
  exit 1
fi

echo "ONIX_NETWORK_OK iface=$interface ip=$ip router=$router"
EOF

  cat > "$PAYLOAD_ROOT/usr/lib/onix/bootstrap-network-proof" <<'EOF'
#!/bin/sh
set -eu

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

i=0
while [ "$i" -lt 25 ]; do
  i=$((i + 1))
  if /usr/lib/onix/bootstrap-network-status; then
    exit 0
  fi
  sleep 1
done

echo "ONIX_NETWORK_ERROR status-timeout"
/bin/ifconfig -a || true
/bin/route -n || true
exit 1
EOF

  cat > "$PAYLOAD_ROOT/usr/lib/onix/bootstrap-remote-inspection-response" <<'EOF'
#!/bin/sh
set -eu

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

echo "ONIX_REMOTE_INSPECTION_OK name=ONIX phase=418 uid=$(/bin/id -u) hostname=$(hostname) kernel=$(uname -s)"
EOF

  cat > "$PAYLOAD_ROOT/usr/lib/onix/bootstrap-remote-inspection-status" <<'EOF'
#!/bin/sh
set -eu

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

port="${ONIX_REMOTE_INSPECTION_GUEST_PORT:-6649}"

if /bin/netstat -ltn 2>/dev/null | /bin/grep -E "[.:]${port}[[:space:]]" >/dev/null 2>&1; then
  echo "ONIX_REMOTE_INSPECTION_READY port=$port"
  exit 0
fi

echo "ONIX_REMOTE_INSPECTION_WAIT port=$port"
exit 1
EOF

  cat > "$PAYLOAD_ROOT/usr/lib/onix/bootstrap-remote-inspection-proof" <<'EOF'
#!/bin/sh
set -eu

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

i=0
while [ "$i" -lt 25 ]; do
  i=$((i + 1))
  if /usr/lib/onix/bootstrap-remote-inspection-status; then
    exit 0
  fi
  sleep 1
done

echo "ONIX_REMOTE_INSPECTION_ERROR status-timeout"
/bin/netstat -ltn || true
exit 1
EOF

  cat > "$PAYLOAD_ROOT/usr/lib/onix/bootstrap-ssh-status" <<EOF
#!/bin/sh
set -eu

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

port="\${ONIX_SSH_GUEST_PORT:-22}"
user="\${ONIX_SSH_USER:-$SSH_USER}"

if /bin/netstat -ltn 2>/dev/null | /bin/grep -E "[.:]\${port}[[:space:]]" >/dev/null 2>&1; then
  echo "ONIX_SSH_READY user=\$user port=\$port"
  exit 0
fi

echo "ONIX_SSH_WAIT user=\$user port=\$port"
exit 1
EOF

  cat > "$PAYLOAD_ROOT/usr/lib/onix/bootstrap-ssh-proof" <<'EOF'
#!/bin/sh
set -eu

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

i=0
while [ "$i" -lt 25 ]; do
  i=$((i + 1))
  if /usr/lib/onix/bootstrap-ssh-status; then
    exit 0
  fi
  sleep 1
done

echo "ONIX_SSH_ERROR status-timeout"
/bin/netstat -ltn || true
exit 1
EOF

  chmod 0755 "$PAYLOAD_ROOT"/usr/lib/onix/bootstrap-*

  cat > "$PAYLOAD_ROOT/usr/lib/onix/systemd/system/onix-bootstrap-serial-shell.service" <<EOF
[Unit]
Description=ONIX bootstrap serial root shell on $SERIAL_CONSOLE_TTY
Documentation=file:/usr/share/onix/bootstrap/serial-console.txt
After=systemd-user-sessions.service
Conflicts=serial-getty@$SERIAL_CONSOLE_TTY.service getty@$SERIAL_CONSOLE_TTY.service
ConditionPathExists=/dev/$SERIAL_CONSOLE_TTY

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/root
Environment=HOME=/root
Environment=TERM=vt220
Environment=PATH=/bin:/usr/bin:/sbin:/usr/sbin
ExecStart=/usr/bin/busybox sh /usr/lib/onix/bootstrap-serial-shell
StandardInput=tty-force
StandardOutput=tty
StandardError=tty
TTYPath=/dev/$SERIAL_CONSOLE_TTY
TTYReset=yes
TTYVHangup=no
TTYVTDisallocate=no
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF

  cat > "$PAYLOAD_ROOT/usr/lib/onix/systemd/system/onix-bootstrap-network.service" <<'EOF'
[Unit]
Description=ONIX bootstrap QEMU user networking
Documentation=file:/usr/share/onix/bootstrap/networking.txt
After=systemd-udevd.service systemd-modules-load.service
Before=network.target
Wants=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh /usr/lib/onix/bootstrap-network-up
StandardOutput=journal+console
StandardError=journal+console
TimeoutStartSec=45

[Install]
WantedBy=multi-user.target
EOF

  cat > "$PAYLOAD_ROOT/usr/lib/onix/systemd/system/onix-bootstrap-remote-inspection.service" <<'EOF'
[Unit]
Description=ONIX bootstrap TCP inspection listener
Documentation=file:/usr/share/onix/bootstrap/remote-inspection.txt
After=onix-bootstrap-network.service
Requires=onix-bootstrap-network.service

[Service]
Type=simple
Environment=ONIX_REMOTE_INSPECTION_GUEST_PORT=6649
ExecStart=/bin/nc -lk -p 6649 -e /usr/lib/onix/bootstrap-remote-inspection-response
Restart=always
RestartSec=1
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  cat > "$PAYLOAD_ROOT/usr/lib/onix/systemd/system/onix-bootstrap-dropbear.service" <<EOF
[Unit]
Description=ONIX bootstrap Dropbear SSH server
Documentation=file:/usr/share/onix/bootstrap/dropbear-stone.txt
After=onix-bootstrap-network.service
Requires=onix-bootstrap-network.service

[Service]
Type=simple
Environment=ONIX_SSH_USER=$SSH_USER
Environment=PATH=/bin:/usr/bin:/sbin:/usr/sbin
ExecStart=/usr/sbin/dropbear -F -E -e -m -s -w -j -k -p 0.0.0.0:22 -r /etc/dropbear/dropbear_ed25519_host_key -P /run/dropbear.pid
Restart=always
RestartSec=1
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "$PAYLOAD_ROOT"/usr/lib/onix/systemd/system/*.service

  cat > "$PAYLOAD_ROOT/usr/share/onix/bootstrap/bootstrap.txt" <<EOF
ONIX Phase 418 bootstrap package

Package:

- bootstrap

Policy:

- Bootstrap helper scripts and bootstrap service source units are machine-plane
  policy.
- Machine-plane policy should be carried by moss/.stone packages.
- Phase 418 moves the source of the bootstrap scripts and units into this
  package.
- Image assembly still activates unit copies into the current systemd unit tree.

Package-owned script paths:

- /usr/lib/onix/bootstrap-serial-shell
- /usr/lib/onix/bootstrap-network-up
- /usr/lib/onix/bootstrap-network-status
- /usr/lib/onix/bootstrap-network-proof
- /usr/lib/onix/bootstrap-remote-inspection-response
- /usr/lib/onix/bootstrap-remote-inspection-status
- /usr/lib/onix/bootstrap-remote-inspection-proof
- /usr/lib/onix/bootstrap-ssh-status
- /usr/lib/onix/bootstrap-ssh-proof

Package-owned unit source paths:

- /usr/lib/onix/systemd/system/onix-bootstrap-serial-shell.service
- /usr/lib/onix/systemd/system/onix-bootstrap-network.service
- /usr/lib/onix/systemd/system/onix-bootstrap-remote-inspection.service
- /usr/lib/onix/systemd/system/onix-bootstrap-dropbear.service

Important limitation:

The active unit files are still copied into the current systemd unit tree:

  /usr/lib/systemd/system

That activation copy is still image-assembly glue. The improvement is that the
source files now come from a package instead of shell heredocs.

Bootstrap debt ledger:

- /usr/share/onix/bootstrap/bootstrap-debt.tsv
EOF

  cat > "$PAYLOAD_ROOT/usr/share/onix/bootstrap/bootstrap-debt.tsv" <<'EOF'
item	status	owned_by	next_step
serial-root-shell	bootstrap-only	bootstrap	replace with authenticated login/session policy
static-qemu-network	bootstrap-only	bootstrap	replace after native systemd grows networkd or ONIX packages another network manager
remote-inspection-listener	bootstrap-only	bootstrap	remove before any real user image
dropbear-ssh-bootstrap	bootstrap-access	dropbear+bootstrap	decide final SSH/server access policy
active-unit-copy-glue	bootstrap-only	image-assembly	replace with package preset/trigger activation
EOF

  cat > "$PAYLOAD_ROOT/usr/share/onix/bootstrap/serial-console.txt" <<EOF
ONIX bootstrap serial console

This is temporary bootstrap access for bring-up. It is unauthenticated and not
the final ONIX login design.

The service source is now package-owned by bootstrap.

Proof marker:

ONIX_BOOTSTRAP_SERIAL_CONSOLE_READY

Serial TTY:

/dev/$SERIAL_CONSOLE_TTY
EOF

  cat > "$PAYLOAD_ROOT/usr/share/onix/bootstrap/networking.txt" <<'EOF'
ONIX bootstrap networking

This is the minimal QEMU user-mode networking proof used during Phase 4.

The service source and helper scripts are now package-owned by
bootstrap.

Proof marker:

ONIX_NETWORK_OK iface=<name> ip=10.0.2.15 router=10.0.2.2
EOF

  cat > "$PAYLOAD_ROOT/usr/share/onix/bootstrap/remote-inspection.txt" <<'EOF'
ONIX bootstrap remote inspection

This listener is unauthenticated and temporary inspection glue. It exists only
to prove host-to-guest connectivity before the SSH path is available.

The service source and helper scripts are now package-owned by
bootstrap.

Proof marker:

ONIX_REMOTE_INSPECTION_OK name=ONIX
EOF

  cat > "$PAYLOAD_ROOT/usr/share/onix/bootstrap/ssh.txt" <<EOF
ONIX bootstrap SSH

This is temporary authenticated SSH access for Phase 4 bring-up.

Policy:

- SSH user: $SSH_USER
- root SSH login disabled
- Password authentication is disabled
- public-key authentication only

The status/proof scripts are now package-owned by bootstrap.

Proof marker:

ONIX_SSH_OK user=$SSH_USER uid=1000
EOF

  cat > "$PAYLOAD_ROOT/usr/share/onix/bootstrap/dropbear-stone.txt" <<'EOF'
ONIX Phase 413 dropbear image install

ONIX dropbear bootstrap service policy

The Dropbear binary is owned by dropbear.

The bootstrap service source that starts Dropbear is now owned by
bootstrap.

The active service starts:

/usr/sbin/dropbear
EOF

  chmod 0644 \
    "$PAYLOAD_ROOT"/usr/share/onix/bootstrap/*.txt \
    "$PAYLOAD_ROOT/usr/share/onix/bootstrap/bootstrap-debt.tsv"

  cat > "$PAYLOAD_ROOT/usr/share/onix/packages/bootstrap.md" <<EOF
# bootstrap

\`bootstrap\` is the Phase 418 package-owned source of the
temporary ONIX bootstrap service policy.

Version:

\`\`\`text
$BOOTSTRAP_POLICY_VERSION
\`\`\`

It owns:

- bootstrap helper scripts under \`/usr/lib/onix\`,
- source copies of bootstrap systemd units under \`/usr/lib/onix/systemd/system\`,
- bootstrap proof and explanation notes under \`/usr/share/onix/bootstrap\`,
- a machine-readable bootstrap debt ledger at
  \`/usr/share/onix/bootstrap/bootstrap-debt.tsv\`.

It does not yet remove all image-assembly glue.

The active systemd unit tree is currently:

\`\`\`text
/usr/lib/systemd/system
\`\`\`

Phase 418 copies package-owned unit source files into that active tree. Later
ONIX should make unit activation a normal package-manager/systemd preset flow.
EOF
  chmod 0644 "$PAYLOAD_ROOT/usr/share/onix/packages/bootstrap.md"
}

mkdir -p "$STONE_DIR" "$LOCAL_REPO_DIR" "$STONE_WORK_DIR"
cleanup_work_dir
mkdir -p "$PAYLOAD_ROOT"

log "Phase 418 bootstrap stone"
cat <<EOF
version    : $BOOTSTRAP_POLICY_VERSION
serial tty : $SERIAL_CONSOLE_TTY
ssh user   : $SSH_USER
stone out  : ${STONE_DIR#$ONIX_ROOT/}
local repo : ${LOCAL_REPO_DIR#$ONIX_ROOT/}
EOF

log "staging package-owned bootstrap policy payload"
write_payload

log "verifying staged payload"
test -x "$PAYLOAD_ROOT/usr/lib/onix/bootstrap-serial-shell"
test -x "$PAYLOAD_ROOT/usr/lib/onix/bootstrap-network-up"
test -x "$PAYLOAD_ROOT/usr/lib/onix/bootstrap-ssh-proof"
test -f "$PAYLOAD_ROOT/usr/lib/onix/systemd/system/onix-bootstrap-network.service"
test -f "$PAYLOAD_ROOT/usr/share/onix/bootstrap/bootstrap.txt"
test -f "$PAYLOAD_ROOT/usr/share/onix/bootstrap/bootstrap-debt.tsv"
test -f "$PAYLOAD_ROOT/usr/share/onix/packages/bootstrap.md"
grep -q 'ExecStart=/usr/sbin/dropbear ' \
  "$PAYLOAD_ROOT/usr/lib/onix/systemd/system/onix-bootstrap-dropbear.service"
grep -q ' -m ' \
  "$PAYLOAD_ROOT/usr/lib/onix/systemd/system/onix-bootstrap-dropbear.service"
grep -q 'ONIX_BOOTSTRAP_SERIAL_CONSOLE_READY' \
  "$PAYLOAD_ROOT/usr/lib/onix/bootstrap-serial-shell"
grep -q '^remote-inspection-listener[[:space:]]' \
  "$PAYLOAD_ROOT/usr/share/onix/bootstrap/bootstrap-debt.tsv"

log "creating prepared payload archive"
tar --numeric-owner -C "$WORK" -czf "$PAYLOAD_ARCHIVE" "$PAYLOAD_NAME"
PAYLOAD_HASH="$(sha256sum "$PAYLOAD_ARCHIVE" | awk '{print $1}')"

cat > "$BUILD_ENV" <<EOF
BOOTSTRAP_POLICY_VERSION='$BOOTSTRAP_POLICY_VERSION'
BOOTSTRAP_POLICY_PAYLOAD_ARCHIVE='$(basename "$PAYLOAD_ARCHIVE")'
BOOTSTRAP_POLICY_PAYLOAD_SHA256='$PAYLOAD_HASH'
EOF

log "copying recipe template + prepared payload into the forge"
tar -cf - \
  -C "$WORK" build.env "$(basename "$PAYLOAD_ARCHIVE")" \
  -C "$(dirname "$RECIPE_TEMPLATE")" "$(basename "$RECIPE_TEMPLATE")" \
  | "$PHASE0_DIR/ssh.sh" "$user" "if [ -d '$LAB' ]; then chmod -R u+rwX '$LAB' 2>/dev/null || true; rm -rf '$LAB'; fi && mkdir -p '$LAB/src' && tar -C '$LAB' -xf - && mv '$LAB/$(basename "$PAYLOAD_ARCHIVE")' '$LAB/src/$(basename "$PAYLOAD_ARCHIVE")' && if [ '$LAB/$(basename "$RECIPE_TEMPLATE")' != '$LAB/stone.yaml.in' ]; then mv '$LAB/$(basename "$RECIPE_TEMPLATE")' '$LAB/stone.yaml.in'; fi"

"$PHASE0_DIR/ssh.sh" "$user" /bin/sh -s <<'REMOTE'
set -eu

export PATH="$HOME/.local/bin:$PATH"

need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: missing '$1' in the forge. From the host, run: make phase 004" >&2
        exit 1
    fi
}

need_tool boulder
need_tool moss
need_tool tar
need_tool gzip
need_tool sha256sum
need_tool sed
need_tool grep
need_tool awk
need_tool install

LAB="$HOME/stone-lab/bootstrap"
OUT="$LAB/out"
EXTRACT="$LAB/extracted"
REPO="$LAB/repo"
ROOT="$LAB/moss-root"
CACHE="$LAB/moss-cache"
TARGET="$LAB/install-target"

safe_rm_rf() {
    for path in "$@"; do
        if [ -e "$path" ]; then
            chmod -R u+rwX "$path" 2>/dev/null || true
            rm -rf "$path"
        fi
    done
}

if [ ! -f "$LAB/build.env" ]; then
    echo "error: missing build environment: $LAB/build.env" >&2
    exit 1
fi

# shellcheck disable=SC1091
. "$LAB/build.env"

PAYLOAD_ARCHIVE="$LAB/src/$BOOTSTRAP_POLICY_PAYLOAD_ARCHIVE"
PAYLOAD_HASH="$(sha256sum "$PAYLOAD_ARCHIVE" | awk '{print $1}')"
if [ "$PAYLOAD_HASH" != "$BOOTSTRAP_POLICY_PAYLOAD_SHA256" ]; then
    echo "error: bootstrap policy payload checksum mismatch" >&2
    echo "expected: $BOOTSTRAP_POLICY_PAYLOAD_SHA256" >&2
    echo "actual  : $PAYLOAD_HASH" >&2
    exit 1
fi

sed \
  -e "s|@BOOTSTRAP_POLICY_VERSION@|$BOOTSTRAP_POLICY_VERSION|g" \
  -e "s|@BOOTSTRAP_POLICY_PAYLOAD_URL@|file://$PAYLOAD_ARCHIVE|g" \
  -e "s|@BOOTSTRAP_POLICY_PAYLOAD_SHA256@|$BOOTSTRAP_POLICY_PAYLOAD_SHA256|g" \
  "$LAB/stone.yaml.in" > "$LAB/stone.yaml"

echo "==> recipe"
sed -n '1,240p' "$LAB/stone.yaml"

echo
echo "==> building bootstrap stone"
safe_rm_rf "$OUT"
mkdir -p "$OUT"
(
    cd "$LAB"
    boulder build -y --normal-priority -o "$OUT" stone.yaml
)

STONE="$(find "$OUT" -maxdepth 1 -name 'bootstrap-*.stone' ! -name '*dbginfo*' | sort | head -n 1)"
if [ ! -f "$STONE" ]; then
    echo "error: boulder did not produce a bootstrap .stone under $OUT" >&2
    exit 1
fi
printf '%s\n' "$STONE" > "$LAB/stone.path"

echo
echo "==> built artifact"
ls -lh "$OUT"
file "$STONE"

echo
echo "==> moss integrity check"
moss inspect --check "$STONE"

echo
echo "==> moss layout"
moss inspect "$STONE" | sed -n '1,220p'

echo
echo "==> extract and verify bootstrap policy payload"
safe_rm_rf "$EXTRACT"
mkdir -p "$EXTRACT"
moss extract -o "$EXTRACT" "$STONE"
set -- "$EXTRACT"/*
PAYLOAD="$1"

test -x "$PAYLOAD/usr/lib/onix/bootstrap-serial-shell"
test -x "$PAYLOAD/usr/lib/onix/bootstrap-network-up"
test -x "$PAYLOAD/usr/lib/onix/bootstrap-network-proof"
test -x "$PAYLOAD/usr/lib/onix/bootstrap-remote-inspection-response"
test -x "$PAYLOAD/usr/lib/onix/bootstrap-ssh-proof"
test -f "$PAYLOAD/usr/lib/onix/systemd/system/onix-bootstrap-serial-shell.service"
test -f "$PAYLOAD/usr/lib/onix/systemd/system/onix-bootstrap-network.service"
test -f "$PAYLOAD/usr/lib/onix/systemd/system/onix-bootstrap-remote-inspection.service"
test -f "$PAYLOAD/usr/lib/onix/systemd/system/onix-bootstrap-dropbear.service"
test -f "$PAYLOAD/usr/share/onix/bootstrap/bootstrap.txt"
test -f "$PAYLOAD/usr/share/onix/bootstrap/bootstrap-debt.tsv"
test -f "$PAYLOAD/usr/share/onix/packages/bootstrap.md"
grep -q 'ONIX_BOOTSTRAP_SERIAL_CONSOLE_READY' "$PAYLOAD/usr/lib/onix/bootstrap-serial-shell"
grep -q '^ExecStart=/usr/sbin/dropbear ' "$PAYLOAD/usr/lib/onix/systemd/system/onix-bootstrap-dropbear.service"
grep -q ' -m ' "$PAYLOAD/usr/lib/onix/systemd/system/onix-bootstrap-dropbear.service"
grep -q '^active-unit-copy-glue[[:space:]]' "$PAYLOAD/usr/share/onix/bootstrap/bootstrap-debt.tsv"

echo
echo "==> index local repo and install into disposable target"
safe_rm_rf "$REPO" "$ROOT" "$CACHE" "$TARGET"
mkdir -p "$REPO" "$ROOT" "$CACHE" "$TARGET"
cp "$STONE" "$REPO/"
moss index "$REPO"
moss -D "$ROOT" --cache "$CACHE" repo add local "file://$REPO/stone.index" -c "local ONIX bootstrap repo"
moss -D "$ROOT" --cache "$CACHE" repo update
moss -D "$ROOT" --cache "$CACHE" -y install --to "$TARGET" bootstrap

test -x "$TARGET/usr/lib/onix/bootstrap-serial-shell"
test -f "$TARGET/usr/lib/onix/systemd/system/onix-bootstrap-network.service"
test -f "$TARGET/usr/share/onix/bootstrap/bootstrap.txt"
test -f "$TARGET/usr/share/onix/bootstrap/bootstrap-debt.tsv"
test -f "$TARGET/usr/share/onix/packages/bootstrap.md"
grep -q '^static-qemu-network[[:space:]]' "$TARGET/usr/share/onix/bootstrap/bootstrap-debt.tsv"

echo
echo "==> success"
echo "stone : $STONE"
echo "repo  : $REPO/stone.index"
echo "root  : $ROOT"
echo "target: $TARGET"
REMOTE

log "copying built stone back to host artifacts"
rm -f \
  "$STONE_DIR"/bootstrap-[0-9]*.stone \
  "$STONE_DIR"/bootstrap-dbginfo-*.stone \
  "$STONE_DIR"/bootstrap-policy-*.stone \
  "$STONE_DIR"/bootstrap-policy-dbginfo-*.stone
"$PHASE0_DIR/ssh.sh" "$user" "stone=\$(cat '$LAB/stone.path') && cd \"\$(dirname \"\$stone\")\" && tar -cf - \"\$(basename \"\$stone\")\"" \
  | tar -C "$STONE_DIR" -xf -

HOST_STONE="$(find "$STONE_DIR" -maxdepth 1 -name 'bootstrap-[0-9]*.stone' ! -name '*dbginfo*' | sort | tail -n 1)"
[[ -f "$HOST_STONE" ]] || die "failed to copy bootstrap stone into ${STONE_DIR#$ONIX_ROOT/}"

log "host moss integrity check"
"$HOST_MOSS" inspect --check "$HOST_STONE"

log "refreshing local Phase 4 moss repo"
rm -f \
  "$LOCAL_REPO_DIR"/bootstrap-[0-9]*.stone \
  "$LOCAL_REPO_DIR"/bootstrap-dbginfo-*.stone \
  "$LOCAL_REPO_DIR"/bootstrap-policy-*.stone \
  "$LOCAL_REPO_DIR"/bootstrap-policy-dbginfo-*.stone
cp "$HOST_STONE" "$LOCAL_REPO_DIR/"
"$HOST_MOSS" index "$LOCAL_REPO_DIR"

cat <<EOF

==> success
bootstrap stone: ${HOST_STONE#$ONIX_ROOT/}
local repo index           : ${LOCAL_REPO_DIR#$ONIX_ROOT/}/stone.index

Next:
  make phase 418

EOF
