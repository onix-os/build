# 504 — canonical essential package build lane

Run:

```sh
make phase 504
```

Phase 504 makes the essential package builders consume the canonical
`packages/` recipes.

This is the first step where `packages/` stops being only a copy of old recipes
and starts becoming the source of truth for builds.

## What changed

Earlier phases used recipes from older learning locations:

```text
recipes/branding/
recipes/filesystem/
vm/phase4/stone-recipes/
```

Phase 503 copied those recipes into:

```text
packages/
```

Phase 504 changes builder defaults so the next build reads from:

```text
packages/base/branding/
packages/base/filesystem/
packages/core/busybox/
packages/services/dropbear/
packages/services/systemd/
packages/services/bootstrap-policy/
```

## Why the old paths still exist

Phase 504 does not delete old paths.

That is intentional.

The migration order is:

```text
503 — copy recipes
504 — make builders default to canonical copies
later — remove old paths only after all builders and docs stop needing them
```

This keeps the repo safe while the package system moves into place.

## Builders switched by Phase 504

Phase 504 switches the default recipe paths in these scripts:

```text
vm/phase1/build-branding-stone.sh
vm/phase1/build-filesystem-stone.sh
vm/phase4/build-busybox-stone.sh
vm/phase4/build-dropbear-stone.sh
vm/phase4/build-bootstrap-policy-stone.sh
vm/phase4/build-native-systemd-stone.sh
vm/phase4/native-systemd-prep.sh
```

They still keep environment-variable overrides.

For example:

```sh
ONIX_BUSYBOX_RECIPE_TEMPLATE=some/other/stone.yaml.in \
  vm/phase4/build-busybox-stone.sh
```

But the default is now canonical:

```text
packages/core/busybox/stone.yaml.in
```

### What "switching a default" concretely means

The change inside each builder is one line — a shell default-value expansion:

```sh
RECIPE_TEMPLATE="${ONIX_BUSYBOX_RECIPE_TEMPLATE:-$ONIX_ROOT/packages/core/busybox/stone.yaml.in}"
```

Read it as: "use `ONIX_BUSYBOX_RECIPE_TEMPLATE` if the caller set it; otherwise fall
back to the canonical path." Before Phase 504 that fallback pointed at the old
`vm/phase4/stone-recipes/...` location; after Phase 504 it points into `packages/`.
The override still exists, so nothing that explicitly set the variable breaks — but
the *unattended* default, the one CI and casual builds hit, now reads from the
canonical tree. That is the whole migration: not a rewrite, a change of default. The
step 504 checker verifies this by grepping each builder for the exact expected
default line, so a builder that quietly kept pointing at the old path fails the phase.

## What `make phase 504` proves

The default Phase 504 command is a proof lane, not a forced full rebuild.

It verifies:

- builders default to `packages/` recipes,
- canonical recipes exist,
- old recipe paths still exist,
- existing essential stones exist,
- existing essential stones pass `moss inspect --check`.

This keeps normal validation fast.

## Why it does not always rebuild everything

Some essential packages are cheap.

Some are not.

Native `systemd` can be expensive to rebuild.

So the normal command:

```sh
make phase 504
```

checks that the canonical build lane is correct and that existing essential
artifacts are valid.

### Why a proof lane instead of always rebuilding

There is a real tension here. You want confidence that the canonical recipes actually
build; but a full rebuild — especially native systemd, a large source compile — is
slow and turns a quick validation into a coffee break. Phase 504 resolves it by
splitting *correctness* from *rebuilding*:

- The default `make phase 504` proves the lane is **wired correctly** (builders
  default to `packages/`, canonical recipes exist, old paths still exist) and that the
  **existing** essential stones are valid, using `moss inspect --check` on each. This
  is the cheap, always-run path.
- A rebuild is opt-in via `ONIX_PHASE504_REBUILD=1`, and native systemd needs *one
  more* explicit flag on top. Nothing expensive happens unless you ask for it.

`moss inspect --check` is the key to making the cheap path trustworthy: it opens each
`.stone` and verifies its internal integrity (metadata and content hashes) without
installing it. So "we didn't rebuild" does not mean "we didn't verify" — the existing
artifacts are proven intact every run, just not regenerated.

To force rebuilds, use:

```sh
ONIX_PHASE504_REBUILD=1 make phase 504
```

That rebuilds the cheaper essential package set from canonical defaults:

```text
branding
filesystem
busybox
dropbear
bootstrap-policy
```

Native systemd rebuild is intentionally one more explicit flag:

```sh
ONIX_PHASE504_REBUILD=1 \
ONIX_PHASE504_REBUILD_NATIVE_SYSTEMD=1 \
make phase 504
```

## Why native systemd is separate

`systemd` is essential, but it is a large source build.

It also currently has a documented dynamic musl/bootstrap-native exception.

That does not weaken the Phase 5 policy for new Rust-first core packages.

It only says:

```text
systemd is special; do not casually inherit its exception
```

The danger a young distro faces is *exception creep*: one package gets a documented
pass for a shared-library dependency, and six months later three more packages point
at it and say "well, systemd does it." Phase 504 heads that off by making the systemd
exception loud, isolated, and gated behind its own extra flag. The exception is real,
but it is quarantined to one package with a written justification in its
`PACKAGE.md`; new Rust-first core packages start from the strict default and must earn
any exception of their own.

## Existing artifact sets

Phase 504 checks two existing artifact roots.

Base publish artifact:

```text
artifacts/onix-publish/unstable/x86_64/
```

Expected:

```text
branding-*.stone
filesystem-*.stone
stone.index
```

Runtime local repo:

```text
artifacts/onix-local-repo/
```

Expected:

```text
busybox-*.stone
dropbear-*.stone
systemd-*.stone
bootstrap-policy-*.stone
stone.index
```

## Important honesty

Phase 504 does not claim every old artifact is already a perfect final Phase 5
package.

It proves the build lane now points at canonical package recipes.

Strict runtime-clean auditing still happens package-by-package as we rebuild and
accept packages through the Phase 5 gates.

## What comes next

The next step should be:

```text
505 — assemble local ONIX repo from canonical packages
```

Phase 505 should produce one local repository layout that collects the canonical
essential stones together.
