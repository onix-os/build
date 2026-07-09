# Phase 400 — booted-base readiness

| Item | Value |
|---|---|
| Command | `make phase 400` |
| Underlying make target | `vm/phase4/Makefile`, target `readiness` |
| Mutates disk/image? | No |
| Boots QEMU? | No |
| Main proof | Phase 4 direction is explicit before we start changing the booted image. |

## What this phase does

Phase 400 is the Phase 4 doorway.

It does not install packages, edit the image, or boot QEMU. It prints the
direction for the next implementation lane.

That matters because Phase 4 starts after a big milestone:

```text
ONIX now boots to systemd multi-user mode.
```

A booting system is exciting, but it is still not a usable system.

### What "multi-user mode" actually means

systemd organizes startup around **targets** — named groups of services that
represent a stage of boot. `multi-user.target` is the classic "the system is up,
networked, and ready for logins, but without a graphical desktop" stage. Reaching
it means PID 1 started, mounted the filesystems, and brought its base services up
without wedging.

But "reached multi-user mode" is a statement about *systemd finishing its startup
graph*, not a statement about the machine being pleasant to use. A system can
reach `multi-user.target` and still have no way to log in, no network address, and
no shell you would want to type into. Phase 400 marks exactly that gap: the boot
works, the usability does not exist yet, and Phase 4 is the plan to close the
distance.

## What we have at the start of Phase 4

From Phase 2:

- an ONIX raw disk image
- GPT partitions with ONIX labels
- systemd-boot/BLS boot menu
- borrowed Alpine virt kernel/initramfs payload
- first musl systemd userspace payload
- matching kmod/module payload
- successful QEMU boot probe

The important proof from Phase 212 after Phase 214:

```text
/boot mounted
/efi mounted
/persist mounted
/home mounted
/nix mounted
systemd reached Multi-User System
```

That is enough to start base userspace work.

## What is still missing

The image can boot, but it is still thin.

Examples of missing or early-stage areas:

- live `/etc` is mostly assembled by image scripts, not a clear ONIX policy yet
- users and login policy are not a proper ONIX base story yet
- serial console access needs to become an intentional proof, not an accident
- networking is not yet an ONIX-owned base behavior
- remote inspection is not yet a stable interface
- base service units are still mostly inherited from the temporary systemd payload

Those are Phase 4 problems.

## Why `/etc` comes first

Most real Linux behavior eventually touches `/etc`.

Examples:

```text
/etc/os-release
/etc/fstab
/etc/passwd
/etc/group
/etc/shadow
/etc/shells
/etc/hostname
/etc/systemd/system
/etc/ssh
```

ONIX wants package-owned defaults under:

```text
/usr/share/defaults
```

and live machine configuration under:

```text
/etc
```

Phase 4 should make that relationship explicit.

### Background: the stateless-`/usr` model

ONIX is an atomic distro, which means `/usr` is *stateless and package-owned*.
moss assembles a complete `/usr` tree for a system state and swaps it into place
in one indivisible step (a `renameat2` swap), keeping the old one so you can roll
back. Because `/usr` can be replaced wholesale at any update, **nothing that a
human or a running machine edits can live inside it.** Your hostname, your SSH
host keys, your `/etc/fstab` tweaks — none of that can sit in a directory that
moss is free to swap out from under you.

That is the whole reason for the split:

```text
/usr/share/defaults   read-only, package-owned templates (safe to swap)
/etc                  writable, machine-local live state (survives updates)
```

A package ships a *default* under `/usr/share/defaults`; the live copy under
`/etc` is what the machine actually reads and what the admin may override. This is
the same idea NixOS and other image-based systems reach for, and it is what makes
"a moss rollback never eats your local config" possible. Phase 401 is where that
model stops being an image-assembly accident and becomes a stated policy.

The first real implementation after Phase 400 is Phase 401:

```text
materialize live /etc from /usr/share/defaults
```

## What success looks like

Run:

```sh
make phase 400
```

Expected result:

```text
Phase 4 starts from the Phase 2 boot proof.
...
Kernel ownership remains reserved for Phase 3.
```

Then we can begin designing `401` as the first real booted-base mutation.

## Reminder

Phase 4 does not remove the Alpine kernel payload.

That replacement belongs to Phase 3 later. Phase 4 keeps using the borrowed
payload so we can focus on userspace.
