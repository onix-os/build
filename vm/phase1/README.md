# Phase 1 — first real ONIX stones

Phase 0 proved the toolchain path:

```text
boot forge -> build moss+boulder -> build a toy .stone -> prove Moss rollback
```

Phase 1 starts turning that proof into real ONIX packages.

We begin deliberately small with `onix-branding`.

## Why start with branding?

`onix-branding` is a real base package, but it has almost no technical risk.
It does not need a compiler, libc bootstrap, patches, or a package dependency
graph. It only installs identity files.

That makes it a good first Phase 1 lesson:

- how a real ONIX recipe lives under `recipes/`
- how Boulder builds a source-less/static package
- how Moss checks, extracts, indexes, and installs that package
- how we keep `/etc` mostly policy/defaults instead of random imperative edits

## Phase commands

```sh
make phase 100
make phase 101
make phase 102
```

The format is three digits. `102` means "Phase 1, step 02". Running
`make phase 1` runs all Phase 1 steps, `100..102`, in order.

### Phase 100 — forge readiness

Checks that the running forge is reachable and that these tools exist inside it:

- `moss`
- `boulder`

If this fails, Phase 0 is not ready. Run:

```sh
make phase 003
make phase 004
```

### Phase 101 — build `onix-branding`

Builds the recipe at:

```text
recipes/onix-branding/stone.yaml
```

inside the forge, then verifies:

- the `.stone` passes `moss inspect --check`
- `/usr/lib/os-info.json` exists
- Moss generates `/usr/lib/os-release` from that metadata during install
- default `/etc` text lives under `/usr/share/defaults/etc/`
- installing into a disposable target root works

Boulder currently ignores non-`/usr` payload files in this layout. That means
`onix-branding` ships the canonical input metadata at `/usr/lib/os-info.json`.
Moss uses that to generate `/usr/lib/os-release` during install. Later image
assembly or first-boot glue creates the compatibility symlink:

```text
/etc/os-release -> ../usr/lib/os-release
```

## Why defaults under `/usr/share/defaults/etc`?

The final ONIX contract is:

```text
moss owns the machine plane
local admin/user changes live outside the immutable package payload
```

So for mutable configuration text like `issue` and `motd`, the package ships
defaults under:

```text
/usr/share/defaults/etc/
```

Later boot/install glue can copy or merge those into `/etc` if needed. The
package still ships the canonical `/usr/lib/os-info.json`; Moss generates
`/usr/lib/os-release`, and image assembly creates the standard `/etc/os-release`
compatibility symlink outside the `.stone`.

### Phase 102 — build `onix-filesystem`

Builds the recipe at:

```text
recipes/onix-filesystem/stone.yaml
```

This package does **not** own live `/etc`, `/var`, `/run`, `/dev`, `/proc`, or
`/sys`. Instead, it installs policy and templates under `/usr`:

```text
/usr/share/onix/filesystem-layout.md
/usr/share/defaults/etc/fstab
/usr/share/defaults/etc/profile.d/onix-path.sh
```

The Phase 102 test installs both `onix-branding` and `onix-filesystem` into the
same disposable target root, so we prove the first two real ONIX stones compose.
