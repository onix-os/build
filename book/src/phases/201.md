# Phase 201 — assemble the first ONIX root tree

## At a glance

| Field | Value |
|---|---|
| Phase family | Phase 2 — bootable image |
| Run command | `make phase 201` |
| Underlying make target/script | `vm/phase2/build-root-tree.sh` |
| Runs on | host plus guest over SSH |
| Main proof/artifact | Assembles artifacts/onix-root-tree/ through the older forge bridge path. |


Phase 201 is the first big conceptual jump in Phase 2.

Before this point, we proved packages in disposable Moss test targets. Phase
201 starts acting like an image builder:

```text
exported repo artifact -> package install -> root filesystem tree
```

### Background: what "assemble a root tree" means

A **root tree** is a directory on the host that has the *shape* of a Linux root
filesystem — `usr/`, `etc/`, `boot/`, `dev/`, and so on — but is still just a
folder. It is what an image builder fills before it ever touches a disk. The way
you fill it is to point a package manager at an empty directory and tell it
"install these packages *into here* instead of into the running system". moss
does exactly that with `install --to <dir>`: it unpacks each `.stone`'s
`/usr` payload into the target directory and records the transaction, without
altering the machine you are running on.

So "assemble a root tree" = run moss against a fresh empty directory, let it lay
down the package-owned files, then add the handful of root-level files that no
package owns (the image's `/etc` glue). The result is a self-contained tree you
can later copy byte-for-byte into a real partition.

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

> **Guest moss vs host moss.** moss is a single Rust binary, but *where it runs*
> matters. The **forge** (the Alpine musl VM, hostname `quarry`) already has moss
> from Phase 0 — that is "guest moss". The host — your dev machine — does not have
> it yet. Phase 201 borrows guest moss over SSH to do the unpack, because only
> moss can read a `.stone`. Phase 202 removes that dependency by building moss on
> the host; Phase 203 then re-does this assembly with host moss and no SSH.

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

Concretely, the script `tar`-streams the exported repo into the forge over SSH,
runs `moss repo add` + `repo update` + `install --to` inside the forge to build
the tree, then `tar`-streams the finished tree back to the host and re-verifies
it there. Two machines, one artifact.

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
/usr/share/defaults/etc/profile
/usr/share/defaults/etc/profile.d/onix-path.sh
/usr/share/defaults/etc/profile.d/onix-login.sh
```

Notice that every package-owned path is under `/usr`. That is not an accident —
it is the central ownership rule of an atomic distro.

> **Why packages only own `/usr`.** ONIX's machine plane is *stateless* under
> `/usr`: moss swaps the whole `/usr` tree atomically (via a `renameat2` swap of
> directories) on every transaction, so a rollback is just pointing back at the
> previous `/usr`. That only works if nothing you want to *keep* lives in `/usr`.
> Live machine state — the actual `/etc/fstab`, `/etc/hostname`, `/etc/os-release`
> — lives outside `/usr`. Packages therefore ship *defaults* under
> `/usr/share/defaults/etc/`, and image assembly copies (or symlinks) them into
> the live `/etc`. Package data is atomic and disposable; `/etc` is persistent
> and machine-local.

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
/etc/profile
/etc/profile.d/onix-path.sh
/etc/profile.d/onix-login.sh
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
  file under `/usr/lib`. Because it is a *relative* symlink
  (`../usr/lib/os-release`), it keeps pointing at whatever `/usr` moss has
  currently swapped in — the identity follows the active transaction for free.
- `/etc/issue`, `/etc/motd`, `/etc/fstab`, `/etc/profile`, and
  `/etc/profile.d/*.sh` are materialized from packaged defaults. These are copied
  (not symlinked) because they are live, editable machine config — the sort of
  file an admin may change and expect to persist across a moss update.
- runtime/kernel directories such as `/dev`, `/proc`, `/sys`, and `/run` are
  created as empty mount points/placeholders. They are not package payload —
  their contents are views of the running kernel, created at boot, not files that
  belong to any package.
- `/tmp` gets sticky permissions (`1777`) because users/processes share it; the
  sticky bit stops one user from deleting another's files there.

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

That last check matters more than it looks: moss keeps its own bookkeeping
(`.moss`, `moss-root`, `moss-cache`) while it installs. None of that belongs in a
shipped root tree, so the script explicitly fails if any of it survives into the
exported artifact. A clean tree contains only the OS, not the machinery that
built it.

#### What Phase 201 does not prove

Phase 201 does **not** prove bootability.

The root tree still has no real ONIX kernel package, no init system package, no
bootloader installation, no partition table, and no mounted filesystems. Those
are later Phase 2 steps.

The point of this phase is to make the next step smaller. After 201, disk image
work can consume a known-good root tree instead of solving packaging,
repository, filesystem policy, and disk layout all at once.
