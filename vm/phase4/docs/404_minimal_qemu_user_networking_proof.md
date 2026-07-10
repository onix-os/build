# Phase 404 — minimal QEMU user networking proof

| Item | Value |
|---|---|
| Command | `make phase 404` |
| Underlying make target/scripts | `vm/phase4/materialize-etc.sh --network`, then `vm/phase4/network-probe.sh` |
| Mutates disk/image? | Yes, it mounts `artifacts/onix-image/onix.raw` and installs bootstrap networking pieces |
| Boots QEMU? | Yes, it runs an automated serial-controlled network proof |
| Main proof | The booted ONIX image configures its QEMU virtio network card and reports `ONIX_NETWORK_OK iface=<name> ip=10.0.2.15 router=10.0.2.2`. |

## The basic Linux networking idea

A Linux machine does not become networked just because a virtual network card
exists.

There are several layers:

```text
hardware / virtual device       the NIC exists
kernel driver                   Linux can talk to the NIC
interface name                  Linux exposes it as enp0s3, eth0, ...
link state                      the interface is brought up
IP address                      the interface receives an address
route                           the kernel knows where to send packets
DNS                             names can be translated to IP addresses
```

Phase 403 proved we can type commands inside the booted image.

Phase 404 uses that control path to prove the next base-system fact:

```text
ONIX can bring up its first network interface and install an IPv4 route.
```

## Why this phase uses QEMU's static contract

The obvious first idea was DHCP.

But the current boot image still uses the borrowed Alpine kernel/initramfs/module
payload from Phase 2. The module set imported in Phase 214 is intentionally
small: it was just enough to mount filesystems and keep the boot proof moving.

BusyBox `udhcpc` needs Linux packet-socket support. In this borrowed kernel
setup that support may live in a module that is not currently part of our
minimal imported module set.

So Phase 404 makes a deliberate boundary decision:

```text
do not expand kernel/module ownership inside Phase 4
```

Kernel and module ownership belongs to Phase 3.

Instead, Phase 404 uses the stable QEMU user-networking contract. QEMU normally
gives guests this private NAT layout:

```text
guest IP     10.0.2.15
gateway      10.0.2.2
DNS helper   10.0.2.3
```

That is enough to prove:

- the virtio network device appears,
- the kernel driver works,
- ONIX has network tools,
- ONIX can assign an IPv4 address,
- ONIX can install a default route.

It is not the final network stack.

It is the first honest userspace networking proof.

### Background: QEMU user-mode networking (SLIRP)

QEMU can give a guest a network card in several ways. The default, and the one
ONIX uses here, is **user-mode networking**, historically called **SLIRP**. It
needs no root, no bridge, and no host configuration: QEMU itself pretends to be a
tiny home router sitting between the guest and the outside world, doing NAT
(network address translation) in userspace.

Because that virtual router is entirely simulated by QEMU, its layout is fixed and
predictable for every guest:

```text
guest IP     10.0.2.15    the address the guest should give itself
gateway      10.0.2.2     QEMU's virtual router (the default route)
DNS helper   10.0.2.3     QEMU forwards DNS queries to the host's resolver
```

The guest sees this router through a **virtio** network card. virtio is a family
of *paravirtualized* devices: instead of emulating some real-world NIC chip
bit-for-bit, the guest runs a lightweight driver that talks a protocol designed
for VMs, which is faster and simpler. The borrowed Alpine kernel already has the
virtio-net driver, so Linux exposes the card as a normal interface (commonly
`enp0s3`). What it does *not* reliably have in our trimmed module set is the
packet-socket support BusyBox `udhcpc` needs for DHCP — hence the decision to hard-
code the known SLIRP addresses instead of negotiating them, keeping kernel/module
ownership firmly inside Phase 3.

## What provides the network tools

Phase 404 still uses the temporary musl BusyBox payload introduced in Phase 403.

BusyBox provides small versions of early network tools:

```text
ifconfig
ip
route
ping
nslookup
nc
netstat
wget
```

The important tools for this phase are:

```text
ifconfig    bring the interface up and assign 10.0.2.15
route       install the default route through 10.0.2.2
```

This is old-school networking on purpose. It avoids adding a larger network
manager before the base image is ready for one.

## Runtime state under `/run`

Phase 404 writes runtime network state under:

```text
/run/onix/network.env
/run/onix/resolv.conf
```

The state file looks conceptually like:

```text
method=static-qemu-user
interface=enp0s3
ip=10.0.2.15
subnet=255.255.255.0
router=10.0.2.2
dns=10.0.2.3
```

It lives under `/run` because this is not permanent machine configuration.

That means:

```text
reboot -> /run is empty again -> networking is configured again
```

The interface name is not hardcoded because Linux may rename the virtio NIC.
In our current boot logs it is commonly:

```text
enp0s3
```

but the script accepts the first non-loopback interface it sees.

## The systemd unit

Phase 404 installs:

```text
onix-bootstrap-network.service
```

into the same temporary copied systemd unit tree used by Phase 403:

```text
/nix/store/...-systemd-.../example/systemd/system/
/persist/nix/store/...-systemd-.../example/systemd/system/
```

The `/persist` copy matters for the same reason learned in Phase 403:

```text
/nix is bind-mounted from /persist/nix at boot
```

If a unit only exists in the root filesystem's hidden pre-mount `/nix`, systemd
may not see it after the real `/persist` partition is mounted.

The service runs:

```text
/bin/sh /usr/lib/onix/bootstrap-network-up
```

That script:

1. waits for a non-loopback interface,
2. brings up `lo`,
3. assigns `10.0.2.15/24` to the virtio interface,
4. installs a default route through `10.0.2.2`,
5. writes runtime state to `/run/onix/network.env`,
6. prints `ONIX_BOOTSTRAP_NETWORK_READY`.

## The automated proof

`make phase 404` has two parts.

First it mutates the image:

```text
./materialize-etc.sh --network
```

That installs:

```text
/usr/lib/onix/bootstrap-network-up
/usr/lib/onix/bootstrap-network-status
/usr/lib/onix/bootstrap-network-proof
/usr/share/onix/bootstrap/networking.txt
onix-bootstrap-network.service
```

Then it boots QEMU:

```text
./network-probe.sh
```

The network probe reuses the Phase 403 serial shell on `ttyS1`.

It waits until the bootstrap shell is ready, then sends:

```sh
/usr/lib/onix/bootstrap-network-proof
```

That proof script waits for the network service to write `/run/onix/network.env`
and then runs:

```sh
/usr/lib/onix/bootstrap-network-status
```

The phase passes only when the serial output contains:

```text
ONIX_NETWORK_OK iface=<name> ip=10.0.2.15 router=10.0.2.2
```

That proves:

- the virtio network driver loaded,
- Linux exposed a non-loopback network interface,
- BusyBox networking applets exist,
- the guest has the expected QEMU NAT address,
- the guest has a default route through QEMU.

## Run it

From the repo root:

```sh
make phase 404
```

Expected image-mutation output includes:

```text
network  : /usr/lib/onix/bootstrap-network-up
network  : /usr/lib/onix/bootstrap-network-status
network  : /usr/lib/onix/bootstrap-network-proof
unit     : /nix/store/.../onix-bootstrap-network.service
unit     : /persist/nix/store/.../onix-bootstrap-network.service
proof    : /usr/share/onix/bootstrap/networking.txt
```

Expected QEMU proof output ends with:

```text
command : observed ONIX_NETWORK_OK iface=[^[:space:]]+ ip=10\.0\.2\.15 router=10\.0\.2\.2

==> success
Phase 404 proved minimal QEMU user networking inside the booted ONIX image.
```

The actual serial log contains the concrete interface name, for example:

```text
ONIX_NETWORK_OK iface=enp0s3 ip=10.0.2.15 router=10.0.2.2
```

## What this phase does not do

Phase 404 is not the final ONIX network architecture.

It does not decide yet:

- whether ONIX uses `systemd-networkd`,
- whether ONIX uses NetworkManager later for desktop systems,
- where permanent DNS policy belongs,
- how Wi-Fi is managed,
- how static IPs are configured outside QEMU,
- how DHCP should be provided once Phase 3 owns the full module story,
- how user-facing network commands should look.

It only proves the smallest useful base-system networking fact:

```text
the booted image can configure QEMU user networking and report it from inside ONIX
```

That is enough to continue toward remote inspection in the next phase.
