# Phase 411 — boot-prove `onix-busybox`

| Item | Value |
|---|---|
| Command | `make phase 411` |
| Underlying make target/script | `vm/phase4/stone-busybox-probe.sh` |
| Re-validates image install with | `vm/phase4/materialize-etc.sh --busybox-stone` |
| Mutates disk/image? | Yes, idempotently re-applies Phase 410 first |
| Boots QEMU? | Yes, several short snapshot boots |
| Main proof | The running ONIX image can use `onix-busybox` for serial shell, networking, remote inspection, and SSH command execution. |

## Background: what "boot-proving a stone" means

A **stone** (`.stone`) is ONIX's package format — a self-describing archive of files
plus metadata, produced by **boulder** (the builder) and installed by **moss**
(the atomic package/state manager). Both are Rust tools ONIX borrows from AerynOS;
ONIX ships none of AerynOS's packages, only this tooling. Phase 409 built the
`onix-busybox` stone; Phase 410 installed it into the disk image and pointed the
active command paths at it.

But installing a package into a disk image only proves the *files are in the right
place*. It does not prove the operating system actually runs those files once it is
alive. **Boot-proving** closes that gap: you boot the real image in a virtual
machine, let the kernel hand off to userspace, let the init system start its
services, and only then check that the tool you packaged is the one actually doing
the work.

The phrase you will see repeated in Phase 4 is *"PID 1-served userspace."* PID 1 is
the first process the kernel starts after mounting the root filesystem — in ONIX
that is systemd. Every service (the serial shell, networking, SSH) is a child that
systemd starts. So when Phase 411 confirms that the serial shell, the network
scripts, and the SSH session all run `/usr/bin/busybox`, it is confirming the whole
chain: kernel → PID 1 → services → your stone-provided binary. That is a
qualitatively stronger claim than "the file exists on disk."

## Why this phase exists

Phase 410 proved the filesystem shape:

```text
/usr/bin/busybox exists
/bin resolves to the BusyBox applet path
the serial service ExecStart points at /usr/bin/busybox
```

That is necessary, but it is not enough.

A Linux system can have correct-looking files and still fail at runtime.

Examples:

- a binary exists but cannot execute,
- a symlink resolves on the mounted host but not after boot,
- a systemd unit points at the right path but never starts,
- a network script exists but fails inside the VM,
- SSH starts but the user's shell cannot run commands.

Phase 411 is the runtime proof.

It asks:

```text
After the VM actually boots, do the existing ONIX behaviors still work with the
stone-provided BusyBox?
```

## Filesystem proof vs runtime proof

This is one of the most important operating-system lessons in Phase 4.

Filesystem proof means:

```text
mount the disk image
look at files
check symlinks
check executable bits
check systemd unit text
```

Runtime proof means:

```text
boot the kernel
mount the real root
start systemd as PID 1
start services
execute commands inside the guest
observe behavior from the host
```

Both are needed.

Phase 410 was mostly filesystem proof.

Phase 411 is runtime proof.

## Why Phase 411 re-applies Phase 410 first

The target does this:

```make
./materialize-etc.sh --busybox-stone
./stone-busybox-probe.sh
```

That makes `make phase 411` safe to run by itself.

If you already ran Phase 410, the first line is mostly a verification and
idempotent refresh.

If you forgot Phase 410, Phase 411 installs the stone BusyBox before booting.

This follows the pattern of earlier Phase 4 targets:

```text
materialize expected image state
then boot-prove behavior
```

## What "snapshot boot" means

The QEMU probes use:

```text
snapshot=on
```

That means the VM sees the disk image, but writes made during that VM boot are
discarded when QEMU exits.

This matters because booting a system changes things:

- `/run` gets created,
- logs may be written,
- host keys may be touched,
- service state may change,
- temporary files appear.

For proof phases, we usually want:

```text
observe runtime behavior without permanently changing the image
```

So Phase 411 uses snapshot boots.

The image is mutated before boot by Phase 410. The boot-time changes themselves
are throwaway.

## Background: how the host reaches inside the guest

Two of the four proofs (remote inspection and SSH) need the host to open a TCP
connection *into* the running guest. That works through **QEMU user-mode
networking**, a lightweight NAT that QEMU implements in userspace. The guest sees a
normal virtual NIC and gets the address `10.0.2.15` from QEMU's built-in DHCP; the
gateway is `10.0.2.2`. No root, no bridge, no tap device is needed on the host.

Because that network is private to QEMU, the host cannot reach guest ports directly.
Instead QEMU **forwards** a chosen host port to a guest port. Phase 411 forwards:

```text
host 127.0.0.1:7666  ->  guest :6649   (remote inspection listener)
host 127.0.0.1:7627  ->  guest :22     (SSH)
```

`6649` is the ONIX magic number ("ONIX" on a phone keypad); it reappears as the
GID for Nix build users and as port offsets throughout the project. When you read a
proof that says "the host connects to `127.0.0.1:7666`," that is the host end of
this forward, tunnelling into the guest's BusyBox `nc` listener.

The serial and network proofs do not need forwarding — they talk to the guest over
a **serial console** (a virtual UART exposed to the host as a Unix socket), which is
the most primitive channel available and works even before networking is up.

## What Phase 411 proves

Phase 411 runs four live proofs.

### 1. Serial shell proof

The first proof boots the image and waits for the bootstrap serial shell marker:

```text
ONIX_BOOTSTRAP_SERIAL_CONSOLE_READY
```

Then the host sends a command over the serial socket.

That command runs:

```text
/usr/bin/busybox sh -c ...
```

and expects:

```text
ONIX_STONE_BUSYBOX_SERIAL_OK uid=0 ... busybox=/usr/bin/busybox
```

This proves:

- the VM booted far enough for systemd to start the serial service,
- the serial service can execute the stone BusyBox,
- the root bootstrap shell can run commands.

### 2. Network proof

The second proof boots again and runs:

```text
/usr/lib/onix/bootstrap-network-proof
```

That script uses BusyBox commands such as:

```text
/bin/ifconfig
/bin/route
/bin/grep
/bin/awk
```

Because Phase 410 made `/bin` resolve to the `onix-busybox` payload, this checks
the running network bootstrap against the stone BusyBox.

The expected marker is:

```text
ONIX_STONE_BUSYBOX_NETWORK_OK uid=0 ... busybox=/usr/bin/busybox
```

The normal network proof still has to pass first:

```text
ONIX_NETWORK_OK iface=<name> ip=10.0.2.15 router=10.0.2.2
```

### 3. Remote inspection proof

The third proof boots with QEMU host port forwarding.

Inside the guest:

```text
onix-bootstrap-remote-inspection.service
```

starts a BusyBox `nc` listener.

The host connects to:

```text
127.0.0.1:7666
```

and expects the remote marker:

```text
ONIX_REMOTE_INSPECTION_OK name=ONIX phase=405
```

The serial side also verifies:

```text
ONIX_STONE_BUSYBOX_REMOTE_OK uid=0 ... busybox=/usr/bin/busybox
```

This proves:

- the guest network came up,
- the BusyBox `nc` listener started,
- host-to-guest TCP forwarding still works,
- the BusyBox command path is the stone path.

### 4. SSH proof

The fourth proof boots with SSH port forwarding.

The host connects to:

```text
127.0.0.1:7627
```

as the bootstrap SSH user:

```text
onix
```

The remote SSH command deliberately runs:

```text
/usr/bin/busybox sh -c ...
```

and expects:

```text
ONIX_STONE_BUSYBOX_SSH_OK user=onix uid=1000 ... busybox=/usr/bin/busybox
```

This proves:

- Dropbear still starts,
- public-key authentication still works,
- the non-root SSH account can run commands,
- the command path can use `onix-busybox`.

## Why the proof uses several boots

It would be faster to boot once and test everything in one VM.

We do not do that yet.

The current probe scripts are intentionally small and specialized:

- serial proof,
- network proof,
- remote inspection proof,
- SSH proof.

Phase 411 composes those existing proofs instead of inventing a larger test
harness too early.

That costs time, especially without KVM acceleration, but it keeps each failure
easier to understand.

If the serial proof fails, we know the problem is early shell/service startup.

If the SSH proof fails, we know serial and network probably already worked, and
the bug is closer to Dropbear/account/key behavior.

Later ONIX can combine these into a faster single-boot integration probe.

## Expected output

You should see:

```text
==> Phase 411 stone BusyBox live proof
==> probe 1/4: serial shell uses onix-busybox
==> probe 2/4: network scripts use onix-busybox commands
==> probe 3/4: remote inspection listener uses onix-busybox nc/netstat
==> probe 4/4: SSH session uses onix-busybox commands
```

Each sub-proof prints its own success message.

The final success block is:

```text
==> success
Phase 411 proved the booted ONIX image can use onix-busybox for:

  - serial bootstrap shell
  - bootstrap QEMU user networking
  - host-to-guest TCP inspection
  - authenticated SSH command execution
```

## Evidence logs

The logs are written under:

```text
vm/state/
```

with Phase 411 names:

```text
phase411.serial-boot.log
phase411.serial-shell.log
phase411.network-boot.log
phase411.network-serial.log
phase411.remote-boot.log
phase411.remote-serial.log
phase411.ssh-boot.log
phase411.ssh-serial.log
```

If a proof fails, those logs are usually more useful than the final error line.

The boot logs show kernel/systemd progress.

The serial logs show what the bootstrap shell printed and what commands the
host sent.

## How to stop a stuck probe

If a QEMU probe gets stuck, run:

```sh
make stop
```

or directly:

```sh
vm/phase4/stone-busybox-probe.sh --kill
```

The stop path knows about the Phase 411 QEMU probe names and keeps generated
disk/image state. Use `make cleanup` only for an intentional destructive reset.

## What this phase does not prove

Phase 411 does not prove that all Nix-sourced machine-plane payloads are gone.

It proves only:

```text
the active BusyBox runtime path works through onix-busybox
```

The old copied Nix BusyBox closure may still exist on disk.

That is okay for now.

The safe order is:

```text
410 — switch active BusyBox path
411 — boot-prove the replacement works
later — remove/audit leftover Nix-sourced machine-plane payloads
```

Do not delete fallback-looking data before the replacement has a live proof.
