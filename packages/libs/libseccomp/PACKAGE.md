# libseccomp

## Summary

libseccomp is the ONIX-owned seccomp filtering library surface.

Phase 510 packages it because RootAsRole's `chsr` uses seccomp for hardening.
That dependency must be owned by ONIX before RootAsRole can become a clean
system package.

## System role

- Group: `libs`
- Installed plane: machine/system
- Why ONIX needs it: privileged tools need a small, auditable way to install
  Linux seccomp filters.

## Implementation choice

- Implementation language: C
- Rust alternative considered: Rust crates wrap or bind to the kernel interface,
  but RootAsRole's current upstream path links libseccomp
- Serious Rust implementation exists: not for the current RootAsRole ABI need
- Selected implementation: libseccomp
- Why this implementation: it is the standard small C library used by upstream
  tools for seccomp filter construction.

## Source and provenance

- Upstream: `https://github.com/seccomp/libseccomp`
- Source archive or repository: pinned through the repo's `nixpkgs_2` input
- Pinned version: read by `make phase 510`
- Source hash: generated and checked by `make phase 510`
- Patch set: none

## Build model

- Build environment: Alpine/musl forge VM
- Build tools: C toolchain, autotools-generated configure, boulder, moss
- Target triple: forge-native musl target
- C runtime: `musl`
- Link model: `dynamic musl exception`
- Static attempt/result: static output is not the default accepted surface here
  because RootAsRole needs a package-owned shared runtime library; static can be
  revisited later if upstream supports it cleanly.
- Shared runtime libraries: documented minimal surface

Expected first surface:

```text
libseccomp.so.2
```

## Runtime-clean contract

- No runtime `/nix/store` dependency: required
- No `/nix/store` shebangs: required
- No `/nix/store` RPATH/RUNPATH: required
- No systemd units calling `/nix/store`: not applicable
- No glibc loader path: required
- No unexpected shared runtime libraries: required
- All expected shared libraries are ONIX-owned: required

## Runtime dependencies

```text
- musl:
  reason: dynamic musl libc.
  owner package: musl / base runtime
```

## Installed paths

Expected installed files:

```text
/usr/lib/libseccomp.so*
/usr/include/seccomp.h
/usr/lib/pkgconfig/libseccomp.pc
/usr/share/onix/packages/libseccomp.md
```

## Exceptions

libseccomp is a dynamic-musl exception so RootAsRole can depend on an ONIX-owned
seccomp library instead of a host library.

No glibc and no `/nix/store` runtime paths are allowed.
