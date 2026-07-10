# Phase 001 — passwordless disk builder

## At a glance

| Field | Value |
|---|---|
| Phase family | Phase 0 — forge |
| Run command | `make phase 001` |
| Underlying make target/script | `vm/phase0/install-sudoers.sh --ensure` |
| Runs on | host with sudo only if the rule is missing/stale |
| Main proof/artifact | Rootful image builders can run without repeated sudo prompts. |


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

## Why the disk builder needs root

Building a bootable disk image is inherently privileged work. Walk the four
operations above and what each one requires:

- **`losetup`** attaches a regular file (our `quarry.raw`) to a *loop device*
  like `/dev/loop7`, so the kernel treats the file as if it were a physical
  disk. Creating loop devices is a root-only kernel operation.

  > **Sidebar — loop devices.** A loop device is a kernel gadget that maps a
  > block-device node onto the bytes of an ordinary file. Once `quarry.raw` is
  > "looped," tools like `sgdisk`, `mkfs`, and `mount` can partition and format
  > it exactly as they would a real SSD — the kernel handles the indirection.
  > This is how you build a full disk image without owning a spare disk.

- **`mount`** attaches a filesystem into the host's directory tree. Mounting is
  privileged because it changes what every process on the machine can see.
- **`mkfs`** writes a fresh filesystem (FAT32, ext4) onto a partition — raw
  writes to a block device, root-only.
- **`chroot`** runs a command with a different root directory, so we can `apk
  add` a kernel and bootloader *inside* the new rootfs as if we had booted it.
  Changing root is a privileged syscall.

None of these can be done as an unprivileged user, so `build-disk.sh` re-execs
itself under `sudo` (it exports the config into a temp env file, escalates, and
runs the real work as root — then `chown`s every artifact back to you).

## Why not just type your password each time?

Phase 0 is designed to be **agent- and CI-runnable unattended**. An interactive
`sudo` password prompt in the middle of `make phase 0` would stall the whole
batch. The fix is a narrowly-scoped sudoers rule: allow *this specific script
path* to run as root with no password, and nothing else.

> **Sidebar — what `/etc/sudoers.d` is.** `sudo`'s configuration can be split
> into drop-in files under `/etc/sudoers.d/`. Each file grants specific users
> the right to run specific commands as specific target users, optionally with
> `NOPASSWD`. ONIX writes `/etc/sudoers.d/onix-forge` (no dot in the name — sudo
> ignores dotted files). The rule grants the current user `NOPASSWD` on exactly
> three rootful builder scripts: this phase's `build-disk.sh`, plus the Phase 2
> `build-image-skeleton.sh` and Phase 4 `materialize-etc.sh` builders.

## The clever part: it only prompts when it must

`make doctor` runs this ensure step too. The important detail: the ensure step
first probes the existing rule with `sudo -n ./build-disk.sh --sudoers-check`.
`sudo -n` means "never ask for a password". So if the rule is already correct,
there is no sudo prompt. If the rule is missing or stale, then the installer
prompts once and writes `/etc/sudoers.d/onix-forge`.

Concretely, `install-sudoers.sh --ensure`:

1. Confirms all three target scripts exist on disk.
2. Generates the drop-in into a temp file and validates it with `visudo -cf`
   (a broken sudoers file can lock you out of `sudo` entirely, so it is checked
   for syntax *before* installation).
3. Probes whether the rule already works via `sudo -n … --sudoers-check`. The
   `--sudoers-check` mode is a tiny code path in `build-disk.sh` that just
   verifies it is running as root and exits 0. If the probe succeeds silently,
   the script prints `already OK` and exits **without ever prompting**.
4. Only if the probe fails does it install the drop-in with `sudo install -m
   0440`, which is the one moment you may be asked for your password.

There is also a `--check` mode (used by `make doctor`) that reports missing/stale
rules as a warning instead of installing them, and a `--uninstall` mode to
remove the drop-in and return to prompting.

## The security tradeoff (stated honestly)

Tradeoff: because the script is writable by your user, this is effectively
passwordless root for that script path. That is why it is explicit and separate.

If your user can edit `build-disk.sh`, and your user can run `build-disk.sh` as
root without a password, then your user can run *anything* as root by editing
the script first. The drop-in even says so in a comment. This is an accepted,
deliberate tradeoff for unattended forge builds on a personal machine — not
something to copy onto a shared server. Revert it any time with
`./install-sudoers.sh --uninstall`.

If the script path moves, rerun `make doctor` or this phase so sudoers points at
the new path.

## What comes next

With passwordless rootful builds arranged, [002 — build the forge disk](./002_build_forge_disk.md)
can partition, format, and populate `quarry.raw` unattended.
