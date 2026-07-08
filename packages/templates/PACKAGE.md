# PACKAGE_NAME

## Summary

Short explanation of what this package provides.

## System role

- Group: `base` / `core` / `services`
- Installed plane: machine/system
- Why ONIX needs it:

## Implementation choice

- Implementation language:
- Rust alternative considered:
- Serious Rust implementation exists: `yes` / `no` / `not applicable`
- Selected implementation:
- Why this implementation:

Rust-first is mandatory for ONIX system packages. If this package does not use a
Rust implementation, explain why that is acceptable.

## Source and provenance

- Upstream:
- Source archive or repository:
- Pinned version:
- Source hash:
- Patch set:

## Build model

- Build environment:
- Build tools:
- Target triple:
- C runtime: `musl`
- Link model: `static musl` / `static-pie musl` / `dynamic musl exception`
- Shared runtime libraries: `none` / `documented exception`

ONIX system packages must avoid glibc and avoid shared runtime dependencies by
default. Any dynamic musl or shared-library exception must be explained here.

## Runtime-clean contract

- No runtime `/nix/store` dependency: `yes` / `no`
- No `/nix/store` shebangs: `yes` / `no`
- No `/nix/store` RPATH/RUNPATH: `yes` / `no`
- No systemd units calling `/nix/store`: `yes` / `no` / `not applicable`
- No glibc loader path: `yes` / `no`
- No unexpected shared runtime libraries: `yes` / `no`

Required checks before accepting the package:

```sh
grep -R /nix/store payload/
find payload -type f -perm -111 -exec file {} \;
readelf -l payload/usr/bin/PROGRAM
readelf -d payload/usr/bin/PROGRAM
```

## Runtime dependencies

List the runtime dependencies that are allowed after installation.

```text
- dependency:
  reason:
  owner package:
```

## Installed paths

Important installed files:

```text
/usr/bin/...
/usr/lib/...
/usr/share/...
```

## Stone ownership

The finished `.stone` must own installed system files directly.

Bad:

```text
/usr/bin/foo -> /nix/store/.../bin/foo
```

Good:

```text
/usr/bin/foo
```

## Exceptions

Document every exception to the Rust-first, musl-only, runtime-clean package
law.

No unchecked exceptions.
