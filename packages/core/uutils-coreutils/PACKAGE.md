# uutils-coreutils

## Summary

Rust implementation of the classic coreutils command family.

Phase 509 packages the multicall `coreutils` binary first. Phase 513 rebuilds
the package with command-name links for every applet reported by
`/usr/bin/coreutils --list` after `busybox` stops owning those overlapping
paths.

## System role

- Group: `core`
- Installed plane: machine/system
- Why ONIX needs it: ONIX needs a Rust-first replacement path for the basic
  userland commands currently provided by BusyBox during bootstrap.

## Implementation choice

- Implementation language: Rust
- Rust alternative considered: uutils coreutils
- Serious Rust implementation exists: `yes`
- Selected implementation: uutils coreutils
- Why this implementation: uutils is the mature Rust implementation of the GNU
  coreutils command family and matches ONIX's Rust-first package law.

BusyBox stays in the system for early bootstrap shell, networking, and recovery
needs, but normal coreutils command ownership migrates to uutils in Phase 513.

## Source and provenance

- Upstream: `https://github.com/uutils/coreutils`
- Source archive or repository: pinned through the repo's `nixpkgs_2` input
- Pinned version: `0.8.0`
- Source hash: generated and checked by `make phase 509`
- Patch set: none

Nix is used only to locate and realize the pinned source tree. The build itself
runs in the Alpine/musl forge VM and the finished payload is packaged by
boulder into a `.stone`.

## Build model

- Build environment: Alpine/musl forge VM
- Build tools: `cargo`, `rustc`, `boulder`, `moss`
- Target triple: forge-native musl target
- C runtime: `musl`
- Link model: `static-pie musl`
- Shared runtime libraries: `none`

Build command shape for Phase 509:

```text
cargo rustc --release --locked --no-default-features --features feat_Tier1 --bin coreutils -- -C target-feature=+crt-static
```

That gives ONIX a broad but conservative command set without enabling ACL,
SELinux, SMACK, logind, or other shared-library-oriented feature paths.

## Runtime-clean contract

- No runtime `/nix/store` dependency: `yes`
- No `/nix/store` shebangs: `yes`
- No `/nix/store` RPATH/RUNPATH: `yes`
- No systemd units calling `/nix/store`: `not applicable`
- No glibc loader path: `yes`
- No unexpected shared runtime libraries: `yes`

Required checks before accepting the package:

```sh
file payload/usr/bin/coreutils
readelf -l payload/usr/bin/coreutils
readelf -d payload/usr/bin/coreutils
vm/phase5/audit-stone-payload.sh payload
```

## Runtime dependencies

```text
- dependency: Linux kernel
  reason: normal process/filesystem/syscall interface
  owner package: kernel phase, currently borrowed Alpine virt kernel
```

No shared userspace runtime library dependency is allowed for this Phase 509
payload.

## Installed paths

Important installed files after Phase 509:

```text
/usr/bin/coreutils
/usr/share/onix/packages/uutils-coreutils.md
/usr/share/onix/packages/uutils-coreutils.commands
/usr/share/onix/packages/uutils-coreutils.pending-links
```

Important installed files after Phase 513:

```text
/usr/bin/coreutils
/usr/bin/[ -> coreutils
/usr/bin/ls -> coreutils
/usr/bin/cp -> coreutils
/usr/bin/mv -> coreutils
/usr/bin/rm -> coreutils
```

The command list is generated from the built multicall binary:

```text
/usr/bin/coreutils --list
```

The same list drives the Phase 513 command-name links, so ONIX exposes the full
compiled uutils applet set, including special command names such as `[`.

## Stone ownership

The finished `.stone` owns the multicall binary directly:

```text
/usr/bin/coreutils
```

It must not point at:

```text
/nix/store/...
```

## Exceptions

Phase 509 intentionally does not install command-name links yet.

Reason:

```text
busybox currently owns the bootstrap command paths.
```

Moving `/usr/bin/ls`, `/usr/bin/cp`, and related command ownership from BusyBox
to uutils must be a later explicit package-ownership migration, not an
accidental collision.

Phase 513 is that explicit migration. It rebuilds `busybox` with the
overlapping command links removed, then rebuilds `uutils-coreutils` with all
compiled applet links enabled and proves both packages install together without
path collisions.
