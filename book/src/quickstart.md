# Quickstart

Use the repository `Makefile` for normal work.

```sh
make doctor      # common health check
make phases      # print the numbered learning flow
make phase 0     # run all Phase 0 steps
make phase 1     # run all Phase 1 steps
make phase 2     # run the canonical Phase 2 path
make phase 3     # explain deferred ONIX-owned kernel work
make phase 4     # run the Phase 4 booted-base readiness lane
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
