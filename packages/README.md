# ONIX packages

This directory is the canonical ONIX package workspace.

Phase 5 moves ONIX from phase-local package experiments toward a real
package/repository plane:

```text
source recipe -> .stone -> local repo -> image consumes repo
```

## Package law

ONIX system packages are:

```text
Rust-first, musl-only, and runtime-clean.
```

This means:

- prefer serious Rust implementations whenever they exist;
- build system binaries for musl;
- avoid glibc runtime dependencies;
- avoid shared runtime library dependencies by default;
- prefer static or fully self-contained musl output;
- reject runtime `/nix/store` dependencies;
- install system files through moss from `.stone` packages.

Nix may provide bootstrap build tools such as `rustc`, `cargo`, `gcc`, `make`,
or `pkg-config`.

Nix must not own finished ONIX system packages at runtime.

## Initial layout

```text
packages/
  base/
  core/
  services/
  templates/
```

### `packages/base/`

Base packages define ONIX identity, filesystem layout, defaults, and policy.

Examples:

```text
onix-branding
onix-filesystem
onix-bootstrap-policy
```

### `packages/core/`

Core packages provide command-line system tools.

These should be Rust-first and musl-static by default.

Examples:

```text
uutils-coreutils
sudo-rs
onix-busybox
```

### `packages/services/`

Service packages provide daemons, service units, and service policy.

Examples:

```text
onix-dropbear
onix-systemd
```

## Required files per package

Every canonical package must contain:

```text
PACKAGE.md
stone.yaml
```

`stone.yaml` is the Boulder recipe.

`PACKAGE.md` is the ONIX package contract. It explains why this package exists,
why its implementation was chosen, and how it satisfies the Rust-first,
musl-only, runtime-clean rule.

## Package acceptance questions

Before a package becomes canonical, it must answer:

```text
What system role does this package serve?
Is there a serious Rust implementation?
If yes, are we using it?
If not, why not?
Does every executable target musl?
Is the link model static or otherwise self-contained?
Are there any shared runtime libraries?
Does the payload contain /nix/store references?
Does any shebang point into /nix/store?
Does any RPATH/RUNPATH point into /nix/store?
Does any systemd unit call into /nix/store?
What runtime dependencies are allowed?
```

No unchecked exceptions.

If an exception is needed, document it in `PACKAGE.md` before accepting the
package into the canonical package set.

## Templates

Start new packages from:

```text
packages/templates/PACKAGE.md
packages/templates/stone.yaml
```

Phase 501 creates the contract only.

Later phases will move existing phase-local recipes here.
