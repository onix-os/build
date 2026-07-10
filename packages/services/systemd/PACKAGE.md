# systemd

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
- Link model: dynamic musl service-manager payload
- Shared runtime libraries: `musl` is an explicit dependency stone; some helper
  libraries remain bundled until later split/audit phases

## Runtime-clean contract

- No runtime `/nix/store` dependency: yes for the native Phase 422 package
- No `/nix/store` shebangs: yes
- No `/nix/store` RPATH/RUNPATH: yes
- No systemd units calling `/nix/store`: yes
- No glibc loader path: yes
- No unexpected shared runtime libraries: musl loader/libc belongs to `musl`;
  remaining bundled helper libraries are documented bootstrap debt

## Runtime dependencies

```text
musl
```

The native `systemd` stone must not own:

```text
/usr/lib/ld-musl-x86_64.so.1
/usr/lib/libc.so
/usr/lib/libc.musl-x86_64.so.1
```

Those paths belong to the canonical ONIX `musl` stone. `systemd` may still
carry some immediate non-musl helper libraries and helper binaries as bootstrap
debt until later package split phases.

## Installed paths

```text
/usr/lib/systemd/systemd
/usr/bin/systemctl
/usr/bin/journalctl
/usr/bin/systemd-tmpfiles
/usr/bin/systemd-sysusers
/usr/bin/udevadm
/usr/share/onix/packages/systemd.md
```

## Stone ownership

The finished `.stone` owns native systemd files directly. It must not point back
to the old bootstrap `/nix/store` payload.

## Exceptions

Temporary helper-library/helper-binary bundle exception. The musl runtime itself
is not part of that exception; it is owned by the `musl` stone.
