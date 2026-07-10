# musl

## Summary

musl is the ONIX system libc runtime provider for dynamic-musl packages.

Most ONIX command binaries still try static/static-PIE first. But once ONIX
accepts intentional dynamic-musl library surfaces such as PAM and libseccomp,
the repo also needs an ONIX-owned provider for musl's own runtime soname.

## System role

- Group: `libs`
- Installed plane: machine/system
- Why ONIX needs it: dynamic-musl packages depend on the musl loader/libc
  soname. Moss needs a package-owned provider for that soname during install
  proofs.

## Implementation choice

- Implementation language: C
- Rust alternative considered: not applicable for libc
- Serious Rust implementation exists: `no`
- Selected implementation: musl libc
- Why this implementation: ONIX is a musl system. musl is the libc contract the
  whole system is built around.

## Source and provenance

- Upstream: `https://musl.libc.org/`
- Source archive or repository: pinned through the repo's `nixpkgs_2` input
- Pinned version: read by `make phase 510`
- Source hash: generated and checked by `make phase 510`
- Patch set: none

## Build model

- Build environment: Alpine/musl forge VM
- Build tools: C toolchain, make, boulder, moss
- Target triple: forge-native musl target
- C runtime: self
- Link model: dynamic-musl runtime provider
- Static attempt/result: not applicable; this stone exists specifically to own
  the dynamic musl runtime provider.
- Shared runtime libraries: musl runtime surface

Expected first surface:

```text
/usr/lib/ld-musl-x86_64.so.1
/usr/lib/libc.so -> ld-musl-x86_64.so.1
/usr/lib/libc.musl-x86_64.so.1 -> ld-musl-x86_64.so.1
```

ONIX image roots are usr-merged, so `/lib/ld-musl-x86_64.so.1` resolves through
`/lib -> /usr/lib` in a booted image. The stone owns the file under `/usr/lib`
because that is where Boulder/Moss classify shared-library providers.

## Runtime-clean contract

- No runtime `/nix/store` dependency: required
- No `/nix/store` shebangs: required
- No `/nix/store` RPATH/RUNPATH: required
- No systemd units calling `/nix/store`: not applicable
- No glibc loader path: required
- No unexpected shared runtime libraries: required
- All expected shared libraries are ONIX-owned: required

## Runtime dependencies

musl is the base runtime provider. It must not depend on glibc.

## Installed paths

Expected installed files:

```text
/usr/lib/ld-musl-x86_64.so.1
/usr/include/*
/usr/lib/*
/usr/share/onix/packages/musl.md
```

The first package may include development files because ONIX has not split
runtime/devel packages yet. A later packaging refinement can split them.

## Exceptions

This is a base runtime provider, not an ordinary command package.

No glibc and no `/nix/store` runtime paths are allowed.
