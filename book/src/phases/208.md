# Phase 208 — systemd userspace contract

## At a glance

| Field | Value |
|---|---|
| Phase family | Phase 2 — bootable image |
| Run command | `make phase 208` |
| Underlying make target/script | `vm/phase2/verify-systemd-userspace-plan.sh` |
| Runs on | host |
| Main proof/artifact | Verifies the systemd userspace ownership and PID 1 contract. |


Phase 208 is also a contract phase.

Phase 208 does not build systemd.
It does not copy host systemd.
It does not copy Nix systemd.
It does not mount the image.
It does not boot QEMU.

This phase exists because the Phase 206 boot entry already says:

```text
init=/usr/lib/systemd/systemd
systemd.unit=multi-user.target
```

That means the future kernel/initramfs handoff expects the real root filesystem
to contain:

```text
/usr/lib/systemd/systemd
```

Before we build or import that file, we need to say what owns it and what
minimum userspace shape must exist around it.

#### What PID 1 means

When Linux starts userspace, the first normal process gets process ID 1:

```text
PID 1
```

PID 1 is special. It becomes the init system for the machine.

It is responsible for starting and supervising the rest of userspace:

```text
mounts
device management
services
login
shutdown
reboot
cleanup of orphaned processes
```

For ONIX, the planned PID 1 path is:

```text
/usr/lib/systemd/systemd
```

That is why Phase 206 put this on the kernel command line:

```text
init=/usr/lib/systemd/systemd
```

#### Why not copy host systemd

The Phase 208 decision is:

```text
do not copy host systemd
do not copy Nix systemd
```

The host systemd belongs to the developer machine.
The Nix systemd belongs to the Nix toolbox environment.

ONIX is meant to be a musl-based OS. A random host or Nix systemd may be built
for a different libc, with a different layout, with different assumptions about
paths, users, groups, services, and dependencies.

> **musl vs glibc, and why it makes systemd hard.** Every Linux program is linked
> against a **C library** that provides the basic system-call glue. **glibc** is
> the big, feature-rich default on most distros; **musl** is a small, strict,
> from-scratch alternative (the one Alpine and ONIX use). They are not
> drop-in-compatible: glibc has extensions musl deliberately omits. systemd is
> written assuming glibc in places, so building it on musl needs patches — which
> is precisely why ONIX cannot just grab a host or Nix systemd binary and why the
> *next* step, 209, is a dedicated feasibility gate that checks whether a
> musl-targeted systemd is even obtainable before committing to the path.

So the future package must be ONIX-owned:

```text
onix-systemd
```

That package name is the contract for now. It may eventually be split into
smaller packages, but the ownership rule is clear: ONIX must provide its own
systemd userspace rather than smuggling in the host one.

#### What systemd userspace must include

The minimum future `onix-systemd` package needs more than one binary.

At minimum, the contract needs:

```text
/usr/lib/systemd/systemd
/usr/lib/systemd/systemd-udevd
/usr/bin/systemctl
/usr/bin/journalctl
/usr/lib/systemd/system/multi-user.target
```

`systemd-udevd` matters because device nodes and device events are part of
turning early boot into a usable machine.

> **What udev does.** The kernel discovers hardware asynchronously and announces
> it as a stream of events. **udev** (here `systemd-udevd`) listens to that stream
> and reacts: it creates the right device nodes under `/dev`, applies naming and
> permissions, and loads modules for newly-seen hardware. Without it, `/dev` is a
> nearly empty directory and userspace has no reliable way to find disks, input
> devices, or network interfaces. It is the bridge from "the kernel sees hardware"
> to "userspace can use it".

`multi-user.target` matters because the Phase 206 boot entry already asks for:

```text
systemd.unit=multi-user.target
```

So the target file must exist at:

```text
/usr/lib/systemd/system/multi-user.target
```

#### Runtime filesystems systemd expects

Some paths are not normal package payload. They are runtime filesystems mounted
by the kernel, initramfs, or early userspace:

```text
/run
/dev
/proc
/sys
```

ONIX packages can create the mount-point directories, but they should not ship
host contents for those paths.

That matches the earlier root-tree rule:

```text
/dev   runtime devices
/proc  kernel process/info view
/sys   kernel device/info view
/run   runtime state
```

#### Machine identity and defaults

systemd also expects some machine-local state and policy.

Important early files include:

```text
/etc/machine-id
/etc/fstab
```

`/etc/machine-id` is the unique machine identity. It should not be a baked-in
shared ID copied into every image forever. The first real boot path needs a
policy for creating or seeding it safely.

> **Why a shared machine-id is a bug.** `/etc/machine-id` is a 128-bit id systemd
> uses to identify *this specific machine* — for journald, for per-machine state,
> and for anything keyed on identity. If every image shipped the same baked-in id,
> every ONIX install would claim to be the same machine, which breaks logging and
> any per-host bookkeeping. The correct pattern is to ship it *empty* (or absent)
> and let first boot generate a fresh id, so identity is minted per install, not
> copied. This is one of the must-persist files noted in the architecture: once
> generated, it has to survive across reboots and updates.

`/etc/fstab` already comes from the ONIX filesystem package defaults and is
materialized by image assembly.

#### tmpfiles and sysusers

Two common systemd mechanisms matter for package integration:

```text
tmpfiles
sysusers
```

`tmpfiles` describes runtime directories, files, permissions, and cleanup rules.

`sysusers` describes system users and groups that packages need.

ONIX should eventually support package-owned defaults such as:

```text
/usr/lib/tmpfiles.d/*.conf
/usr/lib/sysusers.d/*.conf
```

This lets packages declare system integration without editing live `/etc`
directly.

> **Why tmpfiles and sysusers fit an atomic distro so well.** Both are
> *declarative*: a package drops a `.conf` under `/usr/lib/...` saying "this
> directory should exist with these permissions" or "this system user/group should
> exist", and systemd materializes it at boot. That is the opposite of the drift
> ONIX exists to avoid, where an installer imperatively runs `useradd` and edits
> `/etc` once, forever. Because the declarations live under `/usr` (atomic,
> package-owned), a moss rollback also rolls back the *rules*, and the next boot
> re-materializes the correct users and directories. This is exactly the mechanism
> Phase 3 leans on for the Nix build users (`nixbld`, GID 6649).

#### Future file contract

The future root filesystem must provide:

```text
/usr/lib/systemd/systemd
/usr/lib/systemd/systemd-udevd
/usr/lib/systemd/system/multi-user.target
```

The future image or first-boot policy must handle:

```text
/etc/machine-id
/run
/dev
/proc
/sys
```

The future package name for this responsibility is:

```text
onix-systemd
```

Again: ONIX should build or package this intentionally for its musl base.

#### What Phase 208 verifies

`make phase 208` verifies:

- this Phase 208 section exists
- the planned PID 1 path is `/usr/lib/systemd/systemd`
- the boot entry still asks for `systemd.unit=multi-user.target`
- the target path is `/usr/lib/systemd/system/multi-user.target`
- the plan names `onix-systemd`
- the plan says `musl`
- the plan says `do not copy host systemd`
- the plan says `do not copy Nix systemd`
- the plan mentions `systemd-udevd`
- the plan mentions `/etc/machine-id`
- the plan mentions `/run`, `/dev`, `/proc`, and `/sys`
- the plan mentions `tmpfiles`
- the plan mentions `sysusers`
- the Phase 206 image script still points at `/usr/lib/systemd/systemd`

This makes Phase 208 a checkpoint between "the boot entry names systemd" and
"ONIX actually provides systemd userspace".

#### What Phase 208 does not prove

Phase 208 does not prove:

```text
systemd builds on musl
systemd starts as PID 1
udev works
services start
the image boots
```

Those are later phases. This phase only protects the ownership boundary.

