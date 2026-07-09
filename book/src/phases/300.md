# Phase 300 — deferred kernel ownership contract

| Item | Value |
|---|---|
| Command | `make phase 300` |
| Underlying make target | `vm/phase3/Makefile`, target `kernel-deferred` |
| Mutates disk/image? | No |
| Boots QEMU? | No |
| Main proof | The project explicitly reserves kernel ownership for later instead of mixing it into Phase 4. |

## What this phase means

Phase 300 is a deliberate pause.

It records that ONIX currently boots with a borrowed Alpine virt kernel payload,
and that this is a temporary bootstrap choice.

The borrowed files are:

```text
vm/state/vmlinuz-virt
vm/state/initramfs-virt
```

Phase 214 extracts the matching module tree from that initramfs so the booted
system has:

```text
/usr/lib/modules/<borrowed-kernel-release>
```

This is internally consistent. That is why it works.

But it is not ONIX-owned yet.

### Why the module tree has to be extracted at all

A running kernel loads drivers by name from a versioned directory:

```text
/usr/lib/modules/<kernel-release>/
```

The `<kernel-release>` value is stamped into the kernel binary itself. `modprobe`
and the kernel's autoload machinery look under *exactly* that release path and
nowhere else. So a booted system that has the Alpine `-virt` kernel but no
matching module directory would be unable to load a single driver on demand — the
loader would report "module not found" even though the filesystem is otherwise
healthy.

The borrowed initramfs already carries the modules the boot chain needs (it must,
to mount the root filesystem in the first place). Phase 214 unpacks that initramfs
and copies its module tree into the ONIX root under the matching release path. The
result is a self-consistent set: the borrowed kernel, the borrowed initramfs, and
a module tree taken from the very same initramfs, all agreeing on one
`<kernel-release>`. Consistency-by-shared-origin is doing all the work here.

## Why not build the kernel immediately?

Because kernel work has a different risk profile from userspace work.

Userspace phases can usually be changed incrementally:

```text
add file
boot
inspect log
fix service
boot again
```

Kernel ownership has tighter coupling:

```text
kernel config
  must match modules
  must match initramfs
  must match root filesystem drivers
  must match bootloader entries
```

If any part is wrong, the failure may happen before systemd starts, before SSH
starts, and sometimes before the logs are pleasant to read.

So Phase 3 gets its own lane.

## How this fits the ownership contract

The kernel, its modules, and the initramfs are all **machine-plane** state. Under
the ONIX constitution — *moss controls the machine, Nix controls the toolbox* —
machine-plane state must eventually be owned by moss-installed `.stone` packages,
never by Nix and never by a borrowed foreign artifact. So the borrowed Alpine
payload is a known, named piece of bootstrap debt, exactly like the temporary Nix
BusyBox and Dropbear payloads that Phase 407 catalogues. The difference is scale:
retiring the kernel debt is large enough to deserve its own phase rather than a
single subphase. Recording that debt honestly now is what keeps the design from
quietly drifting into "ONIX runs on Alpine's kernel forever."

## What the eventual Phase 3 should answer

Later Phase 3 should answer:

1. Which kernel source and version does ONIX track?
2. How is the kernel configured?
3. How are modules packaged?
4. How is the initramfs generated?
5. Which files are written to `/boot`?
6. How are old kernel generations retained or pruned?
7. How does a moss rollback relate to a kernel rollback?
8. How do we prove kernel, initramfs, and modules are from the same generation?

Until those answers exist, the Alpine payload is a useful bootstrapping tool.

## What success looks like right now

Run:

```sh
make phase 300
```

Expected output:

```text
Phase 3 is intentionally reserved for ONIX-owned kernel/initramfs/modules.
...
For now, continue with Phase 4: booted ONIX base userspace.
```

That is all this phase should do today.

## What comes next

Continue with:

```sh
make phase 400
```

Phase 400 starts the booted-base lane. It assumes the Phase 2 image can boot
with the temporary borrowed kernel payload.
