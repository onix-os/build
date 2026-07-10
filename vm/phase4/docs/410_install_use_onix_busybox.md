# Phase 410 — install/use `busybox` in the image

| Item | Value |
|---|---|
| Command | `make phase 410` |
| Underlying make target/script | `vm/phase4/materialize-etc.sh --busybox-stone` |
| Reads package repo | `artifacts/onix-local-repo/stone.index` |
| Installs package payload from | `busybox` |
| Mutates disk/image? | Yes, `artifacts/onix-image/onix.raw` |
| Boots QEMU? | No |
| Main proof | The boot image now uses the locally built `busybox` stone for `/usr/bin/busybox` and the `/bin` compatibility command links. |

## Why this phase exists

Phase 409 built the first replacement system package:

```text
artifacts/onix-stones/busybox-...stone
artifacts/onix-local-repo/stone.index
```

That was only half of the story.

After Phase 409, the package existed, but the boot image still used the older
bootstrap BusyBox copied from Nix during Phases 403-406.

Phase 410 is the handoff:

```text
local moss repo
      |
      v
busybox stone
      |
      v
image /usr/bin/busybox
      |
      v
/bin compatibility links used by early bootstrap scripts
```

This matters because BusyBox is not a user toolbox.

BusyBox is base system machinery:

- `/bin/sh` runs bootstrap scripts.
- `/bin/ifconfig` and `/bin/route` bring up the first network proof.
- `/bin/nc` runs the temporary TCP inspection listener.
- `/bin/netstat` helps the SSH and remote-inspection status checks.
- `/bin/ls`, `/bin/cat`, `/bin/ps`, and friends are the tiny repair toolbox.

So BusyBox belongs in the machine plane:

```text
machine-plane software = moss/.stone packages
user toolbox software  = Nix
```

Phase 410 moves the active command path in that direction.

## The basic Linux idea: root tree and command lookup

When the kernel boots, it eventually mounts the real root filesystem at:

```text
/
```

That mounted filesystem is the running machine's root tree.

Every absolute path starts there:

```text
/usr/bin/busybox
/bin/sh
/etc/passwd
/usr/lib/systemd/systemd
/persist/home
```

When a script says:

```sh
/bin/sh /usr/lib/onix/bootstrap-network-up
```

Linux does not search randomly. It asks the filesystem:

```text
Does /bin/sh exist?
Is it executable?
If it is a symlink, where does it point?
Can the final executable be loaded?
```

That is why symlinks are important in this phase.

## Why BusyBox uses applet symlinks

BusyBox is one binary with many personalities.

The real executable is:

```text
/usr/bin/busybox
```

It knows many applets:

```text
sh
ls
cat
mount
ifconfig
nc
netstat
```

The common layout is:

```text
/usr/bin/sh  -> busybox
/usr/bin/ls  -> busybox
/usr/bin/cat -> busybox
```

When Linux executes `/usr/bin/ls`, it actually starts `busybox`, but BusyBox sees
that it was launched with the name `ls`, so it runs the `ls` applet.

This gives a tiny system many basic commands without shipping many separate
programs.

## Why the stone owns `/usr/bin`, not `/bin`

The `busybox` stone owns:

```text
/usr/bin/busybox
/usr/bin/sh
/usr/bin/ifconfig
/usr/bin/nc
/usr/share/onix/packages/busybox.applets
/usr/share/onix/packages/busybox.md
```

It does not own `/bin`.

That is deliberate.

During Phase 409 we learned that boulder/moss currently treat package payloads
as `/usr`-centric. Non-`/usr` payload paths are not a good package ownership
target yet.

So Phase 410 separates two ideas:

```text
package ownership      = /usr/bin/...
image compatibility    = /bin/...
```

The package owns `/usr/bin`.

The image keeps one of two compatibility layouts.

If the root tree already uses merged `/usr`, then `/bin` itself points at
`usr/bin`:

```text
/bin -> usr/bin
```

In that layout, `/bin/sh` and `/usr/bin/sh` are the same path through the
symlinked directory.

If the image has a real `/bin` directory instead, Phase 410 creates explicit
compatibility links:

```text
/bin/busybox -> ../usr/bin/busybox
/bin/sh      -> busybox
/bin/nc      -> busybox
/bin/ifconfig -> busybox
```

Both layouts keep the package model honest while letting older bootstrap scripts
keep using `/bin/sh`, `/bin/nc`, and similar paths.

### Background: merged `/usr`

Historically Unix split programs across `/bin`, `/sbin`, `/usr/bin`, and
`/usr/sbin` for reasons that stopped mattering decades ago (tiny early disks where
`/usr` might live on a separate volume). Modern distros do a **`/usr` merge**:
`/bin`, `/sbin`, and `/lib` become mere symlinks pointing into `/usr`, so there is
one real location for every program. This is a natural fit for ONIX's
stateless-`/usr` model — if all binaries live under `/usr`, then swapping `/usr`
atomically swaps the entire command set in one step.

On a merged-`/usr` image, `/bin` is itself a symlink to `usr/bin`, so `/bin/sh`
and `/usr/bin/sh` are literally the same file reached by two paths — no per-command
links are needed. On an image that still has a *real* `/bin` directory, the stone
cannot own those paths (boulder/moss keep payloads `/usr`-centric), so Phase 410
instead lays down explicit `/bin/<applet> -> busybox` compatibility symlinks. The
script detects which layout the image has and does the right thing, which is why
its output shows either `/bin -> usr/bin` or a list of explicit `/bin` links.

### Background: installing into a scratch target with `moss --to`

moss can install a package into *any* directory, not just the live system, via its
`install --to <dir>` option. Phase 410 uses this to materialize `busybox`
into a throwaway target directory first, verify the payload there, and only then
copy the verified files into the image. That keeps moss from writing its own
package-manager state into an image that is not yet fully moss-managed — a cleaner
separation that a later phase will close by making the image genuinely
moss-owned.

## Why Phase 410 installs through a scratch moss target first

There is an important safety detail here.

The boot image already has a root tree assembled from earlier phases. It also
has hand-written bootstrap files and systemd units.

A future ONIX image should be fully moss-managed, but we are not completely
there yet.

If Phase 410 asked moss to install directly into the image root, moss might also
write or rewrite package-manager state in ways that deserve their own careful
phase.

So this phase does a safer two-step flow:

```text
1. Use host moss to install busybox into a disposable scratch target.
2. Copy only the verified package payload from that scratch target into the image.
```

The scratch target lives under:

```text
artifacts/onix-phase4-work/busybox-install-target
```

That means Phase 410 still proves:

```text
moss can consume the local repo and materialize busybox
```

but it avoids pretending the whole image is already a final moss-managed system.

That full system-state integration belongs in later phases.

## What the script does

Run:

```sh
make phase 410
```

The target calls:

```text
vm/phase4/materialize-etc.sh --busybox-stone
```

The script:

1. Attaches `artifacts/onix-image/onix.raw` through a loop device.
2. Mounts the `onix-root` partition.
3. Mounts the real `ONIX-PERSIST` partition under `/persist`.
4. Checks that earlier bootstrap files from Phases 403-406 exist.
5. Checks that the local repo index exists:

   ```text
   artifacts/onix-local-repo/stone.index
   ```

6. Uses host Moss from:

   ```text
   artifacts/host-tools/bin/moss
   ```

7. Adds the local repo to a disposable moss root.
8. Installs `busybox` into a scratch target.
9. Verifies the scratch install:

   - `/usr/bin/busybox` exists and runs,
   - the binary has no dynamic interpreter,
   - required applets exist,
   - package notes exist.

10. Copies the verified package payload into the image root.
11. Preserves the image's existing `/bin` policy:
    - if `/bin -> usr/bin`, applets resolve through `/usr/bin`;
    - otherwise explicit `/bin/<applet>` compatibility links are created.
12. Rewrites the bootstrap serial unit to run:

    ```text
    ExecStart=/usr/bin/busybox sh /usr/lib/onix/bootstrap-serial-shell
    ```

13. Writes the proof note:

    ```text
    /usr/share/onix/bootstrap/busybox-stone.txt
    ```

14. Verifies the final image state.

## What changes inside the image

After this phase, the image should contain:

```text
/usr/bin/busybox
/usr/bin/sh -> busybox
/usr/bin/nc -> busybox
/usr/share/onix/packages/busybox.applets
/usr/share/onix/packages/busybox.md
/usr/share/onix/bootstrap/busybox-stone.txt
```

And the image compatibility path should resolve through either merged `/usr`:

```text
/bin -> usr/bin
/bin/sh -> /usr/bin/sh -> busybox
```

or explicit compatibility links:

```text
/bin/busybox -> ../usr/bin/busybox
/bin/sh      -> busybox
/bin/nc      -> busybox
/bin/netstat -> busybox
```

The bootstrap serial systemd unit should no longer execute the Nix BusyBox path.

It should execute:

```text
/usr/bin/busybox
```

## What does not change yet

This phase does not delete the old Nix BusyBox closure.

That sounds annoying, but it is intentional.

Deleting old payloads is a different kind of proof. We should only delete them
after we have booted with the replacement and proved that the shell, network,
remote inspection, and SSH paths still work.

So the truth after Phase 410 is:

```text
active command path = busybox stone
old Nix closure     = may still be present on disk
```

The later audit phase will remove or fail on leftover Nix-sourced machine-plane
payloads.

## Expected output

You should see the script say that it is installing from the local repo:

```text
==> installing and activating busybox from the local Phase 4 repo
==> materializing busybox from local moss repo into a scratch target
```

Then it should copy the package payload and create compatibility links:

```text
stone    : busybox installed under /usr/bin
compat  : /bin -> usr/bin; applets resolve through /usr/bin
```

If the image does not use merged `/usr`, the compatibility line will instead
show explicit `/bin` applet links.

The important success status is:

```text
==> success
status: busybox stone is installed and active for /bin compatibility links
```

## How to inspect it manually

Phase 410 itself does not boot QEMU.

It mutates the image and prints a preview.

If you want to inspect the mounted result while debugging, use the script output
first. It prints paths like:

```text
/usr/bin/busybox
/bin -> usr/bin
/bin/sh -> busybox
```

Do not manually mount the image unless the scripts fail and we are debugging
carefully. Manual mounts are easy to leave stale, and stale loop devices can
confuse later phase runs.

Use:

```sh
make stop
```

if a phase is interrupted and you want to keep generated disk/image state.

Use `make cleanup` only when you intentionally want to remove generated
disk/image state.

## How this connects to the next phase

Phase 410 is a disk mutation proof.

It does not prove that the booted machine still works.

The next phase should boot the image and re-run the important behavioral checks:

```text
serial shell
network status
remote inspection
SSH
```

That matters because filesystem verification can only prove paths exist.

Boot verification proves the running system can actually execute those paths.

In short:

```text
409 = build package
410 = install/use package in image
411 = boot and prove behavior still works
```
