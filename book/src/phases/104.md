# Phase 104 — prepare publishable ONIX repo layout

## At a glance

| Field | Value |
|---|---|
| Phase family | Phase 1 — first stones |
| Run command | `make phase 104` |
| Underlying make target/script | `vm/phase1/build-publishable-repo.sh` |
| Runs on | guest over SSH |
| Main proof/artifact | Assembles the first static-host-style ONIX repo layout. |


Phase 103 proves a named repo works locally. Phase 104 reshapes that idea into
a directory layout we could later upload to static hosting.

## From a flat local repo to a hostable tree

Step 103's repo was a single flat directory — fine for a `file://` URL on one
machine, but not the shape a public mirror needs. A real repository has to answer
two questions a flat directory cannot: *which release channel* is this
(`unstable` vs a future `stable`) and *which CPU architecture* is this
(`x86_64`). Those become directory levels. It also needs machine-readable
identity metadata and tamper-evidence (checksums) so a downloader can trust what
it fetched. Step 104 builds exactly that tree.

## The layout it creates

It creates:

```text
~/stone-lab/onix-publish/
  README.txt
  repo.json
  unstable/x86_64/
    stone.index
    SHA256SUMS
    onix-branding-*.stone
    onix-filesystem-*.stone
```

The `unstable/x86_64/` path is not decoration — it is the URL path a client will
eventually GET. `unstable` is the channel; `x86_64` is the architecture, taken
from `uname -m` in the build script. Adding a `stable` channel or an `aarch64`
architecture later means adding sibling directories, never reorganizing the
existing one. This "channel/arch" split is the standard shape static package
mirrors use, and pinning it now means the public URL layout is decided before
anything is ever uploaded.

### `stone.index` and `SHA256SUMS`

Inside `unstable/x86_64/`, the script re-runs `moss index` to produce a fresh
`stone.index` for the two stones, then generates a checksum manifest:

```sh
sha256sum *.stone stone.index > SHA256SUMS
sha256sum -c SHA256SUMS
```

`SHA256SUMS` lists a SHA-256 hash for every stone *and* for the index itself, and
the `-c` check immediately verifies them. This is the tamper-evidence layer: any
later phase (export, verify, a real upload) can re-run `sha256sum -c SHA256SUMS`
and know byte-for-byte that nothing changed in transit. It is deliberately a
plain, universally-available format — no special tooling needed to validate an
ONIX mirror.

### `repo.json` — the public identity

`repo.json` records the public identity:

```text
homepage: https://onix-os.com
source:   https://github.com/onix-os
hint:     https://repo.onix-os.com/unstable/x86_64/stone.index
```

The full file also records `name`, `id`, `channel`, `architecture`, and a
`local_index` path. It is human- and tool-readable metadata *about* the repo (as
opposed to `stone.index`, which is moss's machine index *of the packages*). The
`repo_url_hint` is the future public URL a client would add — written down now so
that the moment the tree is actually hosted, the address is already fixed and
consistent everywhere. `README.txt` is the plain-language companion, spelling out
the channel, architecture, the local test index, and the future public index.

## This phase does not upload

This phase does **not** upload anything. It only proves the publish-style
layout works by adding the local `stone.index` as repo `onix-unstable` and
installing `onix-branding` + `onix-filesystem` from it.

That final proof is the important one: the script registers the freshly-built
publishable tree as a moss repo named `onix-unstable` over a `file://` URL,
`repo update`s it, and installs both packages by name into a throwaway target —
then asserts `os-release` and the `fstab` label. In other words, it proves the
*publishable* layout is not just a pretty directory but a **working moss repo**:
if `file://.../unstable/x86_64/stone.index` installs correctly, then the very
same tree served at `https://repo.onix-os.com/unstable/x86_64/stone.index` will
too, because moss cannot tell the transports apart. The layout is validated by
consumption, not just by inspection.

## What it proves vs what it does not

It **proves**: ONIX stones can be arranged into the channel/arch directory tree a
static host expects, with a moss index, a SHA-256 manifest, and public-identity
metadata — and that this tree installs correctly as a named repo.

It does **not** prove: anything on the *host* side. The tree still lives only
inside the forge VM. Getting it onto the host as a clean, gitignored artifact is
step 105; verifying that host artifact independently is step 106; and turning it
into a written, auditable no-upload publication plan is steps 107–108. And
nothing here contacts the network or changes DNS.
