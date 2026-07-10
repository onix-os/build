# fish

## Summary

fish is the ONIX default interactive shell for the normal user.

## System role

- Group: `core`
- Installed plane: machine/system
- Why ONIX needs it: ONIX needs a friendly interactive shell while keeping a
  small BusyBox `sh` for scripts and recovery.

## Implementation choice

- Implementation language: Rust
- Rust alternative considered: fish itself, version 4.x, is Rust-based
- Serious Rust implementation exists: `yes`
- Selected implementation: fish shell
- Why this implementation: fish is a mature interactive shell with a real Rust
  implementation, good defaults, ONIX-branded interactive startup hooks, and a
  clear separation from POSIX `/bin/sh`.

ONIX keeps BusyBox as the system `/bin/sh` provider. fish is not used as
`/bin/sh` because fish is intentionally not POSIX-shell compatible.

## Source and provenance

- Upstream: <https://github.com/fish-shell/fish-shell>
- Source archive or repository: pinned `nixpkgs_2#fish.src`
- Pinned version: filled by the Phase 517 build script
- Source hash: filled by the Phase 517 build script
- Patch set: none

## Build model

- Build environment: Alpine/musl forge VM
- Build tools: Cargo, rustc, C compiler, pkg-config, static PCRE2 development
  files
- Target triple: forge-native `x86_64-unknown-linux-musl`
- C runtime: `musl`
- Link model: `static musl` when the static PCRE2 build succeeds
- Static attempt/result: Phase 517 builds with
  per-binary `cargo rustc ... -- -C target-feature=+crt-static` commands and
  `PCRE2_SYS_STATIC=1`
- Shared runtime libraries: `none` expected; if this changes, it must become a
  documented minimal ONIX-owned shared-surface exception before acceptance

## Runtime-clean contract

- No runtime `/nix/store` dependency: `yes`
- No `/nix/store` shebangs: `yes`
- No `/nix/store` RPATH/RUNPATH: `yes`
- No systemd units calling `/nix/store`: `not applicable`
- No glibc loader path: `yes`
- No unexpected shared runtime libraries: `yes`
- All expected shared libraries are ONIX-owned: `not applicable` for static

Required checks before accepting the package:

```sh
vm/phase5/audit-stone-payload.sh payload/
readelf -l payload/usr/bin/fish
readelf -d payload/usr/bin/fish
payload/usr/bin/fish --version
```

## Runtime dependencies

Allowed runtime dependencies:

```text
- dependency: BusyBox sh
  reason: fish startup and user commands may call POSIX shell utilities; ONIX
          also keeps BusyBox sh as the system scripting contract.
  owner package: busybox

- dependency: uutils/coreutils command set
  reason: fish users expect normal command-line utilities.
  owner package: uutils-coreutils
```

## Installed paths

Important installed files:

```text
/usr/bin/fish
/usr/bin/fish_indent
/usr/bin/fish_key_reader
/usr/share/fish/
/usr/share/onix/defaults/etc/fish/conf.d/branding.fish
/usr/share/onix/packages/fish.md
/usr/share/onix/shells/fish-policy.txt
```

`/usr/share/onix/defaults/etc/fish/conf.d/branding.fish` is the packaged ONIX
fish login banner default. Phase 518 materializes it into
`/etc/fish/conf.d/branding.fish`, which is the path fish actually sources at
startup. It uses `/usr/share/onix/branding/logo.ansi` when the `branding` stone
is installed, and falls back to a tiny colored `ONIX` wordmark otherwise.

## Stone ownership

The finished `.stone` owns fish directly:

```text
/usr/bin/fish
/usr/share/onix/defaults/etc/fish/conf.d/branding.fish
```

It must never install:

```text
/usr/bin/fish -> /nix/store/.../bin/fish
```

## Exceptions

No unchecked exceptions.

If fish later cannot remain fully static because of a real upstream/runtime
constraint, the package must be updated to document each shared object and the
ONIX stone that owns it before the exception is accepted.
