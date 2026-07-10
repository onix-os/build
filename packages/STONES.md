# ONIX stone catalog

This file is the single human-facing catalog of ONIX stones.

It is intentionally separate from generated repository manifests. Generated
manifests tell us what was assembled in one artifact directory. This catalog
records what each stone is supposed to mean in the distro.

## Current stone set

| Stone | Group | Phase | Status | Role |
| --- | --- | ---: | --- | --- |
| `branding` | `base` | 101 | canonical | ONIX identity, `/etc/issue`, MOTD, logo assets |
| `filesystem` | `base` | 102 | canonical | base filesystem labels/defaults and profile templates |
| `busybox` | `core` | 409/506/513 | bootstrap canonical | static musl bootstrap/recovery command set; common coreutils command ownership moved to uutils |
| `dropbear` | `services` | 412 | bootstrap canonical | static musl SSH daemon for early machine access |
| `systemd` | `services` | 422 | canonical | native musl systemd PID 1 and system-management tools |
| `bootstrap-policy` | `services` | 418 | bootstrap canonical | bootstrap service and networking policy |
| `uutils-coreutils` | `core` | 509/513 | first Rust essential | Rust coreutils multicall binary; Phase 513 wires command-name links |
| `musl` | `libs` | 510 | shared-surface canonical | ONIX-owned musl runtime soname provider for dynamic-musl package proofs |
| `linux-pam` | `libs` | 510 | shared-surface canonical | ONIX-owned PAM ABI and module surface for RootAsRole and future login/privilege tools |
| `libseccomp` | `libs` | 510 | shared-surface canonical | ONIX-owned seccomp filtering library for RootAsRole `chsr` and future sandboxing tools |
| `libgcc-runtime` | `libs` | 511 | shared-surface canonical | ONIX-owned `libgcc_s.so.1` runtime needed by the current RootAsRole Rust/musl build |
| `rootasrole` | `core` | 511 | first privilege essential | ONIX sudo-class privilege path; `dosr` is the sudo-equivalent command |
| `rootasrole-policy` | `services` | 512 | bootstrap privilege policy | first RootAsRole factory policy under `/usr/share/factory/etc`; root + `onix` bootstrap actors |
| `moss` | `core` | 515 | first package-manager essential | ONIX-owned Rust/musl package manager installed in the booted system |

## Status vocabulary

- `canonical`: accepted as part of the current ONIX system package plane.
- `bootstrap canonical`: accepted for now, but expected to shrink or be replaced
  as ONIX gets more native packages.
- `first Rust essential`: built as a real `.stone` and audited, but may need a
  later integration phase before it owns every final runtime path.
- `first privilege essential`: built as a real `.stone` and audited as the
  first ONIX privilege-delegation package. Live policy integration may still be
  a later phase.
- `first package-manager essential`: built as a real `.stone` and audited as
  the first ONIX-owned package-manager runtime inside the booted system.
- `shared-surface canonical`: accepted as an ONIX-owned shared-library surface
  for packages that cannot honestly be static-only.
- `selected Rust essential`: selected package direction, with package metadata
  and known dependency path. It may still need a later build/integration step.

## Repository flow

Current package flow:

```text
package contract + recipe
  -> source build in the musl forge
  -> boulder .stone
  -> moss inspect/install proof
  -> canonical/local/public-shaped repo phases
```

The catalog is not generated.

When a new stone is accepted, update this file in the same change as:

- `packages/<group>/<stone>/PACKAGE.md`
- `packages/<group>/<stone>/stone.yaml` or `stone.yaml.in`
- the relevant phase documentation
- the relevant build/proof script
