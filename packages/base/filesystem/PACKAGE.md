# filesystem

## Summary

ONIX filesystem layout policy and default `/etc` templates.

## System role

- Group: `base`
- Installed plane: machine/system policy
- Why ONIX needs it: documents the filesystem ownership model and ships
  package-owned defaults that image assembly or boot materialization can copy
  into live `/etc`.

## Implementation choice

- Implementation language: data package with POSIX shell install commands
- Rust alternative considered: not applicable
- Serious Rust implementation exists: not applicable
- Selected implementation: Boulder data-package recipe
- Why this implementation: this package ships policy text and default
  configuration templates. There is no useful Rust implementation to prefer.

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
/usr/share/onix/filesystem-layout.md
/usr/share/defaults/etc/fstab
/usr/share/defaults/etc/profile
/usr/share/defaults/etc/profile.d/onix-path.sh
/usr/share/defaults/etc/profile.d/onix-login.sh
```

## Stone ownership

The finished `.stone` owns defaults under `/usr/share/defaults`. Live `/etc`
remains materialized machine state.

Runtime compatibility expected from image/materialization code:

```text
/var/run -> ../run
```

That link keeps old `/var/run/...` runtime-state paths on writable `/run` tmpfs
instead of the read-only root filesystem.

## Exceptions

None.
