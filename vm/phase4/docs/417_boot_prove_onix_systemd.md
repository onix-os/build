# Phase 417 — boot-prove `systemd`

| Item | Value |
|---|---|
| Command | `make phase 417` |
| Underlying scripts | `vm/phase4/materialize-etc.sh --systemd-stone`, then `vm/phase4/stone-systemd-probe.sh` |
| Requires | Phase 416 image layout |
| Mutates disk/image? | Yes, it reapplies the Phase 416 materialization first |
| Boots QEMU? | Yes |
| Main proof | The booted image reaches systemd userspace with PID 1 running from the `systemd` materialized runtime payload, and authenticated SSH still works. |

## Why this phase exists

Phase 416 proved filesystem layout.

It showed that the image contains:

```text
/usr/lib/systemd/systemd
/usr/lib/onix/bootstrap/nix/store/...
/nix/store/...
/persist/nix/store/...
```

But a filesystem proof is not a boot proof.

Phase 417 asks the runtime question:

```text
Can the kernel and initramfs execute this systemd path and reach the booted
multi-user system again?
```

This is the moment where a bad systemd installation would show up as a real
boot failure.

## What "boot-prove" means

In this project, "boot-prove" means:

1. Start the ONIX image in QEMU.
2. Wait for real guest-side evidence.
3. Send commands into the booted guest.
4. Verify markers from inside the guest.
5. Shut QEMU down.

This is stronger than checking files from the host.

Host-side file checks can tell us:

```text
the systemd file exists
the symlink points somewhere plausible
the boot entry looks correct
```

But only a boot proof can tell us:

```text
the kernel could execute PID 1
systemd actually ran
the bootstrap services started
networking came up
SSH accepted a key
commands executed inside the guest
```

Phase 417 is therefore a runtime proof.

## Why PID 1 matters so much

Linux starts userspace by executing one first program.

That process gets PID 1.

For ONIX right now, the boot entry says:

```text
init=/usr/lib/systemd/systemd
```

So the intended first process is:

```text
systemd
```

If PID 1 cannot execute, the system cannot continue normally.

Common failure shapes include:

```text
switch_root: can't execute '/usr/lib/systemd/systemd'
Kernel panic - not syncing: Attempted to kill init
```

Those messages mean the handoff from initramfs to real userspace failed.

Phase 417 specifically checks that this does not happen after switching systemd
ownership to the `systemd` stone.

## Why Phase 417 still starts with Phase 416

The `make phase 417` target intentionally runs:

```sh
./materialize-etc.sh --systemd-stone
./stone-systemd-probe.sh
```

That means Phase 417 reapplies the Phase 416 image materialization before
booting.

This makes the phase idempotent and teachable:

```text
install/materialize the desired state
then boot-prove the desired state
```

If the image was rebuilt, partially changed, or stale, Phase 417 first restores
the expected systemd stone layout.

Then it boots.

## What the probe actually boots

The runtime probe uses:

```text
vm/phase4/stone-systemd-probe.sh
```

That script reuses the existing Phase 4 SSH probe machinery.

Under the hood, it boots QEMU with:

```text
artifacts/onix-image/onix.raw
```

The disk is attached as a snapshot for the probe, so runtime changes made by the
guest do not dirty the base image.

The probe names its QEMU process:

```text
onix-p417ssh
```

That lets cleanup stop exactly this probe if needed.

## Why the proof uses serial first

The guest exposes a bootstrap serial shell service from earlier phases.

That service is not the final login design. It is a controlled early bring-up
tool.

The important point for Phase 417 is:

```text
the serial shell service is started by systemd
```

So if the probe sees the serial ready marker, it already means:

```text
systemd reached far enough to start the bootstrap serial unit
```

Then the probe sends a command over that serial channel.

The command checks:

```text
/proc/1/comm
```

That file reports the command name of PID 1.

The kernel exposes a virtual filesystem at `/proc`, where each running process has a
numbered directory. `/proc/1` is therefore PID 1, and `/proc/1/comm` is a tiny file
holding that process's command name. Reading it is the most direct possible answer to
"what is actually running as init right now?" — it comes from the kernel's own view
of the process table, not from a symlink or a config file that could be misleading.

Phase 417 expects:

```text
systemd
```

The serial proof marker is:

```text
ONIX_STONE_SYSTEMD_SERIAL_OK
```

The command also checks:

```text
/usr/lib/systemd/systemd
/usr/lib/onix/bootstrap/nix/store/...
/usr/share/onix/bootstrap/systemd-stone.txt
/usr/share/onix/packages/systemd.md
```

This proves the booted guest can see both:

```text
the active runtime systemd path
the package-owned bootstrap copy
```

## Why the proof also uses SSH

Serial proves early local control.

SSH proves more:

```text
network service started
Dropbear service started
host port forwarding works
public-key auth works
the onix user can run commands inside the guest
```

Phase 417 runs a host-side SSH command into the guest and expects:

```text
ONIX_STONE_SYSTEMD_SSH_OK
```

Inside the SSH command, it verifies:

```text
/proc/1/comm == systemd
/usr/lib/systemd/systemd -> /nix/store/...-systemd-.../lib/systemd/systemd
/usr/lib/onix/bootstrap/nix/store/... exists
/usr/bin/systemctl exists
/usr/bin/journalctl exists
/usr/bin/udevadm exists
/usr/share/onix/packages/systemd.closure exists
```

It also runs:

```sh
systemctl --version
```

That is a useful dynamic-linking check.

If the musl loader or systemd runtime libraries were missing, `systemctl` would
not run correctly.

## What Phase 417 proves

Phase 417 proves:

- QEMU can boot the ONIX image after Phase 416,
- the kernel/initramfs can execute `/usr/lib/systemd/systemd`,
- PID 1 is actually `systemd`,
- the systemd symlink resolves to the expected `/nix/store/...-systemd-...`
  runtime path,
- the package-owned bootstrap copy exists under `/usr/lib/onix/bootstrap`,
- the Phase 416 proof file exists in the booted guest,
- bootstrap networking still comes up,
- bootstrap SSH still comes up,
- `systemctl --version` runs inside the guest,
- host-to-guest public-key SSH still works.

That is the first real runtime proof that `systemd` is usable as the
current systemd ownership boundary.

## What Phase 417 does not prove

Phase 417 does not mean systemd is fully native ONIX yet.

It does not prove:

- systemd was source-built by an ONIX recipe,
- all systemd dependencies are separate ONIX stones,
- `/nix/store` can be removed,
- the bootstrap serial shell is final,
- the bootstrap networking stack is final,
- Dropbear is the final remote access choice,
- kernel/module ownership is solved.

Those are later steps.

Phase 417 proves the current bootstrap bridge works at runtime.

That is still a big deal because PID 1 is the most sensitive handoff in the
whole boot chain.

## What to do if it fails

If Phase 417 fails before the serial marker, inspect:

```text
vm/state/phase417.ssh-boot.log
vm/state/phase417.ssh-serial.log
```

The boot log is usually where PID 1 failures appear.

Look for:

```text
switch_root
Kernel panic
can't execute
No such file or directory
```

If it reaches serial but SSH fails, the problem is probably later:

```text
network unit
Dropbear unit
authorized key
host port forwarding
```

Stopping a stuck probe without deleting generated images is safe:

```sh
make stop
```

That stops the Phase 417 QEMU probe and detaches stale image mounts.

Use `make cleanup` only for an intentional destructive reset.

## Expected output shape

Successful output should include:

```text
==> Phase 417 stone systemd live proof
==> waiting for bootstrap serial console service
ONIX_STONE_SYSTEMD_SERIAL_OK pid1=systemd ...
==> running host-side proof
ONIX_STONE_SYSTEMD_SSH_OK user=onix uid=1000 pid1=systemd ...
==> success
Phase 417 proved the image boots with systemd materialized as the PID 1 runtime payload.
```

Evidence logs are written under:

```text
vm/state/phase417.*.log
```

## Next step

After Phase 417, the next natural work is Phase 418:

```text
move more bootstrap unit/default ownership into stones
```

Right now the boot works, but some bootstrap policy is still image-assembly
glue.

Phase 418 should start reducing that by making more of the booted-base behavior
package-owned.
