# Phase 4 overview — booted ONIX base userspace

Phase 4 starts from the Phase 2 boot proof.

Phase 2 answered:

```text
Can ONIX assemble a disk image and reach systemd multi-user mode?
```

The answer is now yes.

Phase 4 asks a different question:

```text
Can the booted image become a usable base system?
```

## What "base userspace" means

The kernel gets the machine started, but userspace is what makes it usable.

**Kernel space vs userspace.** The kernel runs in a privileged CPU mode and owns
the hardware. Everything else — shells, daemons, login, your programs — runs in
*userspace*, an unprivileged mode where code can only touch hardware by asking the
kernel through system calls. "Base userspace" is the minimum set of userspace
software that turns a bare booted kernel into a machine a human can actually log
into, inspect, network, and repair.

### The kernel-to-PID-1 handoff

The kernel does not run programs on its own forever. Once it has mounted the real
root filesystem (with the initramfs's help, see Phase 3), it does exactly one
thing to start userspace: it executes a single program and gives it **process ID
1**. On ONIX that program is:

```text
/usr/lib/systemd/systemd
```

PID 1 is special. It is the ancestor of every other process, it never exits while
the system is up, and it is responsible for bringing the rest of userspace to
life — mounting the other filesystems, starting services in dependency order, and
reaping orphaned processes. If PID 1 crashes, the kernel panics. This is why the
init system is such a load-bearing choice, and why ONIX commits to **systemd as
PID 1** (see the init decision in the architecture chapter).

So the whole boot is a relay of responsibility:

```text
firmware -> bootloader -> kernel -> initramfs -> PID 1 (systemd) -> the rest of userspace
```

Phase 2 proved that relay reaches its final leg: systemd starts and reaches
multi-user mode. Phase 4 is about everything *after* that hand-off — making the
booted system into a base you can live in.

From that point onward, userspace is responsible for:

- creating or validating `/etc` state
- starting udev
- discovering disks and network devices
- mounting local filesystems
- creating users and groups
- starting login prompts
- starting SSH or other remote inspection tools
- preserving persistent state under `/persist`

Phase 2 proved the minimum handoff.

Phase 4 makes that handoff useful.

## The important boundary with Phase 3

Phase 4 does not own the kernel.

For now the image keeps using the borrowed Alpine virt kernel/initramfs/module
payload proved in Phase 2:

```text
vm/state/vmlinuz-virt
vm/state/initramfs-virt
```

That lets Phase 4 focus on the booted system itself:

```text
/etc
/usr
/persist
/home
/nix
systemd units
users
login
networking
```

Kernel ownership remains reserved for Phase 3.

## Initial Phase 4 direction

The first Phase 4 subphases should be small and observable.

Proposed path:

```text
400 — Phase 4 readiness and direction
401 — materialize live /etc from /usr/share/defaults
402 — create base users/groups/shell policy
403 — prove bootstrap serial root console
404 — add minimal QEMU user networking inspection
405 — prove host-to-guest TCP inspection
406 — prove authenticated SSH access
407 — audit temporary Nix-sourced system payloads
408 — define local stone/repo contract
409 — build `busybox.stone`
410 — install/use `busybox` in the image
411 — rerun shell/network/SSH proofs against stone BusyBox
412 — build `dropbear.stone`
413 — install/use `dropbear` and rerun SSH proof
414 — systemd stone dependency audit
415 — build first `systemd.stone`
416 — install `systemd` into the image
417 — boot with `systemd` as PID 1
418 — move bootstrap units/defaults into stone ownership
419 — audit booted-base ownership/debt map
420 — prune stale old Nix BusyBox/Dropbear payloads
421 — prepare native source-built `systemd`
422 — build/install/boot-prove native `systemd`
424 — bring up native ONIX and leave it running for inspection
425 — final Phase 4 acceptance check against the running VM
```

The exact list can change as we learn, but the theme should stay stable:

```text
make the booted image inspectable, login-capable, and base-system shaped
```

## What Phase 4 should not do yet

Phase 4 should avoid:

- building the ONIX kernel
- designing the desktop stack
- adding Nix integration
- solving Mesa/graphics
- making a huge package set

Those are later phases. The base system must become understandable first.

## The theme running through Phase 4: prove, then own

Two ideas repeat across every Phase 4 step, and it helps to name them now.

First, **prove behavior before packaging it.** Writing a `.stone` recipe for
every component before you know it even works would be slow and demoralizing. So
Phase 4 leans on convenient, pinned Nix-built musl payloads (BusyBox, Dropbear,
systemd) as *scaffolding* to prove a behavior — a shell over serial, an IPv4
route, key-based SSH — and only then replaces that scaffolding with a real
moss-owned stone. Steps 401-406 are the "prove" half; 407 audits the debt; 408
onward is the "own" half.

Second, **stay honest about which plane owns what.** The ONIX constitution says
moss owns the machine plane and Nix owns the user toolbox. A shell, an SSH daemon,
and PID 1 are machine-plane software, so a Nix-built copy of them is only ever a
temporary loan. Phase 407 exists specifically to write that loan down and name its
future `.stone` owner, so the shortcut never hardens into the architecture.

## Build/proof steps versus lab steps

Running:

```sh
make phase 4
```

runs the canonical automated Phase 4 build/proof chain:

```text
400..422
```

Phase 424 is intentionally not part of that automatic chain.

Why?

Because Phase 424 leaves QEMU running. That is useful when a human wants to SSH
into the machine, but it is not what we want from an automatic "run every
build/proof step" command.

Use:

```sh
make phase 424
```

or:

```sh
make up
```

when you want the booted native ONIX VM to stay alive for inspection.

After that VM is up, run:

```sh
make phase 425
```

to run the final Phase 4 acceptance gate. Phase 425 checks the live VM through
SSH and through an interactive login transcript. It proves the machine is still
using native `systemd` as PID 1, Dropbear has its MOTD disabled with `-m`,
the colored ONIX login banner is printed by `/etc/profile`, and the shell
policy exposes the `ll` alias.

Phase 425 is also not part of `make phase 4`, because it depends on the live
inspection VM from Phase 424.

## Steps

- [400 — booted-base readiness](./400_booted_base_readiness.md)
- [401 — materialize live `/etc`](./401_materialize_live_etc.md)
- [402 — base users, groups, and shell policy](./402_base_users_groups_shell_policy.md)
- [403 — bootstrap serial root console proof](./403_bootstrap_serial_root_console_proof.md)
- [404 — minimal QEMU user networking proof](./404_minimal_qemu_user_networking_proof.md)
- [405 — host-to-guest TCP inspection proof](./405_host_to_guest_tcp_inspection_proof.md)
- [406 — authenticated SSH proof](./406_authenticated_ssh_proof.md)
- [407 — machine-plane ownership audit](./407_machine_plane_ownership_audit.md)
- [408 — local stone/repo contract](./408_local_stone_repo_contract.md)
- [409 — build `busybox.stone`](./409_build_onix_busybox_stone.md)
- [410 — install/use `busybox`](./410_install_use_onix_busybox.md)
- [411 — boot-prove `busybox`](./411_boot_prove_onix_busybox.md)
- [412 — build `dropbear.stone`](./412_build_onix_dropbear_stone.md)
- [413 — install/use `dropbear`](./413_install_use_onix_dropbear.md)
- [414 — systemd ownership audit](./414_systemd_ownership_audit.md)
- [415 — build `systemd.stone`](./415_build_onix_systemd_stone.md)
- [416 — install/use `systemd`](./416_install_use_onix_systemd.md)
- [417 — boot-prove `systemd`](./417_boot_prove_onix_systemd.md)
- [418 — package/prove bootstrap](./418_package_prove_bootstrap.md)
- [419 — booted-base ownership audit](./419_booted_base_ownership_audit.md)
- [420 — prune stale old Nix BusyBox/Dropbear payloads](./420_prune_stale_old_nix_busybox_dropbear_payloads.md)
- [421 — prepare native `systemd`](./421_prepare_native_onix_systemd.md)
- [422 — native `systemd` build/install/boot proof](./422_native_onix_systemd_build_install_boot_proof.md)
- [424 — bring up native ONIX for inspection](./424_bring_up_native_onix_for_inspection.md)
- [425 — final Phase 4 acceptance check](./425_final_phase_4_acceptance_check.md)
