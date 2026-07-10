# Phase 2 overview — first bootable ONIX image

Phase 2 takes the ONIX package repo artifact from Phase 1 and starts turning it
into a bootable disk image.

Up to now, ONIX has been a *pile of packages*. Phase 0 built the tooling (moss +
boulder) on the throwaway Alpine forge; Phase 1 authored the first musl `.stone`
recipes and published them into a repo. But a repo is not a machine. A machine
is a disk with a partition table, filesystems, a bootloader, a kernel, and an
init process — arranged so that turning on the power leads, step by step, to a
running userspace. Phase 2 is where those pieces first come together.

> **What is a `.stone`?** A `.stone` is moss's package container — not a tarball,
> but a content-addressed archive that moss knows how to unpack atomically. You
> cannot `tar xf` a stone; only moss understands its format. That single fact
> shapes a lot of Phase 2: whoever assembles the root tree must have moss, which
> is why an early sub-phase (202) exists purely to build moss *on the host*.

> **What is the "machine plane"?** ONIX has two planes. The **machine plane** is
> moss-owned: `/usr`, the kernel, the initrd, boot entries — atomic and
> transactional. The **Nix toolbox** (Phase 3 onward) is the glibc software long
> tail on top. Phase 2 builds only the machine plane, and only its skeleton.

## Phase 2 is a boot proof, not the final kernel story

Phase 2 is a boot proof, not the final kernel ownership story. It intentionally
uses the Alpine forge's virt kernel/initramfs/module payload so we can prove the
image layout and systemd-on-musl userspace before spending a full phase on
kernel building.

This is a deliberate separation of concerns. Building a Linux kernel from source
— choosing a config, compiling modules, packaging it as an ONIX-owned stone — is
a large task with its own failure modes. If we tried to do that *and* prove the
disk layout *and* prove that systemd runs on musl all at once, a boot failure
would be almost impossible to bisect. So Phase 2 borrows a kernel it already
trusts (the forge's), proves everything *around* the kernel, and defers the real
kernel to a reserved later phase. The borrow is a scaffold, marked as such.

The Phase 2 learning arc is:

```text
exported package repo
  -> host-side moss
  -> root tree
  -> disk image
  -> systemd-boot skeleton
  -> kernel/initramfs payload
  -> first musl systemd userspace payload
  -> first kernel module/kmod payload
  -> first QEMU boot probe
```

Read that arc as a funnel. Each stage takes a known-good output from the last and
adds exactly one new thing, so that the *next* failure has an obvious address.
"Root tree" is a directory of files. "Disk image" wraps that directory in a real
partitioned disk. "systemd-boot skeleton" adds a bootloader but no kernel. Only
at the very end does QEMU actually try to power the thing on.

The borrowed payload boundary is explicit:

```text
Phase 2: boot with borrowed Alpine kernel payload
Phase 3: later replace that with ONIX-owned kernel/initramfs/modules
Phase 4: continue now with booted ONIX base userspace
```

## Background: the target boot chain

Everything Phase 2 assembles exists to make this chain work, top to bottom:

```text
UEFI firmware
  -> EFI loader on ONIX-ESP (the FAT32 EFI System Partition)
  -> systemd-boot
  -> BLS entry on ONIX-BOOT (the XBOOTLDR /boot partition)
  -> kernel (vmlinuz)
  -> initramfs (early RAM userspace)
  -> mount onix-root (XFS) as /
  -> exec /usr/lib/systemd/systemd  (PID 1)
```

A few terms, defined once:

- **UEFI** is the modern PC firmware standard. At power-on it reads a FAT
  filesystem called the **ESP** (EFI System Partition) and runs an `.efi`
  program from it.
- **systemd-boot** is a tiny UEFI bootloader. ONIX uses it instead of GRUB
  because its config is just plain text files (see step 206).
- **BLS** is the **Boot Loader Specification**: a convention where each bootable
  option is one small text file — a "Type #1" entry — rather than a block inside
  a generated bootloader script. ONIX's entries are named `onix-<txid>.conf`,
  tying each boot option to a moss transaction.
- **XBOOTLDR** is a second, larger boot partition (`/boot`) that holds the actual
  kernel and initramfs, keeping the firmware-visible ESP small.
- **initramfs** ("initial RAM filesystem") is a minimal userspace the kernel
  unpacks into RAM so it can find and mount the *real* root before handing off.
- **PID 1** is the first userspace process; on ONIX that is systemd, which then
  brings up the rest of the machine.

Phase 2 walks this chain from the outside in: partitions first, then the loader,
then contracts for the kernel and systemd, then the borrowed payloads, then a
real power-on.

## About `make phase 2`

`make phase 2` runs the canonical host-native Phase 2 path:

```text
200 -> 202 -> 203 -> 204 -> 205 -> 206 -> 207 -> 208 -> 209 -> 210 -> 211 -> 213 -> 214 -> 212
```

It intentionally skips Phase 201 because Phase 201 is the older bridge step
that uses the forge VM over SSH. Phase 203 is the normal host-native root-tree
assembly path.

Notice the ordering. The image is *built* by 205/206/211/213/214, but those are
interleaved with pure *contract* steps (204, 207, 208, 210) and a *feasibility*
step (209). The contract steps write nothing to disk; they check that the plan on
this book page still matches what the scripts do. They act as design gates: a
place to agree on the shape before the rootful, sudo-driven disk work runs. The
final step, 212, is the QEMU boot probe — it comes last because there is no point
powering on a machine whose contracts you have not yet nailed down.

## Steps

- [200 — image assembly readiness](./200_image_assembly_readiness.md)
- [201 — assemble the first ONIX root tree](./201_assemble_first_onix_root_tree.md)
- [202 — build host-side Moss](./202_build_host_side_moss.md)
- [203 — assemble the root tree with host-side Moss only](./203_assemble_root_tree_with_host_moss_only.md)
- [204 — define image/disk assembly contract](./204_image_disk_assembly_contract.md)
- [205 — create first non-booting disk/root skeleton](./205_create_non_booting_disk_root_skeleton.md)
- [206 — install the systemd-boot/BLS skeleton](./206_install_systemd_boot_bls_skeleton.md)
- [207 — kernel + initramfs contract](./207_kernel_initramfs_contract.md)
- [208 — systemd userspace contract](./208_systemd_userspace_contract.md)
- [209 — systemd-on-musl feasibility gate](./209_systemd_on_musl_feasibility_gate.md)
- [210 — init path decision contract](./210_init_path_decision_contract.md)
- [211 — first kernel + initramfs payload](./211_first_kernel_initramfs_payload.md)
- [212 — first QEMU boot probe](./212_first_qemu_boot_probe.md)
- [213 — first musl systemd userspace payload](./213_first_musl_systemd_userspace_payload.md)
- [214 — first kernel module/kmod payload](./214_first_kernel_module_kmod_payload.md)

Running:

```sh
make phase 2
```

runs the canonical host-native Phase 2 path.

## The Phase 2 gate

The Phase 2 exit gate (from the roadmap) is deliberately experiential, not just
a passing script: `cat /etc/os-release` says ONIX (musl); `moss state list`
shows transactions; and you can *break* the system with an update and recover it
via the boot menu plus state activation — from memory, twice. Steps 200–214 are
the ladder that makes that gate reachable; the ladder is only worth anything once
you can climb up and down it in the dark.

After this passes, the immediate next implementation lane is Phase 4:

```sh
make phase 400
```

Phase 3 is reserved for later kernel ownership work:

```sh
make phase 300
```
