# Phase 205 — create first non-booting disk/root skeleton

## At a glance

| Field | Value |
|---|---|
| Phase family | Phase 2 — bootable image |
| Run command | `make phase 205` |
| Underlying make target/script | `vm/phase2/build-image-skeleton.sh` |
| Runs on | host with rootful loop/mount/filesystem work |
| Main proof/artifact | Creates artifacts/onix-image/onix.raw as a non-booting disk/root skeleton. |


Phase 205 is the first phase that creates the real future ONIX disk shape.

Everything before this was files in directories. Phase 205 is the first step that
produces an actual *disk*: a partition table, real filesystems, and the root tree
copied into them. It is where the abstract "root tree contract" from 203/204
becomes bytes laid out exactly the way a physical disk would be.

It takes this directory:

```text
artifacts/onix-root-tree/
```

and creates this raw disk image:

```text
artifacts/onix-image/onix.raw
```

This is a **raw** disk image, meaning it is just bytes arranged like a normal
disk. QEMU can later attach it as a virtual disk.

> **What a raw disk image is.** A `.raw` image is a plain file whose bytes are
> the literal contents of a disk, from sector 0 onward: partition table first,
> then each partition's filesystem. There is no compression and no wrapper (unlike
> qcow2). That simplicity is the point — the same bytes that sit in this file
> would sit on a real SSD, so `dd`-ing it to a USB stick would produce a bootable
> disk, and QEMU can attach it directly.

Phase 205 is rootful because Linux only lets root do some disk operations:

```text
losetup     attach file as loop disk
sgdisk      write partition table
mkfs.*      create filesystems
mount       mount filesystems
umount      unmount filesystems
```

The script follows the same pattern as the forge disk builder: it starts as
your user, then re-execs itself through `sudo` only when root is needed. Run
`make doctor` or `make phase 001` once if the passwordless builder rule needs
to be refreshed.

> **Why re-exec through sudo instead of running the whole thing as root.** Most of
> the script (path math, verification, reading the root tree) needs no privileges,
> and running everything as root is a good way to turn a small bug into a
> system-wide mess. So the script does the privileged block — loop attach, format,
> mount, copy, unmount, detach — under sudo, and guards it: a `safe_generated_paths`
> check refuses to operate on anything outside `artifacts/onix-image/*.raw` and
> `artifacts/onix-image-work/`. Even as root, it can only touch the generated image,
> never a real host disk.

#### What Phase 205 creates

The generated image path is:

```text
artifacts/onix-image/onix.raw
```

Default size:

```text
12 GiB
```

The default partition plan is:

| # | Label | Filesystem | Size | Mount during assembly |
|---|---|---|---|---|
| 1 | `ONIX-ESP` | `vfat` | 512 MiB | `/efi` |
| 2 | `ONIX-BOOT` | `vfat` | 1 GiB | `/boot` |
| 3 | `onix-root` | `xfs` | 8 GiB | `/` |
| 4 | `ONIX-PERSIST` | `xfs` | rest | `/persist` |

The sizes can be overridden later with environment variables:

```text
ONIX_IMAGE_SIZE
ONIX_IMAGE_ESP_SIZE
ONIX_IMAGE_BOOT_SIZE
ONIX_IMAGE_ROOT_SIZE
```

#### What a loop device is

The image is a normal file on the host:

```text
artifacts/onix-image/onix.raw
```

But partitioning tools expect a block device, not a regular file.

Linux loop devices solve that. `losetup` temporarily presents the file as a
fake disk:

```text
artifacts/onix-image/onix.raw
   │
   │ losetup
   ▼
/dev/loopX
```

Then partitions appear as:

```text
/dev/loopXp1
/dev/loopXp2
/dev/loopXp3
/dev/loopXp4
```

When the phase finishes, it unmounts the filesystems and detaches the loop
device. The final artifact is only the `.raw` file.

#### What gets copied

Phase 205 mounts the `onix-root` partition and copies the root tree into it:

```text
artifacts/onix-root-tree/  ->  onix-root filesystem mounted at /
```

It uses tar with "do not preserve host owner" behavior (`--no-same-owner`) so
files inside the image become `root:root`, not `bresilla:bresilla`.

> **Why ownership has to be rewritten.** The root tree was built by your
> unprivileged user on the host, so its files are owned by your UID. But inside a
> booted machine, system files must be owned by `root` (UID 0). Piping the tree
> through `tar ... | tar --no-same-owner` drops the host ownership on extract, so
> every file lands as `root:root` in the image. Getting this wrong would leave a
> machine whose `/usr/lib/os-release` is owned by a user that does not exist there.

That matters because this host-owned file:

```text
artifacts/onix-root-tree/usr/lib/os-release
```

must become this root-owned file inside the image:

```text
/usr/lib/os-release
```

#### What Phase 205 adds after the copy

The root tree has the main OS payload and mount points.

The disk assembly phase also creates persistent bind-source directories on the
`ONIX-PERSIST` partition:

```text
/persist/home
/persist/nix
```

and ensures the root filesystem has the bind target:

```text
/nix
```

That matches the default fstab lines:

```text
/persist/home       /home     none  bind
/persist/nix        /nix      none  bind
```

#### What Phase 205 verifies

> **GPT partition names vs filesystem labels — two different things.** A GPT
> *partition name* lives in the partition table and names the *slot*. A
> *filesystem label* lives inside the formatted filesystem and names the
> *contents*. ONIX sets both (e.g. partition named `onix-root`, XFS labelled
> `onix-root`) and 205 checks both, because the fstab mounts by *filesystem*
> label — so the label inside the XFS, not just the partition slot, has to be
> right.

`make phase 205` verifies:

- Phase 204 contract still passes
- GPT partition names are correct
- filesystem labels are correct
- filesystem types are correct
- `/usr/lib/os-release` exists in the root filesystem
- copied files are root-owned inside the image
- `/tmp` is still mode `1777`
- `/etc/fstab` still refers to the planned labels
- `/persist/home`, `/persist/nix`, and `/nix` exist
- no EFI loader exists yet

The last check is intentional. If Phase 205 finds:

```text
/efi/EFI/BOOT/BOOTX64.EFI
```

it fails, because that would mean we accidentally started bootloader work too
early.

#### Why Phase 205 is still not bootable

A disk can have a correct root filesystem and still not boot.

To boot, it also needs things like:

```text
kernel
initramfs
init system
bootloader
bootloader entries
kernel command line
```

Phase 205 avoids all of that on purpose. It proves only:

```text
root tree -> real partitioned disk image
```

That keeps the debugging surface small. If Phase 205 passes, then a future boot
failure is probably in the boot layer, not in the root-tree-copy layer.

