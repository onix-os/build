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
402 — create base users/groups/shell policy
403 — prove bootstrap serial root console
404 — add minimal QEMU user networking inspection
405 — prove host-to-guest TCP inspection
406 — prove authenticated SSH access
407 — audit temporary Nix-sourced system payloads
408 — define local stone/repo contract
409 — build `onix-busybox.stone`
410 — install/use `onix-busybox` in the image
411 — rerun shell/network/SSH proofs against stone BusyBox
412 — build `onix-dropbear.stone`
413 — install/use `onix-dropbear` and rerun SSH proof
414 — systemd stone dependency audit
415 — build first `onix-systemd.stone`
416 — install `onix-systemd` into the image
417 — boot with `onix-systemd` as PID 1
418 — move bootstrap units/defaults into stone ownership
419 — audit no Nix-sourced systemd/busybox/dropbear payload remains
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
- [401 — materialize live `/etc`](./401.md)
- [402 — base users, groups, and shell policy](./402.md)
- [403 — bootstrap serial root console proof](./403.md)
- [404 — minimal QEMU user networking proof](./404.md)
- [405 — host-to-guest TCP inspection proof](./405.md)
- [406 — authenticated SSH proof](./406.md)
- [407 — machine-plane ownership audit](./407.md)
- [408 — local stone/repo contract](./408.md)
- [409 — build `onix-busybox.stone`](./409.md)
- [410 — install/use `onix-busybox`](./410.md)
