# ONIX recipes

This tree holds ONIX `.stone` recipes.

Phase 0 used a toy recipe generated inside the forge (`onix-hello`) only to
prove Boulder and Moss work.

Phase 1 starts real ONIX-owned packages here.

## What a `.stone` recipe is

A **`.stone`** is ONIX's package format (borrowed, with the rest of the tooling,
from AerynOS): a single content-addressed archive that holds the files a package
installs plus its metadata. A **recipe** is the source document that tells the
builder how to produce one. In this project a recipe is a file named
`stone.yaml`, and it is to a `.stone` what a `Makefile` or an `APKBUILD` is to a
compiled artifact — a declarative description of a package, not the package
itself.

A minimal recipe is mostly identity plus an `install` script. Here is the shape,
drawn from `onix-branding`'s real recipe:

```yaml
name        : onix-branding
version     : 0.1.0
release     : 1
summary     : ONIX identity and default login text
license     : MIT
homepage    : https://onix-os.com
description : |
    Identity package for ONIX...
install     : |
    install -dm00755 %(installroot)/usr/lib
    install -dm00755 %(installroot)/usr/share/onix/branding
    ...
```

The key ideas:

- The top fields (`name`, `version`, `release`, `summary`, `license`,
  `homepage`, `description`) are the package's identity and end up as metadata
  inside the `.stone`.
- The `install` block is a shell script that lays the package's files into a
  staging directory. `%(installroot)` is a Boulder macro that expands to that
  staging root — everything the script writes under it becomes the package
  payload. ONIX packages are **`/usr`-centric**: they write defaults and policy
  under `/usr` (for example `/usr/lib`, `/usr/share/...`), never mutable
  root-level state.
- Recipes that build from source add an `upstreams` list (a source URL plus its
  SHA-256) and `setup`/`build` steps before `install`; identity-only packages
  like `onix-branding` just synthesize files inline.

### The setgid gotcha

Every ONIX recipe ends its `install` block with a `chmod g-s` over the
directories it created. This is a real Boulder/Moss interaction, not
boilerplate: Boulder's build directories inherit the setgid bit (`g+s`). If a
package hands Moss a `/usr` or `/usr/bin` directory that still has that bit set,
Boulder records it as a special layout entry and Moss rejects the path during
install. Clearing setgid on every directory the recipe creates keeps Moss happy.
You will see this pattern in every `stone.yaml` in the repo.

## How Boulder consumes a recipe

**Boulder** is the `.stone` builder. Given a `stone.yaml`, it:

1. reads the identity fields and, for source packages, fetches and verifies the
   `upstreams` archive against its recorded hash;
2. runs the recipe's build steps and then the `install` script inside an
   isolated build root, collecting everything written under `%(installroot)`;
3. captures that staged tree plus the metadata into a content-addressed `.stone`.

**Moss** then consumes the finished `.stone`: it installs the payload into its
content store (`/.moss`), composes it into the atomic `/usr` tree, and records
the change as a transaction you can list and roll back. So the full pipeline is:

```text
stone.yaml  --(boulder build)-->  .stone  --(moss install)-->  atomic /usr
```

Boulder builds; Moss installs and versions. A recipe is only ever consumed by
Boulder; the resulting `.stone` is only ever consumed by Moss.

## Two trees: legacy `recipes/` and canonical `packages/`

The repository has **two** recipe trees, and it matters which is which.

- **`recipes/`** — the *legacy* Phase 1 tree, the one this page documents. It
  holds the first hand-authored ONIX recipes, kept flat and simple, and is still
  the tree the `make phase 101` / `make phase 102` learning steps build from.
- **`packages/`** — the *canonical* Phase 5 tree. Phase 5 promotes ONIX from
  scattered phase-local experiments to a real package/repository plane, grouped
  by role:

  ```text
  packages/
    base/       identity, filesystem layout, defaults, policy
    core/       Rust-first, musl-static command-line tools
    services/   daemons, service units, service policy
    templates/  starting point for new packages
  ```

  The canonical tree adds a **package law** — ONIX system packages must be
  *Rust-first, musl-only, and runtime-clean* (no glibc, no shared-library
  surprises, and no `/nix/store` references in the finished payload) — and
  requires every package to ship a `PACKAGE.md` contract alongside its
  `stone.yaml`. `PACKAGE.md` records why the package exists, why its
  implementation was chosen, and how it satisfies that law. Phase 5's steps copy
  the existing recipes into this layout (`503`), prove the essential builders use
  the canonical copies (`504`), and assemble the results into a real local repo
  (`505` onward) — all without deleting the legacy paths that existing builders
  still depend on.

Short version: `recipes/` is where ONIX started and where Phase 1 still builds;
`packages/` is where ONIX is heading — the same recipes, reorganized under a
strict contract, on their way to a published repository.

## The Phase 1 packages

Current Phase 1 packages:

```text
onix-branding     identity metadata; Moss generates os-release from it
onix-filesystem   filesystem layout policy and default templates
```

### `onix-branding`

This is ONIX's identity package. Its `install` script writes
`/usr/lib/os-info.json` — a structured description of the distro (id `onix`, name
`ONIX`, atomic/transactional update strategy, systemd-boot, XFS default) that
**Moss reads to generate `/usr/lib/os-release`**, the standard file every Linux
tool consults to answer "what distribution is this?". It also ships the login
identity: an `/etc/issue` template, the ANSI-colored ONIX logo under
`/usr/share/onix/branding/`, and an `/etc/motd` carrying the project slogan,
"moss controls the machine. Nix controls the toolbox." Because Moss derives
`os-release` from this one package, ONIX's identity lives in a single auditable
place instead of being hand-edited into the running system.

### `onix-filesystem`

This package encodes ONIX's **filesystem layout policy** as shipped defaults. It
writes `/usr/share/onix/filesystem-layout.md` documenting the ownership boundary
(moss owns `/usr` and boot artifacts; Nix owns `/nix`; local state lives outside
immutable payloads), and a set of templates under `/usr/share/defaults/etc`: an
`fstab` describing the `ONIX-ESP` / `ONIX-BOOT` / `onix-root` / `ONIX-PERSIST`
partitions and the `/persist/home` and `/persist/nix` bind mounts, a login
`profile` that sources `/etc/profile.d/*.sh`, a PATH-policy drop-in, and a login
banner drop-in. Note these ship under `/usr/share/defaults/etc`, **not** `/etc`
directly — the package provides *defaults*; image assembly or boot-time glue
materializes the live `/etc` from them. That is the atomic contract in miniature:
packages own read-only defaults under `/usr`, and mutable machine state is
derived from them, never edited inside the package payload.

Build them through the learning flow:

- `make phase 101`
- `make phase 102`
