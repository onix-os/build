# Phase 0 overview — forge VM and first `.stone`

Phase 0 is not the ONIX operating system yet. It is the **forge**: a temporary
Alpine/musl VM where we build and test the package tooling before trying to
build ONIX itself.

The Phase 0 proof chain is:

```text
Alpine minirootfs
  -> bootable forge VM
  -> moss + boulder
  -> first tiny .stone
  -> real Moss state install/remove/rollback
```

## Why Phase 0 exists

ONIX wants to be musl-based and Moss-managed. To build `.stone` packages we
need `moss` and `boulder` running on a musl machine. Alpine gives us a small
temporary musl environment. It is scaffolding, not the final distro.

## Steps

- [000 — validate](./000.md)
- [001 — passwordless disk builder](./001.md)
- [002 — build the forge disk](./002.md)
- [003 — boot the forge](./003.md)
- [004 — provision tools](./004.md)
- [005 — first `.stone`](./005.md)
- [006 — real Moss state smoke test](./006.md)

Running:

```sh
make phase 0
```

runs the whole Phase 0 family.
