# 425 — final Phase 4 acceptance check

Run:

```sh
make phase 425
```

Phase 425 is the closing check for Phase 4.

It does not build a new package. It does not change the disk image. It does not
start a new design thread.

Instead, it asks:

```text
Is the Phase 4 machine that we just brought up actually acceptable?
```

## Why this phase exists

Phase 4 has many moving parts:

- `/etc` defaults
- users and groups
- login shell policy
- BusyBox
- Dropbear SSH
- systemd
- bootstrap systemd units
- package provenance notes
- QEMU port forwarding
- interactive login behavior

Each earlier subphase proves one piece.

But the final question is not "did one script pass?".

The final question is:

```text
Can we look at the running machine and say:
yes, this is a valid booted ONIX base userspace?
```

That is what Phase 425 proves.

In ONIX, the **phase gate is the real deliverable** — not the scripts, not the
intermediate artifacts. Each phase earns the right to move on by proving exactly one
thing end to end. Phase 425 is the gate for the whole "booted base userspace" arc of
Phase 4: it does not trust that the earlier subphases passed, it re-checks the
finished machine as a whole. A gate that only re-ran one earlier script would prove
nothing new; a gate that inspects the running machine from the outside proves the
pieces actually compose into a usable system.

## Relationship to Phase 424

Phase 424 boots the native ONIX image and leaves QEMU running:

```sh
make phase 424
```

Phase 425 then inspects that live VM:

```sh
make phase 425
```

This split is intentional.

Phase 424 is "bring it up".

Phase 425 is "accept what is up".

Keeping them separate is useful while learning because you can:

1. boot the VM,
2. log into it yourself,
3. inspect it manually,
4. then run the acceptance gate.

If Phase 425 cannot connect, the usual fix is:

```sh
make phase 424
make phase 425
```

## Why Phase 425 is not inside `make phase 4`

The canonical command:

```sh
make phase 4
```

runs the automated Phase 4 build/proof chain:

```text
400..422
```

Phase 424 and Phase 425 are operational lab steps.

They deal with a VM that remains alive after the command finishes. That is good
for human inspection, but not good for an automatic "run the whole phase" target.

So the shape is:

```text
make phase 4     # build/proof chain
make phase 424   # bring up live VM
make phase 425   # accept live VM
```

## What Phase 425 checks on the host

The script first checks host-side prerequisites:

```text
artifacts/onix-image/onix.raw
artifacts/onix-local-repo/stone.index
vm/state/id_ed25519
```

These prove that:

- the ONIX image exists,
- the local stone repository exists,
- the host has the SSH key used for VM inspection.

Then the script connects to:

```text
onix@127.0.0.1:7630
```

Port `7630` is the host side of QEMU port forwarding for the Phase 424 VM.

## What Phase 425 checks inside the VM

Inside the guest, Phase 425 checks that PID 1 is real native systemd:

```sh
cat /proc/1/comm
```

Expected:

```text
systemd
```

It also checks that:

- `/usr/lib/systemd/systemd` exists,
- `/usr/lib/systemd/systemd` is not a symlink,
- `systemctl`, `journalctl`, `systemd-tmpfiles`, `systemd-sysusers`, and
  `udevadm` exist,
- the systemd provenance notes do not refer to `/nix/store`.

That matters because Phase 4 moved from a bootstrap systemd payload to a native
source-built `systemd` stone.

The important idea is:

```text
systemd is now a system package, not a Nix toolbox payload.
```

## Why it checks `/usr/lib/onix/bootstrap`

Earlier in Phase 4, ONIX used temporary bootstrap payloads under:

```text
/usr/lib/onix/bootstrap
```

Those were useful while crossing the gap from "image boots" to "image has real
system packages".

By Phase 425, that old bootstrap payload must be gone.

If it still exists, we have hidden compatibility debt. The system may appear to
work, but it would not be cleanly package-owned.

So Phase 425 rejects the image if:

```text
/usr/lib/onix/bootstrap
```

still exists.

## What it checks for BusyBox and Dropbear

ONIX currently uses BusyBox for the small shell/tool base and Dropbear for early
SSH access.

Phase 425 checks:

```text
/usr/bin/busybox
/usr/sbin/dropbear
```

This proves the running system still has:

- a shell/toolbox base,
- SSH access.

It also checks the Dropbear systemd unit:

```text
/usr/lib/systemd/system/onix-bootstrap-dropbear.service
```

The unit must start Dropbear with:

```text
-m
```

That option matters because Dropbear has a small MOTD/banner path. If Dropbear
prints the big ONIX logo itself, the logo can be truncated.

So ONIX deliberately does this:

```text
Dropbear authenticates the SSH session.
/etc/profile prints the full interactive banner after login.
```

## What it checks for login branding

Phase 425 checks both the fallback MOTD and the real interactive login banner.

The fallback file is:

```text
/etc/motd
```

That file must stay small. It is useful as a safe non-colored fallback, but it
must not be the primary colored logo path.

The colored login path is:

```text
/etc/profile
/etc/profile.d/onix-login.sh
/usr/share/onix/branding/logo.ansi
```

The flow is:

1. BusyBox `ash` starts a login shell.
2. The shell reads `/etc/profile`.
3. `/etc/profile` sources `/etc/profile.d/*.sh`.
4. `onix-login.sh` prints `logo.ansi` when the shell is interactive.

That is why the full colored logo appears after login instead of being printed
by Dropbear.

### Background: login shells and `/etc/profile`

A shell behaves differently depending on how it starts. A **login shell** — the one
you get when you actually log in over SSH — reads system-wide startup files,
including `/etc/profile`, which in turn sources the snippets in `/etc/profile.d/`.
That is where ONIX prints its colored banner and defines the `ll` alias. A shell
started only to run one remote command (`ssh host somecommand`) may *not* be a login
shell and may skip those files entirely.

This is exactly why Phase 425 does two different kinds of check. A plain remote
command can verify that files and packages exist on disk, but it does not prove the
login experience works. Only a real interactive login (`ssh -tt`, which allocates a
pseudo-terminal) exercises the full login-shell path and proves that `/etc/profile`
actually ran, painted the banner, and set up the alias. Reading a script file proves
it is present; logging in proves it is *sourced*.

## What it checks for shell convenience

The default shell policy includes:

```sh
alias ll='ls -laF'
```

Phase 425 verifies this through a real interactive SSH login.

This is intentionally different from only reading the file. Reading the file
would prove the script exists. An interactive login proves the script is actually
sourced by the login shell.

## Two kinds of SSH checks

Phase 425 performs two SSH checks.

First, a normal remote command:

```text
host -> ssh -> guest command
```

This is good for checking files, PID 1, packages, and units.

Second, an interactive login transcript:

```text
host -> ssh -tt -> guest login shell
```

This is good for checking what a human sees after logging in.

That second check is how we prove:

- the colored logo has ANSI escape codes,
- the `ll` alias exists in the interactive shell,
- the ONIX welcome text appears.

## What success means

A successful Phase 425 means Phase 4 has reached this milestone:

```text
ONIX can boot into a native systemd userspace, accept SSH login,
show its own login branding, and expose a clean package-owned base.
```

That is enough to close the first booted-base userspace section.

## What Phase 425 does not prove

Phase 425 does not prove:

- ONIX owns its kernel,
- ONIX has a remote public package server,
- ONIX has a desktop,
- ONIX has a large package set,
- ONIX has permanent installer UX.

Those are later phases.

Phase 425 is deliberately narrower:

```text
accept the Phase 4 booted base before moving on
```

## Expected output

Successful output includes markers like:

```text
ONIX_PHASE425_REMOTE_OK user=onix uid=1000 pid1=systemd ...
==> success
Phase 425 accepted the Phase 4 booted ONIX base.
```

After success, you can still SSH into the VM:

```sh
ssh -i vm/state/id_ed25519 -p 7630 onix@127.0.0.1
```

Stop it safely with:

```sh
make stop
```
