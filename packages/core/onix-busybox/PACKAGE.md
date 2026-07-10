# onix-busybox

## Summary

Static musl BusyBox payload used by the early ONIX base system and later as a
bootstrap/recovery shell.

## System role

- Group: `core`
- Installed plane: machine/system command base
- Why ONIX needs it: provides a compact shell and command set while ONIX
  replaces bootstrap pieces with more canonical Rust-first packages.

## Implementation choice

- Implementation language: C
- Rust alternative considered: uutils coreutils and other Rust command suites
- Serious Rust implementation exists: partial
- Selected implementation: BusyBox
- Why this implementation: BusyBox provides one compact static musl binary with
  shell and many applets needed for early bootstrapping. Rust alternatives are
  preferred for individual command families, but they do not replace the whole
  early BusyBox role yet.

This is a documented non-Rust bootstrap package. It shrinks in importance as
Rust-first core packages such as `uutils-coreutils` enter the system.

## Source and provenance

- Upstream: BusyBox
- Source archive or repository: recorded by the Phase 4 source recipe
- Pinned version: recipe placeholder `@BUSYBOX_VERSION@`
- Source hash: recipe placeholder `@BUSYBOX_SOURCE_SHA256@`
- Patch set: Phase 4 build script state

## Build model

- Build environment: Alpine/musl forge VM during current bootstrap
- Build tools: C compiler, make, BusyBox build system
- Target triple: x86_64 musl environment
- C runtime: musl
- Link model: static musl
- Shared runtime libraries: none expected

## Runtime-clean contract

- No runtime `/nix/store` dependency: yes
- No `/nix/store` shebangs: yes
- No `/nix/store` RPATH/RUNPATH: yes
- No systemd units calling `/nix/store`: not applicable
- No glibc loader path: yes
- No unexpected shared runtime libraries: yes

## Runtime dependencies

None expected. The BusyBox binary is intended to be static musl.

## Installed paths

```text
/usr/bin/busybox
/usr/share/onix/packages/onix-busybox.applets
/usr/share/onix/packages/onix-busybox.links
/usr/share/onix/packages/onix-busybox.systemd-owned
/usr/share/onix/packages/onix-busybox.md
```

## Stone ownership

The finished `.stone` owns `/usr/bin/busybox` directly and owns only the
bootstrap/recovery applet links listed in `onix-busybox.links`.

It must not install a symlink into `/nix/store`.

It must not own `/usr/bin/reboot` or `/usr/bin/poweroff`; those command names
belong to `onix-systemd`.

Starting in Phase 513, it must also not own common coreutils command names such
as:

```text
/usr/bin/ls
/usr/bin/cp
/usr/bin/mv
/usr/bin/rm
/usr/bin/cat
/usr/bin/echo
```

Those belong to `uutils-coreutils`.

## Exceptions

Non-Rust implementation accepted temporarily because this is the early compact
bootstrap command base.
