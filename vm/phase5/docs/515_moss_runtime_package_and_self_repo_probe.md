# 515 — `moss` runtime package and self-repo probe

Phase 515 packages `moss` itself.

That sounds small, but it is an important distro milestone.

Before this step, ONIX used `moss` mostly from the outside:

```text
host moss / forge moss -> install stones into a scratch target or image
```

After this step, the booted ONIX machine contains:

```text
/usr/bin/moss
```

owned by a `.stone` package.

That lets ONIX begin moving from:

```text
host-assembled image
```

toward:

```text
self-inspecting, self-consuming package-managed system
```

## Why `moss` before more random packages?

It is tempting to immediately add more essentials: editors, networking tools,
archive tools, compilers, and so on.

But if ONIX adds many packages before shipping its own package manager, every
later proof still depends on host-side magic. The machine boots, but the machine
itself cannot yet ask basic package questions:

```text
what repositories do I know?
what packages are available?
what files would this package install?
can I install a package into a target root?
```

Phase 515 closes that gap for the first time.

## What is `moss`?

`moss` is the package and system-state manager from AerynOS tooling. ONIX is
currently using the AerynOS `.stone` format, so `moss` is the tool that knows
how to:

- read a repository index;
- inspect package metadata;
- fetch package payloads;
- install packages into a target root;
- track installed state;
- support transaction-style state changes.

`boulder` and `moss` are related but different:

```text
boulder -> build a .stone package from a recipe
moss    -> consume .stone packages and manage installed state
```

That is why Phase 515 packages only `moss`. `boulder` is a forge/build tool and
can remain outside the runtime image for now.

## What this phase builds

Phase 515 builds:

```text
moss.stone
```

from the pinned `os-tools` commit already used by ONIX bootstrap tooling.

The package installs:

```text
/usr/bin/moss
/usr/share/onix/packages/moss.md
```

The package contract lives at:

```text
packages/core/moss/PACKAGE.md
packages/core/moss/stone.yaml.in
```

## Why static musl here?

`moss` is a runtime package manager. If the package manager itself accidentally
depends on `/nix/store`, glibc, or random host libraries, the system's recovery
story gets worse immediately.

So Phase 515 keeps the strict model:

```text
Rust source
Alpine/musl forge build
static/static-pie musl payload
no shared runtime surface
no /nix/store reference
```

This is different from packages such as RootAsRole. RootAsRole honestly needs a
small shared surface today: PAM, seccomp, musl, and the current libgcc runtime.
`moss` should not need that exception for the first runtime package.

## What "self-repo probe" means

This phase does **not** yet make the booted ONIX system manage `/` with a
complete persistent moss system database.

That will come later.

Phase 515 proves a smaller and safer thing:

```text
the packaged /usr/bin/moss inside the booted VM can consume an ONIX repo
```

The live proof does this:

1. Build and audit `moss.stone`.
2. Add `moss.stone` to the canonical local ONIX repo.
3. Install the Phase 5 runtime package set into the image, now including
   `moss`.
4. Boot the VM with native systemd.
5. Copy the current canonical repo into a scratch directory inside the VM.
6. From inside the VM, run packaged `/usr/bin/moss`.
7. Add the scratch repo as a `file://` repository.
8. Query package metadata.
9. Scratch-install `moss` and `uutils-coreutils` into a temporary target root.

The important line is:

```text
/usr/bin/moss inside ONIX reads an ONIX repository and installs ONIX stones
```

That is the first package-manager runtime proof.

## Why install into a scratch target instead of `/`?

Because ONIX does not yet have its final live system-state model.

The image was originally assembled by host-side moss and then copied into the
disk image. That means the booted machine has package-owned files, but not yet a
fully designed persistent moss database for managing `/` live.

Installing straight into `/` before that design exists would mix two problems:

```text
1. does the moss binary work inside ONIX?
2. how should ONIX manage live system state on the real root filesystem?
```

Phase 515 answers only the first question.

So the proof uses:

```text
/tmp/onix-phase515-work/root
/tmp/onix-phase515-work/cache
/tmp/onix-phase515-work/target
```

That keeps the probe honest and reversible.

## Commands

Run:

```sh
make phase 515
```

Rebuild even if a previous `moss.stone` exists:

```sh
ONIX_PHASE515_REBUILD=1 make phase 515
```

Keep the VM running after the proof:

```sh
ONIX_PHASE515_KEEP_RUNNING=1 make phase 515
```

## Expected success marker

The live VM proof should print:

```text
ONIX_PHASE515_REMOTE_OK
```

That marker means:

- `/usr/bin/moss` exists in the booted VM;
- it is installed from the ONIX `moss.stone`;
- it can read a `file://` ONIX repository from inside the VM;
- it can query `moss`, `uutils-coreutils`, `rootasrole`, and `systemd`;
- it can scratch-install `moss` and `uutils-coreutils`.

## What this does not solve yet

Phase 515 does not yet solve:

- persistent repo configuration under the real system root;
- live upgrades of `/`;
- rollback UX from inside ONIX;
- repository signing;
- HTTP hosting at `repo.onix-os.com`;
- building packages inside ONIX itself.

Those are later package/repository/system-state steps.

Phase 515 is still the correct next step because it gives the booted system the
tool it needs before ONIX starts growing many more packages.
