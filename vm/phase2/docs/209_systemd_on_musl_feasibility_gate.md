# Phase 209 — systemd-on-musl feasibility gate

## At a glance

| Field | Value |
|---|---|
| Phase family | Phase 2 — bootable image |
| Run command | `make phase 209` |
| Underlying make target/script | `vm/phase2/check-systemd-musl.sh` |
| Runs on | host |
| Main proof/artifact | Confirms pinned nixpkgs can represent a musl-targeted systemd build graph. |


## Background: what this gate is really asking

Before the question makes sense, three ideas need to be on the table.

**PID 1 and the init system.** When the Linux kernel finishes bringing up the
hardware and mounts the real root filesystem, it starts exactly one userspace
program and gives it process ID 1. That process is the *init system*. It is the
ancestor of every other process on the machine; if it dies, the kernel panics.
Its job is to mount the rest of the filesystems, create device nodes, start and
supervise services (networking, logging, SSH), and reap orphaned processes.
ONIX has chosen **systemd** for this role (the decision is formalized in Phase
210). systemd is not just PID 1 — it is a large suite: the PID 1 binary plus
`udev` (device manager), `journald` (logging), `systemctl`, unit files, and more.

**glibc vs musl.** Every normal Linux program is linked against a *C library*
(libc), which provides the functions between the program and the kernel:
`printf`, `malloc`, DNS lookups, threads, and so on. The mainstream choice is
**glibc** (GNU C Library) — large, feature-rich, and what almost all
distributions assume. ONIX instead builds its machine plane on **musl** — a
small, strict, statically-linkable libc favored by Alpine and by people who want
a tiny, auditable base. musl is deliberately *not* bug-for-bug compatible with
glibc: it omits or implements differently several GNU extensions and legacy
interfaces. That is the whole reason this phase exists.

**Why systemd-on-musl is the "scary question."** systemd is developed primarily
against glibc and has historically leaned on glibc-only features. Building it on
musl means someone has to patch around the gaps (for example `utmp`/`wtmp`, the
old login-record files musl does not ship, and the glibc NSS plugin system).
Because ONIX is musl-only on the machine plane but wants systemd as PID 1, the
project has to answer, up front, whether that combination is even *possible*
before pouring effort into building and booting it.

## Why this is a "gate" and not a build

Phase 209 is a **feasibility gate**: a cheap, host-only check that answers a
yes/no question before an expensive commitment. If the answer were "no", ONIX
would have to pivot its entire init story (a different init system, or a glibc
carve-out) — so it is worth confirming plausibility *first*, in seconds, rather
than discovering it after days of build work. A gate proves *"this is worth
attempting"*, not *"this works"*.

Phase 209 checks the scary question directly:

```text
can systemd exist in a musl-only ONIX world?
```

Short answer:

```text
glibc is not a hard requirement
musl is still a risk
```

So we continue with systemd-on-musl. But we also do **not** declare victory yet.

Phase 209 does not build systemd.
It does not install systemd.
It does not mount the image.
It does not boot QEMU.

It only checks whether the upstream and pinned-tooling story is plausible
enough to keep going.

#### What upstream says

The current upstream systemd README lists both libc families in its
requirements:

```text
glibc >= 2.34
musl >= 1.2.6
```

It also says musl is used by building systemd with:

```text
-Dlibc=musl
```

That means systemd-on-musl is an upstream-recognized build mode, not something
we invented.

Source:

```text
https://raw.githubusercontent.com/systemd/systemd/main/README
```

#### Background: nixpkgs, `pkgsMusl`, derivations, and a build graph

ONIX has two planes. The **machine plane** is musl, moss-owned, and atomic. The
**Nix toolbox** is the second plane, and it is where this check lives. Nix is a
package system whose central object is a **derivation**: a pure, hashed recipe
that says "given exactly these inputs, run exactly this build to produce exactly
this output." Because every input is pinned by hash, a derivation is
reproducible — the same recipe yields the same bytes anywhere.

`nixpkgs` is the giant collection of such recipes. Inside it, `pkgs.systemd` is
the ordinary (glibc) systemd derivation, and **`pkgs.pkgsMusl`** is a parallel
universe of the *same* package set re-pointed at the musl C library. So
**`pkgsMusl.systemd`** is nixpkgs's recipe for "systemd, but built against
musl." Its mere existence, and the metadata attached to it, is exactly the
evidence Phase 209 wants.

"Pinned" matters. ONIX records the exact revision of nixpkgs it uses in
`flake.lock`. The check reads that lock file, fetches that one revision, and asks
*it* — not whatever nixpkgs happens to be newest today. That is why the phase can
speak about a specific `systemd-259.3` and a specific `musl 1.2.5`.

A **build graph** is the tree of derivations you would have to build to get a
result: systemd depends on util-linux, which depends on… and so on. Asking Nix to
*plan* that graph (without building it) proves the recipe is coherent — every
input resolves, nothing is missing — which is a strong feasibility signal for a
few seconds of work.

#### What the script actually runs

`vm/phase2/check-systemd-musl.sh` is host-only. It never uses `sudo`, never
mounts the image, never boots QEMU. It does three things:

1. Greps this very page (`vm/phase2/docs/209_systemd_on_musl_feasibility_gate.md`) for the decision text below,
   so the documented contract and the code cannot silently drift apart.
2. Runs `nix eval` on `pkgsMusl.systemd` from the pinned lock to read its
   metadata (`name`, `hostLibc`, `broken`, whether `-Dlibc=musl` is in its Meson
   flags).
3. Runs `nix build --dry-run` to confirm Nix can *plan* the build graph.

If any of those fail, the script exits non-zero and ONIX does not treat
systemd-on-musl as feasible.

#### What our pinned nixpkgs says

Our pinned nixpkgs exposes:

```text
pkgsMusl.systemd
```

The local metadata check currently reports:

```text
name      : systemd-259.3
host libc : musl
broken    : false
flag      : -Dlibc=musl
musl      : musl 1.2.5
```

That means Nix can describe a musl-targeted systemd derivation for our pinned
tooling.

Important nuance: current upstream `main` says `musl >= 1.2.6`, while our
pinned Nix metadata reports `musl 1.2.5` for `systemd-259.3`. That does not
automatically kill the plan because the pinned package is an older systemd
version, but it does mean we must treat this as a feasibility gate, not final
proof.

#### What the pinned source says

The pinned systemd source has a Meson option:

```text
option('libc', type : 'combo', choices : ['glibc', 'musl'])
```

Its Meson logic also has musl-specific handling, and it disables at least one
feature that musl does not support:

```text
utmp
```

That matters because it tells us musl support is not just a string in Nix. The
source tree itself contains a musl path.

#### What the dry-run proves

`make phase 209` also asks Nix to plan:

```text
pkgsMusl.systemd
```

with:

```text
nix build --dry-run
```

Dry-run does not compile anything. It only proves Nix can construct the build
graph.

If dry-run fails, we should not continue with systemd until we understand why.

#### What Phase 209 proves

`make phase 209` proves:

- this Phase 209 section exists
- upstream has a musl build mode
- the pinned Nix package path exists as `pkgsMusl.systemd`
- the pinned package is named `systemd-259.3`
- the pinned package targets musl
- the pinned package is not marked broken
- the pinned package uses `-Dlibc=musl`
- Nix can plan the build graph

This is enough to say:

```text
continue systemd-on-musl
```

#### What Phase 209 does not prove

Phase 209 does not prove:

```text
systemd compiles successfully in our own boulder recipe
systemd links exactly how ONIX wants
systemd starts as PID 1
udev works
networking works
services work
boot reaches login
```

Those are still hard problems.

The current decision is:

```text
continue systemd-on-musl
```

#### How this ties to the big picture

Phase 209 is the first link in the Phase 2 boot chain. It does not touch the
image at all — it only decides whether the *plan* is sane. The next step, Phase
210, freezes this feasibility signal into an explicit, recorded project decision
(systemd as PID 1 + systemd-boot). Only after that do the real image phases
begin placing bytes on disk: kernel and initramfs (211), the first boot probe
(212), the first musl systemd userspace at `/usr/lib/systemd/systemd` (213), and
the first kernel-module payload (214). Every one of those later phases assumes
the answer this gate produced: *systemd-on-musl is worth attempting.*
