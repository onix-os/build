# Phase 003 — boot the forge

## At a glance

| Field | Value |
|---|---|
| Phase family | Phase 0 — forge |
| Run command | `make phase 003` |
| Underlying make target/script | `vm/phase0/launch.sh` |
| Runs on | host QEMU process, guest serial/login console |
| Main proof/artifact | Boots the forge VM named quarry. |


```sh
make phase 003
```

This starts QEMU using the disk from Phase 002.

## Why boot at all?

Phase 002 only *assembled* a disk; it never proved the disk boots. Phase 003 is
that proof. It launches the `quarry.raw` image under **QEMU/KVM** and gets you a
running musl machine you can log into and SSH to. Everything after this —
building moss+boulder, cutting stones, testing moss states — happens *inside*
this running VM.

> **Sidebar — QEMU, KVM, OVMF.** **QEMU** is a machine emulator: it presents a
> virtual CPU, disk, network card, and serial port to a guest OS. **KVM** is the
> Linux kernel feature that lets QEMU run the guest's instructions directly on
> the host CPU instead of emulating them — near-native speed. `launch.sh` uses
> KVM when `/dev/kvm` is writable and falls back to slow TCG emulation with a
> warning otherwise. **OVMF** is the open-source UEFI firmware QEMU loads so the
> virtual machine boots the way a real UEFI PC does — reading the ESP and
> launching `\EFI\BOOT\BOOTX64.EFI`. Each VM gets its own writable copy of the
> UEFI NVRAM (`quarry_OVMF_VARS.fd`) so boot variables persist without mutating
> the shared firmware template.

## The boot path

By default `launch.sh` boots the disk through its own **GRUB + OVMF** (the UEFI
path the disk was built for). It builds a `qemu-system-x86_64` command with a
q35 machine, virtio devices (RNG, balloon, network), a user-mode NAT network
with one host→guest SSH forward, and the OVMF firmware pflash drives. There is
also a `--direct` mode that boots the exported kernel+initramfs directly with
QEMU's `-kernel`/`-initrd`, bypassing GRUB entirely — the safety net for when
the bootloader misbehaves.

Expected login:

```text
username: mason
password: onix
```

`mason` is the non-root build user created in Phase 002; `onix` is the throwaway
forge password. In practice you rarely type it — the host's generated SSH key
was baked into the image, so `./ssh.sh` and `make phase 004` log in key-only.

SSH is forwarded from host port `6649` to guest port `22`.

> **Sidebar — why port 6649.** 6649 spells "ONIX" on a phone keypad — the
> project's magic number (it also shows up as the nixbld GID and the VM's MAC
> suffix). QEMU's user-mode networking NATs the guest behind the host; the one
> `hostfwd=tcp:127.0.0.1:6649-:22` rule means `ssh -p 6649 mason@127.0.0.1`
> reaches the guest's sshd. It is bound to `127.0.0.1`, so only the local host
> can reach it.

The VM hostname is:

```text
quarry
```

The forge is the *quarry* — the place the first stones are cut. The name is set
in `config.sh` and written into `/etc/hostname` by `chroot-setup.sh`.

## Foreground vs batch boot

When you run `make phase 003` directly, QEMU stays in the foreground so you can
watch and interact with the console.

Interactive boot is what you want when debugging: you see the serial console
live and can log in at the `quarry login:` prompt. The serial console works
because `chroot-setup.sh` added a getty on `ttyS0` and GRUB passes
`console=ttyS0,115200` on the kernel command line.

When you run the whole family with `make phase 0`, phase 003 uses a batch-safe
boot path instead:

```text
launch QEMU in the background
tail vm/state/quarry.serial.log so you still see boot logs
wait until SSH on 127.0.0.1:6649 is ready
continue automatically to phase 004
```

That means the full batch does not get stuck at the Alpine login prompt.

Under the hood this is `launch.sh --background --wait --display vnc`. QEMU is
`-daemonize`d with a pidfile, its serial output is redirected to
`vm/state/quarry.serial.log`, and the script polls SSH (`ssh … true`) until it
succeeds — while also watching the log for the `quarry login:` marker so it
knows userspace really came up. If QEMU exits before SSH is ready, or the wait
times out (default 240s), it fails loudly instead of hanging forever. Only once
SSH answers does the batch move on to [004](./004_provision_tools.md).

## Reading the serial log

The serial log at `vm/state/quarry.serial.log` is your window into a headless
boot. If a batch boot fails, read it: you will see the kernel messages, OpenRC
bringing services up, and finally the `quarry login:` prompt. No prompt and no
SSH usually means the kernel could not mount root (check the initramfs drivers)
or networking/sshd did not start.

## What it proves — and what it does not

**Proves:** the Phase 002 disk is genuinely bootable, the musl userland comes
up, networking and sshd start, and the host can reach the guest over SSH on
port 6649.

**Does not prove:** anything about moss or boulder — they are not built yet.
Phase 003 is purely "the forge is alive and reachable." The tooling comes in
[004](./004_provision_tools.md).

## What comes next

With the forge booted and SSH ready, [004 — provision tools](./004_provision_tools.md) SSHes in
as `mason` and compiles moss + boulder from the pinned `os-tools` commit.
