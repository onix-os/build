# Phase 204 — define image/disk assembly contract

## At a glance

| Field | Value |
|---|---|
| Phase family | Phase 2 — bootable image |
| Run command | `make phase 204` |
| Underlying make target/script | `vm/phase2/verify-image-contract.sh` |
| Runs on | host |
| Main proof/artifact | Verifies the disk/image contract before loop devices, filesystems, or mounts. |


Phase 204 is deliberately boring and important.

It does **not** create a disk image.
It does **not** partition anything.
It does **not** format filesystems.
It does **not** mount anything.
It does **not** use sudo.

It only verifies that this book page contains the contract for the next layer.

The reason is simple: before we ask Linux for loop devices, partitions, mounts,
and filesystems, we want the target shape written down in human language.
Disk-building mistakes are easy to make and annoying to debug. A contract phase
lets us agree on the shape first.

### Background: a contract phase is a design gate

Several Phase 2 steps (204, 207, 208, 210) build nothing. They are **contract
phases**: their script reads *this very book page* plus the relevant build script
and checks that the two still agree on the plan — the paths, labels, filesystem
types, and boot arguments. If someone edits the disk builder to use a different
label but forgets to update the plan, the contract phase fails. It is a test that
the documentation and the code have not drifted apart.

Why bother? Because the destructive, rootful work is a few steps away, and the
cheapest possible moment to catch "we disagree about the layout" is *before* any
disk exists. Writing the shape down in prose first, then having a script enforce
that the prose matches reality, is much cheaper than debugging a mangled
partition table. So Phase 204 verifies that this page contains the contract text —
`verify-image-contract.sh` literally greps this file for every label, mount point,
and filesystem type below.

#### The artifact names

The canonical root tree input is still:

```text
artifacts/onix-root-tree/
```

The future raw disk image will be:

```text
artifacts/onix-image/onix.raw
```

Temporary mount/work state for image assembly should live under:

```text
artifacts/onix-image-work/
```

All of these paths are under `artifacts/`, so they are generated local build
outputs and are gitignored.

#### Root tree vs disk image, again

The root tree is a directory on the host:

```text
artifacts/onix-root-tree/
```

The disk image is a fake disk file:

```text
artifacts/onix-image/onix.raw
```

The future Phase 205 job is to copy the root tree into a filesystem inside the
disk image:

```text
artifacts/onix-root-tree/
   │
   │ copied into the root partition
   ▼
artifacts/onix-image/onix.raw
```

That raw image can later be attached to QEMU as if it were a real disk.

#### Planned GPT partition table

The first ONIX image should use GPT.

GPT is the modern partition-table format used by UEFI systems. It lets one disk
contain several named partitions. Names matter here because ONIX will mount
partitions by label instead of by fragile device names.

> **GPT, ESP, and XBOOTLDR, defined.** A **partition table** is the map at the
> start of a disk that says "bytes X to Y are partition 1", and so on. **GPT**
> (GUID Partition Table) is the UEFI-era format; it replaced the old MBR scheme
> and supports many partitions, each with a name and a type GUID. Two of ONIX's
> partitions have special roles the firmware and bootloader know about:
> - The **ESP** (EFI System Partition) is the FAT partition UEFI firmware reads at
>   power-on to find an `.efi` program to run. It is small and firmware-facing.
>   ONIX mounts it at `/efi`.
> - **XBOOTLDR** is an optional second boot partition defined by the Boot Loader
>   Specification. It holds the bulky kernels and initramfs images, so the ESP can
>   stay small. ONIX mounts it at `/boot` (label `ONIX-BOOT`). systemd-boot reads
>   BLS entries and kernels from here.
>
> Splitting ESP from XBOOTLDR is why ONIX has *two* FAT boot partitions instead of
> one — it keeps the firmware-visible surface tiny while giving the kernels room.

The contract is:

| # | Label | Filesystem | Mount point | Early purpose |
|---|---|---|---|---|
| 1 | `ONIX-ESP` | `vfat` | `/efi` | EFI System Partition for firmware-visible boot files later |
| 2 | `ONIX-BOOT` | `vfat` | `/boot` | kernel/initramfs/BLS/systemd-boot files later |
| 3 | `onix-root` | `xfs` | `/` | generated ONIX root filesystem from `artifacts/onix-root-tree/` |
| 4 | `ONIX-PERSIST` | `xfs` | `/persist` | persistent machine data such as homes and Nix store later |

Proposed early sizes:

```text
ONIX-ESP      512 MiB
ONIX-BOOT       1 GiB
onix-root       8 GiB minimum for the first image
ONIX-PERSIST    rest of the disk
```

Those sizes can change later, but the labels and mount roles are the important
contract.

#### Why `vfat` for `/efi` and `/boot`

UEFI firmware understands the EFI System Partition as a FAT filesystem. In
Linux tools that usually means `vfat`.

So `/efi` must be `vfat`.

For the first image, `/boot` is also planned as `vfat` because it keeps the boot
partition simple and readable by the early boot tooling. Later we can revisit
that if the real boot model needs a different split.

The first fstab marks `/efi` and `/boot` as `nofail`.

That is deliberate. The machine can reach userspace without those partitions
mounted. During early bootstrap we may not yet have the final kernel-module and
`modprobe` policy needed for vfat mounts after switch-root. A failed `/efi` or
`/boot` mount should be visible in logs, but it should not force the whole boot
into emergency mode.

#### Why `xfs` for `/` and `/persist`

The root and persist partitions are Linux-owned filesystems. They need normal
Unix permissions, symlinks, device-node support, and good behavior for large
trees.

So the contract uses `xfs` for:

```text
/
/persist
```

The Phase 1 `filesystem` package already emits the same policy in the
default fstab template:

```text
LABEL=ONIX-ESP      /efi      vfat  rw,relatime,noatime,nofail,x-systemd.device-timeout=10s
LABEL=ONIX-BOOT     /boot     vfat  rw,relatime,noatime,nofail,x-systemd.device-timeout=10s
LABEL=onix-root     /         xfs
LABEL=ONIX-PERSIST  /persist  xfs
```

That is the reason Phase 200 checks for `mkfs.xfs`.

#### Why labels instead of `/dev/vda3`

Inside Linux, disks appear with names like:

```text
/dev/vda
/dev/sda
/dev/nvme0n1
```

Partitions appear as:

```text
/dev/vda1
/dev/vda2
/dev/vda3
```

Those names depend on the virtual hardware, boot order, and driver timing.
They are not the identity of the filesystem.

Filesystem labels are much more stable:

```text
LABEL=onix-root
LABEL=ONIX-PERSIST
```

That is why the ONIX fstab contract mounts by label.

#### What gets copied into `/`

The root partition labeled `onix-root` receives the contents of:

```text
artifacts/onix-root-tree/
```

That means this host file:

```text
artifacts/onix-root-tree/usr/lib/os-release
```

becomes this file inside the future machine:

```text
/usr/lib/os-release
```

And this host symlink:

```text
artifacts/onix-root-tree/etc/os-release -> ../usr/lib/os-release
```

becomes:

```text
/etc/os-release -> ../usr/lib/os-release
```

#### What does not get copied as real data

Some directories are mount points or runtime filesystems:

```text
/dev
/proc
/sys
/run
```

They should exist as directories in the image, but their contents are created or
mounted at boot. We do not copy host `/dev` into the image. We do not copy host
`/proc`. Those are views of the running host kernel, not package payload.

`/persist` is also a mount point. The image will have an `ONIX-PERSIST`
partition mounted there. Later ONIX can bind persistent paths from it:

```text
/persist/home -> /home
/persist/nix  -> /nix
```

> **Why one persistence partition.** ONIX's whole design goal is that the machine
> plane (`/usr`, kernel, boot) is disposable and atomically rolled back, while the
> things you actually *care about* live somewhere a rollback never touches. That
> somewhere is `ONIX-PERSIST`. `/home` (your files) and `/nix` (the Nix toolbox's
> store, added in Phase 3) are bind-mounted out of it, so a single partition is the
> one surface to back up. A moss rollback rewinds `/usr`; it does not touch
> `/persist`. This is the concrete shape of the "two planes" split — the machine
> plane on `onix-root`, the durable state on `ONIX-PERSIST`.

#### What Phase 204 checks

`make phase 204` verifies:

- this Phase 204 section exists
- the future disk path is `artifacts/onix-image/onix.raw`
- the source root tree path is `artifacts/onix-root-tree/`
- all required labels are documented:
  - `ONIX-ESP`
  - `ONIX-BOOT`
  - `onix-root`
  - `ONIX-PERSIST`
- all required mount points are documented:
  - `/efi`
  - `/boot`
  - `/`
  - `/persist`
- the contract mentions both `vfat` and `xfs`
- the current root tree still contains `/usr/lib/os-release`
- the current root tree fstab still references the planned labels

This makes Phase 204 a safe checkpoint between "we can assemble files" and "we
are about to create filesystems".

#### What Phase 204 does not prove

Phase 204 does not prove booting.

At this point ONIX still does not have:

```text
kernel package
initramfs policy
systemd package
systemd-boot installation
BLS entries
real first userspace path
```

So the next disk phase should be a **non-booting** skeleton first. That lets us
verify partition creation and root-tree copy before mixing in boot complexity.

The immediate sequence after this contract is:

```text
Phase 205 -> create the non-booting disk/root skeleton
Phase 206 -> install the systemd-boot/BLS skeleton
```
