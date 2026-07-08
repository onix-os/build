# Phase 5 overview — Rust-first musl package/repository plane

Phase 5 starts after the Phase 4 booted-base acceptance gate.

Phase 4 proved:

```text
ONIX can boot, run native systemd as PID 1, accept SSH login, and use
stone-owned base packages for the current machine plane.
```

Phase 5 asks a different question:

```text
Can ONIX build, collect, verify, and publish its own system packages?
```

This is the package/repository plane.

## The important Phase 5 law

ONIX system packages are:

```text
Rust-first, musl-only, and runtime-clean.
```

That sentence is intentionally strict.

It means:

- if a serious Rust implementation exists, prefer it;
- system binaries target musl, not glibc;
- installed system packages must not need `/nix/store` at runtime;
- installed system files come from `.stone` packages consumed by moss;
- Nix may help us build during bootstrap, but Nix must not become the runtime
  owner of the system.

## Rust-first does not mean Rust-blind

Rust-first means ONIX should choose Rust when a serious Rust implementation
exists.

Examples:

```text
coreutils -> prefer uutils coreutils
sudo      -> prefer sudo-rs
ONIX tools -> Rust by default
repo tooling -> Rust by default where practical
```

But Rust-first does not mean pretending that everything has a mature Rust
replacement today.

Some system pieces may remain non-Rust for now:

- the Linux kernel,
- musl libc,
- systemd,
- low-level boot components,
- temporary bootstrap components while we cross gaps.

When ONIX chooses a non-Rust implementation, the package should explain why.

## Musl-only system packages

ONIX is a musl system.

That means Phase 5 must reject accidental glibc dependencies.

Bad signs include:

```text
/lib64/ld-linux-x86-64.so.2
glibc
RPATH into /nix/store
RUNPATH into /nix/store
```

Good signs include:

```text
musl
static
static-pie
/lib/ld-musl-x86_64.so.1
no /nix/store
```

The exact acceptable linker model may differ by package, but the policy is
stable:

```text
no glibc runtime in ONIX system packages
```

## Build dependency versus runtime dependency

Phase 5 allows a very important distinction:

```text
build dependency != runtime dependency
```

During bootstrap, Nix may provide tools such as:

```text
rustc
cargo
gcc
make
pkg-config
cmake
```

That is acceptable if the final `.stone` payload is clean.

For example:

```text
Nix cargo builds sudo-rs
sudo-rs is installed into a .stone payload
moss installs that .stone into /usr/bin
the installed sudo-rs binary has no /nix/store runtime dependency
```

That is acceptable.

This would not be acceptable:

```text
/usr/bin/sudo -> /nix/store/.../bin/sudo
```

or:

```text
/usr/bin/sudo has RPATH=/nix/store/...
```

The package was built with Nix in both cases, but only the first model produces
an ONIX-owned system package.

## What Phase 5 should build first

Phase 5 should not start with public hosting.

It should start locally:

```text
source recipe -> .stone -> local repo -> image consumes repo
```

Only after that is boring and repeatable should ONIX publish the same layout to:

```text
repo.onix-os.com
```

The first package set should be small and essential:

```text
onix-branding
onix-filesystem
onix-busybox
onix-dropbear
onix-systemd
onix-bootstrap-policy
uutils-coreutils
sudo-rs
```

The first six already exist in earlier phase/lab form. Phase 5 will turn the
package/repo flow into a canonical ONIX workflow.

## Package metadata should explain implementation choice

Every new system package should answer:

```text
Implementation language:
Rust alternative considered:
Why this implementation:
Musl/runtime-clean status:
Runtime dependencies:
```

This makes Rust-first enforceable instead of vague.

It also prevents a quiet slide back into random C packages when a Rust package
would be a better ONIX fit.

## Proposed Phase 5 path

```text
500 — Phase 5 package/repo direction and Rust-first musl-only law
501 — canonical recipe layout and package metadata contract
502 — runtime-clean stone audit helper
503 — move existing Phase 4 package recipes into canonical layout
504 — build essential package set from canonical recipes
505 — assemble local ONIX repo from canonical packages
506 — make the image consume only the canonical local repo
507 — repo publishing contract for repo.onix-os.com
508 — dry-run repo publication layout without upload
```

The exact list can change as we learn.

The boundary should not change:

```text
Phase 5 owns packages and repositories.
Phase 5 does not own kernel work, desktop work, or general user toolboxes.
```

## Steps

- [500 — Rust-first musl-only package law](./500.md)
- [501 — canonical package layout and metadata contract](./501.md)
