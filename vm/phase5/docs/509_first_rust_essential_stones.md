# 509 — first Rust essential stones

Run:

```sh
make phase 509
```

Phase 509 starts building the first non-ONIX-specific Rust system packages.

It has two jobs:

```text
uutils-coreutils -> build and accept the first Rust essential .stone
rootasrole       -> select ONIX's sudo-class direction and record the gate
```

This is the first phase where the Phase 500 package law stops being abstract.
The law says:

```text
Rust-first
musl-only
runtime-clean
static/static-PIE first by default
minimal ONIX-owned shared-library surface only by exception
```

`uutils-coreutils` passes the strict static/static-PIE path now. RootAsRole is
selected as the ONIX privilege tool, and Phase 510 turns its PAM/seccomp
dependencies into ONIX-owned shared-library stones.

## Why these two packages

ONIX currently boots because of bootstrap packages:

```text
onix-busybox
onix-dropbear
onix-systemd
onix-bootstrap-policy
```

That is enough to boot, log in, and inspect the machine.

But it is not the final ONIX userland.

The direction is:

```text
basic command family -> Rust uutils
controlled privilege -> RootAsRole dosr/chsr model
```

`uutils-coreutils` gives ONIX a Rust path for the classic command family:

```text
ls cp mv rm cat echo sort wc ...
```

RootAsRole gives ONIX a Rust path for controlled privilege escalation. The
native command is:

```text
dosr
```

In ONIX language, `dosr` is the sudo-equivalent command: the command a user
reaches for when a task needs controlled privilege. A future `/usr/bin/sudo`
compatibility command may point into this model, but the canonical privilege
implementation is RootAsRole.

## The stone catalog

Phase 509 also introduces:

```text
packages/STONES.md
```

This is the human-maintained catalog of ONIX stones.

Generated repo manifests answer:

```text
what files are in this artifact directory right now?
```

The stone catalog answers:

```text
what does each ONIX stone mean?
what group does it belong to?
which phase introduced it?
is it canonical, bootstrap-only, accepted, or gated?
```

When a new stone is accepted, update:

```text
packages/STONES.md
packages/<group>/<stone>/PACKAGE.md
packages/<group>/<stone>/stone.yaml or stone.yaml.in
vm/phaseN/docs/NNN_title.md
```

That keeps package meaning, package recipe, and educational notes together.

## Why `uutils-coreutils` does not yet own `/usr/bin/ls`

This is the most important packaging detail in Phase 509.

`uutils-coreutils` can provide commands such as:

```text
ls
cp
mv
rm
cat
echo
sort
wc
```

But ONIX already has:

```text
onix-busybox
```

and `onix-busybox` currently owns many bootstrap command paths under:

```text
/usr/bin
```

If Phase 509 installed uutils command-name links like:

```text
/usr/bin/ls
/usr/bin/cp
/usr/bin/mv
```

then Moss would see duplicate package ownership:

```text
onix-busybox owns /usr/bin/ls
uutils-coreutils owns /usr/bin/ls
```

That is exactly the class of problem Phase 506 taught us to avoid.

So Phase 509 installs only:

```text
/usr/bin/coreutils
```

That binary is a multicall binary. It contains many utilities, but this package
does not yet claim the command-name paths.

The package records the deferred command list in:

```text
/usr/share/onix/packages/uutils-coreutils.commands
/usr/share/onix/packages/uutils-coreutils.pending-links
```

A later phase should intentionally migrate command ownership:

```text
reduce BusyBox-owned applet links
add uutils-owned command links
prove no duplicate Moss ownership
boot the image
```

That migration should be explicit because command ownership is distro design,
not a side effect.

## Why RootAsRole is selected but gated

RootAsRole fits ONIX better than a direct sudoers clone because its native model
is roles, tasks, and Linux capabilities. That is closer to the kind of system
ONIX wants to grow into:

```text
not "give me all root"
but "allow this role to perform this privileged task"
```

However, Phase 509 still does not package it as a finished `.stone`.

Why?

Because ONIX refined the policy from an earlier static-only rule:

```text
only static system binaries
```

to the more realistic and stricter policy:

```text
static/static-PIE first by default
minimal ONIX-owned shared-library surface only where it makes sense
```

RootAsRole is exactly the kind of package that tests that distinction.

The investigation found:

```text
dosr -> needs PAM
chsr -> needs libseccomp
```

That does not mean "reject RootAsRole forever." It means:

```text
do not ship a half-owned privilege binary
```

Before RootAsRole enters ONIX as a real stone, ONIX needs package-owned stones
for the shared surface:

```text
linux-pam
libseccomp
musl
toolchain runtime, if libgcc_s is still needed
```

Only then can the RootAsRole package honestly say:

```text
these shared libraries are expected
these exact ONIX stones own them
there is no glibc
there is no /nix/store runtime path
there is no random host .so leakage
```

That is why Phase 509 writes a gate report instead of pretending the package is
finished.

## Build model

Phase 509 uses this model:

```text
host Nix
  -> locate pinned source trees for built packages

forge VM
  -> cargo build on Alpine/musl
  -> static/static-PIE musl binary where possible
  -> boulder creates .stone files
  -> moss inspects and installs them
  -> records rootasrole gate

host
  -> copies .stone files back
  -> copies the rootasrole gate report back
  -> refreshes artifacts/onix-local-repo
  -> installs accepted stones into a scratch target
  -> runs the Phase 502 runtime-clean audit
```

The host Nix store is not copied into the payload.

Nix is only source acquisition and build-tool scaffolding.

The payload rule remains:

```text
no /nix/store references
no glibc loader
no unexpected shared libraries
```

For accepted dynamic-musl exceptions later, the extra rule is:

```text
every expected shared library must be documented and ONIX-owned
```

## What `make phase 509` builds

The helper is:

```text
vm/phase5/build-rust-essential-stones.sh
```

It builds one accepted stone and records one gate.

### `uutils-coreutils`

Source:

```text
github.com/uutils/coreutils, pinned through nixpkgs_2
```

Build command shape inside the forge:

```text
cargo rustc \
  --release \
  --locked \
  --no-default-features \
  --features feat_Tier1 \
  --bin coreutils \
  -- \
  -C target-feature=+crt-static
```

Installed payload:

```text
/usr/bin/coreutils
/usr/share/onix/packages/uutils-coreutils.md
/usr/share/onix/packages/uutils-coreutils.commands
/usr/share/onix/packages/uutils-coreutils.pending-links
```

The package is useful immediately for proof and inspection, but it does not yet
replace BusyBox command links.

### `rootasrole`

Source:

```text
https://github.com/LeChatP/RootAsRole
```

Expected future installed payload:

```text
/usr/bin/dosr
/usr/bin/chsr
/usr/share/defaults/rootasrole/
/usr/share/defaults/pam.d/dosr
/usr/share/onix/packages/rootasrole.md
```

Expected future allowed shared-library surface:

```text
libpam.so.0       owner: linux-pam
libseccomp.so.2   owner: libseccomp
ld-musl-*.so.1    owner: musl
libgcc_s.so.1     owner: toolchain runtime package, only if still needed
```

Phase 509 records this as:

```text
artifacts/onix-phase5-work/509/rootasrole.gate.md
```

That gate is a positive decision, not a failure:

```text
RootAsRole is selected.
RootAsRole is not yet accepted as a built stone.
The missing work is the minimal shared-library surface.
```

## What the phase proves

Phase 509 proves:

- source for the built package comes from the pinned `nixpkgs_2` package source;
- the source build runs inside the musl forge VM;
- `uutils-coreutils` builds as a static/static-PIE musl binary;
- `uutils-coreutils` has no shared-library `NEEDED` entries;
- the accepted payload does not contain `/nix/store`;
- boulder can package `uutils-coreutils` into a `.stone`;
- moss can inspect and install that stone;
- RootAsRole is recorded as the ONIX sudo-class direction;
- RootAsRole's required `linux-pam` and `libseccomp` stones are the next
  dependency-surface step;
- the Phase 502 payload audit passes on the installed scratch target.

The host proof target is:

```text
artifacts/onix-phase5-work/509/install-target/
```

The generated stones are copied to:

```text
artifacts/onix-stones/
```

and added to:

```text
artifacts/onix-local-repo/
```

The RootAsRole gate report is:

```text
artifacts/onix-phase5-work/509/rootasrole.gate.md
```

## What this phase does not do yet

Phase 509 does not itself:

- add uutils command-name links to `/usr/bin`;
- remove overlapping BusyBox command-name links;
- build/accept `rootasrole` as a finished `.stone`;
- add `linux-pam` or `libseccomp` stones; Phase 510 does that;
- make RootAsRole part of the boot image;
- materialize live privilege policy under `/etc`;
- add these packages to the canonical public-shaped repo proof.

Those are later integration steps.

This phase is deliberately narrower:

```text
build the first Rust essential stone correctly
select the ONIX privilege path honestly
record the dependency gate instead of hiding it
```

## How to inspect the result

After running:

```sh
make phase 509
```

list the generated stone and gate:

```sh
ls -lh artifacts/onix-stones/uutils-coreutils-*.stone
cat artifacts/onix-phase5-work/509/rootasrole.gate.md
```

Inspect the stone with Moss:

```sh
artifacts/host-tools/bin/moss inspect artifacts/onix-stones/uutils-coreutils-*.stone
```

Inspect the scratch install target:

```sh
find artifacts/onix-phase5-work/509/install-target -maxdepth 4 -type f | sort
```

Run the runtime-clean audit again:

```sh
vm/phase5/audit-stone-payload.sh artifacts/onix-phase5-work/509/install-target
```

## What comes next

After Phase 509, the next useful Phase 5 work is the dependency surface:

```text
510 — build linux-pam and libseccomp as ONIX-owned shared-library stones
511 — build RootAsRole against that owned surface
```

The uutils path is mostly an ownership migration problem:

- decide which command names move from BusyBox to uutils first;
- remove or stop generating the BusyBox-owned links for those paths;
- add uutils-owned links;
- prove no duplicate Moss ownership;
- boot the image.

Phase 510 handles the RootAsRole shared-library-surface problem:

- package `linux-pam`;
- package `libseccomp`;
- then build RootAsRole against those package-owned libraries;
- audit it as a dynamic-musl exception with a very small expected soname list;
- install `dosr` as the ONIX sudo-class command.
