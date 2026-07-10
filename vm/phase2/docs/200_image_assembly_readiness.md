# Phase 200 — image assembly readiness

## At a glance

| Field | Value |
|---|---|
| Phase family | Phase 2 — bootable image |
| Run command | `make phase 200` |
| Underlying make target/script | `vm/phase2/check-readiness.sh` |
| Runs on | host |
| Main proof/artifact | Confirms Phase 2 has repo artifacts and image tools available. |


Phase 200 is host-only. It does not boot QEMU, does not SSH into the forge, and
does not build an image yet.

## Why a readiness step exists at all

The rest of Phase 2 is expensive and, in places, rootful: it attaches loop
devices, writes GPT partition tables, formats XFS and FAT filesystems, and mounts
things as root. Failures that deep are miserable to debug, and the most common
cause is boring — a missing tool, or a stale input from an earlier phase. Phase
200 front-loads all of those cheap checks into one fast, unprivileged gate. If
200 is green, a later disk failure is almost certainly a *real* image problem,
not "you forgot to enter the dev shell". This is the same "shrink the debugging
surface" discipline that shapes the whole phase.

## What it verifies

It verifies:

- Phase 1 exported repo artifact exists at `artifacts/onix-publish/`
- `SHA256SUMS` validates through the Phase 1 verifier
- `onix-branding` and `onix-filesystem` stones exist
- no forbidden brand spelling exists in tracked project areas
- host/dev-shell has the tools needed for image assembly

Walking those in order:

**The exported repo artifact.** Phase 200 re-runs Phase 1's own
`verify-exported-repo.sh` against `artifacts/onix-publish/`, then checks that the
per-arch repo directory (`unstable/x86_64/`) contains a `stone.index` and a
`SHA256SUMS`. The `stone.index` is moss's catalogue of what is in the repo; the
`SHA256SUMS` lets a consumer prove each `.stone` arrived intact. Together they
are the *input contract* for image assembly — the repo has to be a real, checked
repo, not a loose folder of files.

> **What is a moss repo?** It is a directory of `.stone` files plus an index that
> moss reads. ONIX serves it as `file://` locally now and static HTTPS later.
> There is only one repo (`onix`); nothing sits beneath it. Phase 2 consumes this
> repo exactly the way a real installer would.

**Exactly one branding + one filesystem stone.** The script counts
`onix-branding-*.stone` and `onix-filesystem-*.stone` and insists on *exactly
one* of each. Two would mean an old build was never cleaned up, and image
assembly could silently pick the wrong one. These two packages are the entire
payload of the first image: `onix-branding` ships the identity
(`/usr/lib/os-release`, the logo), and `onix-filesystem` ships the default
`/etc` templates and the fstab that describes the disk layout.

**No forbidden brand spelling.** ONIX branding is always `ONIX` or `onix`, never
mixed case. The script greps the whole tree (excluding `.git`, `artifacts`, and
build state) for the forbidden mixed-case spelling and fails if it appears. This
keeps the identity consistent everywhere before it gets baked into a disk.

**The image tools.** The script checks that the dev shell actually provides the
tools the later steps call. Important future image tools include:

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

Each maps to a concrete job later: `truncate` creates the empty raw image file,
`losetup` presents that file to the kernel as a fake disk, `sgdisk` writes the
GPT partition table, `partprobe` re-reads it, the `mkfs.*` family formats each
partition, `mount`/`umount` attach them, and `tar` streams the root tree in. The
script also confirms `bootctl` and a `systemd-bootx64.efi` binary are reachable —
those are needed by step 206 to install the bootloader.

`mkfs.xfs` matters because Phase 1's filesystem template already describes the
future ONIX root and persist filesystems as XFS:

```text
LABEL=onix-root     /         xfs
LABEL=ONIX-PERSIST  /persist  xfs
```

> **Why XFS for root?** The machine plane holds `/.moss` — moss's content store
> plus every retained transaction state. More disk means more rollback history.
> XFS handles large trees and many hardlinks well, which is exactly moss's access
> pattern. The boot partitions, by contrast, must be FAT so UEFI firmware can
> read them; see step 204.

## The reload gotcha

If `make phase 200` says `mkfs.xfs` is missing, re-enter the dev shell:

```sh
direnv reload
```

The flake includes `xfsprogs`, so the command should appear after the updated
environment loads. The same applies to `bootctl`/`systemd-bootx64.efi`: those
come from the flake too, exported as `ONIX_SYSTEMD_BOOT_EFI`. A "missing tool"
here almost never means the tool is unavailable — it means the current shell
predates the flake change that added it, and a reload fixes it.

## What Phase 200 proves vs does not prove

Phase 200 proves the *preconditions* for image work: the inputs exist and are
verified, and the host can do the work. It proves nothing about the image itself
— no disk is created, no partition is written, nothing is mounted or booted. It
is purely a gate. The very next step (203, via 201/202) is the first one that
turns the repo into a directory tree; from there the disk work begins.
