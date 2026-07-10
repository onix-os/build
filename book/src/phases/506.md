# 506 — essential package ownership collision fix

Run:

```sh
make phase 506
```

If the local artifacts have not yet been rebuilt after the source fix, run the
one-time rebuild form:

```sh
ONIX_PHASE506_REBUILD=1 make phase 506
```

Phase 506 fixes the first real cross-package ownership problem found by the
canonical local repository proof.

## The problem

Phase 505 assembled one local ONIX repository and installed all essential
packages from it.

That worked, but Moss reported duplicate path ownership for:

```text
/usr/bin/reboot
/usr/bin/poweroff
```

Both of these package paths were claimed by:

```text
onix-busybox
onix-systemd
```

That is not clean distribution packaging.

A package repository should make file ownership boring and explicit.

## Why collisions matter

If two packages own the same path, several bad things can happen:

- install order can decide which file wins,
- upgrades can replace a file unexpectedly,
- rollback state becomes harder to reason about,
- package removal can remove a file another package still expects,
- future signing/publishing policy becomes less trustworthy.

ONIX wants atomic and inspectable system state.

That means a path should have one clear owner.

### Background: what "owning a path" means

An atomic package manager like moss does not just dump files on disk; it maintains a
*ledger* of which package owns which path. That ledger is what makes removal, upgrade,
and rollback safe: to remove a package, moss deletes exactly the paths that package
owns; to roll back, it restores the set of paths the previous transaction recorded.
The ledger's core assumption is **one path, one owner**. When two packages both claim
`/usr/bin/reboot`, that assumption breaks and every operation on that path becomes
ambiguous — which is why moss flags it as a `duplicate entry:` rather than silently
picking a winner. ONIX treats the collision as a packaging bug to fix, not a warning
to live with, precisely because the whole atomic/rollback story depends on the
one-owner rule holding.

## Why systemd should own these names

`reboot` and `poweroff` are system-management commands.

On a systemd-based system, those commands should route through systemd policy.

So the Phase 506 decision is:

```text
onix-systemd owns /usr/bin/reboot
onix-systemd owns /usr/bin/poweroff
onix-busybox does not install those applet links
```

The BusyBox binary may still contain `reboot` and `poweroff` internally because
BusyBox builds many applets into one executable.

The important packaging rule is different:

```text
the onix-busybox stone must not own /usr/bin/reboot or /usr/bin/poweroff
```

In other words:

```text
compiled applet exists inside busybox     okay for now
package-owned command link exists         not okay
```

### Background: BusyBox applets and the link farm

BusyBox is one executable that contains hundreds of tiny tools ("applets") — `ls`,
`sh`, `reboot`, `poweroff`, and so on. It decides which applet to run by looking at
the name it was invoked as (`argv[0]`). So a working BusyBox system is one binary plus
a *farm of symlinks*: `/usr/bin/ls -> busybox`, `/usr/bin/reboot -> busybox`, etc.
Each of those links is a real path in the filesystem — and therefore a path a package
*owns*.

This is the crux of the fix. The `reboot` and `poweroff` code still lives *inside* the
BusyBox binary; nobody is recompiling BusyBox to strip it out. What changes is that
the `onix-busybox` package stops creating and owning the `/usr/bin/reboot` and
`/usr/bin/poweroff` *links*. The applet is present but unlinked; the command name is
left for `onix-systemd` to own. The package records this split in two manifests
shipped in its own payload:

```text
onix-busybox.links           the command links BusyBox does own
onix-busybox.systemd-owned   applets present in the binary but deliberately not linked
```

The `systemd-owned` list is documentation-as-data: it tells a future reader exactly
which BusyBox capabilities were intentionally surrendered to another package, so the
omission reads as a decision rather than an oversight.

## What changed

Phase 506 changes the BusyBox package rules so the bootstrap applet-link list no
longer includes:

```text
poweroff
reboot
```

The package now records two manifests:

```text
/usr/share/onix/packages/onix-busybox.links
/usr/share/onix/packages/onix-busybox.systemd-owned
```

`onix-busybox.links` is the list of command links BusyBox actually owns.

`onix-busybox.systemd-owned` documents BusyBox applets that exist in the binary
but are intentionally not installed as package-owned command paths because
systemd owns them.

## Why the BusyBox release is bumped

The `onix-busybox` stone payload changed.

It no longer owns two paths.

That is a package-content change, so the recipe release is bumped:

```text
release: 1 -> 2
```

This prevents two different BusyBox package payloads from pretending to be the
same package release.

That matters even before public hosting.

Local discipline now avoids repository pain later.

### Why the release number carries identity

A package is identified by more than its name and upstream version. The **release**
number is ONIX's own revision counter for the *packaging* — bump it whenever the stone
payload changes even if the upstream software did not. Here BusyBox itself is
unchanged, but the package now owns two fewer paths, so the payload is genuinely
different. Leaving the release at `1` would let two different payloads both call
themselves "onix-busybox release 1," and a client could not tell which one it has.
Bumping `release: 1 -> 2` gave the new payload a distinct identity, so caches,
indexes, and rollback history could never confuse the old collision-prone build with the
fixed one. Later Phase 513 bumps the same package again because it removes more
BusyBox-owned command links for the uutils migration. This is basic distro
hygiene: every payload ownership change needs a new package release.

## What `make phase 506` checks

The helper is:

```text
vm/phase5/fix-essential-ownership.sh
```

Normal check mode verifies:

- `build-busybox-stone.sh` no longer asks BusyBox to own `reboot`/`poweroff`,
- Phase 4 image materialization no longer expects those BusyBox links,
- the canonical and old BusyBox recipe templates still match during migration,
- the BusyBox recipe release is bumped,
- `PACKAGE.md` documents the ownership rule,
- the current `onix-busybox` artifact does not contain `/usr/bin/reboot`,
- the current `onix-busybox` artifact does not contain `/usr/bin/poweroff`,
- the canonical local repo remains installable.

Important: Phase 506 is scoped to the BusyBox/systemd command collision. Later
Phase 5 stones introduce a separate known overlap around the musl loader path:

```text
/usr/lib/ld-musl-x86_64.so.1
```

That later overlap is not fixed by Phase 506. It remains visible in the repo
proof as a warning until a later package-ownership cleanup phase gives the musl
loader path one clear owner.

## One-time rebuild mode

After the source fix, the old already-built `onix-busybox` stone may still
exist in:

```text
artifacts/onix-local-repo/
```

That artifact has to be rebuilt once.

Run:

```sh
ONIX_PHASE506_REBUILD=1 make phase 506
```

That command does three things:

1. checks the source policy;
2. calls the Phase 4 BusyBox build target through Make;
3. reassembles the canonical local repo and proves it remains installable.

After that, normal check mode should pass:

```sh
make phase 506
```

## Why this is still Phase 5 work

This is not a boot problem.

This is a package/repository problem.

The image may boot either way, but the repository would be sloppy if two
packages owned the same file.

Phase 5 owns package hygiene, package contracts, and repository correctness.

So Phase 506 belongs here.

## What comes next

After Phase 506, the next step returns to the original repository plan:

```text
507 — make image assembly consume the canonical local repo
```

That means future image assembly should use:

```text
artifacts/onix-repo/unstable/x86_64/stone.index
```

instead of older split artifact roots.
