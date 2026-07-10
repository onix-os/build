# ONIX

ONIX is a step-by-step build of an atomic, **musl-based** Linux distro using:

- `moss` for package/state management
- `boulder` for `.stone` package builds
- systemd/systemd-boot for the real ONIX boot path
- Nix as the host development toolbox

The detailed learning documentation is wired through the root mdBook files:

```text
book.toml
SUMMARY.md
```

Start here:

- [Book introduction](./vm/INTRODUCTION.md)
- [Quickstart](./vm/QUICKSTART.md)
- [Phase 0 — forge VM and first `.stone`](./vm/phase0/docs/phase_0_forge_vm_and_first_stone.md)
- [Phase 1 — first real ONIX stones](./vm/phase1/docs/phase_1_first_real_onix_stones.md)
- [Phase 2 — first bootable ONIX image](./vm/phase2/docs/phase_2_first_bootable_onix_image.md)
- [Phase 4 — booted ONIX base userspace](./vm/phase4/docs/phase_4_booted_onix_base_userspace.md)
- [Architecture](./ARCHITECTURE.md)

## Common commands

```sh
make doctor      # common health check
make stop        # stop QEMU/probes and detach stale mounts; keep disks/images
make cleanup     # destructive reset: stop everything and remove generated disks/images
make up          # boot native ONIX, prove SSH, and leave QEMU running
make phases      # print the numbered phase map
make book        # build the mdBook into site/
make book-serve  # serve the mdBook locally
```

Everything build-related is still run by numbered phase:

```sh
make phase 002
make phase 101
make phase 212
make phase 424
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
site/
```

## Branding rule

Use only:

```text
ONIX
onix
```

Do not use mixed-case spelling.
