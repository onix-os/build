# Quickstart

Use the repository `Makefile` for normal work.

```sh
make doctor      # common health check
make phases      # print the numbered learning flow
make phase 0     # run all Phase 0 steps
make phase 1     # run all Phase 1 steps
make phase 2     # run the canonical Phase 2 path
```

Individual steps use three digits:

```text
002 = Phase 0, step 02
102 = Phase 1, step 02
212 = Phase 2, step 12
```

Examples:

```sh
make phase 002   # build the forge disk
make phase 003   # boot the forge VM
make phase 101   # build onix-branding
make phase 212   # run the first ONIX boot probe
```

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
