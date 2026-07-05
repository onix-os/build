# Phase 2 — first bootable ONIX image

Phase 0 built the forge.

Phase 1 built the first real ONIX stones and exported a clean host-side repo
artifact.

Phase 2 starts the real distro-image work: taking ONIX packages from the repo
artifact and turning them into an ONIX root/image.

We start with one small gate.

## Phase commands

```sh
make phase 200
```

The format is still three digits. `200` means "Phase 2, step 00". Running:

```sh
make phase 2
```

runs every Phase 2 step currently defined. Right now that is only `200`.

### Phase 200 — image assembly readiness

Phase 200 is host-only. It does not boot QEMU, does not SSH into the forge, and
does not build an image yet.

It verifies:

- Phase 1 exported repo artifact exists at `artifacts/onix-publish/`
- `SHA256SUMS` validates through the Phase 1 verifier
- `onix-branding` and `onix-filesystem` stones exist
- no forbidden brand spelling exists in tracked project areas
- host/dev-shell has the tools needed for image assembly

Important future image tools include:

```text
sgdisk
partprobe
losetup
mkfs.fat
mkfs.ext4
mkfs.xfs
mount
umount
truncate
tar
sha256sum
```

`mkfs.xfs` matters because Phase 1's filesystem template already describes the
future ONIX root and persist filesystems as XFS:

```text
LABEL=onix-root     /         xfs
LABEL=ONIX-PERSIST  /persist  xfs
```

If `make phase 200` says `mkfs.xfs` is missing, re-enter the dev shell:

```sh
direnv reload
```

The flake includes `xfsprogs`, so the command should appear after the updated
environment loads.

## What comes after 200?

Do not jump straight to booting yet.

The next safe progression should be:

```text
201 = create first ONIX root tree from exported repo packages
202 = define image assembly contract in this README
203 = create first non-booting disk/root skeleton
204 = add boot path
```

The key learning point: Phase 2 is where we stop proving packages in disposable
targets and start assembling the actual ONIX machine layout.
