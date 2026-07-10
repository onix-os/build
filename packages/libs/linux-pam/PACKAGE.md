# linux-pam

## Summary

Linux-PAM is the ONIX-owned PAM runtime surface for packages that need
pluggable authentication.

Phase 510 packages it as a deliberate shared-library stone because PAM is not a
good static-only dependency model: PAM's design is a shared library plus loadable
authentication modules.

## System role

- Group: `libs`
- Installed plane: machine/system
- Why ONIX needs it: RootAsRole's `dosr` uses PAM for authentication/session
  handling. ONIX must own that library surface instead of linking RootAsRole
  against whatever PAM happened to exist in the forge.

## Implementation choice

- Implementation language: C
- Rust alternative considered: none serious for Linux PAM ABI compatibility
- Serious Rust implementation exists: `no`
- Selected implementation: Linux-PAM
- Why this implementation: RootAsRole and many Unix privilege/login tools expect
  the PAM ABI. ONIX needs a package-owned PAM ABI before it can package those
  tools honestly.

## Source and provenance

- Upstream: `https://github.com/linux-pam/linux-pam`
- Source archive or repository: pinned through the repo's `nixpkgs_2` input
- Pinned version: read by `make phase 510`
- Source hash: generated and checked by `make phase 510`
- Patch set: none

Nix is used only to locate/realize the pinned source. The build itself runs in
the Alpine/musl forge VM and boulder cuts the finished payload into a `.stone`.

## Build model

- Build environment: Alpine/musl forge VM
- Build tools: C toolchain, Meson/Ninja, pkg-config, boulder, moss
- Target triple: forge-native musl target
- C runtime: `musl`
- Link model: `dynamic musl exception`
- Static attempt/result: static-only is explicitly ruled out for PAM because the
  PAM model is a runtime module ABI; ONIX instead owns the smallest useful
  shared surface.
- Shared runtime libraries: documented minimal surface

Expected first surface:

```text
libpam.so.0
libpam_misc.so.0
libpamc.so.0
/usr/lib/security/*.so
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
  reason: dynamic musl interpreter/libc.
  owner package: musl / base runtime
```

If a later PAM module adds another runtime library, update this file and keep the
surface package-owned.

## Installed paths

Expected installed files:

```text
/usr/lib/libpam.so*
/usr/lib/libpam_misc.so*
/usr/lib/libpamc.so*
/usr/lib/security/*.so
/usr/include/security/*.h
/usr/lib/pkgconfig/pam*.pc
/usr/share/onix/packages/linux-pam.md
```

Live `/etc/pam.d` policy is not owned here. Package defaults belong under
`/usr/share/defaults`, and a later materialization step decides what becomes
live machine state.

## Exceptions

Linux-PAM is a dynamic-musl exception by design. The exception is allowed because
the shared-library and module surface is the product being packaged.

No glibc and no `/nix/store` runtime paths are allowed.
