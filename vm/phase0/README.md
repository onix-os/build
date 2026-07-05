# Phase 0 — the forge

Phase 0 is not the ONIX operating system yet. It is the **forge**: a small
musl Linux VM where we learn and prove the tooling path before building real
ONIX packages.

The goal is:

```text
Alpine minirootfs -> bootable forge VM -> moss + boulder -> first .stone -> Moss state rollback
```

In plain words: we build a tiny temporary Linux VM, compile the AerynOS package
tools inside it, build one tiny package, and prove Moss can install, remove, and
roll back that package.

## Why this phase exists

ONIX wants to be:

- **musl-based**
- **atomic**
- managed by **Moss**
- packaged with **Boulder**
- independent from AerynOS's glibc package repository

But to build `.stone` packages, we first need working `moss` and `boulder`
binaries on a musl machine. Alpine is useful here because it is already musl and
small. It is scaffolding, not the final distro.

Important distinction:

| Thing | Role in Phase 0 | Final ONIX? |
|---|---|---|
| Alpine | temporary musl build host | no |
| OpenRC | temporary forge init | probably no |
| GRUB | temporary forge bootloader | probably no |
| moss | package/state manager we keep | yes |
| boulder | `.stone` package builder we keep | yes |
| `.stone` packages | package format we build | yes |

The forge lets us test scary low-level work in a disposable VM instead of
touching the host system.

## Host vs guest

This repo uses two machines at once:

```text
host: your current Linux system
guest: the QEMU VM named quarry
```

Host-side things:

- downloads the Alpine minirootfs
- creates the raw disk image
- attaches loop devices
- partitions/formats/mounts the image while building it
- launches QEMU
- SSHes into the VM

Guest-side things:

- boots Alpine
- runs as user `mason`
- builds `moss` and `boulder`
- builds `.stone` packages
- runs Moss state tests in disposable roots

This distinction matters because host disk-building needs root privileges, while
package experiments after boot mostly happen safely inside the VM.

## Numbered flow

Top-level phase commands are intentionally numbered:

```sh
make phase 000
make phase 001
make phase 002
...
```

The format is three digits:

```text
XYZ
│└┴─ step inside that phase family
└─── phase family
```

So `002` means "Phase 0, step 02". Running `make phase 0` runs all Phase 0
steps, `000..006`, in order.

Only common cross-phase operations are named at top level:

```sh
make doctor
make cleanup
make phases
```

Phase 0 currently has these steps:

| Step | What it does | Why it matters |
|---|---|---|
| `make phase 0` | Run every Phase 0 step in order | Convenience when you want the whole forge path |
| `make phase 000` | Validate scripts/config without mutating the VM | Fast safety check before doing anything bigger |
| `make phase 001` | Ensure the sudoers rule for disk building | Avoid repeated password prompts for loop/mount/chroot work |
| `make phase 002` | Build the bootable forge disk | Produces `vm/state/quarry.raw` |
| `make phase 003` | Boot the forge VM | Starts QEMU so we can enter/SSH into `quarry` |
| `make phase 004` | Build `moss` and `boulder` in the VM | Produces the package manager and package builder |
| `make phase 005` | Build/check/install/run a tiny `.stone` | Proves Boulder can produce a valid package |
| `make phase 006` | Real Moss install/remove/rollback smoke test | Proves Moss state transactions work |

## Common commands

### `make doctor`

Runs from the repo root. This is common, not a phase.

It checks:

- script syntax
- minirootfs checksum if already downloaded
- QEMU dry-run construction
- required host commands like `qemu-system-x86_64`, `losetup`, `sgdisk`,
  `mkfs.ext4`, `ssh`, and `visudo`

It should be safe and non-mutating.

### `make cleanup`

Runs from the repo root. This is common, not a phase.

It first stops the ONIX forge QEMU process (`onix-quarry`), then cleans stale
loop/NBD mount trees left behind by interrupted disk builds, then removes the
generated forge disk/NVRAM/kernel/initrd under `vm/state/`.

It does **not** kill unrelated QEMU VMs. It keeps the cached Alpine rootfs and
the generated SSH key.

## Step details

### Phase 000 — validate

```sh
make phase 000
```

This runs the cheap validation lane. It does not boot the VM and does not build
a disk. It is the "are my scripts still sane?" step.

Under the hood it checks shell syntax for the Phase 0 scripts and confirms the
QEMU command can be assembled.

### Phase 001 — passwordless disk builder

```sh
make phase 001
```

Disk building needs operations normal users cannot do:

- `losetup`
- `mount`
- `mkfs`
- `chroot`

So `build-disk.sh` re-execs itself with `sudo`. This phase ensures a sudoers
drop-in allowing only this repo's Phase 0 disk builder to run without another
password prompt.

`make doctor` runs this ensure step too. The important detail: the ensure step
first probes the existing rule with `sudo -n ./build-disk.sh --sudoers-check`.
`sudo -n` means "never ask for a password". So if the rule is already correct,
there is no sudo prompt. If the rule is missing or stale, then the installer
prompts once and writes `/etc/sudoers.d/onix-forge`.

Tradeoff: because the script is writable by your user, this is effectively
passwordless root for that script path. That is why it is explicit and separate.

If the script path moves, rerun `make doctor` or this phase so sudoers points at
the new path.

### Phase 002 — build the forge disk

```sh
make phase 002
```

This creates the bootable forge disk:

```text
vm/downloads/alpine-minirootfs-*.tar.gz
        |
        v
vm/state/quarry.raw
```

The disk layout is intentionally simple:

```text
ONIX-ESP    FAT32 EFI system partition
onix-root   ext4 root filesystem
```

During the build, the script:

1. creates a sparse raw disk
2. attaches it with `losetup`
3. partitions it
4. formats the ESP and root partition
5. extracts Alpine minirootfs
6. enters a chroot
7. installs kernel, OpenRC, SSH, GRUB, Rust/build tools
8. creates the `mason` build user
9. exports kernel/initramfs for direct boot fallback

OpenRC and GRUB are only forge scaffolding. The real ONIX target can still
use systemd/systemd-boot later if we choose that route.

### Phase 003 — boot the forge

```sh
make phase 003
```

This starts QEMU using the disk from Phase 002.

Expected login:

```text
username: mason
password: onix
```

SSH is forwarded from host port `6649` to guest port `22`.

The VM hostname is:

```text
quarry
```

When you run `make phase 003` directly, QEMU stays in the foreground so you can
watch and interact with the console.

When you run the whole family with `make phase 0`, phase 003 uses a batch-safe
boot path instead:

```text
launch QEMU in the background
tail vm/state/quarry.serial.log so you still see boot logs
wait until SSH on 127.0.0.1:6649 is ready
continue automatically to phase 004
```

That means the full batch does not get stuck at the Alpine login prompt.

### Phase 004 — provision tools

```sh
make phase 004
```

This SSHes into the running forge and builds:

- `moss`
- `boulder`

from the pinned `os-tools` commit in `config.sh`.

Result inside the guest:

```text
/home/mason/.local/bin/moss
/home/mason/.local/bin/boulder
```

Conceptually:

- `moss` manages installed package states atomically
- `boulder` builds `.stone` packages from `stone.yaml`

### Phase 005 — first `.stone`

```sh
make phase 005
```

This builds a deliberately tiny package called `onix-hello`.

It creates a local source archive in the guest, writes a `stone.yaml`, builds a
`.stone`, checks it, extracts it, indexes it into a local repo, installs it into
a throwaway target root, and runs:

```sh
/usr/bin/onix-hello
```

Expected output:

```text
hello from onix forge
```

This proves the package build pipeline works:

```text
source tarball -> stone.yaml -> boulder -> .stone -> moss inspect/extract/install
```

Important recipe gotcha learned here:

```yaml
install     : |
    install -Dm00755 onix-hello %(installroot)%(bindir)/onix-hello
    chmod g-s %(installroot)/usr %(installroot)%(bindir)
```

Boulder build directories inherit `g+s`. If `/usr` keeps that bit, Boulder can
emit a `/usr/` layout entry that Moss rejects during extract/install.

### Phase 006 — real Moss state smoke test

```sh
make phase 006
```

Phase 005 uses `moss install --to`, which blits files into a target directory but
does not create a real Moss state transaction.

Phase 006 uses:

```sh
moss -D <root> install onix-hello
```

That creates real state history under a disposable root.

Expected proof:

```text
install onix-hello -> State #1
remove onix-hello  -> State #2
activate State #1     -> rollback works
```

This is the final Phase 0 gate because atomic state management is the whole
reason we are using Moss.

## Files in this phase

| File | Purpose |
|---|---|
| `Makefile` | Phase 0 target implementation |
| `config.sh` | shared settings: Alpine pin, VM name, disk path, ports, os-tools ref |
| `fetch-rootfs.sh` | downloads and verifies Alpine minirootfs |
| `build-disk.sh` | builds the bootable forge disk |
| `chroot-setup.sh` | runs inside the new rootfs while building the disk |
| `launch.sh` | starts QEMU |
| `ssh.sh` | SSH helper for the running forge |
| `provision.sh` | builds `moss` and `boulder` inside the VM |
| `build-hello-stone.sh` | creates and verifies the first `.stone` |
| `state-smoke.sh` | proves real Moss state install/remove/rollback |
| `clean.sh` | removes generated forge disk/boot artifacts |
| `install-sudoers.sh` | installs/uninstalls the passwordless disk-builder sudoers rule |

## When Phase 0 is complete

Phase 0 is complete when all of these have worked:

- `make doctor`
- `make phase 002`
- `make phase 003`
- `make phase 004`
- `make phase 005`
- `make phase 006`

At that point we know:

1. we can boot a musl forge,
2. we can build the AerynOS tools on musl,
3. we can build a valid `.stone`,
4. we can create a local Moss repo,
5. we can install/remove packages with real Moss states,
6. we can roll back to an older state.

Only after this does Phase 1 make sense: real ONIX recipe/repo bootstrap.
