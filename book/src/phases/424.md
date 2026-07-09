# Phase 424 — bring up native ONIX for inspection

| Item | Value |
|---|---|
| Command | `make phase 424` |
| Shortcut | `make up` |
| Underlying target | `make -C vm/phase4 native-systemd-up` |
| Image used | `artifacts/onix-image/onix.raw` |
| SSH key | `vm/state/id_ed25519` |
| SSH port | `7630` by default |
| Mutates disk/image? | Yes, it rematerializes the native systemd payload into the image before boot. |
| Boots QEMU? | Yes |
| Leaves QEMU running? | Yes |
| Main proof | The native `onix-systemd` image boots, SSH works, and the VM remains available for learning/debugging. |

Phase 422 proved that ONIX can build, install, and boot native
`onix-systemd`.

Phase 424 is the operational version of that proof:

```sh
make phase 424
```

or:

```sh
make up
```

It boots the current native ONIX image, proves SSH, and then intentionally
leaves QEMU running so you can inspect the system yourself.

## Why this is a separate phase

Build phases and operating phases have different jobs.

Phase 422 is a build/proof milestone:

```text
build native systemd
package it as onix-systemd.stone
install it
boot once
prove PID 1
shut down
```

Phase 424 is a lab/inspection milestone:

```text
install the already-built native onix-systemd stone
boot ONIX
prove SSH
leave QEMU running
let a human inspect the booted system
```

That difference matters.

When we are building, we want a clean automatic proof that exits by itself.
When we are learning, we want the machine to stay alive so we can run commands
inside it.

## Refresher: what the image is

The file:

```text
artifacts/onix-image/onix.raw
```

is a virtual disk.

QEMU treats it like a real hard drive.

Inside that one file are partitions such as:

```text
EFI system partition
/boot partition
root filesystem
/persist filesystem
```

When the VM boots, firmware reads the boot partition, systemd-boot loads the
kernel and initramfs, the initramfs mounts the root filesystem, and then Linux
executes:

```text
/usr/lib/systemd/systemd
```

That process becomes PID 1.

Phase 424 is not creating a brand-new OS from nothing. It is taking the current
assembled image and booting it as a real virtual machine.

## Refresher: what the root tree is

Before an image exists, we usually have a root tree:

```text
artifacts/onix-root-tree/
```

A root tree is just a directory that looks like the future `/` filesystem:

```text
usr/
etc/
var/
home/
persist/
```

Linux does not boot directly from this directory on the host. Instead, image
assembly copies that tree into a disk filesystem.

The simplified flow is:

```text
.stone packages
    ↓ installed by moss
root tree
    ↓ copied into image filesystems
raw disk image
    ↓ booted by QEMU
running ONIX VM
```

Phase 424 starts at the end of that chain. It assumes the useful artifacts
already exist, then brings up the running VM.

## What `make phase 424` does

The target runs:

```sh
make -C vm/phase4 native-systemd-up
```

That target performs these important actions:

1. stops any older Phase 422/424 native-systemd QEMU probe,
2. refreshes compact login defaults such as `/etc/motd` and `/etc/profile`,
3. rematerializes the native `onix-systemd` package into the image,
4. boots QEMU with SSH forwarding and keeps QEMU alive after the proof passes.

The materialization step uses:

```sh
./materialize-etc.sh --native-systemd-stone
```

The stop-first guard matters because `artifacts/onix-image/onix.raw` is the disk
file QEMU boots from. We should not rewrite that disk image while an older QEMU
process is still using it.

The login-default refresh matters because the bootstrap SSH server has a small
MOTD/banner byte budget. ONIX starts Dropbear with `-m`, so Dropbear does not
print `/etc/motd` itself. Then `/etc/profile.d/onix-login.sh` prints the
colored `/usr/share/onix/branding/logo.ansi` after the login shell starts. That
keeps the colored logo while avoiding Dropbear's truncation path.

The boot/proof step uses:

```sh
./native-systemd-probe.sh --keep-running
```

The `--keep-running` flag is the key difference from Phase 422. Without it, the
probe shuts QEMU down after the proof. With it, the VM remains alive.

## How SSH works here

QEMU uses user-mode networking with host port forwarding.

Inside the VM, Dropbear listens on port:

```text
22
```

On the host, QEMU forwards:

```text
127.0.0.1:7630
```

to the guest's port:

```text
22
```

So from the host you connect with:

```sh
ssh -i vm/state/id_ed25519 -p 7630 onix@127.0.0.1
```

The important pieces are:

- `-i vm/state/id_ed25519` tells SSH which private key to use,
- `-p 7630` connects to QEMU's forwarded host port,
- `onix` is the normal ONIX user created by the base policy,
- `127.0.0.1` means the connection stays on the host machine and enters QEMU.

### Background: public-key authentication

ONIX's bootstrap SSH accepts no passwords (`dropbear -s`) and no root login
(`-w`) — the only way in is **public-key authentication**. That relies on a key pair:
a private key the host keeps secret (`vm/state/id_ed25519`) and a matching public key
placed inside the guest at `/persist/home/onix/.ssh/authorized_keys`. When you
connect, Dropbear challenges the client to prove it holds the private key, without
the private key ever crossing the wire. Because the public key was baked into the
image during earlier Phase 4 materialization, the `onix` user can log in with no
password prompt. This is why the `-i` flag points at that specific private key: it is
the one half whose public counterpart the guest already trusts.

## Things to inspect inside the VM

After SSH connects, try:

```sh
cat /proc/1/comm
systemctl --version
id
hostname
mount
ls -l /usr/lib/systemd/systemd
```

Expected important result:

```text
systemd
```

from:

```sh
cat /proc/1/comm
```

That tells us PID 1 is systemd.

Also check:

```sh
test -L /usr/lib/systemd/systemd && echo symlink || echo real-file
```

For native `onix-systemd`, the expected answer is:

```text
real-file
```

That means the active systemd executable is package-owned inside the image, not
a runtime symlink into an old bootstrap payload.

## Safe stop versus destructive cleanup

Use this when you are done inspecting:

```sh
make stop
```

`make stop` is the safe operation. It stops QEMU probes and detaches stale host
mounts, but it keeps generated artifacts such as:

```text
artifacts/onix-image/onix.raw
artifacts/onix-local-repo/
artifacts/onix-stones/
vm/state/quarry.raw
```

Use this only when you intentionally want to wipe generated state:

```sh
make cleanup
```

`make cleanup` is destructive. It stops QEMU and removes generated disks/images.

For day-to-day learning, prefer:

```sh
make stop
```

not:

```sh
make cleanup
```

## Why VM changes do not persist yet

The QEMU probes currently boot with a snapshot-style disk mode.

That means:

```text
changes made inside the running VM are temporary
```

This is deliberate for now. It lets us boot, inspect, test, and break things
without corrupting the host-side image artifact.

Later ONIX will need a more explicit persistence story around:

```text
/persist
/home
/nix
machine identity
user data
```

For Phase 424, remember the rule:

```text
Phase 424 is for inspection, not permanent VM customization.
```

## If state was wiped

If `make cleanup` removed the image, Phase 424 cannot boot until the image and
package artifacts exist again.

The safest conceptual rebuild path is:

```sh
make phase 002
make phase 2
make phase 401
make phase 402
make phase 403
make phase 404
make phase 405
make phase 406
make phase 410
make phase 413
make -C vm/phase4 bootstrap-policy-proof
make phase 424
```

That path:

1. rebuilds the forge disk,
2. rebuilds the bootable ONIX image skeleton,
3. rematerializes the booted-base policy,
4. reinstalls the BusyBox and Dropbear stones,
5. reinstalls/proves the bootstrap policy stone,
6. brings the native systemd image up for inspection.

If the native `onix-systemd` stone itself is missing, rebuild it with:

```sh
make phase 422
```

Then bring the VM up again:

```sh
make phase 424
```

## Mental model

Phase 424 is the first point where ONIX starts to feel like a small machine you
can enter.

The stack looks like this:

```text
host shell
  ↓ make phase 424
QEMU virtual machine
  ↓ systemd-boot
Alpine kernel/initramfs payload for now
  ↓ root=LABEL=onix-root
ONIX root filesystem
  ↓ init=/usr/lib/systemd/systemd
native onix-systemd as PID 1
  ↓ units
network + Dropbear SSH
  ↓ forwarded port 7630
host SSH session as user onix
```

That is the purpose of this phase:

```text
turn the proof into a running lab.
```
