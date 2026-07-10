# Phase 416 — install/use `systemd`

| Item | Value |
|---|---|
| Command | `make phase 416` |
| Underlying script | `vm/phase4/materialize-etc.sh --systemd-stone` |
| Requires | Phase 415 `systemd` stone in the local Phase 4 repo |
| Mutates disk/image? | Yes |
| Boots QEMU? | No |
| Main proof | The image consumes `systemd` from the local Moss repo and materializes its runtime store paths so `/usr/lib/systemd/systemd` can execute as PID 1. |

## Why this phase exists

Phase 415 built the package:

```text
systemd
```

But building a package is not the same as using it in the image.

Phase 416 asks:

```text
Can the ONIX image consume the systemd stone and make its PID 1 runtime
paths real inside the disk image?
```

That is a separate question from booting.

The split is deliberate:

```text
415 = build the stone
416 = install/materialize the stone into the image
417 = boot-prove that stone-owned systemd still starts
```

If something fails, we know which layer failed.

## The basic Linux boot idea

A Linux boot has a few major handoffs.

Simplified:

```text
firmware
  -> bootloader
  -> kernel
  -> initramfs
  -> real root filesystem
  -> PID 1
```

For the current ONIX image, the boot entry tells the kernel:

```text
init=/usr/lib/systemd/systemd
```

That means:

1. the kernel starts,
2. the initramfs finds and mounts the real root filesystem,
3. the kernel tries to execute this file from the mounted root:

   ```text
   /usr/lib/systemd/systemd
   ```

That program becomes PID 1.

PID 1 is special. It is the first userspace process, and if it cannot start,
the machine cannot continue booting normally.

### Background: initramfs and the root handoff

The kernel cannot always mount the real root filesystem on its own — it may need
drivers, or need to find the right disk by label. So the bootloader loads two things:
the kernel and a small temporary root filesystem called the **initramfs** (initial
RAM filesystem), unpacked into memory. The kernel runs the initramfs first; the
initramfs job is to locate and mount the *real* root filesystem, then hand control
over to it by executing the init program named on the kernel command line. This
final handoff is often done with `switch_root`. If the init binary named by
`init=/usr/lib/systemd/systemd` is missing or cannot execute at that moment, the
handoff fails and you get a kernel panic — which is exactly the failure Phase 417
watches for. Phase 416 exists to make sure every byte that handoff needs is really
present on disk *before* Phase 417 tries the boot.

(In Phase 4 the kernel and initramfs are still the borrowed Alpine `virt` payload
from Phase 2 — owning those is reserved for the later Phase 3 work. Phase 416 is only
about the systemd userspace the handoff lands in.)

## Why `/usr/lib/systemd/systemd` is not enough

The file:

```text
/usr/lib/systemd/systemd
```

is a symlink in this bootstrap image.

It points to the real systemd binary inside the Nix store:

```text
/nix/store/...-systemd-.../lib/systemd/systemd
```

And that binary is dynamically linked.

That means the kernel does not only need the systemd file.

It also needs the ELF interpreter recorded inside that file:

```text
/nix/store/...-musl-.../lib/ld-musl-x86_64.so.1
```

Then systemd needs its runtime libraries and helper files.

So the real boot requirement is:

```text
/usr/lib/systemd/systemd symlink exists
/nix/store/...-systemd-... exists
/nix/store/...-musl-... exists
all required runtime closure paths exist
```

If any of those paths are missing, the kernel may find the symlink but still
fail to execute PID 1.

## Why the stone carries a bootstrap store under `/usr`

Moss packages normal system payload under:

```text
/usr
```

But the current systemd payload still has absolute runtime paths under:

```text
/nix/store
```

Phase 415 solved that by making `systemd` carry the full runtime closure
under a package-owned bootstrap area:

```text
/usr/lib/onix/bootstrap/nix/store
```

That path is package content.

It belongs to the `systemd` stone.

But at boot, the runtime still expects:

```text
/nix/store
```

So Phase 416 does the image-assembly part:

```text
/usr/lib/onix/bootstrap/nix/store/...  ->  /nix/store/...
```

This is not final architecture.

It is an honest bootstrap bridge:

```text
stone owns the bytes
image assembly places a runtime copy where the current binary expects it
```

Later native ONIX systemd work should remove this Nix-store runtime dependency.

## Why we also copy into `/persist/nix/store`

The ONIX image uses persistent state.

The root filesystem contains a `/nix` directory, but the booted system may bind
or use persistent state from:

```text
/persist/nix
```

Earlier boot phases copied important runtime closures into both places:

```text
/nix/store
/persist/nix/store
```

Phase 416 keeps that rule.

It materializes the `systemd` bootstrap store into both:

```text
/nix/store
/persist/nix/store
```

That makes the phase robust whether the runtime is reading from the root copy or
the persistent copy.

## Why we use a scratch Moss target first

The script does not manually unpack a random `.stone` into the image.

It first asks host-side Moss to install the package into a disposable scratch
target:

```text
artifacts/onix-phase4-work/systemd-install-target
```

That does two useful things:

1. Moss proves the package can be resolved from the local repo.
2. Moss performs the normal package install layout before image assembly copies
   selected payload into the mounted image.

The image gets the package-installed shape, not an ad hoc archive extraction.

This keeps the phase closer to how ONIX should eventually install system
packages for real.

## What the phase changes in the image

Phase 416 installs package-owned paths such as:

```text
/usr/lib/onix/bootstrap/nix/store/...
/usr/lib/systemd/systemd
/usr/lib/systemd/system
/usr/lib/systemd/user
/usr/bin/systemctl
/usr/bin/journalctl
/usr/bin/systemd-tmpfiles
/usr/bin/systemd-sysusers
/usr/bin/udevadm
/usr/share/onix/packages/systemd.md
/usr/share/onix/packages/systemd.closure
/usr/share/onix/packages/systemd.links
```

Then it materializes runtime copies:

```text
/nix/store/...
/persist/nix/store/...
```

Finally it writes a proof note:

```text
/usr/share/onix/bootstrap/systemd-stone.txt
```

## What the phase must preserve

This phase must not break the already-working bootstrap stack.

The image already has:

```text
busybox
dropbear
bootstrap network unit
bootstrap remote-inspection unit
bootstrap serial unit
bootstrap SSH unit
```

Those units live inside the current systemd unit tree:

```text
/nix/store/...-systemd-.../example/systemd/system
```

When Phase 416 copies the package-owned systemd closure into `/nix/store`, it
does not delete that tree first.

That matters because the ONIX bootstrap units are extra files added by earlier
phases.

The copy overlays the packaged systemd files but preserves the ONIX bootstrap
unit files.

The verification checks that these commands still point at the stone-owned
BusyBox and Dropbear payloads:

```text
onix-bootstrap-serial-shell.service -> /usr/bin/busybox
onix-bootstrap-dropbear.service     -> /usr/sbin/dropbear
```

## What the script does

Run:

```sh
make phase 416
```

The script:

1. Mounts the ONIX image root.
2. Mounts the ONIX boot partition for BLS verification.
3. Mounts the ONIX persist partition.
4. Uses host-side Moss to install `systemd` from:

   ```text
   artifacts/onix-local-repo/stone.index
   ```

   into a scratch target.

5. Verifies that scratch target contains:

   ```text
   /usr/lib/onix/bootstrap/nix/store
   /usr/lib/systemd/systemd
   /usr/bin/systemctl
   /usr/share/onix/packages/systemd.*
   ```

6. Copies the package payload into the mounted image.
7. Copies the package-owned bootstrap store into:

   ```text
   /nix/store
   /persist/nix/store
   ```

8. Verifies the boot entry still uses:

   ```text
   init=/usr/lib/systemd/systemd
   ```

9. Verifies the existing bootstrap units survived.
10. Prints a preview of the active systemd paths and unit `ExecStart` lines.

## What this phase proves

Phase 416 proves:

- the image can consume `systemd` from the local Moss repo,
- `/usr/lib/systemd/systemd` is now supplied by the package install shape,
- the systemd runtime closure exists under package-owned bootstrap storage,
- the runtime `/nix/store` paths exist in the root image,
- the runtime `/persist/nix/store` paths exist in persistent state,
- the BLS entry still points at `/usr/lib/systemd/systemd`,
- `busybox` and `dropbear` are still active for bootstrap services,
- the previous serial/network/SSH service definitions were not lost.

## What this phase does not prove

Phase 416 does not boot QEMU.

It proves image layout only.

It does not prove:

- systemd starts as PID 1 after this change,
- udev works at runtime,
- network and SSH come up at runtime,
- old Nix-origin payload debt is fully removed,
- systemd has a native ONIX source recipe.

Those are later steps.

The next phase should boot the image.

## Expected output shape

Successful output should include:

```text
==> installing and activating systemd from the local Phase 4 repo
==> materializing systemd from local moss repo into a scratch target
stone    : systemd installed under /usr/lib/systemd + /usr/bin
runtime  : materialized systemd bootstrap store into /nix/store
runtime  : materialized systemd bootstrap store into /persist/nix/store
proof    : /usr/share/onix/bootstrap/systemd-stone.txt
==> verifying Phase 416 systemd image install
==> success
status: systemd stone is installed and materialized for PID 1 runtime paths
```

The preview should show:

```text
/usr/lib/systemd/systemd -> /nix/store/...-systemd-.../lib/systemd/systemd
/usr/bin/systemctl      -> /nix/store/...-systemd-.../bin/systemctl
/nix/store/.../lib/systemd/systemd
/persist/nix/store/.../lib/systemd/systemd
```

## Next step

Phase 417 should boot the image and prove the new image layout really works at
runtime.

That boot proof should answer:

```text
Can the kernel execute the systemd-owned PID 1 path and reach the existing
bootstrap serial/network/SSH proofs again?
```
