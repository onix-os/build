# Phase 414 — systemd ownership audit

| Item | Value |
|---|---|
| Command | `make phase 414` |
| Underlying scripts | `vm/phase4/systemd-ownership-audit.sh`, then `vm/phase4/materialize-etc.sh --systemd-audit` |
| Requires | Phase 413 image state |
| Mutates disk/image? | No |
| Boots QEMU? | No |
| Main proof | ONIX knows exactly what still comes from the Nix systemd payload before building `onix-systemd`. |

## Why this phase exists

Phase 410 moved the active shell/tool applets to:

```text
/usr/bin/busybox
```

from:

```text
onix-busybox.stone
```

Phase 413 moved the active SSH daemon to:

```text
/usr/sbin/dropbear
```

from:

```text
onix-dropbear.stone
```

That means two important machine-plane payloads are now ONIX package-owned.

The next big one is systemd.

But systemd is much larger than BusyBox or Dropbear.

Before writing `onix-systemd`, Phase 414 asks:

```text
What is the current systemd payload actually doing?
What paths are active?
What dependencies came along with it?
What exactly must the future stone own?
```

This is a pause-and-map phase.

It prevents us from building a fake `onix-systemd` package that only contains
one binary while the boot still secretly depends on the copied Nix closure.

### Background: what an ownership audit (debt map) is

ONIX has a hard ownership contract: machine-plane software must be owned by
moss/`.stone` packages, and the user toolbox is Nix's job. During bootstrap that
contract is deliberately violated in small, tracked ways — for example, systemd is
still a borrowed Nix payload. An **ownership audit** is the act of writing down every
place the contract is currently broken, so the debt is *explicit* rather than
forgotten. The output is a **debt map**: a list of "this file works, but it is not
yet package-owned, and here is who must eventually own it."

The reason this deserves its own phase is a subtle failure mode. It is very easy to
build a package named `onix-systemd`, point one symlink at it, declare victory, and
never notice that the boot still depends on dozens of borrowed files underneath. The
audit exists so the next package's scope is honest.

### Background: what a Nix closure is

When Nix builds something, it records every store path that build's output needs at
runtime — its dependencies, their dependencies, and so on, transitively. That
complete set is called the **closure**. So the systemd closure is not just the
systemd binary; it is systemd *plus* the musl loader it links against, `libkmod`,
`util-linux` helpers, compression libraries, and everything else required for it to
run. Phase 414 records that closure in `systemd-payload.closure`, because the future
`onix-systemd` package must reproduce ownership of the whole set, not just the one
headline binary.

## Why systemd is different from BusyBox and Dropbear

BusyBox and Dropbear are relatively small.

For this bootstrap stage:

```text
BusyBox  -> one static binary plus applet links
Dropbear -> two static binaries
```

systemd is not like that.

systemd includes:

- PID 1,
- service manager logic,
- unit files,
- target files,
- `systemctl`,
- `journalctl`,
- `udevadm`,
- `systemd-udevd`,
- tmpfiles/sysusers helpers,
- dynamic library loading behavior,
- kmod/libkmod integration,
- mount/swap/helper integration,
- compiled unit search paths.

So the future `onix-systemd` package cannot be treated as:

```text
copy one executable and call it done
```

It needs a full ownership map.

Phase 414 creates that map.

## Current boot shape

The kernel command line still says:

```text
init=/usr/lib/systemd/systemd
```

That looks like an ordinary ONIX path.

But currently `/usr/lib/systemd/systemd` is a symlink into the copied Nix
systemd payload:

```text
/usr/lib/systemd/systemd
  -> /nix/store/...-systemd-.../lib/systemd/systemd
```

The systemd unit tree is also still linked into the copied Nix payload:

```text
/usr/lib/systemd/system
  -> /nix/store/...-systemd-.../example/systemd/system
```

And command-line tools such as `systemctl` still point there:

```text
/usr/bin/systemctl
  -> /nix/store/...-systemd-.../bin/systemctl
```

That is the remaining machine-plane ownership debt.

It is not wrong for the current bootstrap stage.

It is wrong as a final ONIX package story.

## What is already fixed

Phase 414 should see that two active service paths have already moved away from
temporary Nix payloads:

```text
serial bootstrap shell -> /usr/bin/busybox
SSH server             -> /usr/sbin/dropbear
```

Those paths come from:

```text
onix-busybox
onix-dropbear
```

So the audit expects:

```text
/usr/bin/busybox
/usr/sbin/dropbear
/usr/bin/dropbearkey
```

to exist as package-owned ONIX files.

The active Dropbear service should start:

```text
ExecStart=/usr/sbin/dropbear ...
```

The serial console service should start:

```text
ExecStart=/usr/bin/busybox sh /usr/lib/onix/bootstrap-serial-shell
```

That tells us the current package migration is working.

## What remains Nix-owned

The audit expects the current systemd payload metadata:

```text
artifacts/onix-image/systemd-payload.out
artifacts/onix-image/systemd-payload.closure
```

`systemd-payload.out` names the current Nix output:

```text
/nix/store/...-systemd-...
```

`systemd-payload.closure` lists the runtime closure copied into the image.

That closure currently includes things such as:

- `systemd`,
- `musl`,
- `kmod` / libkmod,
- `util-linux-minimal`,
- `coreutils`,
- compression libraries,
- libc support libraries.

Those closure entries are not just random files.

They are clues.

They tell us what `onix-systemd` and its dependency stones may need to own.

## Why this phase checks both host artifacts and mounted image state

There are two levels of truth.

Artifact truth:

```text
What did Phase 213 record as the systemd payload?
What closure did it copy?
What stones exist in the local repo?
```

Image truth:

```text
What paths does the bootable disk actually contain?
What does /usr/lib/systemd/systemd point to?
What do the active service units execute?
```

Phase 414 checks both.

The wrapper script checks host artifacts first:

```text
systemd-payload.out
systemd-payload.closure
artifacts/onix-local-repo/stone.index
```

Then it asks the existing materializer to mount the image and inspect the live
filesystem state:

```sh
./materialize-etc.sh --systemd-audit
```

Using the materializer matters because it already has the safe sudo path for
attaching the generated ONIX disk image.

## Why stale old payloads are allowed here

The audit may report old BusyBox or Dropbear Nix payload paths still present on
disk.

That is okay for Phase 414.

There is a difference between:

```text
active path
```

and:

```text
old file still present
```

Phase 410 and Phase 413 changed the active paths.

They did not yet garbage-collect old copied payloads.

Garbage collection is a later cleanup/audit step. Removing old files too early
can make debugging harder because two different questions get mixed together:

```text
Did the new package path work?
Did cleanup remove exactly the right old files?
```

Phase 414 keeps those separate.

## What `make phase 414` verifies

The phase verifies host-side artifacts:

- `artifacts/onix-image/systemd-payload.out` exists,
- `artifacts/onix-image/systemd-payload.closure` exists,
- the systemd closure contains a systemd Nix output,
- the closure contains expected dependency families such as kmod, util-linux,
  and musl,
- the local Phase 4 repo contains `onix-busybox`,
- the local Phase 4 repo contains `onix-dropbear`.

Then it verifies mounted image state:

- `/usr/lib/systemd/systemd` exists,
- `/usr/lib/systemd/systemd` still points to the Nix systemd payload,
- `/usr/lib/systemd/system` still points to the Nix unit tree,
- `/usr/bin/systemctl` still points to the Nix systemd payload,
- the boot entry still uses `init=/usr/lib/systemd/systemd`,
- the serial shell unit uses `/usr/bin/busybox`,
- the Dropbear unit uses `/usr/sbin/dropbear`,
- `onix-busybox` files are present,
- `onix-dropbear` files are present.

That gives us a precise before-picture for `onix-systemd`.

## What this phase does not do

Phase 414 does not build systemd.

It does not install `onix-systemd`.

It does not delete the Nix systemd closure.

It does not redesign unit ownership.

It only says:

```text
Here is the current boundary.
Here is what still depends on Nix.
Here is what Phase 415 must start replacing.
```

## Expected output shape

Run:

```sh
make phase 414
```

You should see:

```text
systemd  : active PID 1 path is /usr/lib/systemd/systemd
systemd  : /usr/lib/systemd/systemd -> /nix/store/...-systemd-.../lib/systemd/systemd
stone    : /usr/bin/busybox is present from onix-busybox
stone    : /usr/sbin/dropbear is present from onix-dropbear
debt     : systemd, udev, systemctl, kmod/libkmod, util-linux helpers, and musl loader support remain in the Nix systemd closure
```

And at the end:

```text
==> success
Phase 414 audited the current systemd boundary.
```

## Next step

Phase 415 should begin the first `onix-systemd.stone`.

The first version can still be narrow, but it must be honest.

It should not pretend the job is only:

```text
package /usr/lib/systemd/systemd
```

The audit tells us the real package boundary includes:

- systemd binaries,
- systemd unit/default directories,
- helper commands,
- runtime dependency ownership,
- musl loader/runtime behavior,
- kmod/util-linux relationships,
- eventual movement of bootstrap units out of the borrowed Nix unit tree.

That is why Phase 414 exists before Phase 415.
