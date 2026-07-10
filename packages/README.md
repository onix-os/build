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
- try static or static-PIE musl first by default;
- keep the shared-library surface minimal when static is not the right model;
- allow shared libraries only when they are ONIX-owned stones with documented
  runtime reasons;
- reject runtime `/nix/store` dependencies;
- install system files through moss from `.stone` packages.

Nix may provide bootstrap build tools such as `rustc`, `cargo`, `gcc`, `make`,
or `pkg-config`.

Nix must not own finished ONIX system packages at runtime.

The policy is **not** "shared libraries are forbidden forever." The policy is:

```text
static by default; minimal managed shared surface by exception.
```

Examples that may justify shared libraries:

- PAM modules and PAM consumers;
- systemd's shared/internal libraries and NSS/PAM integration;
- graphics, audio, desktop, and plugin frameworks;
- OpenSSL providers and similar module systems.

Forbidden even in an exception:

- glibc runtime paths on the musl system plane;
- `/nix/store` runtime paths;
- random host `.so` files;
- undocumented `NEEDED` entries.

## Initial layout

```text
packages/
  base/
  core/
  libs/
  services/
  templates/
```

### `packages/base/`

Base packages define ONIX identity, filesystem layout, defaults, and policy.

Examples:

```text
branding
filesystem
```

### `packages/core/`

Core packages provide command-line system tools.

These should be Rust-first and static-first by default. If a core package needs
a shared-library model, the exception must be small, package-owned, and written
in that package's `PACKAGE.md`.

Examples:

```text
uutils-coreutils
rootasrole
busybox
moss
```

### `packages/libs/`

Library packages provide the small shared surfaces that ONIX explicitly chooses
to own.

Examples:

```text
musl
linux-pam
libseccomp
```

This group exists because the static-first rule is not a static-only rule.
Shared libraries are allowed when they are the right model, but every soname must
be intentional, documented, and owned by an ONIX stone.

### `packages/services/`

Service packages provide daemons, service units, and service policy.

Examples:

```text
dropbear
systemd
bootstrap
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
Was static/static-PIE tried first or explicitly ruled out?
Is the link model static, static-PIE, or a documented dynamic-musl exception?
Are there any shared runtime libraries, and which ONIX stone owns each one?
Does the payload contain /nix/store references?
Does any shebang point into /nix/store?
Does any RPATH/RUNPATH point into /nix/store?
Does any systemd unit call into /nix/store?
What runtime dependencies are allowed?
```

No unchecked exceptions.

If an exception is needed, document it in `PACKAGE.md` before accepting the
package into the canonical package set. Shared libraries are allowed only as a
minimal managed surface, never as accidental host leakage.

## Templates

Start new packages from:

```text
packages/templates/PACKAGE.md
packages/templates/stone.yaml
```

Phase 501 creates the contract only.

Phase 503 copies existing phase-local recipes here while keeping the old paths
alive for existing builders.

Phase 504 migrates the existing essential builders so their defaults consume
the canonical copies.

Phase 505 assembles the resulting essential stones into one canonical local
repository under:

```text
artifacts/onix-repo/
```

Phase 506 fixes the first cross-package ownership collision discovered by that
repo proof: `busybox` no longer owns `/usr/bin/reboot` or
`/usr/bin/poweroff`; those command names belong to `systemd`.

Phase 507 makes the current image assembly consume the canonical repo through:

```text
ONIX_IMAGE_REPO_DIR=artifacts/onix-repo/unstable/x86_64
```

That keeps the image path aligned with the repository shape ONIX will later
publish.

Phase 508 reshapes the same canonical repo into a local public-style repository
under:

```text
artifacts/onix-public-repo/
```

That tree contains a Moss root index, stream index, history index, and pooled
stones. It is still local-only, but it matches the shape ONIX can later serve
from:

```text
https://repo.onix-os.com
```

Phases 509–513 add the first Rust essential package contracts, shared surfaces,
RootAsRole package build, integrated factory policy, and the first BusyBox-to-uutils ownership
migration:

```text
packages/core/uutils-coreutils/
packages/core/rootasrole/
packages/core/moss/
packages/core/fish/
packages/libs/musl/
packages/libs/linux-pam/
packages/libs/libseccomp/
```

`uutils-coreutils` is the first built/audited Rust essential stone.
`musl`, `linux-pam`, and `libseccomp` are the first package-owned
shared-library/runtime surface stones. `rootasrole` is then built as the first
ONIX privilege-delegation stone; its build links GCC runtime support from static
archives so ONIX does not need a runtime `libgcc_s.so.1` stone.
The same `rootasrole` stone owns the first RootAsRole factory policy under
`/usr/share/factory/etc`; the image/runtime materializer copies that factory
policy into live `/etc` when needed.
Phase 513 rebuilds `uutils-coreutils` with command-name links and reduces
`busybox` to bootstrap/recovery command ownership for overlapping names.
Phase 515 packages `moss` itself so the booted system has an ONIX-owned
package manager instead of depending only on host-side bootstrap tooling.
Phase 517 packages `fish` as the first interactive shell essential, and Phase
518 makes it the normal user's default login shell while BusyBox remains the
system `/bin/sh` provider.

The human-maintained stone catalog lives at:

```text
packages/STONES.md
```

Update that catalog whenever ONIX accepts a new stone.
