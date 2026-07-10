# 500 — Rust-first musl-only static-first package law

Run:

```sh
make phase 500
```

Phase 500 starts the ONIX package/repository plane.

It is deliberately a policy gate, not a package build.

Before ONIX adds more packages, we need to decide what kind of packages are
allowed into the system.

## Why a policy comes before code

It is tempting to open a phase by building something. Phase 500 does the opposite on
purpose. A package policy written *after* a dozen packages already exist is a policy
you have to retrofit and argue with; a package policy written *before* the package
universe grows is a filter every future package passes through cleanly. Phase 500 is
the cheapest step in Phase 5 to get right and the most expensive to get wrong later,
so it goes first and it builds nothing.

`make phase 500` prints the law and checks that the Phase 5 documentation exists. Its
entire job is to make the rule *visible and repeatable* before any package leans on
it.

## The law

ONIX system packages are:

```text
Rust-first, musl-only, and runtime-clean.
```

This is the foundation for Phase 5.

## Why we need a hard package law

Without a hard policy, a young distro can accidentally become a pile of copied
host artifacts.

That would be bad for ONIX.

ONIX should not become:

```text
random binaries copied from Nix
random glibc programs
random shell scripts with /nix/store shebangs
random systemd units pointing at host paths
```

Phase 5 exists to turn packages into a real ONIX-owned system.

That means every system package must be understandable, repeatable, and audited.

Remember the ONIX constitution from the architecture: *moss controls the machine, Nix
controls the toolbox.* A system binary that reaches into `/nix/store` at runtime
quietly violates that contract — it lets the Nix plane own a piece of the machine
plane. The package law is how that constitutional rule becomes something you can
check on a single `.stone`.

## Rust-first

Rust-first means:

```text
If a serious Rust implementation exists, prefer it.
```

Examples:

```text
coreutils -> uutils coreutils
sudo-class privilege -> RootAsRole, with dosr as the native command
ONIX-specific tools -> Rust by default
repository tooling -> Rust when practical
```

Rust-first is crucial for ONIX identity.

It gives ONIX:

- memory-safety bias,
- modern tooling,
- easier ONIX-specific tool development,
- a clear package selection philosophy.

There is also a lineage argument. ONIX's own tools — moss and boulder — are Rust
binaries from AerynOS. A distribution whose package manager is Rust and whose base
utilities keep drifting back to decades-old C has an identity split. Rust-first keeps
the philosophy consistent from the package manager down to `ls`.

## Rust-first is not Rust-blind

Some things are not realistic Rust replacements today.

Examples:

```text
Linux kernel
musl libc
systemd
boot firmware
some low-level filesystem tools
```

If ONIX uses non-Rust software, the package metadata should explain why.

The question should always be:

```text
Is there a serious Rust alternative?
If yes, why are we not using it?
```

The word doing the work is **serious**. "A Rust crate exists on crates.io" is not the
bar; "a production-quality implementation that can carry this system role today" is.
systemd as PID 1 has no serious Rust replacement, so `onix-systemd` stays C — but its
`PACKAGE.md` says so out loud, which is what keeps the exception honest rather than
lazy.

## Musl-only

ONIX is a musl system.

System packages must not accidentally bring in glibc.

Bad:

```text
/lib64/ld-linux-x86-64.so.2
glibc
```

Good:

```text
/lib/ld-musl-x86_64.so.1
static
static-pie
```

For system packages, ONIX tries static or static-PIE musl first by default. If
that is not the right model, the package may use a minimal shared-library surface
only when every shared object is intentional, documented, and owned by an ONIX
stone.

### Background: what these paths actually are

`/lib64/ld-linux-x86-64.so.2` and `/lib/ld-musl-x86_64.so.1` are **dynamic loaders**
— the small program the kernel runs first to wire up a dynamically linked
executable's shared libraries. The first belongs to **glibc** (the GNU C library);
the second belongs to **musl** (the small, correctness-focused C library ONIX is
built on). They are not interchangeable: glibc and musl differ in ABI, in behavior at
the edges, and in which extensions they provide.

A binary that names the glibc loader is a glibc binary, full stop — even if it
otherwise "works" on the box, it drags glibc semantics into a musl system and becomes
a latent surprise. **static** and **static-pie** binaries name *no* loader because
they carry their C library inside themselves; that is why ONIX prefers them for the
base. `static-pie` is simply a static binary that is also position-independent (it
can be loaded at a randomized address), giving you the isolation of static linking
without giving up address-space layout randomization.

The point is not to pretend shared libraries never make sense. PAM, libseccomp,
systemd internals, graphics stacks, audio stacks, and plugin systems are real
shared-library worlds. The ONIX rule is stricter and more useful:

```text
try static first
use shared libraries only for the smallest package-owned surface that makes sense
never accept glibc, /nix/store, or random host .so leakage
```

## Runtime-clean

Runtime-clean means the installed package does not need the build environment.

Most importantly:

```text
No runtime /nix/store dependency.
```

Bad:

```text
/usr/bin/foo -> /nix/store/.../bin/foo
```

Bad:

```text
#!/nix/store/.../bin/bash
```

Bad:

```text
RUNPATH=/nix/store/...
```

Bad:

```text
ExecStart=/nix/store/.../bin/foo
```

Good:

```text
/usr/bin/foo
/usr/lib/libfoo.so
/usr/share/foo/...
```

owned by a `.stone` package and installed by moss.

Notice the four *shapes* a `/nix/store` leak can take, because the audit in step 502
hunts each one separately: a **symlink** into the store, a **shebang** into the store
at the top of a script, an **RPATH/RUNPATH** baked into an ELF header, and a systemd
unit **ExecStart** pointing into the store. All four mean the same disease — the
installed file cannot function without the build host's `/nix/store` present — but
they hide in different places, so they need four different checks.

## Nix is allowed as a bootstrap builder

This is the subtle but important part.

Phase 5 does not ban Nix from the build side.

During bootstrap, Nix may provide:

```text
rustc
cargo
gcc
make
pkg-config
cmake
```

Those are build tools.

Using them is acceptable if the final `.stone` payload is runtime-clean.

The rule is:

```text
Nix may build the package.
Nix must not own the installed system package.
```

So this is acceptable:

```text
Nix rustc -> build uutils -> install into payload/usr/bin/coreutils -> boulder cuts .stone -> moss installs .stone
```

This is not acceptable:

```text
payload/usr/bin/sudo -> /nix/store/.../bin/sudo
```

This is the pragmatic heart of the law. ONIX is bootstrapping on musl from almost
nothing; forbidding Nix on the *build* side would mean hand-rolling a full toolchain
before shipping a single package. The compromise is a clean boundary: Nix is welcome
in the kitchen, but nothing from `/nix/store` may follow the food out to the table.
The audit exists to check the plate, not the kitchen.

## Checks every system stone should pass

A Phase 5 package audit should check the payload before accepting a `.stone`.

Text scan:

```sh
grep -R /nix/store payload/
```

Interpreter scan:

```sh
find payload -type f -perm -111 -exec file {} \;
```

ELF interpreter scan:

```sh
readelf -l payload/usr/bin/foo
```

Dynamic dependency scan:

```sh
readelf -d payload/usr/bin/foo
```

Bad signs:

```text
/nix/store
/lib64/ld-linux-x86-64.so.2
RPATH
RUNPATH
glibc
```

Potentially good signs:

```text
statically linked
static-pie
/lib/ld-musl-x86_64.so.1
no dynamic section
```

### How to read these commands

- `grep -R /nix/store payload/` walks the whole payload as text and bytes, catching
  store paths hiding in scripts, config, and even inside binaries.
- `file` on each executable tells you at a glance whether it is `ELF ... statically
  linked` (good) or `dynamically linked` (needs the loader check).
- `readelf -l` prints program headers; the line `Requesting program interpreter:`
  reveals the loader path — the single most important line for the musl-only rule.
- `readelf -d` prints the dynamic section: `NEEDED` entries are shared-library
  dependencies, and `RPATH`/`RUNPATH` entries are the search paths the loader will
  use — where a stray `/nix/store` would betray the build environment.

Step 502 wraps exactly these four checks into a single script,
`vm/phase5/audit-stone-payload.sh`, so nobody has to remember to run them by hand.

## What Phase 500 does

`make phase 500` prints the policy and validates that Phase 5 documentation is
present.

It does not build packages yet.

The point is to make the policy visible before adding more packages.

## What comes next

Phase 501 should define the canonical package recipe layout.

For example:

```text
packages/core/uutils-coreutils/
packages/core/rootasrole/
packages/base/onix-busybox/
packages/base/onix-dropbear/
packages/base/onix-systemd/
```

The exact directory names can change, but the metadata contract should be strict.

Each package should document:

```text
Implementation language:
Rust alternative considered:
Why this implementation:
Musl target:
Static attempt/result:
Runtime-clean check:
Runtime dependencies:
Allowed shared-library surface, if any:
```

That gives ONIX a real package policy instead of a pile of scripts.

## Success output

Successful output looks like:

```text
Phase 5 starts the ONIX package/repository plane.

Hard policy for ONIX system packages:
  - Rust-first: prefer serious Rust implementations whenever they exist.
  - musl-only: no glibc runtime in system packages.
  - runtime-clean: no /nix/store runtime dependency.
  - static-first: try static/static-PIE musl first by default.
  - minimal shared surface: allow shared libraries only when package-owned,
    documented, and genuinely needed.
```

After this, we can begin real Phase 5 package work.
