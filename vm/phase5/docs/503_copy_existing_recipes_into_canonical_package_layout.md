# 503 — copy existing recipes into canonical package layout

Run:

```sh
make phase 503
```

Phase 503 copies existing ONIX package recipes into the canonical Phase 5
`packages/` tree.

It is intentionally copy-only.

It does not remove old paths.

It does not change builders yet.

## Why copy instead of move

Earlier phases still build from the old locations:

```text
recipes/branding/
recipes/filesystem/
vm/phase4/stone-recipes/
```

If Phase 503 moved those files destructively, working Phase 1 and Phase 4 build
steps could break.

So Phase 503 does this instead:

```text
old path remains
new canonical packages/ copy appears
```

That gives ONIX a safe migration path.

### The migration invariant: byte-for-byte equal

While two copies of a recipe exist, there is exactly one rule that keeps the
transition safe: the canonical copy must be **byte-for-byte identical** to its old
source. If they are identical, it does not matter which one a builder reads — the
output is the same `.stone`. The moment they diverge, "which recipe built this
package?" becomes a real, dangerous question.

The step 503 checker enforces this with `cmp -s` on every mapped pair. That is why
Phase 503 can honestly call itself *copy-only*: it does not just assert the copies
exist, it proves they still match the originals. Later phases (504 onward) will start
pointing builders at the canonical copy and eventually retire the old paths — but only
after nothing depends on them. Until then, `cmp` equality is the safety rail.

## The migration sequence

The intended sequence is:

```text
503 — copy existing recipes into packages/
504 — build essential package set from canonical recipes
later — remove old paths only after no script needs them
```

This keeps the repo usable during the transition.

## What gets copied

Phase 503 creates these canonical package directories:

```text
packages/base/branding/
packages/base/filesystem/
packages/core/busybox/
packages/services/dropbear/
packages/services/systemd/
packages/services/bootstrap-policy/
```

## Copy map

```text
recipes/branding/stone.yaml
-> packages/base/branding/stone.yaml

recipes/filesystem/stone.yaml
-> packages/base/filesystem/stone.yaml

vm/phase4/stone-recipes/busybox/stone.yaml.in
-> packages/core/busybox/stone.yaml.in

vm/phase4/stone-recipes/dropbear/stone.yaml.in
-> packages/services/dropbear/stone.yaml.in

vm/phase4/stone-recipes/systemd-native/stone.yaml.in
-> packages/services/systemd/stone.yaml.in

vm/phase4/stone-recipes/bootstrap-policy/stone.yaml.in
-> packages/services/bootstrap-policy/stone.yaml.in
```

Notice the systemd choice:

```text
systemd-native
```

is copied as the canonical Phase 5 `systemd` recipe. The older bootstrap
systemd recipe remains Phase 4 history and is not promoted as the canonical
Phase 5 package.

This is the one place the copy is also a *decision*. Phase 4 experimented with two
ways to get systemd: an early bootstrap recipe that packaged a Nix-built payload, and
a later native recipe (`systemd-native`) that builds systemd from source on musl.
The native one is the honest ONIX package — it does not smuggle a `/nix/store` payload
into the machine plane — so Phase 5 promotes *it* to the canonical name `systemd`
and leaves the bootstrap recipe behind as history. Canonicalization is not just moving
files; it is choosing which experiment becomes the real package.

## Package contracts

Each copied package also gets:

```text
PACKAGE.md
```

This file answers the Phase 501 metadata questions:

```text
Implementation language
Rust alternative considered
Selected implementation
Why this implementation
musl target
Link model
Runtime cleanliness
Runtime dependencies
Exceptions
```

This matters because a recipe alone says how to package something. It does not
explain why that package belongs in ONIX.

## Important package notes

### `branding`

Data package. Rust alternative is not applicable.

### `filesystem`

Data/policy package. Rust alternative is not applicable.

### `busybox`

C package. Accepted as a temporary compact bootstrap command base.

Future Rust-first core packages such as `uutils-coreutils` should reduce its
importance.

### `dropbear`

C package. Accepted as temporary bootstrap SSH because it is small and proven.

A Rust SSH server replacement needs a separate evaluation.

### `systemd`

C package. Accepted because ONIX currently chooses systemd as PID 1 and there is
no serious Rust replacement for its full role.

The canonical copy uses the native source-built Phase 422 recipe, not the older
bootstrap Nix-payload recipe.

### `bootstrap-policy`

Shell/unit policy package. Accepted as small bootstrap glue.

If a helper grows into a real ONIX tool, it should become Rust.

## The checker

Phase 503 adds:

```text
vm/phase5/canonical-package-copies.sh
```

It verifies:

- every old source recipe still exists,
- every canonical copy exists,
- every canonical copy is byte-for-byte equal to its old source,
- every package has `PACKAGE.md`,
- every `PACKAGE.md` contains the required contract fields.

This is how Phase 503 proves it is copy-only.

## What Phase 503 does not do

Phase 503 does not:

- build from `packages/`,
- rewrite Phase 1 or Phase 4 scripts,
- delete old recipe locations,
- assemble a package repository,
- upload anything,
- audit final binary payloads.

Those are later steps.

## What comes next

The next step should be:

```text
504 — build essential package set from canonical recipes
```

That is where builders start consuming `packages/` instead of the older
phase-local recipe paths.
