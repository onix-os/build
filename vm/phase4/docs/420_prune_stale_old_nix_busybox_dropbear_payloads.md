# Phase 420 — prune stale old Nix BusyBox/Dropbear payloads

| Item | Value |
|---|---|
| Command | `make phase 420` |
| Wrapper script | `vm/phase4/prune-stale-bootstrap-nix.sh` |
| Rootful implementation | `vm/phase4/materialize-etc.sh --prune-stale-bootstrap-nix` |
| Mutates disk/image? | Yes |
| Boots QEMU? | No |
| Main proof | The old bootstrap-only Nix BusyBox/Dropbear output roots are absent, while the active systemd closure still exists. |

## Why this phase exists

Earlier Phase 4 steps needed small tools before ONIX had real packages for
those tools.

At that time we copied temporary Nix-built payloads into the image:

```text
BusyBox from Nix
Dropbear from Nix
```

Those were useful bootstrap tools.

But later we built real ONIX stones:

```text
onix-busybox
onix-dropbear
```

And then we proved that the booted system uses those stones:

```text
/usr/bin/busybox
/usr/bin/sh
/usr/sbin/dropbear
/usr/bin/dropbearkey
```

So Phase 420 removes the stale old Nix copies.

The goal is not:

```text
remove all of /nix/store
```

That would break the image.

The goal is narrower:

```text
remove the old bootstrap-only BusyBox/Dropbear Nix outputs
```

## Background: why the Nix store shares paths

The `/nix/store` holds each build output in its own directory whose name includes a
hash of everything that produced it. A key consequence: if two different programs
need the *same* version of, say, musl built the same way, they both reference the
*one* store path for it — the store does not keep duplicate copies. This sharing is
what makes deletion dangerous. A store path can look like it "belongs to" the old
Dropbear because Dropbear's closure lists it, while systemd's closure lists the exact
same path. Deleting it to clean up Dropbear would quietly break systemd. That is why
Phase 420 never deletes by name; it deletes only paths that are in the stale closures
*and not* in the live systemd closure.

## Why we cannot delete the whole old closure blindly

A Nix closure is a set of store paths needed by one output.

For example, old Nix Dropbear may have depended on:

```text
/nix/store/...-dropbear-...
/nix/store/...-musl-...
/nix/store/...-libxcrypt-...
/nix/store/...-zlib-...
```

But systemd may also need some of those same dependency paths.

For example:

```text
/nix/store/...-musl-...
/nix/store/...-libxcrypt-...
```

So if we blindly deleted every path listed in the old Dropbear closure, we could
delete paths that systemd still needs.

That would be a classic OS bring-up mistake:

```text
we removed "unused" files without checking whether they were shared
```

Phase 420 avoids that.

## The safety rule

Phase 420 uses this rule:

```text
delete old BusyBox/Dropbear closure paths only if they are NOT listed in the
active systemd closure
```

In simpler words:

```text
old BusyBox-only path? delete it.
old Dropbear-only path? delete it.
shared with systemd? keep it.
systemd path? keep it.
```

That is why Phase 420 needs three pieces of metadata:

```text
artifacts/onix-image/serial-console-payload.closure
artifacts/onix-image/dropbear-payload.closure
artifacts/onix-image/systemd-payload.closure
```

The first two describe the old bootstrap-only closures.

The last one describes what systemd still needs.

## Where paths are removed from

The stale paths are removed from the runtime stores:

```text
/nix/store
/persist/nix/store
```

That matters because the image currently has both:

```text
root filesystem store:
  /nix/store

persistent store:
  /persist/nix/store
```

Phase 420 does **not** remove the packaged systemd bootstrap copy under:

```text
/usr/lib/onix/bootstrap/nix/store
```

That directory is owned by `onix-systemd`.

It is the package-owned source used to materialize systemd's runtime closure
into `/nix/store`.

## What remains after this phase

After Phase 420, these should still exist:

```text
/usr/bin/busybox
/usr/bin/sh
/usr/sbin/dropbear
/usr/bin/dropbearkey
/usr/lib/systemd/systemd
/nix/store/...-systemd-...
/persist/nix/store/...-systemd-...
/usr/lib/onix/bootstrap/nix/store/...-systemd-...
```

But the old Nix output roots should be gone:

```text
/nix/store/...-busybox-...
/persist/nix/store/...-busybox-...
/nix/store/...-dropbear-...
/persist/nix/store/...-dropbear-...
```

Shared dependencies may remain.

That is expected.

For example, if the old Dropbear closure and the active systemd closure both
used the same musl or libxcrypt store path, Phase 420 keeps it.

## Why this phase does not boot QEMU

Phase 420 is a mounted-image cleanup.

It checks the filesystem directly:

```text
is the stale old path gone?
is systemd still present?
are the stone-owned replacements still present?
do the bootstrap units still point at the stone-owned paths?
```

Booting QEMU would be useful as an additional confidence check, but the primary
question in this phase is filesystem ownership and stale payload removal.

Runtime boot proofs already happened in:

```text
411 — boot-prove onix-busybox
413 — install/use onix-dropbear and prove SSH
417 — boot-prove onix-systemd
418 — package/prove bootstrap policy ownership
```

If a later phase changes the boot path again, it should boot-prove again.

## What this phase proves

Phase 420 proves:

- the old BusyBox Nix output root is absent from `/nix/store` and
  `/persist/nix/store`,
- the old Dropbear Nix output root is absent from `/nix/store` and
  `/persist/nix/store`,
- shared paths with systemd are preserved,
- the systemd runtime closure is still present,
- `onix-busybox` still owns the active BusyBox command path,
- `onix-dropbear` still owns the active SSH command path,
- active bootstrap units no longer reference the old Nix BusyBox path.

## What this phase does not solve

Phase 420 does not:

- remove systemd's Nix-built closure,
- make systemd natively built by ONIX,
- implement package garbage collection,
- implement package triggers or systemd preset activation,
- remove the borrowed Alpine kernel/initramfs/modules,
- change the bootloader or kernel command line.

Those are separate pieces of debt.

The important thing is that Phase 420 removes a safe, small piece of debt
without pretending the bigger debt is gone.

## Mental model

Think of the image as having three categories:

```text
1. active stone-owned runtime
2. active Nix-backed systemd compatibility
3. stale bootstrap leftovers
```

Phase 420 deletes only category 3.

It leaves category 1 and category 2 alone.

That is the correct level of caution for an OS bring-up step.

## Next step

After this cleanup, the biggest remaining Phase 4 system-package debt is:

```text
systemd is package-owned but still Nix-built
```

So the next compressed step is:

```text
421 — prepare native source-built onix-systemd
422 — build/install/boot-prove native onix-systemd
```
