# Phase 212 — first QEMU boot probe

## At a glance

| Field | Value |
|---|---|
| Phase family | Phase 2 — bootable image |
| Run command | `make phase 212` |
| Underlying make target/script | `vm/phase2/boot-probe.sh` |
| Runs on | host QEMU process |
| Main proof/artifact | Boots the ONIX image in QEMU and captures serial evidence for the current image layer. |


Phase 212 is the QEMU boot probe for the generated ONIX image.

It is still a probe.

It is not a promise that the OS reaches login.

#### Background: QEMU, OVMF, and UEFI

To test a boot without a physical machine, ONIX boots the image in **QEMU** — a
software machine emulator/virtualizer. QEMU pretends to be a whole computer:
CPU, RAM, a disk, a network card. Given ONIX's raw disk image as its virtual
disk, it can attempt to boot it exactly as real hardware would, and (crucially)
it can be scripted and thrown away.

A real modern PC does not start executing your disk directly; firmware runs
first. On modern systems that firmware follows the **UEFI** standard (Unified
Extensible Firmware Interface), the successor to the legacy BIOS. UEFI knows how
to read a FAT filesystem on the *EFI System Partition* (ESP) and launch a
bootloader from it. QEMU has no built-in UEFI, so ONIX supplies one:
**OVMF** (Open Virtual Machine Firmware), an open-source UEFI build for virtual
machines. The `boot-probe.sh` script hunts for an `OVMF_CODE.fd` on the host and
feeds it to QEMU as a `pflash` (emulated flash chip). It also copies a writable
`OVMF_VARS.fd` per run so the firmware has somewhere to keep its variables
without mutating the shared template.

So the full launch stack QEMU assembles is:

```text
QEMU virtual machine
  -> OVMF (UEFI firmware)
    -> systemd-boot (bootloader on the ESP)
      -> Linux kernel + initramfs
        -> ONIX root filesystem
          -> /usr/lib/systemd/systemd (PID 1)
```

Each layer's only job is to hand control cleanly to the next. Phase 212 exists to
watch that hand-off happen (or fail) at each link.

The exact meaning of the probe depends on which image layers have already been
staged.

After Phase 211, the image has:

```text
disk partitions
root filesystem skeleton
systemd-boot
BLS boot entry
kernel
initramfs
```

At that point, Phase 212 is expected to find the next missing userspace layer.

After Phase 213, the image also has:

```text
/usr/lib/systemd/systemd
```

After Phase 214, the image also has:

```text
/usr/bin/kmod
/usr/sbin/modprobe
/usr/lib/modules/<kernel-release>
```

So Phase 212 is reusable. It asks:

```text
what exact boot milestone does the current image reach?
```

The expected learning value is still not "a finished OS".

The expected learning value is evidence:

```text
does OVMF find systemd-boot?
does systemd-boot load /boot/ONIX/vmlinuz?
does the kernel receive the right command line?
does the initramfs get far enough to try the real root?
does the kernel hand off to systemd?
does systemd reach multi-user.target?
do /boot and /efi mount cleanly?
what is the next missing layer or warning?
```

#### Why a boot probe is useful even before login

Boot is a chain.

Each link hands control to the next link:

```text
QEMU
  -> OVMF firmware
  -> systemd-boot
  -> Linux kernel
  -> initramfs
  -> ONIX root filesystem
  -> /usr/lib/systemd/systemd
```

If the chain breaks, the serial log tells us which link broke.

That is better than guessing.

#### Background: what a serial console is

A **serial console** is the oldest and simplest way to get text in and out of a
machine: a plain byte stream over a serial port, no graphics involved. The kernel
command line ONIX stamps in Phase 211 ends with `console=tty0
console=ttyS0,115200`, which tells the kernel to mirror its console onto both the
virtual screen (`tty0`) *and* the first serial port (`ttyS0`) at 115200 baud.
QEMU exposes that serial port as a file or as your terminal, so every line the
firmware, kernel, and systemd print becomes capturable plain text. This is the
single most valuable diagnostic in early-boot work: when there is no login, no
network, and no logging daemon yet, the serial console is often the *only* window
into what the machine is doing.

#### Why Phase 212 uses a serial log

Graphical boot output is easy to miss and hard to copy.

Serial output is plain text.

Phase 212 writes it here:

```text
vm/state/phase212.serial.log
```

The probe also prints the serial log while QEMU is running so you can watch the
boot happen.

The script does not just save the log — it *reads* it, and that is what makes
this a diagnostic rather than a demo. While QEMU runs, it watches the log for a
few telltale strings and stops early the moment it sees decisive evidence:

```text
Kernel panic
switch_root:.*systemd
Run /usr/lib/systemd/systemd as init process
```

After QEMU stops, it asserts the log actually shows a kernel starting (`Linux
version`), that the command line carried `root=LABEL=onix-root` and
`init=/usr/lib/systemd/systemd`, and then reports the *strongest milestone*
reached: `Reached target ... Multi-User System` (best), a `Kernel panic` (useful
evidence of the next missing layer), or "kernel started, no panic." A panic is
not a failure of the probe — it is the probe succeeding at its real job, which is
telling you precisely which link in the chain broke.

#### Background: KVM vs TCG (why it might be slow)

QEMU can run the guest two ways. With **KVM** (Kernel-based Virtual Machine) it
uses hardware virtualization, so guest CPU instructions run nearly at native
speed. Without access to `/dev/kvm`, it falls back to **TCG**, a pure-software
instruction translator — correct but much slower. `boot-probe.sh` checks whether
`/dev/kvm` is writable and warns (`run: make kvm`) if it has to use TCG. This
only affects how *fast* the probe boots, not what it proves; but on TCG you may
need a longer probe window (`--seconds N`) for boot to reach systemd.

#### How to watch Phase 212 attached

Normal Phase 212 is headless and automatic:

```sh
make phase 212
```

If you want to see the serial console directly in your terminal, run one of
these:

```sh
ATTACHED=1 make phase 212
make phase 212 ATTACHED=1
```

Those are equivalent.

Attached mode runs QEMU in the foreground. It does not stop QEMU automatically.
The default attached display is the terminal serial console:

```text
ONIX_BOOT_PROBE_DISPLAY=serial
```

To exit terminal serial mode, press:

```text
Ctrl-a then x
```

or press `Ctrl-C`.

If you explicitly want a GTK window:

```sh
ONIX_BOOT_PROBE_DISPLAY=gtk ATTACHED=1 make phase 212
```

If you explicitly want VNC:

```sh
ONIX_BOOT_PROBE_DISPLAY=vnc ATTACHED=1 make phase 212
```

Then connect a VNC viewer to:

```text
127.0.0.1:5900
```

There is also a QEMU `-nographic` mode:

```sh
ONIX_BOOT_PROBE_DISPLAY=none ATTACHED=1 make phase 212
```

#### Why normal Phase 212 stops QEMU itself

Normal Phase 212 is not meant to leave you trapped in a VM.

It runs QEMU in the background, waits for a short probe window, captures the
serial log, then stops only the Phase 212 QEMU process:

```text
process name: onix-phase212
```

It does not kill unrelated QEMU VMs.

#### Why Phase 212 uses a snapshot disk

The QEMU disk is opened with snapshot writes.

That means the boot probe can read the generated image, but runtime writes do
not permanently change `artifacts/onix-image/onix.raw`.

A **snapshot disk** works like a scratch overlay: QEMU keeps every write the
guest makes in a temporary layer and discards it when the VM exits, leaving the
underlying `onix.raw` byte-for-byte unchanged (`snapshot=on` in the `-drive`
line). This matters for two reasons. First, reproducibility: the image artifact
is exactly what the build phases produced, so re-running the probe always tests
the same thing. Second, safety: a boot that half-initializes the filesystem or a
systemd that rewrites `/etc` cannot corrupt the artifact you spent Phases
211–214 assembling. You can boot-probe as many times as you like without ever
"using up" the image.

This keeps the image artifact reproducible while we are still learning.

#### What Phase 212 verifies

`make phase 212` verifies:

- `artifacts/onix-image/onix.raw` exists
- OVMF firmware exists
- QEMU can launch the image
- serial output is captured
- the Linux kernel starts
- the kernel command line contains `root=LABEL=onix-root`
- the kernel command line contains `init=/usr/lib/systemd/systemd`
- the log contains useful boot evidence
- if present, systemd userspace can be observed in the serial log
- if reached, `multi-user.target` is reported as the strongest milestone

#### What Phase 212 does not prove

Phase 212 does not prove:

```text
networking works
login works
the final package ownership model is complete
all mounts are strict and clean
```

Those need later phases.

## What comes after 212?

Once Phase 212 proves the image reaches systemd, the next safe progression is
to remove bootstrap shortcuts one by one.

Examples:

```text
214 = add the first module/kmod payload
future = make /boot and /efi strict once they mount cleanly
future = add real login/user/networking policy
future = replace imported bootstrap payloads with ONIX-owned stones
```

The key learning point: Phase 2 is where we stop proving packages only in
disposable targets and start assembling the actual ONIX machine layout one
layer at a time.
