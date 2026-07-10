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

## Where Phase 5 sits in the ONIX story

Every earlier phase was about *making one machine work*. The forge built moss and
boulder (Phase 0). The base stones were authored and installed (Phase 1). An image
booted (Phase 2). The Nix plane and native systemd matured (Phases 3–4). By the end
of Phase 4 there was a real, bootable, SSH-reachable ONIX machine.

But "a machine that boots" and "a distribution" are not the same thing. A
distribution is the *supply chain* behind the machine: a place recipes live, a way
to build them into packages, a way to verify those packages are honest, and a
repository the machine can install from by name. Phase 5 is where ONIX grows that
supply chain.

Two vocabulary anchors used throughout Phase 5:

- **`.stone`** — ONIX's package file format (from AerynOS tooling). A `.stone` is a
  compressed, content-addressed archive of a *payload* (the files a package installs,
  like `/usr/bin/busybox`) plus metadata (name, version, the paths it owns). It is
  the unit moss installs and removes atomically.
- **moss / boulder** — the two Rust tools ONIX borrows. **boulder** *builds* a
  `.stone` from a recipe. **moss** *installs* `.stone` files, tracks system state,
  and can roll transactions back. Phase 5 leans on both: boulder to cut packages,
  moss to `index`, `inspect`, and `install` them from a repository.

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

### Why a *law*, and why now

A young distribution is most vulnerable to one failure: quietly becoming a pile of
copied host artifacts. The forge had glibc tools around. The build host has Nix,
which is glibc-based, all over `/nix/store`. Without a written, *enforced* rule, it
is disturbingly easy to `cp` a working binary out of `/nix/store` into a payload,
watch it run once, and ship it — carrying an invisible `/nix/store` runtime
dependency and a glibc loader into a system that is supposed to be pure musl.

That would break the two central ONIX promises at once: the machine plane is meant
to be **musl-only** (so there are no accidental glibc/ABI surprises), and it is meant
to be **self-owned** (moss controls the machine; Nix controls only the toolbox). A
system binary that reaches into `/nix/store` at runtime hands machine ownership to
Nix. Phase 5 exists so that can never happen by accident — the law turns a vibe into
a checkable contract, and steps 502–508 turn the contract into scripts that fail
loudly.

## Rust-first does not mean Rust-blind

Rust-first means ONIX should choose Rust when a serious Rust implementation
exists.

Examples:

```text
coreutils -> prefer uutils coreutils
sudo-class privilege -> prefer RootAsRole, with dosr as the native command
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

The mechanism for "explain why" is the **`PACKAGE.md` contract** (defined in step
501). Rust-first stays honest only because every non-Rust choice has to be written
down and justified in a reviewable file, not silently accepted.

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
try static/static-PIE musl first by default
allow only a minimal ONIX-owned shared-library surface when static is not right
```

### Background: static vs dynamic, musl vs glibc

Every compiled Linux program is *linked* one of two ways. A **dynamically linked**
binary defers to shared libraries at run time: the kernel first loads a small
program called the **dynamic loader** (the "ELF interpreter") named in the binary's
header, and that loader finds and maps the shared libraries. A **statically linked**
binary bakes everything it needs into the file, so there is no loader path to follow
and no external library to miss.

The loader path is the tell-tale. A glibc binary asks for
`/lib64/ld-linux-x86-64.so.2`; a musl binary asks for `/lib/ld-musl-x86_64.so.1`; a
fully static binary asks for nothing. ONIX prefers **static or static-pie musl** for
system packages precisely because it removes the whole class of "which libc, which
version, whose `/nix/store`" questions — a static musl binary carries its own answer.
That is why the audit helper in step 502 reads exactly these headers.

This is a default, not a religion. Some real system pieces are designed around
shared objects: PAM, seccomp-using helpers, systemd internals, graphics stacks,
audio stacks, and plugin frameworks. ONIX allows those only as a **minimal managed
shared surface**: the package must try or justify the static build first, list every
needed soname, and make sure every shared object is owned by an ONIX stone. The
forbidden case is not "shared library exists"; the forbidden case is "random host
library leaked into the machine."

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
Nix cargo helps build uutils-coreutils
uutils-coreutils is installed into a .stone payload
moss installs that .stone into /usr/bin/coreutils
the installed binary has no /nix/store runtime dependency
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

The line to hold: **the build environment is disposable; the payload is forever.**
A compiler that lived in `/nix/store` during the build is fine, because it does not
follow the binary onto the installed system. A *reference* to `/nix/store` embedded
inside the shipped binary — a loader path, an RPATH, a shebang, a systemd
`ExecStart` — does follow it, and that is what the audit rejects.

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

"Make it boring locally first" is the recurring Phase 5 method. Every network,
signing, DNS, and CDN question is deliberately deferred; the same *directory shape*
that a web server will one day serve is first proven with `file://` URLs on the
build host. If the shape works over `file://`, uploading it later is a transport
detail, not a redesign.

The first package set should be small and essential:

```text
onix-branding
onix-filesystem
onix-busybox
onix-dropbear
onix-systemd
onix-bootstrap-policy
uutils-coreutils
rootasrole
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
Static attempt/result:
Allowed shared-library surface, if any:
```

This makes Rust-first enforceable instead of vague.

It also prevents a quiet slide back into random C packages when a Rust package
would be a better ONIX fit.

## Proposed Phase 5 path

```text
500 — Phase 5 package/repo direction and Rust-first musl-only static-first law
501 — canonical recipe layout and package metadata contract
502 — runtime-clean stone audit helper
503 — copy existing package recipes into canonical layout
504 — build essential package set from canonical recipes
505 — assemble local ONIX repo from canonical packages
506 — fix essential package ownership collisions
507 — make the image consume only the canonical local repo
508 — local public repository layout without upload
509 — build/audit first Rust essential stones
510 — build/audit PAM + seccomp shared-library surface stones
511 — build RootAsRole against the owned shared surface
512 — materialize live RootAsRole policy as an owned stone
513 — move coreutils command links from BusyBox to uutils
```

The exact list can change as we learn.

The boundary should not change:

```text
Phase 5 owns packages and repositories.
Phase 5 does not own kernel work, desktop work, or general user toolboxes.
```

### How the steps build on each other

The current steps are not independent chores; they are one pipeline assembled left to
right, each step relying on the guarantees the previous one established:

```text
500  law                 -> what a package is allowed to be
501  layout + contract    -> where packages live, what they must document
502  audit helper         -> a script that enforces part of the law
503  copy recipes         -> real recipes moved into the canonical tree
504  canonical build lane -> builders read from the canonical tree
505  local repo           -> built stones collected into one moss repo
506  ownership fix        -> BusyBox/systemd reboot/poweroff collision fixed
507  image consumes repo  -> the bootable image installs from that one repo
508  public-shaped repo   -> the same content in a publishable tree layout
509  Rust essentials      -> first Rust core package plus RootAsRole gate
510  shared surface       -> PAM/seccomp become ONIX-owned stones
511  RootAsRole package   -> dosr/chsr become ONIX-owned stones
512  RootAsRole policy    -> live /etc policy becomes package-owned
513  uutils wiring        -> common coreutils commands point at uutils
```

Read top to bottom, the arrow from "a rule on paper" (500) to "an image that boots
from a publish-shaped repository and accepts its first Rust/shared-surface packages" (507–513)
is the current Phase 5 deliverable.

## Steps

- [500 — Rust-first musl-only static-first package law](./500.md)
- [501 — canonical package layout and metadata contract](./501.md)
- [502 — runtime-clean stone payload audit helper](./502.md)
- [503 — copy existing recipes into canonical package layout](./503.md)
- [504 — canonical essential package build lane](./504.md)
- [505 — canonical local ONIX package repo](./505.md)
- [506 — essential package ownership collision fix](./506.md)
- [507 — make the image consume the canonical local repo](./507.md)
- [508 — local public repository layout](./508.md)
- [509 — first Rust essential stones](./509.md)
- [510 — privilege shared-library surface](./510.md)
- [511 — RootAsRole privilege stone](./511.md)
- [512 — live RootAsRole policy stone](./512.md)
- [513 — uutils command ownership](./513.md)
