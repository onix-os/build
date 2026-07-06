# Phase 2 — first bootable ONIX image

Phase 0 built the forge.

Phase 1 built the first real ONIX stones and exported a clean host-side repo
artifact.

Phase 2 starts the real distro-image work: taking ONIX packages from the repo
artifact and turning them into an ONIX root/image.

We start with one small gate.

## About `make phase 2`

`make phase 2` runs the canonical host-native Phase 2 path:

```text
200 -> 202 -> 203 -> 204 -> 205 -> 206 -> 207 -> 208 -> 209 -> 210 -> 211
```

It intentionally does not include Phase 201.

Phase 201 is still available as an individual learning step:

```sh
make phase 201
```

But Phase 201 uses the forge VM over SSH. After Phase 202, ONIX has host-side
`moss`, so the normal image-assembly path no longer needs the forge VM for root
tree assembly.

That is why the aggregate path uses:

```text
Phase 203 = host-native root tree assembly
```

## Basic mental model: what is a root tree?

A Linux system is mostly a filesystem.

When people say "the root filesystem", they mean the filesystem mounted at:

```text
/
```

That `/` is called the **root** because every absolute path starts from it:

```text
/etc/os-release
/usr/bin/sh
/home
/var
/tmp
```

A **root tree** is the same layout, but just sitting in a normal host
directory, not booted yet.

In this repo our generated root tree is:

```text
artifacts/onix-root-tree/
```

Inside that directory you see paths that will eventually become the VM's `/`:

```text
artifacts/onix-root-tree/etc
artifacts/onix-root-tree/usr
artifacts/onix-root-tree/boot
artifacts/onix-root-tree/var
artifacts/onix-root-tree/tmp
```

So this host path:

```text
artifacts/onix-root-tree/etc/os-release
```

means:

```text
/etc/os-release
```

inside the future ONIX machine.

### Root tree vs disk image

A root tree is only files and directories.

A disk image is a fake disk file with partitions and filesystems.

They are different layers:

```text
root tree directory
   │
   │ copied into a filesystem
   ▼
disk image
   │
   │ booted by QEMU
   ▼
running machine
```

Phase 201 and 203 only create the root tree. They do **not** create a disk.

### How Linux uses the root filesystem when booting

Very simplified boot flow:

```text
firmware
  -> bootloader
  -> kernel
  -> initramfs maybe
  -> mount real root filesystem at /
  -> run first userspace program
```

The important part for Phase 2 is:

```text
kernel needs a root filesystem mounted at /
```

Once the kernel has `/`, it can start using normal paths:

```text
/sbin/init
/usr/lib/systemd/systemd
/bin/sh
/etc/fstab
/etc/os-release
```

Right now ONIX does not have the boot pieces yet:

```text
kernel package       not yet
init system          not yet
bootloader config    not yet
disk partitions      not yet
```

So our root tree is not bootable yet. But it is still a real milestone because
it is the filesystem content that a future boot will mount as `/`.

### What common root directories are for

These are the basic meanings we care about now:

```text
/usr      package-owned operating-system files
/etc      machine configuration
/boot     kernel/initramfs/boot files later
/efi      EFI System Partition mount point later
/var      variable machine data
/home     user homes later
/persist  persistent data for installed ONIX systems later
/tmp      temporary files; must be mode 1777
/dev      device files, created by kernel/userspace at runtime
/proc     kernel process/info filesystem, mounted at runtime
/sys      kernel device/info filesystem, mounted at runtime
/run      runtime state, mounted/created at runtime
```

Important distinction:

```text
/usr comes mostly from packages
/etc is assembled from policy/defaults plus machine-specific choices
/dev, /proc, /sys, /run are not package payload; they are runtime filesystems
```

That is why Phase 201/203 creates empty mount-point directories for `/dev`,
`/proc`, `/sys`, and `/run`, but does not fill them with package files.

### Why ONIX packages install mostly into `/usr`

ONIX follows a simple rule:

```text
moss owns the machine payload
local/admin state lives outside immutable package payloads
```

So our early packages install stable OS content under `/usr`:

```text
/usr/lib/os-release
/usr/share/onix/filesystem-layout.md
/usr/share/defaults/etc/fstab
```

Then image assembly creates live machine glue under `/etc`:

```text
/etc/os-release -> ../usr/lib/os-release
/etc/fstab
/etc/motd
/etc/hostname
```

This keeps packages clean and makes later image/boot policy explicit.

## Phase commands

```sh
make phase 200
make phase 201
make phase 202
make phase 203
make phase 204
make phase 205
make phase 206
make phase 207
```

The format is still three digits. `200` means "Phase 2, step 00". Running:

```sh
make phase 2
```

runs every Phase 2 step currently defined. Right now that is `200..207`.

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

### Phase 201 — assemble the first ONIX root tree

Phase 201 is the first big conceptual jump in Phase 2.

Before this point, we proved packages in disposable Moss test targets. Phase
201 starts acting like an image builder:

```text
exported repo artifact -> package install -> root filesystem tree
```

It still does **not** create a disk image. It does **not** partition anything.
It does **not** mount anything. It does **not** boot. The output is just a
directory tree on the host:

```text
artifacts/onix-root-tree/
```

That directory is gitignored because it is generated build output.

#### Why Phase 201 uses the forge

When Phase 201 was introduced, the host did not yet have `moss`.

Also, `.stone` files are not tarballs. They are Moss stone containers. That
means Phase 201 should not pretend the host can unpack them with `tar`.

So the Phase 201 flow is:

```text
host artifacts/onix-publish/
   │
   │  stream to forge
   ▼
forge moss install --to root-tree
   │
   │  materialize image-owned /etc glue
   ▼
forge root-tree/
   │
   │  tar stream back to host
   ▼
host artifacts/onix-root-tree/
```

This is temporary bootstrap architecture, but it is honest. Phase 201 remains a
useful bridge/proof, even after Phase 202 adds host-side Moss, because it shows
the exact point where the forge used to be required.

#### What the packages provide

The root tree receives package-owned files from:

```text
onix-branding
onix-filesystem
```

Important package-owned files include:

```text
/usr/lib/os-info.json
/usr/lib/os-release
/usr/share/onix/branding/logo.txt
/usr/share/onix/branding/logo.ansi
/usr/share/onix/filesystem-layout.md
/usr/share/defaults/etc/fstab
/usr/share/defaults/etc/issue
/usr/share/defaults/etc/motd
/usr/share/defaults/etc/profile.d/onix-path.sh
```

The important design rule stays the same:

```text
packages own /usr
image assembly owns root-level machine glue
```

That is why `onix-branding` and `onix-filesystem` ship defaults under
`/usr/share/defaults/etc/` instead of directly owning live `/etc`.

#### What image assembly materializes

Phase 201 creates the first root-level machine view:

```text
/etc/os-release -> ../usr/lib/os-release
/etc/issue
/etc/motd
/etc/fstab
/etc/profile.d/onix-path.sh
/etc/hostname

/boot
/dev
/efi
/home
/persist
/proc
/run
/sys
/tmp
/var
```

This is not random copying. It is the first image-assembly policy:

- `/etc/os-release` is a compatibility symlink to the Moss-generated identity
  file under `/usr/lib`.
- `/etc/issue`, `/etc/motd`, `/etc/fstab`, and `/etc/profile.d/onix-path.sh`
  are materialized from packaged defaults.
- runtime/kernel directories such as `/dev`, `/proc`, `/sys`, and `/run` are
  created as empty mount points/placeholders. They are not package payload.
- `/tmp` gets sticky permissions because users/processes share it.

#### What Phase 201 proves

Phase 201 proves:

- the host-exported repo artifact is usable as an image input
- the forge can install from that copied artifact by repo index
- `onix-branding` and `onix-filesystem` compose into one root tree
- image-owned `/etc` materialization is separated from package payload
- the result can be exported back to the host as a clean artifact

It also verifies:

- `/usr/lib/os-release` says `NAME="ONIX"` and `ID="onix"`
- `ANSI_COLOR` matches the real ONIX blue
- the ONIX terminal logo exists
- `/etc/os-release` is the correct relative symlink
- fstab contains `onix-root` and `ONIX-PERSIST`
- no forbidden mixed-case brand spelling appears
- Moss assembly state does not leak into the exported root tree

#### What Phase 201 does not prove

Phase 201 does **not** prove bootability.

The root tree still has no real ONIX kernel package, no init system package, no
bootloader installation, no partition table, and no mounted filesystems. Those
are later Phase 2 steps.

The point of this phase is to make the next step smaller. After 201, disk image
work can consume a known-good root tree instead of solving packaging,
repository, filesystem policy, and disk layout all at once.

### Phase 202 — build host-side Moss

Phase 202 is the next bootstrap cleanup.

Phase 201 proved that the exported repo can become a root tree, but it still
used Moss inside the forge:

```text
host repo artifact -> forge moss -> host root tree
```

That is useful, but it is not where we want to stay. The forge is temporary
bootstrap scaffolding. Image assembly should become host-native:

```text
host repo artifact -> host moss -> host root tree -> disk image
```

Phase 202 builds a host-side `moss` binary from the same pinned `os-tools`
source used by Phase 0:

```text
artifacts/host-tools/bin/moss
```

It requires Rust `>= 1.91`. The ONIX flake provides a new enough toolchain. If
your shell still reports an older `rustc`, reload the dev shell:

```sh
direnv reload
```

or run the phase explicitly through Nix:

```sh
nix develop --impure -c make phase 202
```

It also records the source pin at:

```text
artifacts/host-tools/os-tools.source
artifacts/host-tools/os-tools.git-deps
```

That file is generated and gitignored with the rest of `artifacts/`.

#### Source policy

ONIX currently treats AerynOS `os-tools` as pinned bootstrap tooling.

The current source of truth is still:

```text
OS_TOOLS_REPO=https://github.com/AerynOS/os-tools.git
OS_TOOLS_REF=36f78e5bcfa9d594d65d1c6d2e332e950f3e4d0e
```

The pinned commit protects ONIX from upstream code changes.

It does **not** protect ONIX from source availability problems such as:

- upstream repository deletion
- upstream repository rename
- GitHub outage
- git dependency disappearing

So the future source-control policy should be:

```text
1. mirror/fork os-tools into github.com/onix-os/os-tools
2. keep the exact same commit first
3. switch OS_TOOLS_REPO to the ONIX mirror
4. only diverge on an ONIX branch when ONIX needs patches
```

That means the first ONIX mirror step is boring on purpose. It is availability
insurance, not a fork-war.

`os-tools` may also contain git dependencies such as boot tooling crates. When
we switch to ONIX mirrors, we must audit the `Cargo.toml`/`Cargo.lock` graph and
mirror every git dependency that matters for reproducible bootstrap.

At the current pin, Phase 202 records these git dependencies:

```text
https://github.com/AerynOS/blsforme.git?rev=680720545303e123e47e0df07a8a85178c9f5c19
https://github.com/AerynOS/disks-rs?rev=d08bc11dcfb2ad4d031e2adccb97139f9d42c2b8
https://github.com/AerynOS/ent.git?rev=42416ecae36c0f29e07647747147672448241f85
https://github.com/AerynOS/os-info?rev=26b39c1d49c3b4f30d778729fb56958824c069de
https://github.com/kdl-org/kdl-rs?rev=e9df058c25cd4486df8fe568d2ff24ea2c4ed0e8
```

The ONIX mirror priority should be the AerynOS-owned dependencies first:

```text
os-tools
blsforme
disks-rs
ent
os-info
```

`kdl-rs` is not AerynOS-owned, but it is still a pinned git dependency. We can
leave it upstream for now or mirror it later if we want fully independent
bootstrap availability.

#### What Phase 202 proves

Phase 202 proves:

- the host dev shell has enough Rust/build tooling to compile Moss
- the host can fetch and checkout the exact same pinned `os-tools` ref
- the resulting host binary runs
- ONIX has a generated host-tool location for future phases

It does **not** yet replace Phase 201.

That replacement should be a separate phase so the learning step is obvious:

```text
203 = rebuild root tree using host Moss only
```

At that point the flow becomes:

```text
artifacts/onix-publish/
   │
   ▼
artifacts/host-tools/bin/moss install --to artifacts/onix-root-tree
```

No SSH, no forge copy, no forge Moss.

### Phase 203 — assemble the root tree with host-side Moss only

Phase 203 is the replacement for Phase 201.

It consumes the same Phase 1 exported repo artifact:

```text
artifacts/onix-publish/
```

and the host-side Moss binary from Phase 202:

```text
artifacts/host-tools/bin/moss
```

Then it builds the canonical root tree directly on the host:

```text
artifacts/onix-root-tree/
```

The Phase 203 flow is:

```text
host artifacts/onix-publish/
   │
   ▼
host artifacts/host-tools/bin/moss install --to root-tree
   │
   ▼
host materializes image-owned /etc glue
   │
   ▼
host artifacts/onix-root-tree/
```

There is no SSH. There is no forge copy. There is no forge Moss.

#### Why Phase 203 matters

This is the point where image assembly becomes host-native.

Before Phase 203, the host could hold artifacts, but the forge still understood
the package format. After Phase 203, the host understands the package format
too.

That changes the role of the forge:

```text
before 203: forge is needed for root tree assembly
after 203:  forge is only bootstrap/build scaffolding
```

Future disk-image steps should consume the host-built root tree from Phase 203,
not the bridge root tree from Phase 201.

#### Phase 201 vs Phase 203

Both phases produce:

```text
artifacts/onix-root-tree/
```

But the assembly path is different:

```text
201: host repo -> forge moss -> host root tree
203: host repo -> host moss  -> host root tree
```

Phase 203 intentionally overwrites the same canonical artifact path because the
disk builder should not care how the tree was assembled. It only cares that the
root tree contract is satisfied.

#### What Phase 203 verifies

Phase 203 verifies:

- Phase 200 readiness still passes
- Phase 1 exported repo artifact is clean
- host Moss exists and matches the pinned `OS_TOOLS_REF`
- `SHA256SUMS` validates
- host Moss can add the local repo index
- host Moss can install `onix-branding` and `onix-filesystem`
- `/usr/lib/system-model.kdl` records the installed packages
- `/etc/os-release` points to `../usr/lib/os-release`
- `/etc/fstab` contains `onix-root` and `ONIX-PERSIST`
- `/tmp` has sticky `1777` permissions
- no Moss assembly state leaks into the root tree
- no forbidden mixed-case brand spelling appears

The generated `system-model.kdl` should now mention:

```text
ONIX Phase 203 host image assembly repo
```

That tells us the root tree was produced by the host-native path, not the
earlier forge path.

### Phase 204 — define image/disk assembly contract

Phase 204 is deliberately boring and important.

It does **not** create a disk image.
It does **not** partition anything.
It does **not** format filesystems.
It does **not** mount anything.
It does **not** use sudo.

It only verifies that this README contains the contract for the next layer.

The reason is simple: before we ask Linux for loop devices, partitions, mounts,
and filesystems, we want the target shape written down in human language.
Disk-building mistakes are easy to make and annoying to debug. A contract phase
lets us agree on the shape first.

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

#### Why `xfs` for `/` and `/persist`

The root and persist partitions are Linux-owned filesystems. They need normal
Unix permissions, symlinks, device-node support, and good behavior for large
trees.

So the contract uses `xfs` for:

```text
/
/persist
```

The Phase 1 `onix-filesystem` package already emits the same policy in the
default fstab template:

```text
LABEL=ONIX-ESP      /efi      vfat
LABEL=ONIX-BOOT     /boot     vfat
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

### Phase 205 — create first non-booting disk/root skeleton

Phase 205 is the first phase that creates the real future ONIX disk shape.

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

It uses tar with "do not preserve host owner" behavior so files inside the
image become `root:root`, not `bresilla:bresilla`.

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

### Phase 206 — install the systemd-boot/BLS skeleton

Phase 206 starts the boot layer, but still does not pretend the OS can fully
boot yet.

The basic boot chain we are building toward is:

```text
UEFI firmware
  -> EFI loader on ONIX-ESP
  -> systemd-boot
  -> BLS entry on ONIX-BOOT
  -> kernel
  -> initramfs
  -> mount onix-root as /
  -> run /usr/lib/systemd/systemd
```

Phase 206 installs only the first bootloader/config part:

```text
UEFI firmware
  -> systemd-boot
  -> BLS entry
```

It does **not** install:

```text
kernel
initramfs
systemd userspace
```

So the image is still not a complete bootable ONIX system. That is intentional.

If Phase 200 or 206 says `bootctl` or `systemd-bootx64.efi` is missing, reload
the dev shell:

```sh
direnv reload
```

`flake.nix` exports the host-side `ONIX_SYSTEMD_BOOT_EFI` path used by this
phase.

#### Why systemd-boot, not GRUB

For the real ONIX image, we want the simple UEFI path:

```text
UEFI + systemd-boot + Boot Loader Specification entries
```

GRUB was useful in Phase 0 because Alpine needed a practical throwaway forge
boot path. ONIX itself should not inherit that forge choice.

systemd-boot is smaller and more direct:

```text
EFI binary on /efi
plain text loader config
plain text boot entries
```

That makes it easier to understand and easier to generate.

#### What the ESP is for

`ONIX-ESP` is mounted at:

```text
/efi
```

UEFI firmware reads this partition before Linux is running. That means it must
contain the EFI executable that firmware can launch.

Phase 206 writes:

```text
/efi/EFI/systemd/systemd-bootx64.efi
/efi/EFI/BOOT/BOOTX64.EFI
/efi/loader/loader.conf
```

`BOOTX64.EFI` is the standard removable-media path. OVMF/QEMU can find it without us
writing host EFI variables.

#### What ONIX-BOOT is for

`ONIX-BOOT` is mounted at:

```text
/boot
```

It is the future boot asset partition. Phase 206 writes the future BLS entry:

```text
/boot/loader/entries/onix-phase-206.conf
```

That entry points to future kernel paths:

```text
/boot/ONIX/vmlinuz
/boot/ONIX/initramfs.img
```

The entry also says the future kernel should mount:

```text
root=LABEL=onix-root
```

and then start:

```text
init=/usr/lib/systemd/systemd
```

Those files do not exist yet. That is why Phase 206 is a boot skeleton, not a
boot success phase.

#### What BLS means

BLS means **Boot Loader Specification**.

For us, the important idea is simple: boot entries are normal text files.

Instead of hiding boot configuration inside a generated GRUB config, ONIX can
write a file like:

```text
title ONIX
linux /ONIX/vmlinuz
initrd /ONIX/initramfs.img
options root=LABEL=onix-root rw init=/usr/lib/systemd/systemd
```

That is easy to inspect, easy to version conceptually, and easy for an image
builder to generate.

#### What Phase 206 verifies

`make phase 206` verifies:

- Phase 204 contract still passes
- the Phase 205 partition labels still exist
- `systemd-bootx64.efi` is available from the dev shell
- `/efi/EFI/systemd/systemd-bootx64.efi` is installed
- `/efi/EFI/BOOT/BOOTX64.EFI` is installed
- `/efi/loader/loader.conf` selects `onix-phase-206.conf`
- `/boot/loader/entries/onix-phase-206.conf` exists
- the entry points at `root=LABEL=onix-root`
- the entry points at `/usr/lib/systemd/systemd`
- kernel/initramfs/systemd are still absent

The last item is important. Phase 206 fails if it accidentally becomes a fake
"it boots" phase. We want each layer to prove exactly one thing.

### Phase 207 — kernel + initramfs contract

Phase 207 is another contract phase.

It does not copy a kernel into the image.
It does not build an initramfs.
It does not mount the image.
It does not boot QEMU.

Phase 207 does not copy kernel files because the kernel is too important to
smuggle in accidentally. If we copied a random host kernel now, the image might
move forward, but ONIX would not have learned how it owns its own boot payload.

#### What the kernel is

The Linux kernel is the first real Linux program that runs after the bootloader.

Very simplified:

```text
firmware
  -> bootloader
  -> kernel
  -> first userspace program
```

The kernel is responsible for things like:

```text
CPU scheduling
memory management
device drivers
filesystems
processes
mounting the root filesystem
```

For ONIX, the future kernel path selected by Phase 206 is:

```text
/boot/ONIX/vmlinuz
```

`vmlinuz` is the normal name for a compressed Linux kernel image.

#### What the initramfs is

`initramfs` means "initial RAM filesystem".

It is a tiny temporary filesystem loaded into memory before the real root
filesystem is mounted.

Boot flow with initramfs:

```text
firmware
  -> systemd-boot
  -> kernel
  -> initramfs in RAM
  -> find real root filesystem
  -> mount real root filesystem at /
  -> run /usr/lib/systemd/systemd
```

The initramfs exists because the kernel often needs help before it can mount
the real root filesystem. For example, it may need userspace tools or modules
to find:

```text
LABEL=onix-root
```

and mount it as:

```text
/
```

For ONIX, the future initramfs path selected by Phase 206 is:

```text
/boot/ONIX/initramfs.img
```

#### Why `root=LABEL=onix-root` needs initramfs help

The Phase 206 BLS entry contains:

```text
root=LABEL=onix-root rootfstype=xfs rw init=/usr/lib/systemd/systemd
```

That means:

```text
find the filesystem labeled onix-root
mount it as /
use xfs as the root filesystem type
start /usr/lib/systemd/systemd
```

Device names like `/dev/vda3` can change. Labels are stable, so the contract
keeps:

```text
root=LABEL=onix-root
```

But resolving a label usually needs early userspace support. That is exactly
the initramfs job.

#### Minimum early-boot capabilities

For the first QEMU ONIX image, the initramfs must be able to handle:

```text
virtio_pci   QEMU virtio PCI transport
virtio_blk   QEMU virtio block disk
xfs          root filesystem type
vfat         ESP/boot filesystem type, useful for inspection and later tooling
devtmpfs     early /dev population
proc         /proc mount
sysfs        /sys mount
```

The must-have path is:

```text
virtio disk -> find LABEL=onix-root -> mount xfs root -> exec systemd
```

If any of those pieces are missing, the bootloader can load the kernel but the
kernel may panic because it cannot find or mount `/`.

#### ONIX ownership decision

The Phase 207 decision is:

```text
do not use the host kernel as the final ONIX kernel
```

The host kernel belongs to the developer machine.
The Alpine forge kernel belongs to the throwaway forge.
A Nixpkgs kernel belongs to the toolbox/source environment.

ONIX needs its own explicit boot payload contract.

The planned package split is:

```text
onix-kernel      owns the kernel image and kernel modules
onix-initramfs   owns or generates the initramfs image
```

That split may evolve, but the ownership boundary matters:

```text
package content        -> /usr/lib/kernel and /usr/lib/modules
image boot material    -> /boot/ONIX/vmlinuz and /boot/ONIX/initramfs.img
bootloader config      -> /boot/loader/entries/*.conf
```

In other words, packages should provide reproducible boot inputs, and image
assembly should place the selected boot artifacts where systemd-boot expects
them.

#### Future file contract

The current Phase 206 BLS entry expects:

```text
/boot/ONIX/vmlinuz
/boot/ONIX/initramfs.img
```

The future root filesystem must contain:

```text
/usr/lib/systemd/systemd
```

The future package payload should make kernel/module content available from
stable package-owned paths, such as:

```text
/usr/lib/kernel/vmlinuz
/usr/lib/modules/<kernel-version>/
```

Then image assembly can copy or link the selected boot artifacts into:

```text
/boot/ONIX/
```

#### What Phase 207 verifies

`make phase 207` verifies:

- this Phase 207 section exists
- the contracted kernel path is `/boot/ONIX/vmlinuz`
- the contracted initramfs path is `/boot/ONIX/initramfs.img`
- the contracted init path is `/usr/lib/systemd/systemd`
- the boot arguments still use `root=LABEL=onix-root`
- the boot arguments still use `rootfstype=xfs`
- the plan mentions the minimum early-boot pieces:
  - `virtio_pci`
  - `virtio_blk`
  - `xfs`
  - `vfat`
- the plan names `onix-kernel`
- the plan names `onix-initramfs`
- the Phase 206 image script still writes the same BLS paths

This makes Phase 207 a checkpoint between "we have a bootloader entry" and "we
are ready to build or import a real kernel/initramfs payload".

#### What Phase 207 does not prove

Phase 207 does not prove:

```text
kernel compiles
initramfs boots
systemd runs
QEMU reaches userspace
```

Those are later phases. Phase 207 only prevents us from taking a shortcut that
would hide ownership problems.

### Phase 208 — systemd userspace contract

Phase 208 is also a contract phase.

Phase 208 does not build systemd.
It does not copy host systemd.
It does not copy Nix systemd.
It does not mount the image.
It does not boot QEMU.

This phase exists because the Phase 206 boot entry already says:

```text
init=/usr/lib/systemd/systemd
systemd.unit=multi-user.target
```

That means the future kernel/initramfs handoff expects the real root filesystem
to contain:

```text
/usr/lib/systemd/systemd
```

Before we build or import that file, we need to say what owns it and what
minimum userspace shape must exist around it.

#### What PID 1 means

When Linux starts userspace, the first normal process gets process ID 1:

```text
PID 1
```

PID 1 is special. It becomes the init system for the machine.

It is responsible for starting and supervising the rest of userspace:

```text
mounts
device management
services
login
shutdown
reboot
cleanup of orphaned processes
```

For ONIX, the planned PID 1 path is:

```text
/usr/lib/systemd/systemd
```

That is why Phase 206 put this on the kernel command line:

```text
init=/usr/lib/systemd/systemd
```

#### Why not copy host systemd

The Phase 208 decision is:

```text
do not copy host systemd
do not copy Nix systemd
```

The host systemd belongs to the developer machine.
The Nix systemd belongs to the Nix toolbox environment.

ONIX is meant to be a musl-based OS. A random host or Nix systemd may be built
for a different libc, with a different layout, with different assumptions about
paths, users, groups, services, and dependencies.

So the future package must be ONIX-owned:

```text
onix-systemd
```

That package name is the contract for now. It may eventually be split into
smaller packages, but the ownership rule is clear: ONIX must provide its own
systemd userspace rather than smuggling in the host one.

#### What systemd userspace must include

The minimum future `onix-systemd` package needs more than one binary.

At minimum, the contract needs:

```text
/usr/lib/systemd/systemd
/usr/lib/systemd/systemd-udevd
/usr/bin/systemctl
/usr/bin/journalctl
/usr/lib/systemd/system/multi-user.target
```

`systemd-udevd` matters because device nodes and device events are part of
turning early boot into a usable machine.

`multi-user.target` matters because the Phase 206 boot entry already asks for:

```text
systemd.unit=multi-user.target
```

So the target file must exist at:

```text
/usr/lib/systemd/system/multi-user.target
```

#### Runtime filesystems systemd expects

Some paths are not normal package payload. They are runtime filesystems mounted
by the kernel, initramfs, or early userspace:

```text
/run
/dev
/proc
/sys
```

ONIX packages can create the mount-point directories, but they should not ship
host contents for those paths.

That matches the earlier root-tree rule:

```text
/dev   runtime devices
/proc  kernel process/info view
/sys   kernel device/info view
/run   runtime state
```

#### Machine identity and defaults

systemd also expects some machine-local state and policy.

Important early files include:

```text
/etc/machine-id
/etc/fstab
```

`/etc/machine-id` is the unique machine identity. It should not be a baked-in
shared ID copied into every image forever. The first real boot path needs a
policy for creating or seeding it safely.

`/etc/fstab` already comes from the ONIX filesystem package defaults and is
materialized by image assembly.

#### tmpfiles and sysusers

Two common systemd mechanisms matter for package integration:

```text
tmpfiles
sysusers
```

`tmpfiles` describes runtime directories, files, permissions, and cleanup rules.

`sysusers` describes system users and groups that packages need.

ONIX should eventually support package-owned defaults such as:

```text
/usr/lib/tmpfiles.d/*.conf
/usr/lib/sysusers.d/*.conf
```

This lets packages declare system integration without editing live `/etc`
directly.

#### Future file contract

The future root filesystem must provide:

```text
/usr/lib/systemd/systemd
/usr/lib/systemd/systemd-udevd
/usr/lib/systemd/system/multi-user.target
```

The future image or first-boot policy must handle:

```text
/etc/machine-id
/run
/dev
/proc
/sys
```

The future package name for this responsibility is:

```text
onix-systemd
```

Again: ONIX should build or package this intentionally for its musl base.

#### What Phase 208 verifies

`make phase 208` verifies:

- this Phase 208 section exists
- the planned PID 1 path is `/usr/lib/systemd/systemd`
- the boot entry still asks for `systemd.unit=multi-user.target`
- the target path is `/usr/lib/systemd/system/multi-user.target`
- the plan names `onix-systemd`
- the plan says `musl`
- the plan says `do not copy host systemd`
- the plan says `do not copy Nix systemd`
- the plan mentions `systemd-udevd`
- the plan mentions `/etc/machine-id`
- the plan mentions `/run`, `/dev`, `/proc`, and `/sys`
- the plan mentions `tmpfiles`
- the plan mentions `sysusers`
- the Phase 206 image script still points at `/usr/lib/systemd/systemd`

This makes Phase 208 a checkpoint between "the boot entry names systemd" and
"ONIX actually provides systemd userspace".

#### What Phase 208 does not prove

Phase 208 does not prove:

```text
systemd builds on musl
systemd starts as PID 1
udev works
services start
the image boots
```

Those are later phases. This phase only protects the ownership boundary.

### Phase 209 — systemd-on-musl feasibility gate

Phase 209 checks the scary question directly:

```text
can systemd exist in a musl-only ONIX world?
```

Short answer:

```text
glibc is not a hard requirement
musl is still a risk
```

So we continue with systemd-on-musl. But we also do **not** declare victory yet.

Phase 209 does not build systemd.
It does not install systemd.
It does not mount the image.
It does not boot QEMU.

It only checks whether the upstream and pinned-tooling story is plausible
enough to keep going.

#### What upstream says

The current upstream systemd README lists both libc families in its
requirements:

```text
glibc >= 2.34
musl >= 1.2.6
```

It also says musl is used by building systemd with:

```text
-Dlibc=musl
```

That means systemd-on-musl is an upstream-recognized build mode, not something
we invented.

Source:

```text
https://raw.githubusercontent.com/systemd/systemd/main/README
```

#### What our pinned nixpkgs says

Our pinned nixpkgs exposes:

```text
pkgsMusl.systemd
```

The local metadata check currently reports:

```text
name      : systemd-259.3
host libc : musl
broken    : false
flag      : -Dlibc=musl
musl      : musl 1.2.5
```

That means Nix can describe a musl-targeted systemd derivation for our pinned
tooling.

Important nuance: current upstream `main` says `musl >= 1.2.6`, while our
pinned Nix metadata reports `musl 1.2.5` for `systemd-259.3`. That does not
automatically kill the plan because the pinned package is an older systemd
version, but it does mean we must treat this as a feasibility gate, not final
proof.

#### What the pinned source says

The pinned systemd source has a Meson option:

```text
option('libc', type : 'combo', choices : ['glibc', 'musl'])
```

Its Meson logic also has musl-specific handling, and it disables at least one
feature that musl does not support:

```text
utmp
```

That matters because it tells us musl support is not just a string in Nix. The
source tree itself contains a musl path.

#### What the dry-run proves

`make phase 209` also asks Nix to plan:

```text
pkgsMusl.systemd
```

with:

```text
nix build --dry-run
```

Dry-run does not compile anything. It only proves Nix can construct the build
graph.

If dry-run fails, we should not continue with systemd until we understand why.

#### What Phase 209 proves

`make phase 209` proves:

- this Phase 209 section exists
- upstream has a musl build mode
- the pinned Nix package path exists as `pkgsMusl.systemd`
- the pinned package is named `systemd-259.3`
- the pinned package targets musl
- the pinned package is not marked broken
- the pinned package uses `-Dlibc=musl`
- Nix can plan the build graph

This is enough to say:

```text
continue systemd-on-musl
```

#### What Phase 209 does not prove

Phase 209 does not prove:

```text
systemd compiles successfully in our own boulder recipe
systemd links exactly how ONIX wants
systemd starts as PID 1
udev works
networking works
services work
boot reaches login
```

Those are still hard problems.

The current decision is:

```text
continue systemd-on-musl
```

### Phase 210 — init path decision contract

Phase 210 turns the Phase 209 probe into an explicit project decision.

Phase 210 does not build the init system.
It does not install systemd.
It does not mount the image.
It does not boot QEMU.

It only records how ONIX will proceed.

#### The decision

The Phase 210 decision is:

```text
init path: systemd-on-musl
bootloader: systemd-boot
```

Project rule:

```text
keep systemd if we can
```

In plain words: ONIX uses systemd as PID 1.

That means we continue with the systemd path for now because Phase 209 showed:

```text
pkgsMusl.systemd exists
pkgsMusl.systemd targets musl
pkgsMusl.systemd is not marked broken
pkgsMusl.systemd uses -Dlibc=musl
Nix can plan the build graph
```

But we do not pretend that systemd is proven boot-ready. The systemd path still
has to prove itself in real ONIX builds and boots.

#### Why bootloader and init are separate

The bootloader chooses and launches the kernel.

The init system is the first userspace process after the kernel mounts the real
root filesystem.

Those are different jobs:

```text
systemd-boot  -> bootloader
systemd       -> init system / PID 1
```

That is why the decision names both parts explicitly:

```text
systemd-boot loads the kernel
systemd runs as PID 1
```

#### What this means for the boot entry

The BLS entry keeps this kernel command line intent:

```text
init=/usr/lib/systemd/systemd systemd.unit=multi-user.target
```

That path is the userspace handoff point:

```text
kernel -> root filesystem -> /usr/lib/systemd/systemd
```

So Phase 211 and later must place a real systemd userspace at that path.

#### What Phase 210 verifies

`make phase 210` verifies:

- this Phase 210 section exists
- the init path is `systemd-on-musl`
- the bootloader is `systemd-boot`
- the project rule says `keep systemd if we can`
- the plan says ONIX uses systemd as PID 1
- the boot entry points at `/usr/lib/systemd/systemd`
- the plan mentions `systemd starts as PID 1`
- the plan mentions `udev/device setup works`
- the plan mentions `basic services work`
- the Phase 206 boot skeleton still follows the systemd path

#### What Phase 210 does not prove

Phase 210 does not prove:

```text
systemd builds
systemd boots
services work
QEMU reaches login
```

It only makes the next engineering decision explicit.

### Phase 211 — first kernel + initramfs payload

Phase 211 installs the first real files at the paths that Phase 206 and Phase
207 already promised:

```text
/boot/ONIX/vmlinuz
/boot/ONIX/initramfs.img
```

This is the first time the ONIX image contains a kernel and initramfs payload.

#### What a payload is

A payload is the thing a previous layer hands to the next layer.

For this part of boot:

```text
systemd-boot payload -> Linux kernel + initramfs
Linux kernel payload -> mounted root filesystem
root filesystem payload -> /usr/lib/systemd/systemd
systemd payload -> services
```

So Phase 211 is not "the whole OS boots now".

Phase 211 only gives systemd-boot something real to load.

#### Where the first payload comes from

The default Phase 211 source is:

```text
vm/state/vmlinuz-virt
vm/state/initramfs-virt
```

Those files are exported by the forge disk build in Phase 0.

That makes them a temporary bootstrap source, not the final ONIX kernel package
story.

The final shape is still:

```text
onix-kernel
onix-initramfs
```

But using the exported forge payload is useful because it is already known to
be a QEMU-capable kernel/initramfs pair.

#### Why Phase 211 checks the initramfs

ONIX root is XFS:

```text
LABEL=onix-root  /  xfs
```

That means the initramfs must understand XFS before the kernel can mount `/`.

If the initramfs cannot mount `/`, the boot fails before systemd even has a
chance to start.

So `make phase 211` checks the initramfs contents before copying it.

It requires:

```text
/init
xfs.ko
vfat.ko
virtio_blk.ko
```

Those mean:

| item | why it matters |
| --- | --- |
| `/init` | the first program inside the initramfs |
| `xfs.ko` | lets early boot mount the ONIX XFS root |
| `vfat.ko` | lets early boot understand FAT boot files if needed |
| `virtio_blk.ko` | lets early boot see the QEMU virtio disk |

If the current exported forge initramfs is old, Phase 211 may stop with:

```text
initramfs lacks xfs.ko
```

That is good. It means the verifier prevented us from installing a boot payload
that cannot mount the ONIX root filesystem.

The forge setup now requests XFS support when it creates the exported
initramfs, so rebuilding the forge disk produces a better payload.

#### What Phase 211 writes

`make phase 211` mounts the existing ONIX image and writes:

```text
/boot/ONIX/vmlinuz
/boot/ONIX/initramfs.img
/boot/ONIX/README.phase211
/boot/loader/entries/onix-phase-211.conf
/efi/loader/loader.conf
```

The BLS entry becomes:

```text
title ONIX
sort-key onix
version phase-211
linux /ONIX/vmlinuz
initrd /ONIX/initramfs.img
options root=LABEL=onix-root rootfstype=xfs rw init=/usr/lib/systemd/systemd systemd.unit=multi-user.target console=tty0 console=ttyS0,115200
```

The important new part is not the path. The path already existed in the
contract.

The important new part is that the files now exist and match the selected
source payload byte-for-byte.

#### What Phase 211 verifies

`make phase 211` verifies:

- the Phase 207 kernel/initramfs contract still exists
- the source kernel file exists and is non-empty
- the source initramfs exists and is non-empty
- the initramfs can be listed
- the initramfs contains `/init`
- the initramfs contains `xfs.ko`
- the initramfs contains `vfat.ko`
- the initramfs contains `virtio_blk.ko`
- the Phase 206 boot skeleton exists first
- `/boot/ONIX/vmlinuz` is installed
- `/boot/ONIX/initramfs.img` is installed
- the installed files match the source files
- the default boot entry is `onix-phase-211.conf`
- the boot entry still points to `/usr/lib/systemd/systemd`
- the image still does not contain systemd userspace yet

#### What Phase 211 does not prove

Phase 211 does not prove:

```text
the kernel boots
the initramfs mounts the root filesystem
systemd exists
systemd starts
QEMU reaches login
```

That is why Phase 212 is still needed.

## What comes after 211?

The next safe progression should be:

```text
212 = first QEMU boot attempt
```

The key learning point: Phase 2 is where we stop proving packages only in
disposable targets and start assembling the actual ONIX machine layout one
layer at a time.
