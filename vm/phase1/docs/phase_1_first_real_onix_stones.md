# Phase 1 overview — first real ONIX stones

Phase 1 turns the Phase 0 tooling proof into real ONIX package artifacts.

We start deliberately small:

```text
branding
filesystem
```

These packages establish identity, default filesystem policy, and the first
publishable repository shape.

## What Phase 0 left us with, and what Phase 1 adds

Phase 0 built the **forge**: a throwaway Alpine/musl virtual machine (hostname
`quarry`) where the two AerynOS tools — **moss** and **boulder** — are compiled
and run. It is worth restating what those two tools are, because every Phase 1
step leans on them:

- **boulder** is the `.stone` *builder*. You hand it a recipe file
  (`stone.yaml`) that says "here is a package name, a version, and a list of
  shell commands that lay files down under an install root," and boulder runs
  those commands in a sandbox and packs the result into a single compressed,
  content-addressed archive called a `.stone`.
- **moss** is the atomic *package and state manager*. It reads `.stone` files,
  indexes them into repositories, installs their payload into a root filesystem,
  and — crucially — records every install/remove as a numbered **state** it can
  roll back to. moss is the thing that will eventually own a running ONIX
  machine's `/usr`.

A `.stone` is not a tarball you extract by hand; it is a moss-native package.
Phase 0 proved boulder can produce one and moss can install and roll it back.
But the package it proved this with — `onix-hello` — was a toy: a single "hello"
binary with no meaning to ONIX. Phase 1 is where the packages start to *be*
ONIX.

## Why Phase 1 exists

Phase 0 proved we can build a toy package. Phase 1 proves ONIX can build real
package payloads, compose them, index them into a Moss repo, export that repo to
the host, and preview a future static package repository.

Concretely, Phase 1 answers five questions in order:

1. Can boulder build a package whose payload is *real ONIX content* — the
   distro's identity and its filesystem policy — and does that package survive
   moss's integrity checks and install cleanly into a fresh root? (Steps 101,
   102.)
2. Do two independent stones **compose** — install side by side into the same
   root without fighting over files? (Step 102.)
3. Can those loose `.stone` files be collected into a **named moss repository**
   and installed *by package name* instead of by file path? (Step 103.)
4. Can that repository be reshaped into the **directory layout a real static web
   host would serve**, complete with checksums and a machine-readable
   `repo.json`? (Step 104.)
5. Can that publishable tree be **exported to the host, verified, and turned
   into a written publication plan** — all without ever uploading anything or
   touching DNS? (Steps 105–108.)

## The two first stones, and why these two first

ONIX's base package set is kept deliberately tiny (the long tail of software is
Nix's job). The very first two stones were chosen because they carry *no
compiled code* and *no dependencies* — they are pure data and policy — so they
isolate the packaging machinery from the far harder problem of cross-compiling a
musl toolchain. If something breaks in Phase 1, it is the repo/index/publish
pipeline, not a compiler.

- **`branding`** ships the system's *identity*: an `os-info.json` metadata
  file that moss turns into a standard `os-release`, plus the terminal logo and
  default login text. This is what makes a booted machine able to say "I am
  ONIX." (Step 101.)
- **`filesystem`** ships the system's *filesystem policy*: a documented
  ownership boundary between moss's `/usr`, Nix's `/nix`, and local `/etc`
  state, plus default templates (`fstab`, login `profile`, PATH policy) that
  future image assembly can materialize. (Step 102.)

Both follow a pattern you will see everywhere in ONIX and which Phase 1
introduces: **packages ship defaults under `/usr/share/defaults/etc`, never
straight into live `/etc`.** More on why in step 101.

## Steps

- [100 — forge readiness](./100_forge_readiness.md)
- [101 — build `branding`](./101_build_onix_branding.md)
- [102 — build `filesystem`](./102_build_onix_filesystem.md)
- [103 — assemble first named local ONIX repo](./103_assemble_first_named_local_onix_repo.md)
- [104 — prepare publishable ONIX repo layout](./104_prepare_publishable_repo_layout.md)
- [105 — export publishable repo to the host](./105_export_publishable_repo_to_host.md)
- [106 — verify exported host artifact](./106_verify_exported_host_artifact.md)
- [107 — verify no-upload publishing plan](./107_verify_no_upload_publishing_plan.md)
- [108 — preview publication without upload](./108_preview_publication_without_upload.md)

## The host/guest split (read this once)

Almost every Phase 1 step runs partly on your **host** (the machine you type
`make` on) and partly inside the **forge guest** (the Alpine VM). The pattern is
consistent:

```text
host  ── ssh ──▶  forge guest (quarry)
 make            boulder builds the stone
                 moss indexes + installs into a disposable target root
 make  ◀── tar ──  stream the publishable tree back to host
 make            verify the host artifact (steps 106–108 are host-only)
```

Steps 101–105 reach into the guest over SSH (boulder and moss only exist there).
Steps 106, 107 and 108 never touch the network at all — they only inspect the
artifact already sitting under `artifacts/onix-publish/` on the host. That
progression, from "runs in the guest" to "host-only, no network," is deliberate:
it walks the repository from a live build environment out to a frozen, auditable
artifact you could hand to a web server.

## The Phase 1 gate

The phase is not "done" because scripts exited 0. It is done when the underlying
claim holds: **the `onix` repo carries a self-consistent base stone set, and
moss can install it, by name, into a fresh root.** Every step below advances one
piece of that claim. The final host-side artifact under `artifacts/onix-publish/`
is the concrete evidence — a checksummed, moss-indexed repository tree that a
later phase could upload verbatim.

What Phase 1 deliberately does **not** do yet: it does not build a kernel, does
not boot anything, and does not upload the repo to the internet. Booting a real
musl ONIX image is Phase 2; real hosting is a later, explicitly separate phase.

Running:

```sh
make phase 1
```

runs the whole Phase 1 family.
