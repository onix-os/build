# onix-systemd

## Summary

Native source-built systemd userspace for ONIX.

## System role

- Group: `services`
- Installed plane: machine/system init and service manager
- Why ONIX needs it: ONIX currently chooses systemd as PID 1 and service manager
  while keeping the rest of the system Rust-first where serious alternatives
  exist.

## Implementation choice

- Implementation language: C
- Rust alternative considered: no complete production replacement for systemd
  as PID 1 and service manager
- Serious Rust implementation exists: no
- Selected implementation: systemd
- Why this implementation: systemd is the current ONIX init/service-manager
  decision. Phase 4 proved native musl systemd can boot ONIX as PID 1.

Rust-first does not mean Rust-blind. systemd is a documented non-Rust system
component because there is no serious Rust replacement for its ONIX role today.

## Source and provenance

- Upstream: systemd
- Source archive or repository: recorded by the Phase 4 native systemd recipe
- Pinned version: recipe placeholder `@SYSTEMD_VERSION@`
- Source hash: recipe placeholder `@SYSTEMD_NATIVE_PAYLOAD_SHA256@`
- Patch set: Phase 4 native systemd build state

## Build model

- Build environment: current Phase 4 native systemd build path
- Build tools: C toolchain, meson/ninja-style systemd build stack
- Target triple: x86_64 musl environment
- C runtime: musl
- Link model: native musl service-manager payload; strict static split is not
  complete yet
- Shared runtime libraries: documented bootstrap exception until dependency
  split/audit phases complete

## Runtime-clean contract

- No runtime `/nix/store` dependency: yes for the native Phase 422 package
- No `/nix/store` shebangs: yes
- No `/nix/store` RPATH/RUNPATH: yes
- No systemd units calling `/nix/store`: yes
- No glibc loader path: yes
- No unexpected shared runtime libraries: documented exception until split

## Runtime dependencies

The current native systemd stone may carry immediate musl runtime libraries and
helper binaries as one bootstrap-native payload. Later phases should split these
into smaller dependency stones.

## Installed paths

```text
/usr/lib/systemd/systemd
/usr/bin/systemctl
/usr/bin/journalctl
/usr/bin/systemd-tmpfiles
/usr/bin/systemd-sysusers
/usr/bin/udevadm
/usr/share/onix/packages/onix-systemd.md
```

## Stone ownership

The finished `.stone` owns native systemd files directly. It must not point back
to the old bootstrap `/nix/store` payload.

## Exceptions

Temporary bootstrap-native monolithic payload exception. New Rust-first core
packages do not inherit this exception.
