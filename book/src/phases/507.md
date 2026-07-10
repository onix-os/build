# 507 — make the image consume the canonical local repo

Run:

```sh
make phase 507
```

Phase 507 changes the package input used by image assembly.

Before this phase, ONIX had two useful but temporary repo shapes:

```text
artifacts/onix-publish/unstable/x86_64/
artifacts/onix-local-repo/
```

Those were good learning artifacts.

They proved different things:

- `artifacts/onix-publish/` proved the first publish-style repository layout for
  `onix-branding` and `onix-filesystem`;
- `artifacts/onix-local-repo/` proved the Phase 4 booted-base packages such as
  `onix-busybox`, `onix-dropbear`, `onix-systemd`, and
  `onix-bootstrap-policy`.

But a real distribution image should not be assembled from two separate
historical artifact roots.

From this point, the image should consume one canonical local package repo:

```text
artifacts/onix-repo/unstable/x86_64/stone.index
```

That path is the local version of the future public repo URL:

```text
https://repo.onix-os.com/unstable/x86_64/stone.index
```

## What "image consumes a repo" means

An ONIX image is just a disk image.

Inside that disk image is a Linux root filesystem:

```text
/
├── etc
├── usr
├── var
├── boot
└── ...
```

When image assembly installs a package, it does not copy random files by hand if
there is already a `.stone` package for that payload.

Instead, the assembly process asks Moss to install a package from a repository
into a scratch directory:

```text
moss repo add onix-image file://.../stone.index
moss install --to scratch-root onix-busybox
```

Then the image assembly script copies the installed package payload into the
mounted disk image.

So this:

```text
image consumes repo
```

means:

```text
image assembly gets package payloads through Moss from stone.index
```

It does **not** mean:

```text
copy files manually from some build directory
```

## Why the old split was not enough

The old split was:

```text
branding/filesystem packages  -> artifacts/onix-publish/
booted-base packages          -> artifacts/onix-local-repo/
```

That made sense while ONIX was still learning.

But it creates a bad distribution shape:

- the base identity packages live in one repo;
- runtime boot packages live in another repo;
- image assembly has to know historical phase details;
- publishing would need extra logic to merge the two worlds later;
- repo correctness can be checked in one place only after everything is merged.

Phase 505 already made the merged repo:

```text
artifacts/onix-repo/
```

Phase 506 fixed the first ownership collision: BusyBox no longer owns
systemd's reboot/poweroff command paths.

Phase 507 now makes image assembly use that merged repo.

## The new repo input variable

Phase 507 introduces this image-assembly input:

```text
ONIX_IMAGE_REPO_DIR
```

For Phase 507, it points at:

```text
artifacts/onix-repo/unstable/x86_64
```

The actual Moss index is:

```text
$ONIX_IMAGE_REPO_DIR/stone.index
```

This split is intentional.

The package builders may still write fresh stones to an intermediate local repo
while we are migrating:

```text
artifacts/onix-local-repo/
```

But image assembly can now be told:

```text
do not read from the intermediate build repo;
read from the canonical merged image repo
```

That keeps earlier Phase 4 learning steps runnable while Phase 5 moves the
distribution flow forward.

## What `make phase 507` does

The helper is:

```text
vm/phase5/canonical-image-repo-consumption.sh
```

It performs four groups of checks.

### 1. Check image assembly wiring

It verifies that the Phase 4 image materializer understands:

```text
ONIX_IMAGE_REPO_DIR
```

and that the native systemd boot probe checks the selected repo path instead of
hard-coding the older Phase 4 local repo.

This matters because a hidden hard-coded repo path would mean Phase 507 is only
pretending to use the canonical repo.

### Why a wiring check comes before the boot proof

It would be easy to write a Phase 507 that installs from the canonical repo into a
scratch root, boots something, sees SSH work, and declares victory — while the *actual
image assembler* still quietly reads from the old `artifacts/onix-local-repo/`. The
boot would pass and prove nothing about the migration. So the phase first *reads the
source* of the image materializer and the boot probe, grepping them to confirm they
honor `ONIX_IMAGE_REPO_DIR` and consume `file://$IMAGE_REPO_DIR/stone.index` rather
than a baked-in path. Only code that genuinely takes the repo as an input can pass this
check. It is the difference between "the test used the canonical repo" and "the thing
under test uses the canonical repo" — and only the second one is worth anything.

### 2. Check the canonical repo

It checks:

```text
artifacts/onix-repo/unstable/x86_64/stone.index
artifacts/onix-repo/unstable/x86_64/SHA256SUMS
artifacts/onix-repo/unstable/x86_64/MANIFEST.tsv
```

It also verifies exactly one stone for each current essential package:

```text
onix-branding
onix-filesystem
onix-busybox
onix-dropbear
onix-systemd
onix-bootstrap-policy
```

Each stone is checked with:

```text
moss inspect --check
```

### 3. Prove Moss can install the full essential set

The phase installs all current essential packages from the canonical repo into a
throwaway proof root:

```text
artifacts/onix-phase5-work/507/install-target/
```

This is not the boot image yet.

It is a fast package-repo proof.

It proves:

- Moss can read the canonical index;
- every essential package is present;
- any remaining package path ownership warnings are visible in the log;
- the installed target contains the expected system files.

Phase 507 does not make all future ownership warnings fatal. Later Phase 5
stones add more of the system package surface, and one known remaining cleanup is
the musl loader path:

```text
/usr/lib/ld-musl-x86_64.so.1
```

That is a package-ownership cleanup problem for a later phase, not a failure of
the image-repo wiring this phase proves.

### 4. Re-materialize the native system package path from the canonical repo

After the repo proof passes, Phase 507 re-runs the package-owned image
materialization step that is safe on the current native-systemd image with:

```text
ONIX_IMAGE_REPO_DIR=artifacts/onix-repo/unstable/x86_64
```

At this point the image is already past the old bootstrap systemd tree.

That matters.

Some older Phase 4 activation steps rewrote units inside the temporary
bootstrap systemd payload. Those steps were correct earlier, but they should
not be replayed after Phase 422 removed the old bootstrap systemd tree.

So Phase 507 uses two layers of proof:

```text
scratch Moss install proof  -> all current essential packages
image materialization proof -> current native onix-systemd package path
```

The image materialization step consumes the canonical repo for:

```text
onix-systemd
```

The scratch install proof already proved the full essential package set:

```text
onix-branding
onix-filesystem
onix-busybox
onix-dropbear
onix-systemd
onix-bootstrap-policy
```

Then the phase boots the image and proves:

- native `onix-systemd` is PID 1;
- the system still brings up bootstrap networking;
- SSH still works;
- the proof path did not fall back to the old split repo.

## Why this still belongs in Phase 5

Phase 507 does boot the image, but its real subject is not bootloader work or
kernel work.

The real subject is package/repository flow:

```text
canonical package repo -> image assembly -> boot proof
```

The boot proof is only the final safety check.

The phase asks:

```text
Can the same repo shape that we plan to publish also feed image assembly?
```

That is package/repository plane work, so it belongs in Phase 5.

## What this does not do yet

Phase 507 does not publish anything.

It does not upload to:

```text
repo.onix-os.com
```

It also does not solve repo signing, channels, retention policy, or release
promotion.

Those are later repository-publishing concerns.

Phase 507 only proves the local canonical repo is now a real image input.

## Mental model

Before:

```text
old phase repo A ----\
                     image assembly
old phase repo B ----/
```

After:

```text
old phase repo A ----\
                     canonical local repo ---- image assembly
old phase repo B ----/
```

The canonical repo becomes the single package source the image cares about.

That is the important move.

### Single source of truth, stated plainly

Before Phase 507 the image had to *know history*: identity packages here, boot
packages there, and assembly logic that remembered which was which. After Phase 507 the
image knows one address, `artifacts/onix-repo/unstable/x86_64/stone.index`, and asks
moss for packages by name. Every downstream question — "what's in the image?", "can we
reproduce it?", "does the thing we boot match the thing we'll publish?" — now has a
single place to look. That collapse from two historical roots to one canonical source
is the entire point; the boot at the end is just the receipt that proves the collapse
did not break anything.

## What comes next

After Phase 507, ONIX has:

```text
source recipes
  -> .stone packages
  -> canonical local repo
  -> bootable image consuming that repo
```

The next natural repository step is:

```text
508 — local public repository layout
```

That should reshape the canonical local repo into the root-index/history/pool
layout ONIX can later serve from `repo.onix-os.com`, without actually uploading
anything yet.
