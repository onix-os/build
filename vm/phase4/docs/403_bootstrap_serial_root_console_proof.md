# Phase 403 — bootstrap serial root console proof

| Item | Value |
|---|---|
| Command | `make phase 403` |
| Underlying make target/scripts | `vm/phase4/materialize-etc.sh --serial-console`, then `vm/phase4/serial-console-probe.sh` |
| Mutates disk/image? | Yes, it mounts `artifacts/onix-image/onix.raw` and installs the bootstrap console pieces |
| Boots QEMU? | Yes, it runs an automated serial-interaction proof |
| Main proof | QEMU boots ONIX, the image prints `ONIX_BOOTSTRAP_SERIAL_CONSOLE_READY`, the host sends a command over serial, and ONIX returns `ONIX_SERIAL_COMMAND_OK uid=0`. |

## The important honesty rule

Phase 403 is **not** the final ONIX login design.

It is a bootstrap serial root console.

That means:

```text
useful for early bring-up
not authenticated
not acceptable as the final installed-system policy
```

This distinction matters.

Phase 402 created real users and groups, but root still has:

```text
/usr/sbin/nologin
```

as its account shell in `/etc/passwd`.

Phase 403 does not change that.

Instead, Phase 403 creates a temporary systemd service that directly starts a
root shell on the serial port.

So the normal account policy still says:

```text
root is not a normal interactive login account yet
```

while the bootstrap policy says:

```text
for early OS bring-up, give the developer a root shell on ttyS1
```

## Why we need this phase

Until now, ONIX could boot to systemd multi-user mode.

That proves the kernel and PID 1 handoff.

But a system that boots and cannot be inspected is painful to develop.

We need a way to type commands inside the booted image:

```text
id
mount
cat /etc/os-release
systemctl status
```

Serial is the simplest early interface because QEMU can wire it directly to the
host terminal or to a script.

### Background: what a serial console is

Long before graphics or networking work, computers talked to terminals over a
**serial port** — a dead-simple two-wire channel that sends one byte at a time.
Linux still exposes serial ports as character devices named `ttyS0`, `ttyS1`, and
so on. If a program reads from and writes to `/dev/ttyS1`, and something on the
other end of that wire is a terminal, you have an interactive session with no
display server, no keyboard driver, and no network stack involved.

That "no dependencies" property is exactly why serial is the first console ONIX
brings up. Under QEMU there is no physical wire; instead QEMU emulates the serial
port and lets the *host* attach to it — piping it to your terminal, to a log file,
or to a control script. So a host program can type into the guest's `ttyS1` and
read whatever the guest prints back, which is precisely the automated proof Phase
403 performs. A real login stack (getty + login + PAM + a password policy) is much
larger; serial lets ONIX get a usable shell *now* and defer that stack honestly.

### A note on systemd units and targets

The mechanism that starts the shell is a **systemd unit**. A unit is a small
declarative file describing something systemd manages — most often a `.service`
(a process to run). `onix-bootstrap-serial-shell.service` is such a unit: it tells
PID 1 "run this command, on this console, at this stage of boot." Units are pulled
in by **targets** (boot stages); this one is wired under `multi-user.target`, the
stage that means "system is up and ready for logins." Masking a unit (linking it
to `/dev/null`) tells systemd to refuse to start it at all, which is how Phase 403
silences the stock serial getties so they do not fight the bootstrap shell for the
same ports.

## Why not proper login yet?

Proper login needs more pieces:

- a getty or terminal service
- a login/authentication program
- a password, passwordless, or first-boot auth decision
- a real shell listed in `/etc/shells`
- a decision about root login

The current bootstrap image may also start generated serial-getty units, but
those are not enough for a usable login stack yet.

Phase 403 chooses a smaller, more honest proof:

```text
Can ONIX start a shell on a serial port and can the host send commands to it?
```

That answer should become yes.

## What provides `/bin/sh`

ONIX is staying musl-based.

So Phase 403 builds or fetches:

```text
pkgs.pkgsMusl.busybox
```

from the pinned nixpkgs in `flake.lock`.

BusyBox is useful here because one small binary can provide many early system
commands:

```text
sh
ls
cat
mount
ps
id
uname
poweroff
```

Phase 403 copies the BusyBox closure into the image and exposes:

```text
/bin/busybox -> /nix/store/...-busybox-.../bin/busybox
/bin/sh      -> busybox
```

It also creates a set of BusyBox applet symlinks under `/bin`.

This is still bootstrap glue. Later, ONIX should own shell packages through real
stones.

## What owns the serial ports

In this proof we deliberately split the serial jobs:

```text
ttyS0 = boot log / kernel console
ttyS1 = temporary bootstrap root shell
```

Why split them?

Because the boot console is noisy. The kernel, firmware, systemd status output,
and generated serial getty can all write there. Trying to use the same TTY as a
clean automated shell makes the proof flaky and hard to read.

Phase 403 masks the generated serial getties for the two serial ports used by
the proof:

```text
/etc/systemd/system/serial-getty@ttyS0.service -> /dev/null
/etc/systemd/system/serial-getty@ttyS1.service -> /dev/null
```

Then it enables:

```text
onix-bootstrap-serial-shell.service
```

under:

```text
multi-user.target
```

There is one ugly bootstrap detail here.

The current systemd payload is still the Phase 213 Nix-store bootstrap payload,
not a real `onix-systemd` stone. Its active unit tree lives under a copied path
like:

```text
/nix/store/...-systemd-.../example/systemd/system
```

So Phase 403 installs the temporary unit into that copied unit tree inside the
image.

That is not the final architecture. It is just the correct place for this
specific bootstrap systemd to see the unit today.

That service runs the pinned musl BusyBox directly:

```text
/nix/store/...-busybox.../bin/busybox sh /usr/lib/onix/bootstrap-serial-shell
```

We run BusyBox explicitly instead of relying only on the script's `#!/bin/sh`
line. That makes the bootstrap dependency visible in the unit.

The wrapper prints:

```text
ONIX_BOOTSTRAP_SERIAL_CONSOLE_READY tty=... uid=0 shell=/bin/sh
```

and then executes:

```text
/bin/sh -l
```

## The `/persist` gotcha

This phase also taught an important image-building rule.

Inside the root filesystem tree there is a directory named:

```text
/persist
```

But at boot, ONIX mounts a separate partition there:

```text
LABEL=ONIX-PERSIST  /persist  xfs  ...
```

That means this is **not enough** while building the image:

```text
copy BusyBox into root-tree /persist/nix/store
```

Why not?

Because when the real `ONIX-PERSIST` partition mounts, it covers that directory.
Anything copied only into the root tree's `/persist` directory becomes hidden.

Then `/nix` is bind-mounted from:

```text
/persist/nix
```

So Phase 403 must:

1. mount the root partition,
2. mount the actual `ONIX-PERSIST` partition at `/persist`,
3. copy the BusyBox closure into the real `/persist/nix/store`,
4. copy the systemd unit into both the root Nix tree and the persist Nix tree.

That is why the successful output includes:

```text
mount    : ONIX-PERSIST -> /persist
unit     : /persist/nix/store/.../onix-bootstrap-serial-shell.service
```

## The automated proof

`make phase 403` does not stop after installing files.

It then starts QEMU with serial connected to the probe script.

The proof script waits for:

```text
ONIX_BOOTSTRAP_SERIAL_CONSOLE_READY
```

Then the host sends this command over the `ttyS1` serial line:

```sh
echo ONIX_SERIAL_COMMAND_OK uid=$(/bin/id -u) kernel=$(/bin/uname -s) pwd=$(pwd)
```

The proof passes only if the serial output contains:

```text
ONIX_SERIAL_COMMAND_OK uid=0
```

That proves:

- ONIX booted far enough to start the bootstrap console service
- `/bin/sh` exists and can run
- the host can send input over serial
- command output comes back over serial
- the shell is running as root

## What the script writes as proof

Phase 403 writes:

```text
/usr/share/onix/bootstrap/serial-console.txt
```

That file records:

- this is a temporary unauthenticated bootstrap console
- root's normal account shell remains `/usr/sbin/nologin`
- `/bin/sh` comes from musl BusyBox
- `ttyS0` is kept as the boot log console
- `ttyS1` is used as the temporary bootstrap shell console
- `serial-getty@ttyS0.service` and `serial-getty@ttyS1.service` are masked for now
- `onix-bootstrap-serial-shell.service` owns the bootstrap shell console
- the probe marker is `ONIX_BOOTSTRAP_SERIAL_CONSOLE_READY`

## Run it

From the repo root:

```sh
make phase 403
```

Expected output includes:

```text
shell    : /bin/busybox -> /nix/store/.../bin/busybox
shell    : /bin/sh -> busybox
mount    : ONIX-PERSIST -> /persist
unit     : /nix/store/...-systemd-.../example/systemd/system/onix-bootstrap-serial-shell.service
unit     : /persist/nix/store/...-systemd-.../example/systemd/system/onix-bootstrap-serial-shell.service
mask     : /etc/systemd/system/serial-getty@ttyS0.service -> /dev/null
mask     : /etc/systemd/system/serial-getty@ttyS1.service -> /dev/null
proof    : /usr/share/onix/bootstrap/serial-console.txt
```

Then the QEMU probe should end with:

```text
console : observed ONIX_BOOTSTRAP_SERIAL_CONSOLE_READY
command : observed ONIX_SERIAL_COMMAND_OK uid=0

==> success
Phase 403 proved two-way bootstrap serial root console access.
```

## How to watch it manually

Phase 403 is automated.

The proof creates two serial channels:

```text
ttyS0 -> vm/state/phase403.boot.log
ttyS1 -> vm/state/phase403.serial.log and vm/state/phase403.serial.sock
```

The QEMU process is stopped after the proof, so this phase is currently a
test/proof target rather than a long-running interactive session.

You can still use the older attached boot view for the Phase 212 image boot:

```sh
ATTACHED=1 make phase 212
```

That connects the QEMU boot serial console to your terminal. It does **not**
show the Phase 403 `ttyS1` bootstrap shell socket.

To exit the attached QEMU serial session:

```text
Ctrl-a then x
```

## What this phase does not do

Phase 403 does not solve final authentication.

It does not decide:

- root password policy
- whether root can log in normally
- whether first boot creates a user
- whether SSH keys are the first real auth method
- whether getty/login should come from util-linux, shadow, BusyBox, or ONIX packages

Those are later decisions.

Phase 403 only proves:

```text
we can interact with the booted ONIX image over serial
```
