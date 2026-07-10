# Phase 418 — package/prove bootstrap

| Item | Value |
|---|---|
| Command | `make phase 418` |
| Build script | `vm/phase4/build-bootstrap-stone.sh` |
| Install script | `vm/phase4/materialize-etc.sh --bootstrap-stone` |
| Runtime probe | `vm/phase4/stone-bootstrap-probe.sh` |
| New stone | `bootstrap` |
| Mutates disk/image? | Yes |
| Boots QEMU? | Yes |
| Main proof | Bootstrap helper scripts, proof docs, and unit source files are package-owned by a stone, activated into the image, and visible in the booted guest while systemd and SSH still work. |

## Why this phase exists

By Phase 417, ONIX can boot with these machine-plane packages:

```text
busybox
dropbear
systemd
```

That is good, but not complete.

Some important booted-base behavior still came from shell heredocs inside the
image materializer:

```text
vm/phase4/materialize-etc.sh
```

Examples:

```text
/usr/lib/onix/bootstrap-serial-shell
/usr/lib/onix/bootstrap-network-up
/usr/lib/onix/bootstrap-network-proof
/usr/lib/onix/bootstrap-remote-inspection-response
/usr/lib/onix/bootstrap-ssh-proof
```

and the temporary bootstrap systemd units:

```text
onix-bootstrap-serial-shell.service
onix-bootstrap-network.service
onix-bootstrap-remote-inspection.service
onix-bootstrap-dropbear.service
```

Those are not random implementation details.

They are machine behavior.

Machine behavior should become package-owned.

Phase 418 starts that migration.

## What `bootstrap` is

`bootstrap` is a data/policy stone.

It does not compile a C or Rust binary.

It packages ONIX-owned files:

```text
/usr/lib/onix/bootstrap-serial-shell
/usr/lib/onix/bootstrap-network-up
/usr/lib/onix/bootstrap-network-status
/usr/lib/onix/bootstrap-network-proof
/usr/lib/onix/bootstrap-remote-inspection-response
/usr/lib/onix/bootstrap-remote-inspection-status
/usr/lib/onix/bootstrap-remote-inspection-proof
/usr/lib/onix/bootstrap-ssh-status
/usr/lib/onix/bootstrap-ssh-proof
```

It also packages source copies of the temporary bootstrap systemd units:

```text
/usr/lib/onix/systemd/system/onix-bootstrap-serial-shell.service
/usr/lib/onix/systemd/system/onix-bootstrap-network.service
/usr/lib/onix/systemd/system/onix-bootstrap-remote-inspection.service
/usr/lib/onix/systemd/system/onix-bootstrap-dropbear.service
```

And it packages explanatory notes:

```text
/usr/share/onix/bootstrap/bootstrap.txt
/usr/share/onix/bootstrap/bootstrap-debt.tsv
/usr/share/onix/packages/bootstrap.md
```

`bootstrap-debt.tsv` is deliberately machine-readable. It lists the pieces that
are useful during bring-up but are not final OS policy: the unauthenticated serial
root shell, the static QEMU-only network helper, the temporary TCP inspection
listener, Dropbear as bootstrap SSH, and the active-unit copy glue.

## Background: systemd units and "enabling" a service

A systemd **unit** is a plain-text file describing something systemd manages. A
`.service` unit describes a process to run. It has sections: `[Unit]` (description
and ordering — `After=`, `Requires=`), `[Service]` (how to run it — the `ExecStart=`
command, restart policy), and `[Install]` (how it gets enabled — usually
`WantedBy=multi-user.target`).

Having a unit file on disk does not make it start. systemd starts **targets** (named
groups of units); `multi-user.target` is the normal "system is up and multi-user"
state. A service runs at boot only if it is **enabled**, which in practice means a
symlink to it exists in that target's `.wants` directory:

```text
multi-user.target.wants/onix-bootstrap-network.service -> ../onix-bootstrap-network.service
```

So "activating" a unit here means two things: place the unit file where systemd looks
for units, and create the `.wants` symlink that pulls it into `multi-user.target`.
That is what the phrase "enables them through `multi-user.target.wants/*.service`"
below refers to.

## Package-owned source vs active unit activation

This phase has an important honesty boundary.

The package owns the source files here:

```text
/usr/lib/onix/systemd/system/*.service
```

But systemd is currently using the temporary unit tree exposed by the bootstrap
systemd payload:

```text
/nix/store/...-systemd-.../example/systemd/system
```

So Phase 418 still has an activation step.

It copies the package-owned unit source files into the active systemd tree:

```text
/usr/lib/onix/systemd/system/*.service
  -> /nix/store/...-systemd-.../example/systemd/system/*.service
```

and enables them through:

```text
multi-user.target.wants/*.service
```

That means:

```text
source ownership improved
activation is still bootstrap glue
```

This is a good intermediate state.

Before Phase 418, the source and activation both lived in a shell script.

After Phase 418, the source lives in a package, and the shell script only
activates package-owned source files into the current temporary unit tree.

## Why not solve all systemd unit ownership now?

Because the current systemd layout is still transitional.

Right now:

```text
/usr/lib/systemd/system -> /nix/store/...-systemd-.../example/systemd/system
```

That is not the final ONIX layout.

A final layout might use:

```text
/usr/lib/systemd/system
/usr/lib/systemd/system-preset
systemctl preset
moss triggers
```

or an ONIX-specific activation mechanism.

But we should not design all of that while we are still proving the base boot
chain.

Phase 418 moves one layer:

```text
from heredoc-owned bootstrap behavior
to stone-owned bootstrap behavior
```

The next layers can be smaller and clearer.

## What the build script does

Run:

```sh
make phase 418
```

The first script is:

```text
vm/phase4/build-bootstrap-stone.sh
```

It:

1. Creates a prepared payload tree on the host.
2. Writes ONIX bootstrap scripts into:

   ```text
   usr/lib/onix/
   ```

3. Writes source systemd units into:

   ```text
   usr/lib/onix/systemd/system/
   ```

4. Writes package/proof notes into:

   ```text
   usr/share/onix/bootstrap/
   usr/share/onix/packages/
   ```

5. Writes `usr/share/onix/bootstrap/bootstrap-debt.tsv` so later proofs can
   tell the difference between accepted bootstrap debt and finished OS design.
6. Archives that payload.
7. Sends the payload and recipe template to the forge VM.
8. Builds:

   ```text
   bootstrap-0.1.0-...
   ```

9. Runs `moss inspect --check`.
10. Extracts and verifies the stone.
11. Installs it into a disposable target.
12. Copies it back into:

    ```text
    artifacts/onix-stones/
    artifacts/onix-local-repo/
    ```

13. Re-indexes:

    ```text
    artifacts/onix-local-repo/stone.index
    ```

## What the install step does

After building the stone, Phase 418 runs:

```sh
./materialize-etc.sh --systemd-stone
./materialize-etc.sh --bootstrap-stone
```

The first command reasserts the Phase 416 systemd layout.

The second command:

1. Uses host-side Moss to install `bootstrap` into a scratch target.
2. Verifies the scratch target.
3. Copies the package payload into the mounted image.
4. Activates package-owned unit source files into the current systemd unit tree.
5. Verifies active units match package-owned source files.
6. Verifies the existing systemd/BusyBox/Dropbear proofs still make sense.

The important check is:

```text
active unit == package-owned source unit
```

That proves the image is no longer relying on hidden heredoc source for those
bootstrap units.

## What the runtime probe checks

The runtime probe is:

```text
vm/phase4/stone-bootstrap-probe.sh
```

It boots QEMU and checks from inside the guest:

```text
/proc/1/comm == systemd
/usr/share/onix/packages/bootstrap.md exists
/usr/share/onix/bootstrap/bootstrap.txt exists
/usr/share/onix/bootstrap/bootstrap-debt.tsv exists
/usr/lib/onix/bootstrap-network-proof is executable
/usr/lib/onix/bootstrap-ssh-proof is executable
/usr/lib/onix/systemd/system/onix-bootstrap-network.service exists
active systemd unit tree contains the bootstrap unit files
SSH still works
```

The proof markers are:

```text
ONIX_BOOTSTRAP_SERIAL_OK
ONIX_BOOTSTRAP_SSH_OK
```

## What Phase 418 proves

Phase 418 proves:

- ONIX can build a data `.stone`,
- Moss can install that bootstrap package,
- the ONIX image can consume it,
- bootstrap helper scripts are package-owned,
- source copies of bootstrap units are package-owned,
- active bootstrap units are copied from package-owned source,
- PID 1 is still systemd,
- network and SSH still work after the policy ownership change.

This is the first step from:

```text
image assembly writes behavior
```

to:

```text
packages own behavior
```

## What Phase 418 does not prove

Phase 418 does not make the service model final.

It does not yet solve:

- systemd presets,
- package triggers,
- final unit installation layout,
- removing the temporary active unit copy into `/nix/store`,
- final login policy,
- final network stack,
- final SSH choice.

The active unit copy is still bootstrap glue.

But the source of that copy is now a package.

That is a meaningful improvement.

## Expected output shape

Successful output should include:

```text
==> Phase 418 bootstrap stone
==> building bootstrap stone
==> success
bootstrap stone: artifacts/onix-stones/bootstrap-...

==> installing and activating bootstrap from the local Phase 4 repo
stone    : bootstrap installed under /usr/lib/onix + /usr/share/onix
unit     : /nix/store/.../onix-bootstrap-network.service from /usr/lib/onix/systemd/system/...
==> verifying Phase 418 bootstrap image install

ONIX_BOOTSTRAP_SERIAL_OK pid1=systemd package=present units=active source=present
ONIX_BOOTSTRAP_SSH_OK user=onix uid=1000 pid1=systemd package=present units=active
```

Evidence logs go under:

```text
vm/state/phase418.*.log
```

## Next step

The next natural step is Phase 419:

```text
audit remaining Nix-sourced and image-assembly-sourced booted-base debt
```

After Phase 418, we should be able to list more clearly:

```text
stone-owned now
still activation glue
still Nix-built
still kernel/initramfs borrowed
```
