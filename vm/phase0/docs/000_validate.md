# Phase 000 — validate

## At a glance

| Field | Value |
|---|---|
| Phase family | Phase 0 — forge |
| Run command | `make phase 000` |
| Underlying make target/script | `make -C vm/phase0 check` |
| Runs on | host |
| Main proof/artifact | Phase 0 scripts parse, cached rootfs is valid if present, and QEMU command construction still works. |


```sh
make phase 000
```

This runs the cheap validation lane. It does not boot the VM and does not build
a disk. It is the "are my scripts still sane?" step.

Under the hood it checks shell syntax for the Phase 0 scripts and confirms the
QEMU command can be assembled.

## Why this step exists

Every later Phase 0 step is expensive or irreversible-ish: 002 formats a disk
image as root, 003 boots a VM, 004 compiles Rust for several minutes. A single
typo in a shell script — an unbalanced quote, a missing `fi` — would blow up
*after* you have already paid that cost. Phase 000 is the fast feedback loop
that catches those errors in under a second, before anything touches root,
loop devices, or QEMU. It is the equivalent of `make lint`: mutating nothing,
proving the machinery is well-formed.

It is also the step `make doctor` and CI can run unconditionally, because it has
no side effects and needs no special privileges.

## What it actually checks

`make phase 000` maps to `make -C vm/phase0 check`. The `check` target does
three things:

1. **Bash syntax check** (`bash -n`) of every bash script in the Phase 0 set:
   `config.sh`, `fetch-rootfs.sh`, `build-disk.sh`, `launch.sh`, `ssh.sh`,
   `install-sudoers.sh`, `clean.sh`, `kill-qemu.sh`, `build-hello-stone.sh`,
   and `state-smoke.sh`.

   > **Sidebar — what `bash -n` does.** The `-n` flag means "read and parse the
   > script, but do not execute a single command." Bash builds the full parse
   > tree, so it catches syntax errors (unterminated strings, mismatched
   > `do`/`done`, bad here-docs) without any of the dangerous side effects —
   > no `losetup`, no `mkfs`, no `rm`. It is a pure "does this parse?" test.

2. **POSIX-sh syntax check** (`sh -n`) of the two scripts that run *inside* the
   guest under Alpine's BusyBox `ash` shell, not bash: `chroot-setup.sh` and
   `provision.sh`. These are deliberately written to the smaller POSIX shell
   dialect because the target rootfs has no bash early on, so they are checked
   with `sh -n` rather than `bash -n`.

3. **Cached rootfs integrity** — if the Alpine minirootfs tarball has already
   been downloaded, its SHA-256 is re-verified against the pin in `config.sh`
   and reported as `rootfs : checksum OK`. If it is absent, the check simply
   notes `rootfs : not downloaded (run make phase 002)` — a missing tarball is
   not an error at this stage, only a state to report.

4. **QEMU command construction** — it runs `launch.sh --direct --dry-run` and
   discards the output. `--dry-run` assembles the entire `qemu-system-x86_64`
   argument array (machine type, CPU, drives, netdev, serial) and prints it
   *without launching QEMU*. If argument assembly fails — a bad variable
   expansion, a missing helper — the dry run exits non-zero and `check` fails
   with `dry-run : failed`. This proves the boot command still builds correctly
   even on a host with no disk and no firmware.

If all four pass, you get `check : OK`.

## What it proves — and what it deliberately does not

**Proves:** the Phase 0 scripts parse in their intended shells, any cached seed
tarball is uncorrupted, and the QEMU invocation is still constructible.

**Does not prove:** that the VM boots, that the disk is valid, that OVMF
firmware is installed, or that moss/boulder build. Those are 002–006's jobs.
Phase 000 is intentionally shallow and instant; its whole value is being safe to
run at any moment.

## What comes next

If `make phase 000` is green, proceed to [001 — passwordless disk builder](./001_passwordless_disk_builder.md),
which arranges the one bit of privilege the disk build needs before 002 formats
anything.
