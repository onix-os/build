# branding

## Summary

ONIX identity, `os-info` metadata, issue text, MOTD fallback, and login logo
assets.

## System role

- Group: `base`
- Installed plane: machine/system identity
- Why ONIX needs it: provides the identity files that make the system call
  itself ONIX and gives image/login materialization code a package-owned source
  for branding assets.

## Implementation choice

- Implementation language: data package with POSIX shell install commands
- Rust alternative considered: not applicable
- Serious Rust implementation exists: not applicable
- Selected implementation: Boulder data-package recipe
- Why this implementation: this package mostly ships text, JSON, and logo
  assets. A Rust program would add complexity without improving the package.

Rust-first still applies to tools. This package is not a tool implementation.

## Source and provenance

- Upstream: ONIX project
- Source archive or repository: this repository
- Pinned version: repository revision
- Source hash: repository revision
- Patch set: none

## Build model

- Build environment: Boulder recipe install phase
- Build tools: POSIX shell utilities from the builder
- Target triple: not applicable
- C runtime: not applicable
- Link model: no executable payload
- Shared runtime libraries: none

## Runtime-clean contract

- No runtime `/nix/store` dependency: yes
- No `/nix/store` shebangs: yes
- No `/nix/store` RPATH/RUNPATH: yes
- No systemd units calling `/nix/store`: not applicable
- No glibc loader path: yes
- No unexpected shared runtime libraries: yes

## Runtime dependencies

None.

## Installed paths

```text
/usr/lib/os-info.json
/usr/share/onix/branding/logo.txt
/usr/share/onix/branding/logo.ansi
/usr/share/onix/branding/logo.motd
/usr/share/defaults/etc/issue
/usr/share/defaults/etc/motd
```

## Stone ownership

The finished `.stone` owns branding files directly under `/usr`.

## Exceptions

None.
