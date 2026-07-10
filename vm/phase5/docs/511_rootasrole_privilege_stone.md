# 511 — RootAsRole privilege stone

Run:

```sh
make phase 511
```

Phase 511 builds ONIX's first real sudo-class package:

```text
rootasrole
```

The user-facing command is:

```text
/usr/bin/dosr
```

ONIX treats `dosr` as the native sudo-equivalent command. It is not a clone of
sudo's policy model. RootAsRole is role-based: users get roles, roles contain
tasks, and tasks describe what command/capability/user transition is allowed.

## Why this phase comes after 510

RootAsRole is written in Rust, which fits the Phase 5 Rust-first rule. But it is
not a fully static binary in the current ONIX forge.

The two binaries need these library surfaces:

```text
dosr -> PAM
chsr -> libseccomp
```

That is why Phase 510 had to happen first. Phase 510 made these libraries
ONIX-owned stones:

```text
musl
linux-pam
libseccomp
```

Without those stones, RootAsRole would build against whatever happened to exist
inside the Alpine forge VM. That would produce a binary that works today but is
not really owned by ONIX.

Phase 511 fixes that by creating a build sysroot from ONIX stones and making
Cargo link against that sysroot.

## What a build sysroot is

A **sysroot** is a fake root filesystem used during compilation.

For example, instead of letting the compiler search the forge machine directly:

```text
/usr/include
/usr/lib
```

Phase 511 asks Moss to install ONIX stones into a scratch directory:

```text
stone repo
  -> moss install --to sysroot
  -> sysroot/usr/include
  -> sysroot/usr/lib
```

Then the build runs with:

```text
PKG_CONFIG_PATH=sysroot/usr/lib/pkgconfig
PKG_CONFIG_LIBDIR=sysroot/usr/lib/pkgconfig
LIBRARY_PATH=sysroot/usr/lib
C_INCLUDE_PATH=sysroot/usr/include
RUSTFLAGS=-L native=sysroot/usr/lib
```

That means:

- `libpam-sys` sees ONIX's PAM headers/libs;
- `libseccomp` sees ONIX's seccomp headers/libs;
- the final binary has normal soname dependencies;
- the finished package does not contain the sysroot path.

This is the important distinction:

```text
build-time path     : temporary sysroot
runtime dependency  : soname owned by an ONIX stone
```

Runtime must never depend on the build sysroot path.

## The musl loader dependency detail

Dynamic musl executables contain an ELF interpreter path. For these binaries it
is:

```text
/lib/ld-musl-x86_64.so.1
```

ONIX images are **usr-merged**. That means `/lib` is expected to point at
`/usr/lib` on a real installed system. The `musl` stone owns:

```text
/usr/lib/ld-musl-x86_64.so.1
/usr/lib/libc.musl-x86_64.so.1
```

So the loader is still ONIX-owned. The awkward part is metadata: Boulder records
the musl package as providing the libc soname, but it does not currently emit
the exact provider:

```text
interpreter(/lib/ld-musl-x86_64.so.1(x86_64))
```

RootAsRole also depends on:

```text
soname(libc.musl-x86_64.so.1(x86_64))
```

That soname dependency already pulls in the `musl` stone. Therefore the
RootAsRole recipe excludes only the exact synthetic interpreter dependency while
keeping the real musl dependency. This is not permission to hide arbitrary
runtime edges. It is a narrow workaround for the usr-merged musl loader metadata
shape.

## The libgcc-runtime discovery

The RootAsRole probe showed this final ELF truth:

```text
dosr:
  NEEDED libpam.so.0
  NEEDED libgcc_s.so.1
  NEEDED libc.musl-x86_64.so.1

chsr:
  NEEDED libseccomp.so.2
  NEEDED libgcc_s.so.1
  NEEDED libc.musl-x86_64.so.1
```

`libgcc_s.so.1` is the GCC runtime shared object. It is not Rust code and it is
not a feature we wanted to add casually, so Phase 511 tries the reduction path
first:

```text
-static-libgcc  -> still needs libgcc_s.so.1
panic=abort     -> still needs libgcc_s.so.1
+crt-static     -> not usable for this build in the forge
```

So ONIX accepts a tiny explicit runtime stone:

```text
libgcc-runtime
```

This keeps the rule honest:

```text
no random forge library at runtime
```

If RootAsRole needs `libgcc_s.so.1`, ONIX owns a `libgcc-runtime` stone that
provides it.

Later, when ONIX has an owned compiler toolchain phase, this bootstrap runtime
stone should be replaced by a source-built ONIX compiler-runtime package or
eliminated if the toolchain can do so cleanly.

## What gets built

Phase 511 builds two stones:

```text
libgcc-runtime
rootasrole
```

`libgcc-runtime` owns:

```text
/usr/lib/libgcc_s.so.1
/usr/lib/libgcc_s.so
/usr/share/onix/packages/libgcc-runtime.md
```

`rootasrole` owns:

```text
/usr/bin/dosr
/usr/bin/chsr
/usr/share/defaults/rootasrole/rootasrole.json
/usr/share/defaults/pam.d/sr
/usr/share/defaults/pam.d/dosr
/usr/share/onix/packages/rootasrole.md
```

`dosr` is the command humans type. `sr` is the PAM service name RootAsRole opens
internally. The package therefore ships both default sample names so the later
live policy phase does not teach the wrong service name.

`dosr` is installed setuid root:

```text
mode 4755
```

That is required for a sudo-class privilege tool. The phase proves the mode, but
it does not yet enable live machine policy.

## Why defaults are not live policy

Phase 511 packages defaults under:

```text
/usr/share/defaults/rootasrole/
/usr/share/defaults/pam.d/
```

It deliberately does **not** write live policy directly into:

```text
/etc/security/rootasrole.json
/etc/pam.d/sr
/etc/pam.d/dosr
```

Reason: privilege policy is security-sensitive machine state. A package can ship
safe defaults and examples, but ONIX needs a later integration phase to decide
how live policy is materialized, audited, and updated.

So Phase 511 answers:

```text
Can ONIX build and install RootAsRole as a clean owned package?
```

It does not yet answer:

```text
What exact ONIX role policy should every installed machine enable?
```

That comes next.

## Why the phase does not run `dosr`

It is tempting to finish the phase with:

```text
dosr --version
```

But RootAsRole is a privilege-policy tool, not a simple leaf command. Even a
basic command invocation can touch the live RootAsRole configuration path. Phase
511 only installs safe package defaults under `/usr/share/defaults`; it does not
create the live machine policy under `/etc`.

So the proof for this phase is deliberately:

```text
install the stone
check dosr exists
check dosr is setuid root
check chsr exists
check exact shared-library dependencies
check no /nix/store or glibc leakage
```

The first phase that creates live `/etc/security/rootasrole.json` and
`/etc/pam.d/sr` should be the first phase allowed to execute `dosr` as a real
machine command.

## What the phase proves

Phase 511 proves:

- RootAsRole source is pinned to `v4.0.0`;
- the resolved commit matches the expected pin;
- Cargo builds `dosr` and `chsr` with locked dependencies;
- the build uses an ONIX-owned PAM/seccomp/libgcc/musl sysroot;
- boulder cuts `libgcc-runtime` and `rootasrole` stones;
- host Moss can inspect both stones;
- the local ONIX repo is refreshed;
- Moss can install `rootasrole` and automatically pull its owned shared surface;
- `/usr/bin/dosr` is installed with mode `4755`;
- `/usr/bin/chsr` is installed executable;
- `/usr/share/defaults/pam.d/sr` and `/usr/share/defaults/pam.d/dosr` are present;
- no `/nix/store` runtime paths leak into the installed target;
- no glibc loader appears;
- the exact allowed runtime dependencies are:

  ```text
  dosr -> libpam.so.0, libgcc_s.so.1, libc.musl-x86_64.so.1
  chsr -> libseccomp.so.2, libgcc_s.so.1, libc.musl-x86_64.so.1
  ```

Anything outside that list fails the phase.

## Result locations

Generated stones:

```text
artifacts/onix-stones/libgcc-runtime-*.stone
artifacts/onix-stones/rootasrole-*.stone
```

Local repo copies:

```text
artifacts/onix-local-repo/libgcc-runtime-*.stone
artifacts/onix-local-repo/rootasrole-*.stone
artifacts/onix-local-repo/stone.index
```

Proof target:

```text
artifacts/onix-phase5-work/511/install-target/
```

## What comes next

The next step is RootAsRole policy integration.

Questions for the next phase:

- Where should ONIX materialize live `/etc/security/rootasrole.json`?
- Should the first policy allow only `root`, or also the build/admin user?
- What should `/etc/pam.d/sr` include in a minimal ONIX system?
- Should ONIX provide `/usr/bin/sudo` as a compatibility wrapper to `dosr`?

Phase 511 gives us the package. The next phase decides the machine policy.
