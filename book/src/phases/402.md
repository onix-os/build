# Phase 402 — base users, groups, and shell policy

| Item | Value |
|---|---|
| Command | `make phase 402` |
| Underlying make target/script | `vm/phase4/materialize-etc.sh --accounts` |
| Mutates disk/image? | Yes, it mounts `artifacts/onix-image/onix.raw` and updates the root filesystem |
| Boots QEMU? | No |
| Main proof | The image has a real account database policy and generated `/etc/passwd`, `/etc/group`, `/etc/shadow`, `/etc/gshadow`, `/etc/nsswitch.conf`, and `/etc/shells`. |

## The basic Linux idea

Linux needs a way to answer simple identity questions:

```text
Who is UID 0?
What group is GID 0?
Which users exist?
Which groups exist?
Which shell should a user get after login?
```

The old and still-important answer is a set of files under `/etc`:

```text
/etc/passwd
/etc/group
/etc/shadow
/etc/gshadow
/etc/shells
/etc/nsswitch.conf
```

These files are not optional decoration.

Even a very small system needs to know that UID `0` is `root`.

## `/etc/passwd`

Despite the name, modern `/etc/passwd` does **not** normally contain password
hashes.

It maps user names to identity information:

```text
name:password-marker:uid:gid:description:home:shell
```

Example:

```text
root:x:0:0:Super User:/root:/usr/sbin/nologin
```

Read it as:

```text
user name    = root
password     = x, meaning "look in /etc/shadow"
uid          = 0
primary gid  = 0
description  = Super User
home         = /root
shell        = /usr/sbin/nologin
```

UID `0` is special. The kernel treats UID `0` as the superuser.

## `/etc/group`

`/etc/group` maps group names to numeric group IDs.

Example:

```text
root:x:0:
wheel:x:10:
```

The important thing is that software can refer to names like `root`, `tty`, or
`wheel`, while the kernel mostly cares about numeric IDs.

## `/etc/shadow`

`/etc/shadow` stores password state.

It is separated from `/etc/passwd` because `/etc/passwd` is commonly readable by
normal programs, while password hashes must not be exposed.

In Phase 402 we are **not** setting a root password.

That is deliberate.

The root account exists, but it is not an interactive login account yet.

## Why use `systemd-sysusers`

ONIX uses systemd as PID 1, so Phase 402 uses the systemd-native account
materialization tool:

```text
systemd-sysusers
```

The package-owned policy lives here:

```text
/usr/lib/sysusers.d/onix-base.conf
```

That file says, in a declarative way:

```text
these users and groups should exist
```

Then `systemd-sysusers` creates missing live entries under:

```text
/etc/passwd
/etc/group
/etc/shadow
/etc/gshadow
```

This matches the ONIX split from Phase 401:

```text
/usr/lib/sysusers.d/onix-base.conf   package-owned policy
/etc/passwd                          live machine state
```

The important behavior is conservative:

```text
create missing users/groups
do not blindly overwrite local account choices
```

### Declarative accounts vs `useradd`

On a traditional distro you create users *imperatively*: you run `useradd`, and it
mutates `/etc/passwd` right then. That is exactly the kind of one-shot,
hand-applied change an atomic distro wants to avoid, because there is no
package-owned record of *why* a user exists or how to recreate it on a fresh
machine.

`sysusers.d` flips this to a *declarative* model. A package drops a small text
file under `/usr/lib/sysusers.d/` that simply *states* which users and groups
should exist. `systemd-sysusers` reads those declarations and reconciles them
against the live database, creating anything missing and leaving everything else
alone. The declaration lives in package-owned `/usr` (safe to swap on update); the
materialized result lives in machine-local `/etc`. The ONIX build runs it with
`--root=<image mount>` so it edits the image's `/etc` rather than the host's.

The ONIX policy file itself (`onix-base.conf`) is worth reading: `g` lines declare
groups with fixed GIDs (`root 0`, `wheel 10`, `shadow 42`, `users 100`, `nogroup
65534`), and `u` lines declare users with their UID:GID, description, home, and
shell — for example `root 0:0 "Super User" /root /usr/sbin/nologin`. This is the
same "sysusers/tmpfiles" family systemd uses to keep `/etc` reproducible from
package data (`tmpfiles.d` does the analogous job for directories and files under
`/run`, `/var`, and friends). It is the mechanism the architecture chapter points
to for the future `nixbld` build users, too.

## What Phase 402 creates

Phase 402 creates a minimal base identity policy:

```text
root       UID 0      GID 0
nobody     UID 65534  GID 65534
```

It also creates common base groups:

```text
root
bin
daemon
sys
adm
tty
disk
wheel
shadow
systemd-journal
users
nogroup
```

This is not the final user model.

It is the first stable base that lets the booted image stop being anonymous.

## Why root uses `/usr/sbin/nologin`

Phase 402 intentionally sets root's shell to:

```text
/usr/sbin/nologin
```

That means:

```text
root exists
root is UID 0
root is not yet an interactive login account
```

This is safer than pretending login is ready.

At this point ONIX still has not proved:

- a real shell such as `/bin/sh`
- a working `agetty` or equivalent serial terminal service
- a working `login` program or explicit password/authentication policy

Those belong in Phase 403.

## Where `/usr/sbin/nologin` comes from

The current ONIX image still uses the bootstrap systemd userspace payload from
Phase 213.

That payload includes a Nix-store copy of util-linux's `nologin`.

Phase 402 exposes it at the normal path:

```text
/usr/sbin/nologin -> /nix/store/...-util-linux-minimal-...-login/bin/nologin
```

This is still bootstrap glue.

Later, ONIX should own this through real stones instead of reaching into a
borrowed host-built closure.

## `/etc/nsswitch.conf`

Programs need to know where to look up users, groups, hosts, services, and other
names.

That policy lives in:

```text
/etc/nsswitch.conf
```

Phase 402 starts simply:

```text
passwd: files
group: files
shadow: files
hosts: files dns
```

For users and groups, `files` means:

```text
look in /etc/passwd and /etc/group
```

For hosts, `files dns` means:

```text
try /etc/hosts first, then DNS
```

Later networking phases can make this more complete.

## `/etc/shells`

`/etc/shells` lists shells that the system considers valid account shells.

Phase 402 writes:

```text
/usr/sbin/nologin
```

That looks strange at first, but it is intentional: Phase 402 is saying:

```text
the only shell policy we have proved is non-interactive
```

Phase 403 is where we add and prove a temporary bootstrap serial console.

## What the script writes as proof

Phase 402 writes:

```text
/usr/share/onix/bootstrap/account-policy.txt
```

That file records:

- account policy lives in `/usr/lib/sysusers.d/onix-base.conf`
- `systemd-sysusers` creates missing live account entries under `/etc`
- local account choices are not silently overwritten
- root exists but is intentionally non-interactive
- authenticated serial login is still a future proof

## Run it

From the repo root:

```sh
make phase 402
```

Expected output includes lines like:

```text
symlink  : /usr/sbin/nologin -> /nix/store/.../bin/nologin
policy   : /usr/lib/sysusers.d/onix-base.conf
sysusers : materialized missing /etc passwd/group/shadow entries
proof    : /usr/share/onix/bootstrap/account-policy.txt
```

Then the phase verifies:

- `/usr/lib/sysusers.d/onix-base.conf` exists
- `/usr/sbin/nologin` points to an executable Nix-store `nologin`
- `/etc/passwd` has `root` and `nobody`
- `/etc/group` has base groups such as `root`, `shadow`, `wheel`, and `nogroup`
- `/etc/shadow` and `/etc/gshadow` exist
- `/etc/nsswitch.conf` uses local files for users and groups
- `/etc/shells` lists `/usr/sbin/nologin`
- `/usr/share/onix/bootstrap/account-policy.txt` records the limitation

## What this phase does not do

Phase 402 does **not** prove login.

That is important.

After Phase 402, the image knows who `root` is, but it still should not promise:

```text
you can authenticate as root on a serial console
```

Phase 403 should be the bootstrap serial-console proof. A later authenticated
login step still needs to answer:

- Which shell exists?
- Which getty or terminal service starts?
- Which login/authentication program is used?
- Is root password login allowed, disabled, or replaced by some other first-boot mechanism?
