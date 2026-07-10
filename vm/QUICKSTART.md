# Quickstart

Use the repository `Makefile` for normal work.

```sh
make doctor      # common health check
make stop        # stop QEMU/probes and detach stale mounts; keep disks/images
make cleanup     # destructive reset: stop everything and remove generated disks/images
make up          # boot native ONIX, prove SSH, and leave QEMU running
make phases      # print the numbered learning flow
make phase 0     # run all Phase 0 steps
make phase 1     # run all Phase 1 steps
make phase 2     # run the canonical Phase 2 path
make phase 3     # explain deferred ONIX-owned kernel work
make phase 4     # run canonical Phase 4 build/proof steps: 400..422
make phase 424   # boot native ONIX and leave it running for inspection
make phase 425   # accept the running Phase 4 VM
make phase 5     # run current Phase 5 package/repository gates
```

## How the Makefile router works

The top-level `Makefile` is not where the build logic lives. It is a **router**:
a thin dispatcher that forwards whatever you ask for to the right per-phase
Makefile under `vm/phase0/`, `vm/phase1/`, … `vm/phase5/`. When you type
`make phase 213`, the router looks at the first digit (`2`), changes into
`vm/phase2/`, and runs that phase's Makefile with the step argument `213`. The
same pattern holds for every phase. This keeps each phase's real recipes,
scripts, and probes self-contained while giving you one consistent front door.

A few consequences worth knowing:

- `make phase` with no number, or `make phases`, prints the full numbered map by
  asking each per-phase Makefile to list its own steps.
- `make doctor`, `make stop`, `make cleanup`, and `make up` are *not* phase steps.
  They are top-level convenience targets the router runs across several phases at
  once (for example, `make stop` tells Phase 0, Phase 2, and Phase 4 to each shut
  down their VMs and probes).
- The phase-family words (`make phase 0`, `make phase 4`, …) and the individual
  numbers are both understood by the router; a family word runs every step in
  that phase in order.

## The three-digit numbering scheme

Individual steps use three digits:

```text
002 = Phase 0, step 02
102 = Phase 1, step 02
212 = Phase 2, step 12
213 = Phase 2, step 13
214 = Phase 2, step 14
300 = Phase 3, step 00
400 = Phase 4, step 00
401 = Phase 4, step 01
402 = Phase 4, step 02
403 = Phase 4, step 03
404 = Phase 4, step 04
405 = Phase 4, step 05
406 = Phase 4, step 06
407 = Phase 4, step 07
408 = Phase 4, step 08
409 = Phase 4, step 09
410 = Phase 4, step 10
411 = Phase 4, step 11
412 = Phase 4, step 12
413 = Phase 4, step 13
414 = Phase 4, step 14
415 = Phase 4, step 15
416 = Phase 4, step 16
417 = Phase 4, step 17
418 = Phase 4, step 18
419 = Phase 4, step 19
420 = Phase 4, step 20
421 = Phase 4, step 21
422 = Phase 4, step 22
424 = Phase 4, step 24
425 = Phase 4, step 25
500 = Phase 5, step 00
501 = Phase 5, step 01
502 = Phase 5, step 02
503 = Phase 5, step 03
504 = Phase 5, step 04
505 = Phase 5, step 05
506 = Phase 5, step 06
507 = Phase 5, step 07
508 = Phase 5, step 08
509 = Phase 5, step 09
510 = Phase 5, step 10
511 = Phase 5, step 11
512 = Phase 5, step 12
513 = Phase 5, step 13
```

Read a step number as **PhaseStep**: the first digit is the phase, the last two
are the step within that phase. So `213` is "Phase 2, step 13" and `504` is
"Phase 5, step 04". The numbers only ever go up within a phase, and they encode
dependency order — a higher step assumes every lower step in its phase already
passed. That is why running an individual step out of order can fail: it may
expect an artifact a previous step produced. When in doubt, run the whole family
(`make phase 4`) so the steps execute in sequence.

Numbering is also intentionally sparse in places (for example Phase 4 jumps from
`422` to `424`). Gaps are reserved slots — they leave room to insert or retire
steps without renumbering everything after them.

Examples:

```sh
make phase 002   # build the forge disk
make phase 003   # boot the forge VM
make phase 101   # build branding
make phase 213   # stage the first musl systemd userspace payload
make phase 214   # stage the first kernel module/kmod payload
make phase 212   # run the ONIX boot probe
make phase 300   # document deferred kernel ownership
make phase 400   # start booted-base userspace planning
make phase 401   # materialize live /etc from packaged defaults
make phase 402   # materialize base users/groups/shell policy
make phase 403   # prove bootstrap serial root console
make phase 404   # prove minimal QEMU user networking
make phase 405   # prove host-to-guest TCP inspection
make phase 406   # prove authenticated SSH access
make phase 407   # audit temporary Nix-sourced system payloads
make phase 408   # define local stone/repo contract
make phase 409   # build source-based busybox stone
make phase 410   # install/use busybox in the image
make phase 411   # boot-prove shell/network/SSH with busybox
make phase 412   # build source-based dropbear stone
make phase 413   # install/use dropbear and prove SSH
make phase 414   # audit systemd ownership before packaging
make phase 415   # build bootstrap systemd stone
make phase 416   # install/use systemd in the image
make phase 417   # boot-prove systemd as PID 1 runtime
make phase 418   # package/prove bootstrap policy ownership
make phase 419   # audit booted-base ownership/debt map
make phase 420   # prune stale old Nix BusyBox/Dropbear payloads
make phase 421   # prepare native source-built systemd plan
make phase 422   # build/install/boot-prove native systemd
make phase 424   # boot native ONIX, prove SSH, and leave QEMU running
make phase 425   # final Phase 4 acceptance check against the running VM
make phase 500   # define Rust-first musl-only static-first package law
make phase 501   # define canonical packages/ layout and metadata contract
make phase 502   # provide runtime-clean stone payload audit helper
make phase 503   # copy existing recipes into canonical packages/ layout
make phase 504   # prove essential package builds use canonical recipes
make phase 505   # assemble one canonical local ONIX package repo
make phase 506   # fix/prove reboot and poweroff package ownership
make phase 507   # make image assembly consume the canonical local repo
make phase 508   # assemble local public repo layout without upload
make phase 509   # build/audit first Rust essential stones
make phase 510   # build/audit linux-pam + libseccomp shared-library stones
make phase 511   # build/audit RootAsRole privilege stone
make phase 512   # build/audit live RootAsRole policy stone
make phase 513   # wire uutils command links instead of BusyBox links
make up          # shortcut for the Phase 424 day-to-day bring-up
```

### What a "phase gate" is in practice

Each phase ends in a **gate**: a step (or the final steps of the phase) that acts
as a pass/fail proof for everything before it. A gate is not documentation — it
runs, and it either succeeds or it stops you. For example, Phase 4's `425` is the
acceptance check that the native-systemd ONIX image actually booted and is
reachable over SSH; you are not "done with Phase 4" until it passes. The gate is
the deliverable. Steps below the gate build the thing; the gate proves the thing.

### First-time host check

Before running any phase, confirm your machine has the tools the harness needs:

```sh
make doctor      # common health check
```

`make doctor` asks every per-phase Makefile to self-check and then verifies the
host has the programs the scripts call — QEMU, loop-device and mount tools,
`sgdisk`/`mkfs.*` for partitioning, `chroot`, `bootctl`, `ssh`, `mdbook`, `nix`,
and more. If anything is missing it names the missing command and exits non-zero.
It is a health check, not a phase step, so it never changes state; run it any
time.

## Stopping vs cleaning

Use:

```sh
make stop
```

when a VM/probe is stuck or you want to detach stale mounts while keeping
generated work such as:

```text
vm/state/quarry.raw
artifacts/onix-image/onix.raw
artifacts/onix-stones/
artifacts/onix-local-repo/
```

Use:

```sh
make cleanup
```

only when you intentionally want a destructive reset of generated disks/images.
It stops QEMU first, then removes generated disk/image state.

Think of three verbs with escalating force:

- **`make stop`** is the gentle one. It kills any running QEMU processes and
  boot probes and unmounts anything the scripts left mounted, but it *keeps* your
  built artifacts: the forge disk (`vm/state/quarry.raw`), the assembled image
  (`artifacts/onix-image/onix.raw`), the built stones, and the local repo. Use it
  constantly — whenever a VM hangs, a mount is stuck, or you just want to free the
  machine without throwing away hours of build work.
- **`make cleanup`** is the destructive one. It does everything `stop` does and
  then *deletes* the generated disks and images. Use it when you want a clean
  slate — a fresh forge, a rebuilt image — and are willing to rebuild from
  scratch. It never touches tracked source; only generated output under the paths
  above.
- **`make up`** is the "bring it up and leave it running" one — the day-to-day
  driver, described next.

## Where artifacts live

Everything the phases generate is untracked and lives in two top-level trees:

```text
vm/state/     forge VM disk, generated SSH keys, per-phase runtime state
artifacts/    assembled ONIX images, built .stone packages, local repos
```

`make stop` preserves both; `make cleanup` removes the generated disks/images
within them. Because it is all regenerable, deleting these trees is always safe —
you just pay the rebuild time.

## Booting and driving the machine

To boot the current native-systemd image and leave it running for interactive
inspection:

```sh
make phase 424
ssh -i vm/state/id_ed25519 -p 7630 onix@127.0.0.1
```

`make phase 424` boots the assembled ONIX image under QEMU **headless** — no
window; the VM runs in the background and QEMU forwards a host port to the
guest's SSH port so you can log in. The `ssh` line uses the key the harness
generated (`vm/state/id_ed25519`) and connects to the forwarded port `7630` on
`127.0.0.1` as user `onix`. Port `7630` is not arbitrary: `6649` spells "ONIX" on
a phone keypad and seeds the project's port offsets.

Then accept the running VM:

```sh
make phase 425
```

`make phase 425` is the Phase 4 gate: it runs the acceptance check against the VM
`424` left running and confirms the native-systemd ONIX base is genuinely up and
reachable, not just that QEMU started.

The shortcut is:

```sh
make up
```

`make up` is simply `make phase 424` under a friendlier name — it boots native
ONIX, proves SSH, and leaves QEMU running for you to log into.

Stop that VM with:

```sh
make stop
```

Phase 3 is intentionally reserved for ONIX-owned kernel/initramfs/modules work.
For now ONIX keeps using the borrowed Alpine virt kernel payload proved in Phase
2, and Phase 4 continues with booted userspace work.

`make phase 3` therefore does not build anything — it explains why the kernel
work is deferred. Until that reserved phase lands, ONIX runs on a kernel and
initramfs temporarily borrowed from Alpine's virt image (proved bootable in Phase
2), while all the *userspace* above it — busybox, Dropbear, systemd, policy — is
already ONIX-owned and packaged as stones.

## Attached vs headless, and the serial console

Some phases can be watched interactively:

```sh
ATTACHED=1 make phase 212
make phase 212 ATTACHED=1
```

By default, phase probes run **headless**: the VM boots in the background, the
script watches for success over a serial log or SSH, and you only see the
pass/fail result. That is ideal for scripted, repeatable proofs. Setting
`ATTACHED=1` flips a probe into **attached** mode, where you watch the boot
happen live in your terminal. The two spellings above are equivalent — an
environment variable and a make variable set the same flag.

A **serial console** is a text-only console the kernel and init write to as if
it were an old-fashioned serial terminal, instead of a graphical screen. QEMU
can pipe that serial stream straight to your terminal, which is perfect for a
headless VM: you see every kernel message and init line as plain text, and it is
trivially loggable. This is how the boot probes capture evidence — the serial log
is the transcript that proves what happened during boot.

For Phase 212, attached mode uses the serial console in the current terminal by
default. GUI/VNC only starts when explicitly requested:

```sh
ONIX_BOOT_PROBE_DISPLAY=gtk ATTACHED=1 make phase 212
ONIX_BOOT_PROBE_DISPLAY=vnc ATTACHED=1 make phase 212
```

Most of the time the serial console is all you want — it is faster, scriptable,
and shows the boot messages directly. Ask for a graphical display only when you
need to *see* a framebuffer: `gtk` opens a local QEMU window, and `vnc` exposes a
VNC server you connect to with a viewer (useful on a remote host). If you are
reading a boot that failed, the serial log is almost always where the answer is.

## Book commands

Build the book:

```sh
make book
```

Serve the book locally:

```sh
make book-serve
```

`make book` runs `mdbook build` to render this book once into static HTML.
`make book-serve` starts a local `mdbook` server that rebuilds on change and
serves the pages at a local address, which is the convenient way to read or edit
the docs.

The generated HTML goes under:

```text
site/
```

That directory is generated output and is not committed.
