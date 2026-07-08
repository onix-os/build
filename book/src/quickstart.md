# Quickstart

Use the repository `Makefile` for normal work.

```sh
make doctor      # common health check
make stop        # stop QEMU/probes and detach stale mounts; keep disks/images
make cleanup     # destructive reset: stop everything and remove generated disks/images
make up          # boot native ONIX, prove SSH, and leave QEMU running
make phases      # print the numbered learning flow
make phase 0     # run all Phase 0 steps
make phase 1     # run all Phase 1 steps
make phase 2     # run the canonical Phase 2 path
make phase 3     # explain deferred ONIX-owned kernel work
make phase 4     # run canonical Phase 4 build/proof steps: 400..422
make phase 424   # boot native ONIX and leave it running for inspection
make phase 425   # accept the running Phase 4 VM
```

Individual steps use three digits:

```text
002 = Phase 0, step 02
102 = Phase 1, step 02
212 = Phase 2, step 12
213 = Phase 2, step 13
214 = Phase 2, step 14
300 = Phase 3, step 00
400 = Phase 4, step 00
401 = Phase 4, step 01
402 = Phase 4, step 02
403 = Phase 4, step 03
404 = Phase 4, step 04
405 = Phase 4, step 05
406 = Phase 4, step 06
407 = Phase 4, step 07
408 = Phase 4, step 08
409 = Phase 4, step 09
410 = Phase 4, step 10
411 = Phase 4, step 11
412 = Phase 4, step 12
413 = Phase 4, step 13
414 = Phase 4, step 14
415 = Phase 4, step 15
416 = Phase 4, step 16
417 = Phase 4, step 17
418 = Phase 4, step 18
419 = Phase 4, step 19
420 = Phase 4, step 20
421 = Phase 4, step 21
422 = Phase 4, step 22
424 = Phase 4, step 24
425 = Phase 4, step 25
```

Examples:

```sh
make phase 002   # build the forge disk
make phase 003   # boot the forge VM
make phase 101   # build onix-branding
make phase 213   # stage the first musl systemd userspace payload
make phase 214   # stage the first kernel module/kmod payload
make phase 212   # run the ONIX boot probe
make phase 300   # document deferred kernel ownership
make phase 400   # start booted-base userspace planning
make phase 401   # materialize live /etc from packaged defaults
make phase 402   # materialize base users/groups/shell policy
make phase 403   # prove bootstrap serial root console
make phase 404   # prove minimal QEMU user networking
make phase 405   # prove host-to-guest TCP inspection
make phase 406   # prove authenticated SSH access
make phase 407   # audit temporary Nix-sourced system payloads
make phase 408   # define local stone/repo contract
make phase 409   # build source-based onix-busybox stone
make phase 410   # install/use onix-busybox in the image
make phase 411   # boot-prove shell/network/SSH with onix-busybox
make phase 412   # build source-based onix-dropbear stone
make phase 413   # install/use onix-dropbear and prove SSH
make phase 414   # audit systemd ownership before packaging
make phase 415   # build bootstrap onix-systemd stone
make phase 416   # install/use onix-systemd in the image
make phase 417   # boot-prove onix-systemd as PID 1 runtime
make phase 418   # package/prove bootstrap policy ownership
make phase 419   # audit booted-base ownership/debt map
make phase 420   # prune stale old Nix BusyBox/Dropbear payloads
make phase 421   # prepare native source-built onix-systemd plan
make phase 422   # build/install/boot-prove native onix-systemd
make phase 424   # boot native ONIX, prove SSH, and leave QEMU running
make phase 425   # final Phase 4 acceptance check against the running VM
make up          # shortcut for the Phase 424 day-to-day bring-up
```

## Stopping vs cleaning

Use:

```sh
make stop
```

when a VM/probe is stuck or you want to detach stale mounts while keeping
generated work such as:

```text
vm/state/quarry.raw
artifacts/onix-image/onix.raw
artifacts/onix-stones/
artifacts/onix-local-repo/
```

Use:

```sh
make cleanup
```

only when you intentionally want a destructive reset of generated disks/images.
It stops QEMU first, then removes generated disk/image state.

To boot the current native-systemd image and leave it running for interactive
inspection:

```sh
make phase 424
ssh -i vm/state/id_ed25519 -p 7630 onix@127.0.0.1
```

Then accept the running VM:

```sh
make phase 425
```

The shortcut is:

```sh
make up
```

Stop that VM with:

```sh
make stop
```

Phase 3 is intentionally reserved for ONIX-owned kernel/initramfs/modules work.
For now ONIX keeps using the borrowed Alpine virt kernel payload proved in Phase
2, and Phase 4 continues with booted userspace work.

Some phases can be watched interactively:

```sh
ATTACHED=1 make phase 212
make phase 212 ATTACHED=1
```

For Phase 212, attached mode uses the serial console in the current terminal by
default. GUI/VNC only starts when explicitly requested:

```sh
ONIX_BOOT_PROBE_DISPLAY=gtk ATTACHED=1 make phase 212
ONIX_BOOT_PROBE_DISPLAY=vnc ATTACHED=1 make phase 212
```

## Book commands

Build the book:

```sh
make book
```

Serve the book locally:

```sh
make book-serve
```

The generated HTML goes under:

```text
book/html/
```

That directory is generated output and is not committed.
