# Phase 1 overview — first real ONIX stones

Phase 1 turns the Phase 0 tooling proof into real ONIX package artifacts.

We start deliberately small:

```text
onix-branding
onix-filesystem
```

These packages establish identity, default filesystem policy, and the first
publishable repository shape.

## Why Phase 1 exists

Phase 0 proved we can build a toy package. Phase 1 proves ONIX can build real
package payloads, compose them, index them into a Moss repo, export that repo to
the host, and preview a future static package repository.

## Steps

- [100 — forge readiness](./100.md)
- [101 — build `onix-branding`](./101.md)
- [102 — build `onix-filesystem`](./102.md)
- [103 — assemble first named local ONIX repo](./103.md)
- [104 — prepare publishable ONIX repo layout](./104.md)
- [105 — export publishable repo to the host](./105.md)
- [106 — verify exported host artifact](./106.md)
- [107 — verify no-upload publishing plan](./107.md)
- [108 — preview publication without upload](./108.md)

Running:

```sh
make phase 1
```

runs the whole Phase 1 family.
