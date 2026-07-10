# Phase 415 — build `systemd.stone`

| Item | Value |
|---|---|
| Command | `make phase 415` |
| Underlying script | `vm/phase4/build-systemd-stone.sh` |
| Recipe template | `vm/phase4/stone-recipes/systemd/stone.yaml.in` |
| Requires | Phase 414 systemd ownership audit |
| Mutates disk/image? | No |
| Boots QEMU? | No |
| Main proof | ONIX can build a moss-installable `systemd` stone for the exact systemd payload Phase 213/414 proved. |

## Why this phase exists

Phase 414 showed the current truth:

```text
/usr/bin/busybox   -> ONIX stone-owned
/usr/sbin/dropbear -> ONIX stone-owned
/usr/lib/systemd   -> still Nix payload-owned
```

So the next machine-plane package is:

```text
systemd
```

Phase 415 builds that package.

It does not install it into the boot image yet.

That separation matters:

```text
415 = can we package the systemd payload as a stone?
416 = can the image consume that stone?
417 = can the machine boot with that stone-owned PID 1 path?
```

Keeping those as separate questions makes failures understandable.

## Why this is not like BusyBox or Dropbear

BusyBox and Dropbear were small enough to build as static musl binaries in the
Alpine forge.

systemd is different.

systemd is not just:

```text
/usr/lib/systemd/systemd
```

The booted system currently depends on:

- the PID 1 binary,
- `systemd-udevd`,
- `systemctl`,
- `journalctl`,
- `udevadm`,
- `systemd-tmpfiles`,
- `systemd-sysusers`,
- system unit files,
- user unit files,
- generators,
- udev rules and helpers,
- libsystemd/libudev pieces,
- kmod/libkmod integration,
- util-linux helper integration,
- the musl dynamic loader path.

So Phase 415 must not make a fake package that only contains one executable.

It packages the full currently proven payload boundary.

## Background: a BOOTSTRAP stone vs a NATIVE stone

ONIX distinguishes two very different kinds of `.stone`, and Phase 4 uses both:

- A **BOOTSTRAP stone** repackages a payload that was *not* built by ONIX from source.
  Here, the systemd bytes were produced by a pinned Nix expression
  (`pkgsMusl.systemd`); Phase 415 simply wraps that proven payload in a stone so a
  moss-owned ownership boundary exists. The bytes are borrowed; only the *ownership*
  is ONIX's. A bootstrap stone typically still carries `/nix/store` runtime paths and
  hides its dependency edges — compromises a real package would never make.

- A **NATIVE stone** is built by boulder from upstream source, in the musl forge,
  with no `/nix/store` runtime dependency. This is the endgame shape for every ONIX
  system package. Phase 422 produces the native `systemd`; Phases 421–422 are
  the whole point of eventually retiring the bootstrap version built here.

Why not skip straight to native? Because systemd is enormous, and building it
natively on musl is its own hard problem (Phase 422 hits real build gotchas). Doing
the *ownership* move (bootstrap stone) and the *source* move (native stone) as
separate steps means that if something breaks, you know which move broke it. Phase
415 deliberately does only the ownership move.

## Important honesty: bootstrap ownership package

This first `systemd` package is a bootstrap ownership package.

The payload was already built by pinned:

```text
nixpkgs pkgsMusl.systemd
```

Phase 415 packages that proven payload into:

```text
systemd-...stone
```

That means:

```text
Nix still built the systemd bits.
Moss/stone now has the machine-plane ownership boundary.
```

This is not the final state.

The final direction is still:

```text
native ONIX recipe builds systemd and its dependencies as ONIX stones
```

But doing both at once would mix too many risks:

```text
systemd source build problems
runtime dependency problems
unit tree ownership problems
image install problems
boot problems
```

Phase 415 isolates the first problem:

```text
Can ONIX package the exact proven systemd payload as a stone?
```

## What the package contains

The package contains the current systemd runtime closure from:

```text
artifacts/onix-image/systemd-payload.closure
```

But there is an important packaging rule here.

Boulder/moss packages normal system payload under:

```text
/usr/...
```

It does not treat arbitrary root-level payload like this as normal package
content:

```text
/nix/store/...
```

So Phase 415 does not try to fight the package manager.

Instead, the stone carries the Nix-built systemd closure under a package-owned
bootstrap area:

```text
/usr/lib/onix/bootstrap/nix/store/...
```

That path is owned by the `systemd` package because it lives under `/usr`.

Then Phase 416 will materialize that bootstrap copy into the image root at:

```text
/nix/store/...
```

That second step is image assembly work, not stone packaging work.

This split is important:

```text
Phase 415 = can a stone carry the proven systemd closure?
Phase 416 = can image assembly materialize it where the runtime needs it?
```

Why do we still need `/nix/store` at boot?

The binaries are dynamically linked against the musl loader path inside the Nix
store:

```text
/nix/store/...-musl-.../lib/ld-musl-x86_64.so.1
```

That path is baked into the ELF interpreter field.

If the image does not provide that exact path, the kernel can find the systemd
file but cannot execute it.

So the first `systemd` stone owns the bytes under:

```text
/usr/lib/onix/bootstrap/nix/store
```

and the next phase places a runtime copy at:

```text
/nix/store
```

Later native ONIX systemd work should remove this `/nix/store` dependency.

## Directory mode gotcha

Nix store directories are commonly not writable by normal users.

That is fine for a live Nix store, but it is awkward for package extraction.

An extractor may create a directory first and then create children inside it.
If the directory was restored as non-writable too early, extraction can fail
with:

```text
EACCES: Permission denied
```

So Phase 415 normalizes directories inside the packaged bootstrap store to:

```text
0755
```

This does not change the actual systemd file bytes or symlink graph.

It only makes the `.stone` safe to extract and install in disposable non-root
test roots.

Later, when ONIX has a native system package graph, we can decide exactly what
the final `/nix/store` replacement or compatibility area should look like.

## Dependency metadata gotcha

Boulder analyzes ELF files automatically.

That is usually excellent.

For a normal dynamic program, boulder sees something like:

```text
program needs libfoo.so.1
```

and records:

```text
soname(libfoo.so.1(x86_64))
```

as a runtime dependency.

For this bootstrap `systemd` stone, though, the dependency graph is already
bundled inside the package under:

```text
/usr/lib/onix/bootstrap/nix/store
```

So if we let the automatic dependency metadata stand, moss tries to find
separate packages for things like:

```text
interpreter(/nix/store/.../ld-musl-x86_64.so.1(x86_64))
soname(libacl.so.1(x86_64))
soname(libstdc++.so.6(x86_64))
```

That is wrong for this phase.

Those dependencies are not separate ONIX stones yet.

They are part of the bundled bootstrap closure.

So the recipe uses:

```text
rundeps-exclude
```

to suppress the auto-detected external runtime dependencies for this one
bootstrap package.

It also uses:

```text
provides-exclude
```

so the internal bootstrap libraries do not look like public system-library
providers.

This is a temporary bootstrap compromise.

Later native ONIX packages should not hide real dependency edges this way.

## `/usr` activation symlinks

The package also contains `/usr` symlinks that match the active Phase 213 image
shape.

Important examples:

```text
/usr/lib/systemd/systemd
  -> /nix/store/...-systemd-.../lib/systemd/systemd

/usr/lib/systemd/system
  -> /nix/store/...-systemd-.../example/systemd/system

/usr/lib/systemd/user
  -> /nix/store/...-systemd-.../example/systemd/user

/usr/bin/systemctl
  -> /nix/store/...-systemd-.../bin/systemctl
```

These symlinks are what Phase 416 will use when installing the package into the
image.

In a disposable moss install target these symlinks may be unresolved by
themselves, because the target has not yet materialized `/nix/store`.

That is expected for Phase 415.

The Phase 415 proof checks two different things:

```text
1. the real bytes exist under /usr/lib/onix/bootstrap/nix/store
2. the runtime symlinks point at the /nix/store paths the image must provide
```

## What metadata the package records

The stone installs package notes under:

```text
/usr/share/onix/packages/
```

The important files are:

```text
/usr/share/onix/packages/systemd.md
/usr/share/onix/packages/systemd.closure
/usr/share/onix/packages/systemd.links
```

They record:

- which systemd output was packaged,
- which closure paths were included,
- which `/usr` symlinks were staged,
- that this is a bootstrap ownership package.

That metadata matters because Phase 415 is intentionally transitional.

The package itself should tell future us what it is and what it is not.

## What the script does

Run:

```sh
make phase 415
```

The host-side script:

```text
vm/phase4/build-systemd-stone.sh
```

does this:

1. Reads:

   ```text
   artifacts/onix-image/systemd-payload.out
   artifacts/onix-image/systemd-payload.closure
   ```

2. Verifies the systemd binary exists and uses the musl loader.

3. Verifies every closure path exists on the host.

4. Creates a prepared payload tree:

   ```text
   usr/lib/onix/bootstrap/nix/store/...
   usr/lib/systemd/...
   usr/bin/...
   usr/share/onix/packages/...
   ```

5. Archives that prepared payload.

6. Sends the payload and recipe template to the forge VM.

7. Uses `boulder` to build:

   ```text
   systemd-...stone
   ```

8. Uses `moss inspect --check` to validate the stone.

9. Extracts the stone and verifies the payload layout.

10. Installs the stone into a disposable Moss target.

11. Copies the stone back to:

    ```text
    artifacts/onix-stones/
    ```

12. Refreshes:

    ```text
    artifacts/onix-local-repo/stone.index
    ```

## What this phase proves

Phase 415 proves:

- the current systemd runtime closure can be represented as a `.stone`,
- Boulder can package that payload,
- Moss can inspect it,
- Moss can install it into a target root,
- the package contains the current PID 1 bytes under the bootstrap store,
- the package contains the current systemd unit tree under the bootstrap store,
- the package contains the command symlinks needed by the current image shape.

That is enough to move to image consumption in Phase 416.

## What this phase does not prove

Phase 415 does not prove:

- the image boots from the package,
- old Nix-copied systemd files can be deleted,
- the bootstrap store has been materialized to `/nix/store`,
- systemd has a native ONIX source recipe,
- dependency stones are split correctly,
- bootstrap units are package-owned in their final location.

Those are later steps.

Especially:

```text
Phase 415 does not boot QEMU.
```

Boot proof belongs after the image consumes the package.

## Expected output shape

Successful output should include:

```text
==> success
systemd stone: artifacts/onix-stones/systemd-...
local repo index  : artifacts/onix-local-repo/stone.index

Next:
  make phase 416
```

After that, the local Phase 4 repo should contain at least:

```text
busybox
dropbear
systemd
```

## Next step

Phase 416 should install/use `systemd` in the ONIX image.

That means the image should consume the package payload from:

```text
artifacts/onix-local-repo
```

and materialize:

```text
/usr/lib/onix/bootstrap/nix/store/... -> /nix/store/...
```

inside the assembled image root.

Phase 417 should then boot-prove the result.
