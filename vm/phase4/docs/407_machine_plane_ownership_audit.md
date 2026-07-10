# Phase 407 — machine-plane ownership audit

| Item | Value |
|---|---|
| Command | `make phase 407` |
| Underlying make target/script | `vm/phase4/ownership-audit.sh` |
| Mutates disk/image? | No |
| Boots QEMU? | No |
| Main proof | Every temporary Nix-sourced system payload is explicitly marked bootstrap-only and has a named future `.stone` owner. |

## Why this phase exists

After Phase 406, ONIX can boot, configure a network interface, and accept
authenticated SSH.

That is good.

But there is a dangerous architectural trap:

```text
because Nix can conveniently build musl packages,
we might accidentally let Nix become the system package manager
```

That would violate the ONIX constitution.

The core rule remains:

```text
moss/.stone owns the machine plane
Nix owns the user toolbox plane
```

So Phase 407 is a correction and guardrail phase.

It says:

```text
Nix-sourced system payloads are bootstrap-only
```

They are allowed only while we are proving behavior. They are not the final
package architecture.

## Machine plane vs toolbox plane

The machine plane includes things like:

```text
kernel
initramfs
PID 1
udev
base shell
base networking
SSH daemon
system users/groups
systemd units
boot entries
/usr
```

Those must be owned by:

```text
moss-installed .stone packages
```

The toolbox plane includes things like:

```text
nix shell
nix develop
nix profile install
developer tools
user applications
optional long-tail packages
```

Those are allowed to be owned by:

```text
Nix
```

This boundary is what makes ONIX different from "a random Linux image with Nix
installed on it."

### Why the boundary is load-bearing, not cosmetic

The payoff of the split is *independent rollback*. moss can atomically roll the
machine plane back to a previous state, and Nix can roll a user profile back to a
previous generation, and neither operation is allowed to corrupt the other. That
guarantee only holds if the two planes genuinely own disjoint things. The moment a
piece of machine plumbing — a shell, PID 1, the SSH daemon — actually lives in
`/nix/store` and is managed by Nix, a `nix store gc` or a Nix rollback could yank
the floor out from under the running machine, and moss would have no way to put it
back. So "Nix-sourced system payloads are bootstrap-only" is not tidiness; it is
what keeps the atomic rollback promise honest. Phase 407 is where the project
audits itself against that promise before writing a single replacement recipe.

## What temporary payloads exist right now?

The current early image uses several temporary payloads to move fast.

That is acceptable only because each one is named and scheduled for replacement.

| Temporary payload | Why it exists now | Future `.stone` owner |
|---|---|---|
| Alpine virt kernel/initramfs/modules | lets Phase 2/4 boot while kernel work is deferred | `onix-kernel`, `onix-initramfs`, `onix-kernel-modules` |
| `pkgsMusl.systemd` | proves systemd-on-musl and service startup | `systemd` |
| `pkgsMusl.busybox` | provides `/bin/sh` and early applets for proofs | `busybox` or `onix-base` |
| `pkgsMusl.dropbear` | proves authenticated SSH before recipe work | `dropbear` or `onix-ssh` |
| Nix-store util-linux `nologin` | gives safe non-interactive account shells | `onix-util-linux` or `onix-base` |

This table is the heart of Phase 407.

## Why the Nix shortcut is still useful

The shortcut has value.

It lets us ask questions in the right order:

```text
Can systemd run on musl here?
Can a shell run?
Can QEMU networking work?
Can SSH key auth work?
```

without spending weeks writing recipes first.

But once a behavior is proved, the project must move from:

```text
Nix-built bootstrap payload
```

to:

```text
ONIX .stone package
```

That migration is not optional.

## What `make phase 407` checks

The phase runs:

```sh
./ownership-audit.sh
```

It prints the ownership table and checks the docs for the important future
owners:

```text
systemd
busybox
dropbear
onix-kernel
```

It also checks that the architecture doc contains the explicit rule:

```text
Nix-sourced system payloads are bootstrap-only
```

This is intentionally a documentation/architecture gate, not a boot test.

## Run it

From the repo root:

```sh
make phase 407
```

Expected output:

```text
Temporary payload                         Final machine-plane owner
---------------------------------------------------------------------------
Alpine virt kernel/initramfs/modules      onix-kernel + onix-initramfs stones
pkgsMusl.systemd                          systemd stone
pkgsMusl.busybox                          busybox / onix-base stone
pkgsMusl.dropbear                         dropbear / onix-ssh stone
Nix-store util-linux nologin              onix-util-linux or onix-base stone

==> success
Phase 407 confirms temporary Nix-sourced system payloads have named future .stone owners.
```

## What this phase does not do

Phase 407 does not yet write the real recipes.

It does not build:

```text
systemd.stone
busybox.stone
dropbear.stone
onix-kernel.stone
```

That work belongs to later package/recipe phases.

Phase 407 only prevents architectural drift.

It keeps the mental model clean:

```text
Nix helped us prove it.
moss/.stone must eventually own it.
```
