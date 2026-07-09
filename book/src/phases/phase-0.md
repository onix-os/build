# Phase 0 overview — forge VM and first `.stone`

Phase 0 is not the ONIX operating system yet. It is the **forge**: a temporary
Alpine/musl VM where we build and test the package tooling before trying to
build ONIX itself.

The Phase 0 proof chain is:

```text
Alpine minirootfs
  -> bootable forge VM
  -> moss + boulder
  -> first tiny .stone
  -> real Moss state install/remove/rollback
```

## Why a forge at all?

ONIX is an *atomic, moss-managed distribution built from scratch on musl*. That
sentence hides a chicken-and-egg problem. To ship ONIX you need `.stone`
packages. To build `.stone` packages you need **boulder** (the builder) and
**moss** (the installer/state manager). Both are Rust programs, and they must be
*compiled and run on a musl host* — because everything they produce for ONIX is
musl-linked, and the cleanest way to guarantee that is to build the tooling in
the same libc world it will target.

But ONIX does not exist yet. There is no musl machine to build on. So we borrow
one. **Alpine Linux** is a tiny, mature, musl-based distribution; its 3.7 MB
*minirootfs* tarball is just enough userland to `chroot` into, install a
toolchain with `apk`, and run a Rust compiler. That throwaway Alpine VM is the
**forge**. Its hostname is `quarry` — the place we cut the first stones.

> **Sidebar — musl vs glibc.** A C library (*libc*) is the layer between
> programs and the kernel: it provides `printf`, `malloc`, `open`, threads, DNS
> resolution, and so on. Almost every mainstream Linux distro uses **glibc**
> (the GNU C library) — large, fast, feature-rich, and the default nixpkgs
> targets. **musl** is a smaller, stricter, MIT-licensed alternative used by
> Alpine. ONIX's machine plane is musl top to bottom: smaller, more auditable,
> statically-friendlier. The catch is that most upstream software assumes glibc,
> so a musl base is a genuine from-scratch bootstrap rather than a repackaging
> job — which is exactly why Phase 0 proves the tooling *before* Phase 1 starts
> authoring real recipes.

> **Sidebar — what is a `.stone`?** A `.stone` is moss's package format: a
> single content-addressed archive holding the files a package installs plus
> metadata (name, version, dependencies, the file layout). boulder *produces*
> stones from a recipe (`stone.yaml`); moss *consumes* them. Think `.deb`/`.rpm`,
> but designed around an atomic, deduplicated content store and rollback from
> day one. Everything ONIX ships to the machine plane is a `.stone`.

## Why Phase 0 exists

ONIX wants to be musl-based and Moss-managed. To build `.stone` packages we
need `moss` and `boulder` running on a musl machine. Alpine gives us a small
temporary musl environment. It is scaffolding, not the final distro.

Nothing Alpine ships ends up in ONIX. Not `apk`, not Alpine's kernel, not its
packages. The forge exists only to (a) give us a musl toolchain, and (b) let us
run boulder inside a Linux *user namespace* so its sandboxed builds work. Once
the tooling is proven, the forge is discarded — the phrase to keep in mind is
"scaffolding, thrown away."

## The two planes (why we bother being this careful)

ONIX is built around a hard ownership contract between two halves of the system:

```text
  Nix toolbox   (glibc apps, per-user, you install these)   "Nix controls the toolbox"
  ─────────────────────────────────────────────────────────
  machine plane (musl, atomic /usr, moss-owned, rollbackable) "moss controls the machine"
```

Phase 0 only touches the **machine plane's tooling**. It proves that moss can
install a package into a root, record that as a *state*, and roll back to a
previous state cleanly. That single capability — transactional, reversible
system changes — is the reason ONIX uses moss at all, so it is the very first
thing we prove.

## Steps

- [000 — validate](./000.md)
- [001 — passwordless disk builder](./001.md)
- [002 — build the forge disk](./002.md)
- [003 — boot the forge](./003.md)
- [004 — provision tools](./004.md)
- [005 — first `.stone`](./005.md)
- [006 — real Moss state smoke test](./006.md)

Each step is a `make phase NNN` target and each has a single job. Read them in
order: 000 checks the scripts are sane, 001 arranges passwordless root for the
disk builder, 002 builds the disk, 003 boots it, 004 compiles moss+boulder
inside it, 005 cuts the first stone, and 006 is the real gate — install, remove,
rollback.

Running:

```sh
make phase 0
```

runs the whole Phase 0 family. It runs 000→002 on the host, boots the VM in the
background (batch-safe, so it does not hang at the login prompt), then drives
004→006 over SSH.

## The Phase 0 gate

Phase 0 is complete — and only then does Phase 1 make sense — when:

> moss + boulder run on musl; you can boulder-build a hello-world `.stone`,
> moss-install it, roll the moss state back, and remove it — cleanly.

Everything below builds toward that one sentence.
