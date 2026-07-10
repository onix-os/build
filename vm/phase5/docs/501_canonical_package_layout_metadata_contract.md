# 501 — canonical package layout and metadata contract

Run:

```sh
make phase 501
```

Phase 501 defines where canonical ONIX packages live and what every package must
document.

It does not move old recipes yet.

It creates the contract that later package work must follow.

## Why this phase exists

Before Phase 5, package work grew in learning-specific places:

```text
recipes/onix-branding/
recipes/onix-filesystem/
vm/phase4/stone-recipes/
```

That was useful while learning.

But a distro cannot keep its real package universe scattered across old phase
directories forever.

Phase 5 needs one canonical package workspace:

```text
packages/
```

That directory becomes the source of truth for ONIX-owned system packages.

### Why one workspace instead of scattered per-phase dirs

Scattered recipe directories are fine while you are *learning* — each phase drops its
experiment where it is convenient. But they are a bad foundation for a distribution,
for concrete reasons:

- **No single answer to "what packages exist?"** The truth is spread across
  `recipes/`, `vm/phase1/`, and `vm/phase4/stone-recipes/`. A newcomer (or future
  you) cannot list the package universe without archaeology.
- **Phase numbers leak into package identity.** A recipe living under
  `vm/phase4/stone-recipes/` implies "this belongs to Phase 4," which is history, not
  a fact about the package. Packages outlive the phase that first built them.
- **No place to enforce policy.** The Phase 500 law needs a home. A canonical tree
  gives every package the same required files (`stone.yaml`, `PACKAGE.md`) in the same
  shape, so a checker can walk one directory and enforce the contract uniformly.
- **Duplication drifts.** Two copies of "the busybox recipe" in two phase dirs
  eventually disagree. One canonical copy cannot disagree with itself.

So Phase 501 is a small act with a large consequence: it declares *one* address where
canonical ONIX packages live, and everything after it (copy, build, repo, image,
publish) points at that address.

## The canonical root

Phase 501 chooses:

```text
packages/
```

The name is intentionally boring and readable.

It means:

```text
this is where canonical ONIX package recipes live
```

## Initial groups

Phase 501 creates four starting groups:

```text
packages/base/
packages/core/
packages/libs/
packages/services/
```

These groups are not package manager concepts yet. They are repository
organization concepts.

They help humans understand what kind of package they are looking at.

The distinction matters: moss does not care about `base/` vs `core` vs `libs` vs `services`.
As far as moss is concerned there is one flat namespace of `.stone` files. The four
directories are purely for *human* review — they answer "how strictly should I judge
this package?" before you even open its contract. A `core/` command tool is held to
the strictest Rust-first, static-first bar; a `base/` data package is judged mostly
on runtime cleanliness; a `libs/` package is judged as an intentionally owned
shared-library surface; a `services/` daemon carries the extra burden of
unit-file hygiene. If a package needs shared libraries, that surface must be
minimal, documented, and owned by ONIX stones. Grouping the packages this way
puts the reviewer in the right frame of mind.

## `packages/base/`

Base packages define ONIX identity, filesystem policy, defaults, and low-level
system policy.

Examples:

```text
onix-branding
onix-filesystem
onix-bootstrap-policy
```

These packages may be mostly data, templates, or scripts.

They still must follow the same runtime-clean rule.

## `packages/core/`

Core packages provide command-line system tools.

Examples:

```text
uutils-coreutils
rootasrole
onix-busybox
```

This group should be especially strict:

```text
Rust-first
musl-only
static/static-PIE first by default
minimal ONIX-owned shared surface only by exception
```

If a core package is not Rust, its `PACKAGE.md` must explain why.

If a core package is not static/static-PIE musl, its `PACKAGE.md` must explain
why, list the allowed shared libraries, and name the ONIX stone that owns each
one.

## `packages/libs/`

Library packages provide explicitly owned shared-library surfaces.

Examples:

```text
linux-pam
libseccomp
```

This group is how ONIX avoids pretending that "static-first" means
"static-only." If a system role genuinely needs a shared library or module ABI,
the answer is to package that ABI as an ONIX stone, document the sonames, and
audit it. The answer is not to let a tool silently link against a host library.

## `packages/services/`

Service packages provide daemons, service units, and service policy.

Examples:

```text
onix-dropbear
onix-systemd
```

Service packages have extra risk because they often include systemd units.

So they must also prove:

```text
no unit calls /nix/store
no unit relies on a host build path
```

## Required files per package

Every canonical package must contain:

```text
stone.yaml
PACKAGE.md
```

`stone.yaml` is the Boulder recipe.

`PACKAGE.md` is the ONIX package contract.

The package is not canonical until both exist.

### Recipe versus contract: two files, two audiences

These two files answer completely different questions, and conflating them is a
common mistake:

```text
stone.yaml   answers  HOW do we build this?      (audience: boulder)
PACKAGE.md   answers  WHY does ONIX ship this?    (audience: a human reviewer)
```

`stone.yaml` is a **recipe** — machine-readable build instructions. It lists the
package `name`, `version`, `release`, `license`, `homepage`, the `upstreams` (source
URLs and their expected SHA-256 hashes), and the `install` steps that lay files into
the install root. boulder reads it and produces a `.stone`. It is silent on intent:
it will happily build a glibc mess if you tell it to.

`PACKAGE.md` is a **contract** — the design justification a reviewer reads before
accepting the package. It records the decisions the recipe cannot express: was a Rust
alternative considered, why this implementation was chosen, what link model the binary
uses, and whether any exception to the Phase 500 law applies. Some ONIX recipes are
`stone.yaml.in` *templates* (with placeholders like `@BUSYBOX_VERSION@` filled in at
build time) rather than final `stone.yaml` files; the contract requirement is the
same either way.

You need both because a recipe alone can build a package that passes every automated
check and still be the *wrong* package for ONIX — a C tool where a mature Rust one
exists. The contract is where that judgment gets written down and reviewed.

## Why `PACKAGE.md` exists

`stone.yaml` tells Boulder how to build a package.

But it does not explain enough design intent.

ONIX needs to know:

- why this package exists,
- why this implementation was chosen,
- whether a Rust alternative exists,
- how the package targets musl,
- whether the package is static or dynamically linked,
- whether static/static-PIE was tried first or explicitly ruled out,
- whether the package has runtime dependencies,
- whether any exception exists.

That is what `PACKAGE.md` records.

## Required metadata

Every `PACKAGE.md` must answer:

```text
Implementation language:
Rust alternative considered:
Serious Rust implementation exists:
Selected implementation:
Why this implementation:
Target triple:
C runtime:
Link model:
Static attempt/result:
Shared runtime libraries:
No runtime /nix/store dependency:
No /nix/store shebangs:
No /nix/store RPATH/RUNPATH:
No systemd units calling /nix/store:
No glibc loader path:
No unexpected shared runtime libraries:
All expected shared libraries are ONIX-owned:
Runtime dependencies:
Exceptions:
```

This is intentionally strict.

The point is to make package acceptance boring and reviewable.

### Reading the metadata block

The long field list is not bureaucracy; each line maps to a specific way a package
can betray the Phase 500 law, so a reviewer can go down the list like a checklist:

- **Implementation language / Rust alternative considered / Serious Rust
  implementation exists / Selected implementation / Why this implementation** — the
  Rust-first audit. Together they force the question "is there a serious Rust option,
  and if so why aren't we using it?" to be answered in writing.
- **Target triple / C runtime / Link model / Static attempt/result / Shared runtime libraries** — the
  musl-only audit. `Link model` is `static musl`, `static-pie musl`, or the explicit
  `dynamic musl exception`; `Static attempt/result` records whether the default
  static path worked or why it did not; `Shared runtime libraries` is `none` or a
  documented minimal surface. This is where accidental glibc or a stray
  shared-library dependency gets caught on paper.
- **No runtime `/nix/store` dependency / No `/nix/store` shebangs / No `/nix/store`
  RPATH/RUNPATH / No systemd units calling `/nix/store` / No glibc loader path / No
  unexpected shared runtime libraries** — the runtime-clean audit, one field per leak
  shape (symlink, shebang, RPATH, unit, loader, extra `.so`). These are exactly the
  things the step 502 audit helper checks in the actual payload, so the contract and
  the automated gate line up field-for-field.
- **Runtime dependencies / Exceptions** — the honesty fields. Anything the package
  genuinely needs at runtime, and any deliberate deviation from the law, is written
  here and nowhere else. "No unchecked exceptions" is the rule: an undocumented
  exception is a bug.

## Why static-first musl is explicit

The user-facing policy is:

```text
we strictly do not want shared runtime dependency surprises
everything targets musl
static/static-PIE gets tried first by default
```

For package metadata, that becomes:

```text
Link model: static musl / static-pie musl / dynamic musl exception
Static attempt/result: passed / failed because ... / ruled out because ...
Shared runtime libraries: none / documented minimal ONIX-owned surface
```

This gives us a way to reject accidental glibc or accidental host/Nix dynamic
links before the package reaches the image.

## Templates

Phase 501 adds:

```text
packages/templates/PACKAGE.md
packages/templates/stone.yaml
```

New package work should start by copying those templates.

Example:

```sh
mkdir -p packages/core/rootasrole
cp packages/templates/PACKAGE.md packages/core/rootasrole/PACKAGE.md
cp packages/templates/stone.yaml packages/core/rootasrole/stone.yaml
```

Then fill in the real metadata and recipe.

## What Phase 501 checks

`make phase 501` verifies the visible contract:

```text
packages/
packages/base/
packages/core/
packages/libs/
packages/services/
packages/templates/
packages/README.md
packages/templates/PACKAGE.md
packages/templates/stone.yaml
```

The Phase 5 `check` target also verifies that the templates mention the required
policy fields:

```text
Implementation language
Rust alternative considered
Link model
Static attempt/result
No runtime /nix/store dependency
All expected shared libraries are ONIX-owned
```

## What Phase 501 does not do

Phase 501 does not:

- copy existing recipes,
- build new packages,
- assemble a repository,
- upload to `repo.onix-os.com`,
- decide the full package universe.

Those are later Phase 5 steps.

## What comes next

The next step should be:

```text
502 — runtime-clean stone audit helper
```

That helper should eventually automate checks such as:

```sh
grep -R /nix/store payload/
find payload -type f -perm -111 -exec file {} \;
readelf -l ...
readelf -d ...
```

After that, ONIX can safely start copying real recipes into:

```text
packages/
```

without losing the Rust-first, musl-only, runtime-clean boundary.
