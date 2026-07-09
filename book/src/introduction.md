# Introduction

ONIX is an experiment in building a small, atomic, musl-based Linux
distribution with:

- **Moss** as the package/state manager
- **Boulder** as the `.stone` package builder
- **systemd** as PID 1, if the musl path keeps working
- **systemd-boot** as the bootloader for the real ONIX image
- **Nix** as the development toolbox, not as the target package manager

This book is the canonical learning document for the repository.

The root `README.md` stays short on purpose. The detailed explanations live
here, because each build step now needs room for:

- what the step does
- why it exists
- what files it reads and writes
- what host/guest boundary it crosses
- what it proves
- what it intentionally does **not** prove yet

If you have general Linux literacy but have never heard of moss, boulder,
`.stone`, atomic `/usr`, or the AerynOS tooling world, this page is written for
you. Read it once, top to bottom, and the rest of the book will make sense.

## What "atomic distro" actually means

On an ordinary distribution (Debian, Ubuntu, Arch), installing a package means a
tool like `dpkg` or `pacman` copies individual files into `/usr`, `/etc`, and
elsewhere, one at a time, mutating the live system in place. If the process is
interrupted halfway, or two packages disagree about a file, you can end up in a
half-updated state that is hard to reason about. Over months, the system drifts:
nobody can say exactly which files came from which package, or reproduce the
machine from scratch.

An **atomic** distribution refuses to mutate the running system file by file.
Instead it treats the whole system tree — really the whole of `/usr` — as a
single unit that is swapped in one indivisible ("atomic") operation. Either the
new system is fully in place, or the old one is, never a blend of the two. The
mechanism ONIX uses is a filesystem-level directory swap: the package manager
builds the *next* `/usr` off to the side, then atomically renames it into place
with the Linux `renameat2(..., RENAME_EXCHANGE)` syscall, which swaps two
directories in a single kernel operation that cannot be half-done. Because the
previous `/usr` is kept as a distinct tree, rolling back is just swapping the
old one back — no uninstall, no repair.

This is why ONIX calls `/usr` **stateless** and **transactional**. Stateless:
you never hand-edit files under `/usr`; everything there comes from a package,
so the tree can be thrown away and rebuilt at any time. Transactional: every
change is a numbered transaction (a "state" or `fstx`) you can list, activate,
or roll back, the way a database lets you commit or undo.

## The two-plane ownership contract

ONIX is really *two* systems layered on top of each other, with a hard rule
about who owns what. This split is the single most important idea in the whole
project.

```text
┌──────────────────────────────────────────────┐
│  NIX TOOLBOX PLANE   (you own it)             │
│  /nix, nix-daemon, per-user profiles          │
│  GUI apps, dev shells, the long tail          │
├──────────────────────────────────────────────┤
│  MACHINE PLANE       (moss owns it)           │
│  musl base, atomic /usr, kernel + initrd,     │
│  boot entries, /.moss content store           │
└──────────────────────────────────────────────┘
```

- The **machine plane** is the foundation: the musl C library, the base
  userland, the kernel, the init system, the bootloader entries. It is owned
  entirely by **moss**, it is atomic, and it is the thing you can always roll
  back. Nix is never allowed to write here.
- The **Nix toolbox plane** is everything you actually live in day to day: the
  editors, browsers, language toolchains, and one-off tools. It lives under
  `/nix`, is managed by the Nix package manager, and is owned by *you*, per
  user. moss is never allowed to write here.

The slogan captures it: **moss controls the machine, Nix controls the toolbox.**
The payoff is that a machine rollback and a Nix rollback are independent
operations that cannot corrupt each other. You can roll back a broken system
update without losing your installed dev tools, and garbage-collect your Nix
store without touching the base OS.

Why use Nix for the top plane at all? Because building a from-scratch musl
distribution means every package is real work. ONIX keeps the base **tiny** and
lets Nix supply the enormous "long tail" of software. Nixpkgs is a glibc world,
but Nix applications are self-contained — each carries its own libc and
libraries in the store — so they run fine on top of a musl base. The base does
not have to package thousands of leaf apps; Nix does that.

## The tools: moss, boulder, `.stone`

These three names come from **AerynOS** (formerly Serpent OS), whose *tooling*
ONIX reuses. ONIX borrows the tools and the naming world, but **none of
AerynOS's packages** — its base is glibc; ONIX's is musl.

- A **`.stone`** is AerynOS's package format: a single content-addressed archive
  holding the files a package installs plus its metadata. Think `.deb` or `.rpm`,
  but designed for the atomic, content-store model above.
- **moss** is the atomic package and state manager. It installs `.stone`s into a
  content store (`/.moss`), composes them into a `/usr` tree, and swaps that tree
  atomically. It records every change as a transaction you can list and roll
  back (`moss state list`, `moss state activate`). moss owns the machine plane.
- **boulder** is the `.stone` *builder*. You hand it a recipe — a `stone.yaml`
  file describing how to build a package — and it produces a `.stone`. boulder is
  to moss what a compiler is to a package installer.

Both moss and boulder are ordinary Rust binaries from
`github.com/AerynOS/os-tools`, pinned to a known commit. They are the **one
external dependency** of the whole project.

### musl vs glibc

Every Linux program is linked against a **C library** that provides the standard
functions (`printf`, `malloc`, file I/O, and the dynamic loader that starts
programs). The dominant one is **glibc** — large, fast, feature-rich, and what
almost every mainstream distro ships. **musl** is a smaller, simpler, more
strictly standards-conforming alternative, popular for static linking and small
systems (Alpine Linux is the well-known musl distro).

ONIX's base is musl, deliberately and from scratch. musl makes static linking
clean, keeps the base auditable and small, and is a genuine engineering exercise
— that *is* the project. The cost is that no upstream `.stone` recipe is musl, so
ONIX has to author its own recipes (using Alpine's build scripts as a reference
for the musl-specific patches). The Nix toolbox stays glibc, which is fine
because those apps carry their own libc.

### Nix as the toolbox, not the installer

ONIX uses Nix as a *toolbox provider*, never by running the official Nix
installer. That installer assumes glibc and systemd, mutates `/etc`, and drops
init units imperatively — exactly the in-place drift ONIX exists to avoid.
Instead the machine plane will ship a single integration package that seeds
`/nix`, declares the build users, and wires up the daemon the atomic way. On the
build *host* (the developer's own machine), Nix also provides the toolchain used
to drive this repository — that is the "development toolbox" role in the list at
the top.

## The most important mental model

We are not installing a distro by running one magic installer.

We are building it layer by layer:

```text
temporary forge VM
  -> package tools
  -> first packages
  -> package repo
  -> root tree
  -> disk image
  -> bootloader
  -> kernel/initramfs
  -> init system
  -> booting ONIX machine
```

Read the chain as a dependency order — each layer can only exist once the one
above it works:

- **temporary forge VM** — a throwaway Alpine/musl virtual machine (hostname
  `quarry`) used purely to build the tools and cut the first packages. Nothing
  Alpine ships ends up in ONIX; it is scaffolding, discarded once it has done its
  job. You cannot build `.stone`s without a musl host to build *in*, and this is
  that host.
- **package tools** — moss and boulder, compiled from `os-tools` inside the
  forge. Until these run on musl, there is no way to make or install a single
  ONIX package.
- **first packages** — the earliest `.stone`s: a hello-world proof, then the real
  identity and layout packages. These prove the recipe → `.stone` → install
  pipeline end to end.
- **package repo** — a static, indexed collection of `.stone`s that moss can
  install *from*. ONIX's is the only repo; there is no upstream beneath it.
- **root tree** — a fresh root directory that moss populates by installing base
  packages into it. This is the future `/` of the running system, assembled on
  the host before anything boots.
- **disk image** — that root tree written into a partitioned, bootable disk
  image (an ESP for firmware, a boot partition, an XFS root).
- **bootloader** — systemd-boot plus Boot Loader Spec (BLS) entries, so firmware
  can find and start the system. Each ONIX transaction gets its own boot entry
  (`onix-<txid>.conf`), which is what makes a broken update recoverable from the
  boot menu.
- **kernel/initramfs** — the Linux kernel and the small early-userspace image
  (initramfs) that mounts the real root and hands off to init. (ONIX temporarily
  borrows a virt kernel during early phases; a reserved later phase replaces it
  with an ONIX-owned one.)
- **init system** — systemd as PID 1, the first process the kernel starts, which
  brings up the rest of userspace.
- **booting ONIX machine** — all the layers together: a moss-managed, atomic,
  musl machine that actually boots and that you can prove works.

Every phase is a small proof. When one phase succeeds, the next phase is allowed
to depend on that proof.

## Why phase gates instead of an installer

A normal distro ships an installer: one program that lays everything down at
once. ONIX is built the opposite way, as a sequence of **phases**, each ending
in a **gate** — a concrete test that must pass before the next phase may begin.
Phase 0 proves the tools run on musl and a trivial package installs and rolls
back. Phase 1 proves a self-consistent base set installs into a fresh root.
Phase 2 proves the image boots. Phase 4 proves the base userspace runs after
boot. Phase 5 proves the packages are canonical, Rust-first, and free of
`/nix/store` references. And so on.

The gates, not the code, are the real deliverable. Building bottom-up with a
proof at every layer means that when something breaks, you know exactly which
layer introduced it, because every layer beneath it was already proven. It is
slower than an installer and far more educational — which is the point of the
book you are reading.

## Branding rule

The project name is written as:

```text
ONIX
onix
```

Do not use mixed-case spelling.
