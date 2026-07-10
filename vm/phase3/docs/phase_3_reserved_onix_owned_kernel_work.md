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

## Background: kernel, modules, and initramfs from scratch

If you have only ever *used* Linux, the boot chain can feel like magic. It is
worth spelling out, because Phase 3 exists precisely to own this chain.

**The kernel** is the single program the bootloader loads into memory and jumps
into. It drives the CPU, memory, and hardware, and it exposes the system-call
interface that every other program uses. On disk it is a single compressed file
(`vmlinuz`).

**Kernel modules** are pieces of the kernel that are *not* baked into that single
file. Instead of compiling every possible driver into `vmlinuz` (which would make
it huge), most drivers are built as separate `.ko` files loaded on demand. They
live in a versioned tree:

```text
/usr/lib/modules/<kernel-release>/
```

The `<kernel-release>` string is stamped into the kernel at build time. When you
run `modprobe e1000e`, the loader looks under exactly that release directory. If
the running kernel says `6.18.38-0-virt` but the only module tree on disk is for a
*different* release, `modprobe` finds nothing — even though modules are clearly
present. That is why "the module tree must match the kernel" is not a style
preference; it is a hard lookup rule.

**The initramfs** (initial RAM filesystem) is a small, self-contained root
filesystem the bootloader loads into memory *alongside* the kernel. The kernel
cannot mount your real root filesystem until it has the driver for the disk
controller and the filesystem type. But those drivers are modules, and the
modules live *on* the root filesystem you cannot mount yet — a chicken-and-egg
problem. The initramfs breaks the cycle: it carries just enough modules and a
tiny init script to find, unlock, and mount the real root, then hands control
over to the real init. So the initramfs also has to contain modules that match
the running kernel's release.

The chain, drawn out:

```text
bootloader
  -> loads kernel (vmlinuz) + initramfs into RAM
  -> kernel starts, runs the initramfs
       -> initramfs loads disk/filesystem modules
       -> initramfs mounts the real root filesystem
       -> initramfs execs the real PID 1 (systemd)
```

Every link couples to the next: bootloader entry -> kernel -> matching modules ->
initramfs that knows how to reach *this* root. Change one and you can break boot
before a single log line is readable.

## Current Phase 2 compromise

Phase 2 proved that ONIX can assemble and boot a real disk image. To keep that
proof focused, it borrowed the kernel payload from the Alpine forge:

```text
vm/state/vmlinuz-virt
vm/state/initramfs-virt
```

Phase 214 also borrowed the matching module tree from that same initramfs.

### What "borrowed Alpine virt kernel" means

Recall the two-plane story from the architecture chapter. ONIX builds its own
musl base from scratch, using AerynOS's *tooling* (moss + boulder) but none of
its packages. The **Alpine forge** (hostname `quarry`) is a throwaway musl VM
where that tooling is built and the first `.stone` packages are cut. The rule is
strict: **nothing Alpine ships ends up in ONIX** — not its package manager, not
its packages, and eventually not its kernel.

The one deliberate exception, for now, is the kernel payload. Alpine ships a
prebuilt `-virt` kernel image, a matching initramfs, and a matching module tree,
all tuned for virtual machines. Phase 2 copied those three coupled pieces into
`vm/state/` and used them to boot the ONIX image. "Borrowed" is the honest word:
they are on loan to unblock the userspace proofs, and Phase 3 is the scheduled
moment to give them back and build ONIX's own.

Because all three came out of the *same* Alpine artifact, they already match each
other — same `<kernel-release>`, same driver set, an initramfs that already knows
how to mount the ONIX root layout. That internal consistency is the only reason
the borrowed payload works at all.

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

### Why coherent rollback is the real problem

ONIX is an *atomic* distro. moss swaps `/usr` in one indivisible step and keeps
old system states so you can roll back a bad update. The kernel is machine-plane
state, so it must live inside that same transactional story — and that is exactly
what makes it hard.

A kernel "generation" is not one file; it is the coupled triple (kernel image +
matching modules + matching initramfs) plus a BLS boot-menu entry that points at
them. To roll back safely, moss cannot just restore an old `/usr` and leave a new
kernel booted against old modules, or an old boot entry pointing at a kernel that
was pruned. Every rollback must move the whole triple *and* its boot entry
*together*, atomically, or the machine can fail to boot after a rollback — the one
situation the whole atomic design exists to prevent.

Owning a kernel that "compiles and boots once" is a weekend. Owning a kernel that
updates and rolls back coherently, generation after generation, alongside
userspace, is a project. That is the line Phase 3 is drawn around.

## What Phase 3 does right now

For now, Phase 3 has one documentation/checkpoint step:

- [300 — deferred kernel ownership contract](./300_deferred_kernel_ownership_contract.md)

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
- users/groups/shell policy
- bootstrap serial console
- networking
- remote inspection

That is Phase 4.
