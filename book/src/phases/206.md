# Phase 206 — install the systemd-boot/BLS skeleton

## At a glance

| Field | Value |
|---|---|
| Phase family | Phase 2 — bootable image |
| Run command | `make phase 206` |
| Underlying make target/script | `vm/phase2/build-image-skeleton.sh --boot-skeleton` |
| Runs on | host with rootful image mount work |
| Main proof/artifact | Installs the systemd-boot/BLS skeleton into the image. |


Phase 206 starts the boot layer, but still does not pretend the OS can fully
boot yet.

### What "a boot skeleton" means

A *skeleton* is the boot chain with its structure in place but its organs missing.
After 206 the image has a bootloader installed on the ESP, a loader config, and a
BLS entry on `/boot` — the *frame* of a bootable system. What it deliberately
lacks is the payload the frame points at: no kernel, no initramfs, no systemd. If
you booted it now, firmware would find systemd-boot, systemd-boot would show a
menu entry, and selecting it would fail to load a kernel that does not exist yet.
That is the intended state. 206 proves the loader plumbing is correct *in
isolation*, so that when the kernel arrives (step 211) a failure is unambiguously
a kernel problem, not a bootloader one.

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

> **systemd-boot vs GRUB, and why it matters for an atomic distro.** GRUB is a
> full bootloader with its own scripting language; its config is usually
> *generated* by a tool (`grub-mkconfig`) that scans the system and emits a large
> file few people read. systemd-boot does much less on purpose: it is a small UEFI
> program that reads a directory of plain-text entries and shows a menu. For ONIX
> this is a perfect fit, because moss creates a *new* transaction on every update
> and wants to drop in *one new boot entry* per transaction — a text file named
> `onix-<txid>.conf` — and prune old ones. Generating and pruning small text files
> is trivial; regenerating a GRUB script on every atomic swap is not. The whole
> "roll back by picking the previous entry in the boot menu" story (the Phase 2
> gate) rests on this simplicity.

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

Two copies of the same bootloader binary are written, and that is deliberate:

- `/efi/EFI/systemd/systemd-bootx64.efi` is systemd-boot's own canonical install
  path, the one a UEFI boot variable would normally point at.
- `/efi/EFI/BOOT/BOOTX64.EFI` is the **removable-media fallback path**. UEFI
  firmware, when it has no specific boot variable telling it what to run, looks
  for exactly this file on the ESP. OVMF (the UEFI firmware QEMU uses) and real
  removable disks both fall back to it.

`BOOTX64.EFI` is the standard removable-media path. OVMF/QEMU can find it without us
writing host EFI variables. That is what makes the image self-contained: we never
have to poke the firmware's NVRAM boot list — the disk carries its own boot entry
in the place firmware already checks.

The `loader.conf` on the ESP is systemd-boot's top-level config. Phase 206 writes
a two-line file:

```text
default onix-phase-206.conf
timeout 3
```

`default` names which BLS entry to boot, and `timeout 3` gives a three-second menu
so you can pick a different one — the seed of the "recover via the boot menu" gate.

> **What is OVMF?** OVMF (Open Virtual Machine Firmware) is a build of the UEFI
> firmware that runs inside QEMU. It is why the QEMU boot probe in step 212 behaves
> like a real UEFI PC: it reads the ESP, honors the removable-media fallback, and
> hands off to systemd-boot exactly as physical firmware would.

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

Each line is a directive systemd-boot understands: `title` is the menu label,
`linux` and `initrd` are paths *relative to the XBOOTLDR partition* (`/boot`), and
`options` is the kernel command line — where the root filesystem, the init
program, and any boot flags are named. The actual entry Phase 206 writes is a bit
longer (it also sets `rootfstype=xfs` and `systemd.unit=multi-user.target`), but
the shape is this.

> **BLS "Type #1" entries and `onix-<txid>.conf`.** The specification calls a
> single text file like this a *Type #1* entry. In production, ONIX names each one
> after the moss transaction that produced it: `onix-<txid>.conf`. That is the
> linchpin of atomic boot — one transaction, one kernel/initramfs set, one boot
> entry, all tagged with the same id, which also rides on the kernel command line.
> Rolling back is then just "boot the previous `onix-*.conf`", and moss prunes
> entries for transactions it has dropped. The skeleton here uses the placeholder
> name `onix-phase-206.conf` because there is no real transaction behind it yet.

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

