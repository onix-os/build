# Phase 211 — first kernel + initramfs payload

## At a glance

| Field | Value |
|---|---|
| Phase family | Phase 2 — bootable image |
| Run command | `make phase 211` |
| Underlying make target/script | `vm/phase2/build-image-skeleton.sh --kernel-payload` |
| Runs on | host with rootful image mount work |
| Main proof/artifact | Installs the first kernel/initramfs payload into /boot/ONIX/ inside the image. |


Phase 211 installs the first real files at the paths that Phase 206 and Phase
207 already promised:

```text
/boot/ONIX/vmlinuz
/boot/ONIX/initramfs.img
```

This is the first time the ONIX image contains a kernel and initramfs payload.

#### Background: the kernel image and the initramfs

Two files sit at the heart of this phase, and it is worth being precise about
what each one is.

`vmlinuz` is the **compressed Linux kernel image** — the operating-system kernel
itself, packaged so the bootloader can load it into memory and jump into it. The
name is historical: *vm* for virtual memory, *linuz* with a "z" for compressed.
When systemd-boot loads `/ONIX/vmlinuz`, it is loading this file.

`initramfs.img` is the **initial RAM filesystem** (also called initrd, "initial
ramdisk"). It is a small, self-contained root filesystem — really a compressed
cpio archive — that the bootloader loads into memory alongside the kernel. The
kernel unpacks it into a RAM disk and runs the program `/init` inside it *before*
the real root filesystem is available. Why does this indirection exist? Because
of a chicken-and-egg problem: to mount the real root filesystem, the kernel needs
the driver for that filesystem's type and for the disk it lives on — but those
drivers might themselves live *on* that unmounted filesystem. The initramfs
breaks the loop: it ships just enough drivers and tools, in RAM, to find and
mount the real root, then hands off to it. In ONIX terms:

```text
initramfs /init  ->  find root by LABEL=onix-root  ->  mount it as /
                 ->  switch to it  ->  exec /usr/lib/systemd/systemd
```

The step that finds the disk by its label (`root=LABEL=onix-root` on the kernel
command line) is why the label matters: the initramfs does not hard-code a
device name like `/dev/vda2`; it searches every block device for one carrying the
filesystem label `onix-root`. That makes the image portable across disk layouts.

#### Background: kernel modules (`.ko`)

The kernel does not build every driver in. Most drivers are **loadable kernel
modules** — files ending in `.ko` ("kernel object") that can be inserted into a
running kernel on demand. The initramfs bundles the handful of modules early boot
needs so it can talk to the disk and the filesystem before anything else exists.
That is why this phase inspects the initramfs's module list before trusting it.

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

This is a deliberate bootstrap shortcut, and it is honest about being one. The
kernel and initramfs here are *borrowed* from the throwaway Alpine forge (the
musl host, hostname `quarry`, that ONIX uses only to bootstrap its tooling).
Nothing Alpine ships is meant to survive into ONIX — and this borrowed pair is
the one temporary exception, scheduled to be replaced by ONIX-owned
`onix-kernel`/`onix-initramfs` stones and removed in the reserved Phase 3. Using
it now lets Phase 2 prove the *boot mechanics* (does the chain reach systemd?)
without first solving the much larger problem of building a kernel from scratch.

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

That byte-for-byte match is a deliberate check, not a coincidence. The verifier
copies the source files in and then compares the installed copies against the
sources, so there is no chance the boot entry points at a kernel that differs
from the one that was validated. It is a small guard against a silent
half-write.

#### Background: what "rootful image mount work" means

The "At a glance" table says this phase "runs on host with rootful image mount
work." Here is what that involves. `artifacts/onix-image/onix.raw` is a raw disk
image — a single file that contains a full partition table and several
filesystems, exactly as a physical disk would. To write files *into* those
filesystems from the host, the script has to attach the image as a block device
(a loop device) and mount its partitions, which requires root privileges. It
mounts the ESP, the boot partition, and the XFS root, copies the payload into
`/boot/ONIX/`, writes the loader files, then unmounts. "Rootful" simply flags
that this step needs `sudo`, unlike the pure host-only checks of Phase 209 and
210. `XFS` is the journaling filesystem ONIX uses for its root partition; it is
labeled `onix-root`, which is the label the kernel command line searches for.

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

