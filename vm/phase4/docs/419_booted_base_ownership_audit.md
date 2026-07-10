# Phase 419 — booted-base ownership audit

| Item | Value |
|---|---|
| Command | `make phase 419` |
| Wrapper script | `vm/phase4/booted-base-ownership-audit.sh` |
| Rootful implementation | `vm/phase4/materialize-etc.sh --booted-base-audit` |
| Mutates disk/image? | No |
| Boots QEMU? | No |
| Main proof | The mounted image has a coherent ownership map after Phases 409-418, and the remaining debt is explicit. |

## Why this phase exists

Phase 4 has moved quickly.

We now have several real stones:

```text
busybox
dropbear
systemd
bootstrap-policy
```

And the image can boot with:

```text
systemd as PID 1
bootstrap networking
bootstrap SSH
package-owned bootstrap policy source
```

Before adding more machinery, Phase 419 stops and asks:

```text
What exactly is owned now?
What is still glue?
What is still Nix-built?
What is still borrowed?
```

This is important because an OS project can become confusing fast.

If we do not keep an ownership map, we can accidentally confuse:

```text
works at runtime
```

with:

```text
is owned cleanly by ONIX packages
```

Those are different claims.

## Read-only audit mode

Phase 419 should not change the image.

It mounts the image read-only:

```text
root    -> read-only XFS mount
boot    -> read-only VFAT mount
persist -> read-only XFS mount
```

The wrapper script is:

```text
vm/phase4/booted-base-ownership-audit.sh
```

But that wrapper does not become a new sudoers entrypoint.

It calls:

```text
vm/phase4/materialize-etc.sh --booted-base-audit
```

That matters because `materialize-etc.sh` is already the approved Phase 4
rootful image tool.

We avoid adding another root-capable script just to mount the image.

Mounting **read-only** is a deliberate safety property for an audit. An audit's whole
value is that it reports the image as it is; if the act of inspecting could also
change the image, you could never fully trust the report, and a buggy audit could
corrupt working state. Read-only mounts make that impossible by construction — the
kernel refuses writes to the mount — so the audit can only *observe*. It also keeps a
clean separation of duties in Phase 4: phases that change the image (410, 413, 416,
418, 420) are distinct from phases that only describe it (407, 414, 419).

## What the audit checks

The audit checks the mounted image and prints a report.

It verifies the current expected state before printing the map.

Important checks include:

```text
/usr/bin/busybox exists
/usr/sbin/dropbear exists
/usr/lib/systemd/systemd resolves to the current systemd payload
/usr/lib/onix/bootstrap-* scripts exist
/usr/lib/onix/systemd/system/*.service source units exist
active systemd units match the package-owned source units
package notes exist under /usr/share/onix/packages
```

The important unit comparison is:

```text
/usr/lib/onix/systemd/system/*.service
  == /nix/store/...-systemd-.../example/systemd/system/*.service
```

That is the Phase 418 promise.

The package owns the source unit.

The active unit tree still receives an activation copy.

## Ownership buckets

The report uses a few buckets.

### Stone-owned now

These are owned by `.stone` packages:

```text
/usr/bin/busybox
/usr/sbin/dropbear
/usr/bin/dropbearkey
/usr/lib/onix/bootstrap-*
/usr/lib/onix/systemd/system/*.service
/usr/share/onix/packages/*.md
```

And systemd is now package-owned in the bootstrap sense:

```text
/usr/lib/onix/bootstrap/nix/store/...
/usr/lib/systemd/systemd
/usr/bin/systemctl
/usr/bin/journalctl
/usr/bin/udevadm
```

But systemd still deserves a separate note because the bytes were built by
pinned Nix.

### Activation glue

The current active systemd unit tree is still:

```text
/nix/store/...-systemd-.../example/systemd/system
```

So Phase 418 still copies package-owned unit source files into that tree.

That is activation glue.

It works, but it is not final.

Later ONIX should replace it with a package trigger, systemd preset flow, or
some other deliberate activation mechanism.

### Nix-built debt

The first `systemd` package is a bootstrap ownership stone.

It owns the systemd payload as package content, but the payload came from:

```text
nixpkgs pkgsMusl.systemd
```

So Phase 419 reports:

```text
systemd payload path
runtime closure count
musl loader path
/nix/store compatibility requirement
```

This tells us what must disappear later if we want a fully native ONIX systemd
stack.

### Borrowed kernel/initramfs debt

Phase 4 still intentionally uses the Alpine virt kernel/initramfs/module
payload from Phase 2.

That debt belongs to Phase 3.

Phase 419 names it so we do not forget:

```text
vm/state/vmlinuz-virt
vm/state/initramfs-virt
/usr/lib/modules
```

### Live machine state

Some files should not be immutable package payload.

Examples:

```text
/etc/passwd
/etc/group
/etc/shadow
/etc/dropbear/dropbear_ed25519_host_key
/persist/home/onix/.ssh/authorized_keys
/etc/machine-id
```

Those are live machine state or materialized policy.

The audit lists them separately so we do not mistake live state for package
ownership.

## Why this phase does not boot QEMU

Phase 417 and Phase 418 already boot-proved runtime behavior.

Phase 419 is different.

It is an image ownership report.

Booting QEMU would prove runtime behavior again, but it would not make the
ownership map clearer.

So Phase 419 mounts the image and inspects it directly.

## What this phase proves

Phase 419 proves:

- the image still has the expected Phase 418 state,
- the active bootstrap units match package-owned source units,
- the current stone-owned payloads are visible,
- the current Nix-built debt is explicit,
- the kernel/initramfs/module debt is still Phase 3 work,
- the next decision can be based on a concrete ownership map.

## What this phase does not prove

Phase 419 does not:

- build a new package,
- boot QEMU,
- remove any old payload,
- make systemd native,
- implement package triggers,
- solve the kernel.

It is a checkpoint.

The goal is clarity.

## Expected output shape

Successful output includes sections like:

```text
== Stone-owned machine-plane payloads ==
stone       : /usr/bin/busybox present
stone       : /usr/sbin/dropbear present
stone       : /usr/lib/systemd/systemd -> /nix/store/...

== Active bootstrap units ==
unit-match  : onix-bootstrap-network.service source == active root unit

== Activation glue still present ==
activation : package-owned unit sources are copied into:
activation :   /nix/store/.../example/systemd/system

== Nix-built bootstrap debt still present ==
nix-built  : systemd payload path /nix/store/...-systemd-...

== Borrowed kernel/initramfs/module debt ==
borrowed   : vm/state/vmlinuz-virt present
```

At the end it gives a conclusion and possible next direction.

## Next step

After Phase 419, Phase 420 starts with the smallest safe debt bucket:

```text
stale old Nix BusyBox/Dropbear payloads
```

That is intentionally smaller than:

```text
activation glue
native systemd dependency ownership
```

The audit exists so that this choice is explicit instead of accidental.
