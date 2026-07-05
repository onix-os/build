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
make phase 103
make phase 104
make phase 105
make phase 106
make phase 107
make phase 108
```

The format is three digits. `102` means "Phase 1, step 02". Running
`make phase 1` runs all Phase 1 steps, `100..108`, in order.

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

### Phase 103 — assemble first named local ONIX repo

Phase 101 and 102 prove individual stones work. Phase 103 proves the next
layer: those stones can live in a named repository.

It collects:

```text
~/stone-lab/onix-branding/out/*.stone
~/stone-lab/onix-filesystem/out/*.stone
```

then creates:

```text
~/stone-lab/onix-repo/repo/stone.index
```

and adds that index to a disposable Moss root as repo name `onix-local`.

The important proof is that the install happens by package name:

```sh
moss ... install --to <target> onix-branding onix-filesystem
```

So this is the bridge from "we have loose package files" to "ONIX has the
beginning of a package repository."

### Phase 104 — prepare publishable ONIX repo layout

Phase 103 proves a named repo works locally. Phase 104 reshapes that idea into
a directory layout we could later upload to static hosting.

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

`repo.json` records the public identity:

```text
homepage: https://onix-os.com
source:   https://github.com/onix-os
hint:     https://repo.onix-os.com/unstable/x86_64/stone.index
```

This phase does **not** upload anything. It only proves the publish-style
layout works by adding the local `stone.index` as repo `onix-unstable` and
installing `onix-branding` + `onix-filesystem` from it.

### Phase 105 — export publishable repo to the host

Phase 104 creates the publishable repo inside the forge VM. Phase 105 copies it
back to the host:

```text
forge: ~/stone-lab/onix-publish/
host:  artifacts/onix-publish/
```

The host artifact is gitignored because it contains generated `.stone` package
files and checksums.

After this phase, the important host files are:

```text
artifacts/onix-publish/repo.json
artifacts/onix-publish/README.txt
artifacts/onix-publish/unstable/x86_64/stone.index
artifacts/onix-publish/unstable/x86_64/SHA256SUMS
artifacts/onix-publish/unstable/x86_64/*.stone
```

This still does **not** publish anything. It gives us a local host-side artifact
that a later phase can upload to `repo.onix-os.com` or another static host.

### Phase 106 — verify exported host artifact

Phase 106 is host-only. It does not SSH into the forge VM.

It verifies:

- `artifacts/onix-publish/repo.json` exists and names ONIX correctly
- homepage is `https://onix-os.com`
- source is `https://github.com/onix-os`
- future repo hint is `https://repo.onix-os.com/unstable/x86_64/stone.index`
- exactly one `onix-branding` stone exists
- exactly one `onix-filesystem` stone exists
- `SHA256SUMS` validates
- no Moss test state (`.moss`, `moss-root`, `moss-cache`, `install-target`) leaked into the artifact
- `artifacts/` is gitignored

This gives us a clean gate before any future upload/publish phase.

### Phase 107 — verify no-upload publishing plan

Phase 107 is also host-only. It does not SSH into the forge VM and does not
publish anything.

It verifies two things:

1. the exported artifact still passes Phase 106 checks
2. [`docs/repo-publishing.md`](../../docs/repo-publishing.md) contains the
   current publication contract

The publication contract records:

- homepage: `https://onix-os.com`
- source: `https://github.com/onix-os`
- future repo root: `https://repo.onix-os.com`
- future Moss index: `https://repo.onix-os.com/unstable/x86_64/stone.index`
- local artifact source: `artifacts/onix-publish/`
- the rule that no current phase uploads or changes DNS

This gives us a safe stopping point before any future real hosting work.

### Phase 108 — preview publication without upload

Phase 108 is still host-only and still safe. It does **not** upload anything,
does **not** contact the network, and does **not** change DNS.

It verifies the Phase 107 plan, then prints:

- local artifact root
- future public root
- every file that would be published
- the future public URL for every file
- critical URLs to check after a real upload
- the `rsync`/`curl` commands that a future real publish phase might run, but
  refuses to run them
- the future user-facing `moss repo add` command

You can optionally preview a concrete upload destination without using it:

```sh
ONIX_REPO_UPLOAD_TARGET='user@host:/srv/repo.onix-os.com' make phase 108
```

It will print the target, but still not upload.
