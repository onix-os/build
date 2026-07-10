# rootasrole

## Summary

RootAsRole is ONIX's selected sudo-class privilege delegation package.

The installed user-facing command is expected to be `dosr`. In ONIX language,
`dosr` is the sudo-equivalent command: it is the tool a user reaches for when a
task needs controlled privilege escalation. If ONIX later provides a
`/usr/bin/sudo` compatibility command, that compatibility layer must point at
the RootAsRole policy model. It must not introduce a second canonical privilege
path.

Phase 509 records the package decision. Phase 510 creates the required
ONIX-owned PAM and libseccomp stones. Phase 511 builds the actual
`rootasrole` stone against that owned surface and records the extra
toolchain-runtime surface the current Rust/musl build needs.

## System role

- Group: `core`
- Installed plane: machine/system
- Why ONIX needs it: ONIX needs a controlled way to run privileged commands
  without treating "full root for everything" as the default mental model.
  RootAsRole is a better fit than a sudo clone because its native model is roles,
  tasks, and Linux capabilities.

## Implementation choice

- Implementation language: Rust
- Rust alternative considered: direct sudo-compatible implementations
- Serious Rust implementation exists: `yes`
- Selected implementation: RootAsRole
- Why this implementation: RootAsRole is Rust-first and models privilege
  delegation through RBAC roles/tasks and capabilities. That fits ONIX's design
  goal better than a direct sudoers-compatible reimplementation.

ONIX should prefer RootAsRole's policy model and only add a `sudo`
compatibility command if users really need the familiar command name.

## Source and provenance

- Upstream: `https://github.com/LeChatP/RootAsRole`
- Source archive or repository: release tag or pinned commit from upstream
- Pinned version: `4.0.0` was investigated during the Phase 509 policy update
- Source hash: pending final packaging recipe
- Patch set: none yet

## Build model

- Build environment: ONIX forge VM
- Build tools: Rust toolchain, Cargo, C toolchain, Boulder
- Target triple: musl target used by the forge
- C runtime: `musl`
- Link model: `dynamic musl exception` expected for initial packaging
- Shared runtime libraries: documented minimal managed surface

RootAsRole was first tried under the earlier static-only rule. That probe
showed:

- `dosr` builds dynamically but links `libpam.so.0` and `libgcc_s.so.1`;
- static `dosr` fails without `libpam.a`;
- `chsr` builds dynamically but links `libseccomp.so.2` and `libgcc_s.so.1`;
- static `chsr` fails without `libseccomp.a`.

ONIX now allows a small, explicit, package-owned shared-library surface where
the upstream design needs it. For RootAsRole this means:

```text
dosr -> linux-pam stone
chsr -> libseccomp stone
```

The exception is not permission to use arbitrary host libraries. Every shared
object must be built and owned by an ONIX `.stone`.

## Runtime-clean contract

- No runtime `/nix/store` dependency: required
- No `/nix/store` shebangs: required
- No `/nix/store` RPATH/RUNPATH: required
- No systemd units calling `/nix/store`: not applicable unless service units are
  added later
- No glibc loader path: required
- No unexpected shared runtime libraries: required

Expected allowed shared libraries for the first accepted RootAsRole package:

```text
libpam.so.0       owner: linux-pam
libseccomp.so.2   owner: libseccomp
libgcc_s.so.1     owner: libgcc-runtime
libc.musl-*.so.1  owner: musl
```

Anything outside that list is a failed audit until documented and package-owned.

## Runtime dependencies

Initial expected dependencies:

```text
- linux-pam:
  reason: RootAsRole dosr uses PAM authentication/session handling.
  owner package: linux-pam

- libseccomp:
  reason: RootAsRole chsr uses seccomp for policy-editor hardening.
  owner package: libseccomp

- musl:
  reason: dynamic musl interpreter and libc.
  owner package: musl

- libgcc-runtime:
  reason: the current Alpine/musl Rust toolchain emits a `libgcc_s.so.1`
  runtime dependency for the RootAsRole build.
  owner package: libgcc-runtime
```

Metadata note: dynamic musl binaries name `/lib/ld-musl-x86_64.so.1` as their
ELF interpreter. ONIX images are usr-merged, and the `musl` stone owns the real
loader at `/usr/lib/ld-musl-x86_64.so.1`. The `rootasrole` recipe therefore
excludes only the exact synthetic interpreter dependency while retaining the
`libc.musl-x86_64.so.1` soname dependency that pulls in the `musl` stone.

## Installed paths

Expected installed files once accepted:

```text
/usr/bin/dosr
/usr/bin/chsr
/usr/share/defaults/rootasrole/
/usr/share/defaults/pam.d/dosr
/usr/share/onix/packages/rootasrole.md
```

ONIX may later add:

```text
/usr/bin/sudo
```

as a compatibility wrapper or alias to the RootAsRole model. That must be a
deliberate compatibility decision, not a second privilege implementation.

## Stone ownership

The finished `.stone` must own installed system files directly.

Bad:

```text
/usr/bin/dosr -> /nix/store/.../bin/dosr
```

Good:

```text
/usr/bin/dosr
```

## Exceptions

RootAsRole is allowed to be a dynamic-musl package only after ONIX has accepted
the minimal shared-library surface it needs. That surface must stay small,
package-owned, and auditable.

No glibc and no `/nix/store` runtime paths are allowed.
