# ONIX

ONIX is a step-by-step build of an atomic, **musl-based** Linux distro using:

- `moss` for package/state management
- `boulder` for `.stone` package builds
- systemd/systemd-boot for the real ONIX boot path
- Nix as the host development toolbox

The detailed learning documentation now lives in the mdBook:

```text
book/
```

Start here:

- [Book introduction](./book/src/introduction.md)
- [Quickstart](./book/src/quickstart.md)
- [Phase 0 — forge VM and first `.stone`](./book/src/phases/phase-0.md)
- [Phase 1 — first real ONIX stones](./book/src/phases/phase-1.md)
- [Phase 2 — first bootable ONIX image](./book/src/phases/phase-2.md)
- [Architecture](./book/src/architecture.md)

## Common commands

```sh
make doctor      # common health check
make cleanup     # stop ONIX QEMU processes and detach generated mounts
make phases      # print the numbered phase map
make book        # build the mdBook into book/html/
make book-serve  # serve the mdBook locally
```

Everything build-related is still run by numbered phase:

```sh
make phase 002
make phase 101
make phase 212
```

Family shortcuts run a whole phase family:

```sh
make phase 0
make phase 1
make phase 2
```

## Generated files

These are generated and gitignored:

```text
artifacts/
vm/downloads/
vm/state/
book/html/
```

## Branding rule

Use only:

```text
ONIX
onix
```

Do not use mixed-case spelling.
