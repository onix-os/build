# Phase 408 — local stone/repo contract

| Item | Value |
|---|---|
| Command | `make phase 408` |
| Underlying make target/script | `vm/phase4/local-stone-contract.sh` |
| Mutates disk/image? | No |
| Boots QEMU? | No |
| Main proof | Phase 4 has a local-only `.stone` and moss-repo layout before we start replacing Nix-sourced bootstrap payloads. |

## Why this phase exists

Phase 407 made the architecture honest:

```text
Nix-sourced system payloads are bootstrap-only.
Final system packages must become .stone packages.
```

The next temptation is to jump straight to a public server:

```text
repo.onix-os.com
```

That will be useful later, but it is too early for the current problem.

Right now we need a smaller loop:

```text
build a local .stone
put it in a local moss repo
install it into the ONIX image
boot and prove the image still works
```

That is what Phase 408 defines.

### Background: stones, moss, boulder, and repos

Four terms carry the whole Phase 4 "own it" story, so it is worth pinning them
down before the loop above makes sense.

- **`.stone`** is ONIX's package format (inherited from AerynOS's tooling). A
  `.stone` is a single content-addressed file bundling a package's files plus
  metadata — its name, version, and the layout of what it installs. It is the unit
  that gets built, verified, shipped, and installed.
- **boulder** is the *builder*: it takes a recipe (`stone.yaml`) describing how to
  build and lay out a package and produces a `.stone`. It is the tool that *cuts*
  stones.
- **moss** is the *package/state manager*: it consumes `.stone` files, installs
  them atomically into a root, and records each change as a transaction you can
  roll back. moss is what *installs* stones and owns the machine's state history.
- A **repo** (repository) is just a directory of `.stone` files plus an **index**
  — a small `stone.index` catalogue listing what is available and where. moss adds
  a repo by URL, reads its index, and pulls packages from it.

Both moss and boulder are Rust binaries from AerynOS's `os-tools`, pinned as
ONIX's one external dependency. The loop Phase 408 sets up is therefore: boulder
cuts a `.stone`, it lands in a local repo directory, `moss index` writes the
`stone.index`, and moss installs from that index into the image.

### Why "local" and a `file://` repo first

A moss repo is reached by URL, and the simplest possible URL is a local path:
`file:///…/stone.index`. No web server, no TLS, no signing — just a directory on
disk. Starting there lets Phase 4 exercise the *entire* build-index-install-boot
loop with the fewest moving parts, so that when a later 5xx phase graduates the
exact same repo shape to static HTTPS at `repo.onix-os.com`, only the transport
changes, not the contract.

## The phase split

The split is:

```text
4xx = local bootstrap stones needed to replace current Nix-sourced system payloads
5xx = real stone factory, recipe repository, remote publishing, repo.onix-os.com
```

This means Phase 4 is still allowed to be practical and local.

It does not need:

- remote hosting,
- signing policy,
- retention policy,
- package promotion,
- CDN/cache design,
- production repository layout.

Those belong later.

## Local paths

Phase 408 defines these generated artifact paths:

```text
artifacts/onix-stones/
artifacts/onix-local-repo/
artifacts/onix-stone-work/
```

They are ignored by git because they are build outputs.

Meaning:

| Path | Purpose |
|---|---|
| `artifacts/onix-stones/` | built local `.stone` files |
| `artifacts/onix-local-repo/` | local moss repository/index used by image proofs |
| `artifacts/onix-stone-work/` | temporary build/extract/check roots |

Phase 408 also reserves a source path:

```text
vm/phase4/stone-recipes/
```

That is where the first local bootstrap recipes can live while Phase 4 is still
proving the replacement loop.

Later, when the recipe system is real, these can move or be mirrored into a
proper `onix-os/recipes` style repository.

## Why not remote publishing yet?

A remote repo is not hard to host.

A static server is enough:

```text
repo.onix-os.com/bootstrap/
repo.onix-os.com/unstable/
```

The harder part is knowing the repo layout is correct and that ONIX can consume
it.

So we prove the local loop first:

```text
.stone -> local repo -> image install -> boot proof
```

Only after that should a 5xx phase publish the same repo shape remotely.

## Planned local replacement path

The current local plan is:

```text
408 — define local stone/repo contract
409 — build `busybox.stone`
410 — install/use `busybox` in the image
411 — rerun shell/network/SSH proofs against stone BusyBox
412 — build `dropbear.stone`
413 — install/use `dropbear` and rerun SSH proof
414 — systemd stone dependency audit
415 — build first `systemd.stone`
416 — install `systemd` into the image
417 — boot with `systemd` as PID 1
418 — move bootstrap units/defaults into stone ownership
419 — audit no Nix-sourced systemd/busybox/dropbear payload remains
```

This sequence is deliberately incremental.

BusyBox comes first because it provides:

```text
/bin/sh
basic command applets
network proof tools
SSH proof command tools
```

Dropbear comes next because Phase 406 already proved the SSH behavior.

Systemd comes after that because it is larger and has more dependencies:

```text
PID 1
udev
sysusers
tmpfiles
unit search path
service startup
boot target behavior
```

Systemd may become multiple stones. Phase 414 exists to discover that before we
pretend a single recipe is enough.

## What `make phase 408` does

Run:

```sh
make phase 408
```

It creates/verifies:

```text
artifacts/onix-stones/
artifacts/onix-local-repo/
artifacts/onix-stone-work/
vm/phase4/stone-recipes/
```

It writes small `CONTRACT.txt` files into the generated artifact directories so
the purpose of each directory is visible if you inspect them.

It also checks this book page for the key contract terms, including:

```text
artifacts/onix-stones
artifacts/onix-local-repo
vm/phase4/stone-recipes
5xx = real stone factory
409 — build busybox.stone
414 — systemd stone dependency audit
```

Expected success:

```text
==> success
Phase 408 local stone/repo contract is ready.
```

## What this phase does not do

Phase 408 does not build any stones.

It does not:

- build BusyBox,
- generate a moss repo index,
- install a package into the image,
- boot QEMU,
- publish to `repo.onix-os.com`.

It only makes the next steps precise.

The next real build phase should be:

```text
409 — build busybox.stone
```
