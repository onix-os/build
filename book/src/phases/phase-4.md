# Phase 4 overview — booted ONIX base userspace

Phase 4 starts from the Phase 2 boot proof.

Phase 2 answered:

```text
Can ONIX assemble a disk image and reach systemd multi-user mode?
```

The answer is now yes.

Phase 4 asks a different question:

```text
Can the booted image become a usable base system?
```

## What "base userspace" means

The kernel gets the machine started, but userspace is what makes it usable.

After the kernel mounts the real root filesystem, it starts PID 1:

```text
/usr/lib/systemd/systemd
```

From that point onward, userspace is responsible for:

- creating or validating `/etc` state
- starting udev
- discovering disks and network devices
- mounting local filesystems
- creating users and groups
- starting login prompts
- starting SSH or other remote inspection tools
- preserving persistent state under `/persist`

Phase 2 proved the minimum handoff.

Phase 4 makes that handoff useful.

## The important boundary with Phase 3

Phase 4 does not own the kernel.

For now the image keeps using the borrowed Alpine virt kernel/initramfs/module
payload proved in Phase 2:

```text
vm/state/vmlinuz-virt
vm/state/initramfs-virt
```

That lets Phase 4 focus on the booted system itself:

```text
/etc
/usr
/persist
/home
/nix
systemd units
users
login
networking
```

Kernel ownership remains reserved for Phase 3.

## Initial Phase 4 direction

The first Phase 4 subphases should be small and observable.

Proposed path:

```text
400 — Phase 4 readiness and direction
401 — materialize live /etc from /usr/share/defaults
402 — create base users/groups/login shell policy
403 — prove serial login
404 — add minimal networking inspection
405 — add SSH or another remote inspection path
```

The exact list can change as we learn, but the theme should stay stable:

```text
make the booted image inspectable, login-capable, and base-system shaped
```

## What Phase 4 should not do yet

Phase 4 should avoid:

- building the ONIX kernel
- designing the desktop stack
- adding Nix integration
- solving Mesa/graphics
- making a huge package set

Those are later phases. The base system must become understandable first.

## Steps

- [400 — booted-base readiness](./400.md)
