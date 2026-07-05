# ONIX

Building an atomic, **musl-based** Linux distro managed by AerynOS's tooling —
`moss` (atomic package/state manager) + `boulder` (the `.stone` builder) — with
a persistent Nix toolbox on top. See [`ONIX.md`](./ONIX.md) for the full
architecture and roadmap.

> **Direction (2026-07):** we do **not** use AerynOS's ISO or its glibc
> packages. We keep only the *tooling* (moss/boulder) and build our own smallest
> possible base on **musl**, from scratch. Alpine is the throwaway *forge* — a
> tiny musl host where we compile moss+boulder and cut the first `.stone` — and
> a dress rehearsal for building the real distro disk later.

## The forge (Phase 0)

A minimal Alpine/musl VM assembled from the 3.7 MB minirootfs tarball into a
bootable disk we build ourselves, then used to build `moss` + `boulder`.
For a step-by-step learning guide, read
[`vm/phase0/README.md`](./vm/phase0/README.md).

```
alpine-minirootfs-3.24.1 (3.7 MB)
   │  fetch-rootfs.sh   download + sha256 verify
   ▼
raw disk image  (GPT: ONIX-ESP + ext4 onix-root)
   │  build-disk.sh     loop device → extract → chroot-setup.sh → grub-efi   [needs sudo]
   ▼
bootable musl forge (quarry)   +  toolchain baked in
   │  launch.sh         QEMU/KVM + OVMF   (or --direct kernel boot)
   ▼
provision.sh  →  git clone os-tools → just get-started → moss + boulder
```

## Quickstart

```sh
make doctor     # common: validate scripts + host dependencies
make phase 002  # fetch minirootfs + build the bootable disk
make phase 003  # boot it (VNC/headless by default)
# log in on the console as mason / onix
make phase 004  # build moss + boulder inside the VM
make phase 005  # cut, inspect, index, install, and run a tiny first .stone
make phase 006  # real Moss state install/remove/rollback smoke test
make phase 100  # verify Phase 1 forge readiness
make phase 101  # build/check/install first real ONIX stone: onix-branding
make phase 102  # build/check/install onix-filesystem with onix-branding
```

Only common operations are named at the top level:

```sh
make doctor    # common health check
make cleanup   # stop forge QEMU, detach mounts, remove generated disk
make phases    # print the numbered phase map
```

Everything else is run by number with `make phase XYZ`.
The first digit is the phase family; the last two digits are the step inside
that family:

- `make phase 002` = Phase 0, step 02
- `make phase 102` = Phase 1, step 02
- `make phase 0` = run all `0xx` steps in order
- `make phase 1` = run all `1xx` steps in order

`make doctor` also ensures the disk-builder sudoers rule. `build-disk.sh` needs
root (`losetup`/`mount`/`chroot`), and it re-execs itself via `sudo`. The
drop-in (`vm/phase0/install-sudoers.sh`) grants NOPASSWD on *this repo's*
`build-disk.sh` so the build runs unattended. If the rule is already correct,
doctor uses `sudo -n` to check it and does **not** prompt. If the rule is
missing/stale, doctor prompts once to install it. Revert with
`vm/phase0/install-sudoers.sh --uninstall`.
**Tradeoff:** `build-disk.sh` is writable by you, so this is effectively
passwordless root for your user — no Unix group can grant `mount`/`chroot`/loop setup,
so sudo is the mechanism. Skip it and `build-disk.sh` just prompts normally.

`make doctor` runs the cheap non-mutating validation lane plus host tool checks.
`make cleanup` first stops the ONIX forge QEMU process (`onix-quarry`), then
detaches stale loop/NBD mounts, then removes generated forge state
(`vm/state/quarry.raw`, OVMF vars, exported kernel/initrd). It keeps the cached
rootfs tarball and SSH key. `make phases` prints the numbered flow.

`make phase 005` is the Phase 0 packaging smoke test. It runs inside the
already-booted forge VM and writes only under `~/stone-lab/onix-hello` in the
guest. It creates a local source tarball, builds `onix-hello` with `boulder`,
checks the resulting `.stone` with `moss inspect --check`, extracts it, creates a
throwaway local Moss repo, installs into a throwaway target root, and runs
`/usr/bin/onix-hello`.

`make phase 006` is the final Phase 0 state smoke test. It
uses the same hello `.stone`, but installs into a disposable Moss root with
`moss -D` instead of `--to`, so Moss creates real states: install becomes
`State #1`, remove becomes `State #2`, and activating state `1` rolls the
disposable root back to the installed package.

`make phase 100` starts Phase 1 by checking the running forge is ready for real
recipe work. `make phase 101` builds the first real ONIX package,
`onix-branding`, from [`recipes/onix-branding/stone.yaml`](./recipes/onix-branding/stone.yaml).
`make phase 102` builds `onix-filesystem` and installs it together with
`onix-branding` into a disposable target root.

## Layout

```
ONIX.md             architecture + roadmap
Makefile            top-level router; forwards targets into per-phase Makefiles
recipes/
  README.md         recipe tree overview
  onix-branding/    first real ONIX stone: os-release + default login text
  onix-filesystem/  filesystem layout policy + default templates
vm/
  phase0/
    README.md       educational guide for the Phase 0 forge
    Makefile        Phase 0 targets; top-level make delegates here
    config.sh       single source of truth (Alpine pin, names, helpers)
    fetch-rootfs.sh download + verify the minirootfs tarball
    build-disk.sh   minirootfs -> bootable musl raw disk  (orchestrates sudo/loop/chroot)
    chroot-setup.sh runs inside the chroot: apk base+kernel+grub+toolchain, users, ssh
    provision.sh    runs inside the booted VM: build moss + boulder from os-tools
    build-hello-stone.sh
                    runs inside the booted VM: build + verify the first tiny .stone
    state-smoke.sh  runs inside the booted VM: real moss install/remove/rollback state test
    launch.sh       boot the forge (grub/OVMF, or --direct)
    ssh.sh          ssh in via the forwarded port + generated key
    clean.sh        wipe forge state to rebuild
  phase1/
    README.md       educational guide for first real ONIX stones
    Makefile        Phase 1 targets; top-level make delegates here
    build-branding-stone.sh
                    runs inside the booted VM: build + verify onix-branding
    build-filesystem-stone.sh
                    runs inside the booted VM: build + verify onix-filesystem
  downloads/        tarballs (gitignored)
  state/            disk, NVRAM, kernel/initrd, ssh key (gitignored)
```

## Notes

- **musl, on purpose.** The endgame distro is musl-based; the forge is musl
  (Alpine) so everything we build and learn transfers. No AerynOS recipe is musl
  yet — a musl base is a genuine bootstrap, which is the point.
- **Networking:** user-mode NAT, host `:6649` → guest `:22` (`6649` = "ONIX",
  ONIX.md §0). SSH password auth is disabled; passwordless SSH uses a key
  generated into `vm/state/`. Use `./vm/phase0/ssh.sh root` for root.
- **Boot:** self-boots via grub-efi under OVMF. `launch.sh --direct` boots the
  exported kernel/initrd directly (bypasses grub) if the bootloader ever fights
  us. The real BLS/`blsforme` boot model is a later phase, for the actual distro.
- **Rootless builds:** the `mason` user has `subuid`/`subgid` ranges + userns so
  boulder/moss can sandbox builds without root.
- **Pinned tooling:** `provision.sh` checks out the pinned `OS_TOOLS_REF` from
  `vm/phase0/config.sh` before building. Override only when intentionally rebasing the
  forge to a newer `os-tools` snapshot.
- **Override anything via env:** `VM_RAM=8G VM_CPUS=8 make phase 003`.

## Requirements (host)

`qemu-system-x86_64`, loop-device support (`losetup`), `edk2-ovmf`, `sgdisk`
(gptfdisk), `partprobe` (parted), `e2fsprogs`, `dosfstools`, `curl`,
`sha256sum`, `sudo`/`visudo`, OpenSSH client tools, and membership in the `kvm`
group.
