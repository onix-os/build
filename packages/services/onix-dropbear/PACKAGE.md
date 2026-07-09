# onix-dropbear

## Summary

Static musl Dropbear SSH server for early ONIX remote access.

## System role

- Group: `services`
- Installed plane: machine/system service
- Why ONIX needs it: provides small SSH access for boot proofs and live
  inspection before the final service/package story is larger.

## Implementation choice

- Implementation language: C
- Rust alternative considered: Rust SSH libraries and daemon candidates
- Serious Rust implementation exists: partial
- Selected implementation: Dropbear
- Why this implementation: Dropbear is small, proven, and can be built as a
  static musl bootstrap SSH server. Rust SSH daemon options need separate
  evaluation before they can replace this early remote-access role.

This is a documented non-Rust bootstrap service package.

## Source and provenance

- Upstream: Dropbear
- Source archive or repository: recorded by the Phase 4 source recipe
- Pinned version: recipe placeholder `@DROPBEAR_VERSION@`
- Source hash: recipe placeholder `@DROPBEAR_SOURCE_SHA256@`
- Patch set: Phase 4 build script state

## Build model

- Build environment: Alpine/musl forge VM during current bootstrap
- Build tools: C compiler, make, Dropbear build system
- Target triple: x86_64 musl environment
- C runtime: musl
- Link model: static musl
- Shared runtime libraries: none expected

## Runtime-clean contract

- No runtime `/nix/store` dependency: yes
- No `/nix/store` shebangs: yes
- No `/nix/store` RPATH/RUNPATH: yes
- No systemd units calling `/nix/store`: yes, when paired with
  `onix-bootstrap-policy`
- No glibc loader path: yes
- No unexpected shared runtime libraries: yes

## Runtime dependencies

None expected. Dropbear binaries are intended to be static musl.

## Installed paths

```text
/usr/sbin/dropbear
/usr/bin/dropbearkey
/usr/share/onix/packages/onix-dropbear.md
```

## Stone ownership

The finished `.stone` owns Dropbear binaries directly. Service units are owned
by `onix-bootstrap-policy` for now.

## Exceptions

Non-Rust implementation accepted temporarily for early bootstrap SSH.
