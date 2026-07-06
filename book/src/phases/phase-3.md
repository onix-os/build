# Phase 3 overview — ONIX-owned kernel work, intentionally deferred

Phase 3 is reserved for the kernel/initramfs/modules story.

It is intentionally not the next implementation lane.

## Why reserve a whole phase?

The kernel is not just "one more package".

A Linux kernel payload is a bundle of tightly-coupled pieces:

```text
kernel image
  + exact module tree
  + initramfs
  + firmware policy
  + bootloader entries
  + update/rollback rules
```

Those pieces have to match each other exactly.

For example, if the booted kernel is:

```text
6.18.38-0-virt
```

then the module loader expects:

```text
/usr/lib/modules/6.18.38-0-virt
```

If the kernel and module directory do not match, `modprobe` can fail even though
the filesystem looks populated.

The initramfs has the same coupling. It must know how to find and mount the
real root filesystem before systemd ever starts.

That makes kernel ownership a large, self-contained project. Mixing it into the
base userspace work would make the learning path much harder to follow.

## Current Phase 2 compromise

Phase 2 proved that ONIX can assemble and boot a real disk image. To keep that
proof focused, it borrowed the kernel payload from the Alpine forge:

```text
vm/state/vmlinuz-virt
vm/state/initramfs-virt
```

Phase 214 also borrowed the matching module tree from that same initramfs.

That is acceptable for the current boot proof because:

- the kernel and modules match each other
- the initramfs already knows how to mount the ONIX root
- it lets us test systemd-on-musl and the image layout now

It is not the final ONIX design.

## What Phase 3 will eventually own

Later, Phase 3 should replace the borrowed Alpine payload with ONIX-owned
artifacts:

- an ONIX kernel config
- an ONIX kernel build recipe
- an ONIX module package
- an ONIX initramfs generator path
- boot entry generation/update rules
- rollback rules for kernel and userspace together

The goal is not merely "compile Linux". The goal is:

```text
ONIX can update and roll back kernel + initramfs + modules coherently.
```

## What Phase 3 does right now

For now, Phase 3 has one documentation/checkpoint step:

- [300 — deferred kernel ownership contract](./300.md)

Running:

```sh
make phase 3
```

prints the deferment clearly and points the work forward to Phase 4.

## Why Phase 4 comes next

The current ONIX image already reaches systemd multi-user mode.

The next useful learning step is not compiling a kernel. The next useful step is
making the booted image into a usable base system:

- live `/etc` materialization
- users/login/shell basics
- serial login
- networking
- remote inspection

That is Phase 4.
