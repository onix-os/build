# 510 — privilege shared-library surface

Run:

```sh
make phase 510
```

Phase 510 fixes the problem Phase 509 exposed.

Phase 509 selected RootAsRole as the ONIX sudo-class direction, but RootAsRole
needs two system library surfaces:

```text
dosr -> PAM
chsr -> libseccomp
```

Phase 510 makes those surfaces ONIX-owned stones:

```text
musl
linux-pam
libseccomp
```

This is the difference between a real distro package and a host leak.

## Why this phase exists

The static-first policy says:

```text
try static/static-PIE musl first by default
```

It does **not** say:

```text
pretend shared-library ABIs do not exist
```

PAM is explicitly a shared-library and module system. libseccomp is a small
shared library that upstream privilege/sandboxing tools commonly link against.

If ONIX wants RootAsRole, the correct move is not to keep saying "blocked on
PAM/libseccomp." The correct move is:

```text
package musl as the ONIX-owned libc soname provider
package PAM as ONIX-owned linux-pam stone
package libseccomp as ONIX-owned libseccomp stone
audit both as intentional dynamic-musl exceptions
then build RootAsRole against those stones
```

That is Phase 510.

## What gets built

### `musl`

`musl` owns the libc/loader soname that dynamic-musl packages depend on:

```text
/usr/lib/ld-musl-x86_64.so.1
/usr/lib/libc.so -> ld-musl-x86_64.so.1
/usr/lib/libc.musl-x86_64.so.1 -> ld-musl-x86_64.so.1
```

The important package-manager fact is that this stone provides the musl libc
soname needed by dynamic ELF files.

This package exists because Moss dependency resolution should not have to assume
"the base image probably has libc." If a dynamic-musl package declares a libc
dependency, the repository should have an ONIX stone that provides it.

There is one subtle detail here. Booted Linux programs often ask the kernel for:

```text
/lib/ld-musl-x86_64.so.1
```

but ONIX image roots are usr-merged:

```text
/lib -> /usr/lib
```

So the package owns the real ELF at `/usr/lib/ld-musl-x86_64.so.1`. In a full
image, `/lib/ld-musl-x86_64.so.1` resolves to that file through the `/lib`
symlink. That keeps the package manager happy and keeps the boot/runtime path
compatible with normal musl binaries.

### `linux-pam`

`linux-pam` owns the PAM ABI and module surface:

```text
/usr/lib/libpam.so*
/usr/lib/libpam_misc.so*
/usr/lib/libpamc.so*
/usr/lib/security/*.so
/usr/include/security/*.h
/usr/lib/pkgconfig/pam*.pc
/usr/share/onix/packages/linux-pam.md
```

This first package keeps live `/etc/pam.d` policy out of the stone. Live machine
policy should be materialized deliberately later. The stone owns the library
surface, not the machine's final authentication policy.

### `libseccomp`

`libseccomp` owns the seccomp filtering ABI:

```text
/usr/lib/libseccomp.so*
/usr/include/seccomp.h
/usr/lib/pkgconfig/libseccomp.pc
/usr/share/onix/packages/libseccomp.md
```

RootAsRole's `chsr` can use this later instead of linking against an
uncontrolled forge library.

## Why these are dynamic-musl exceptions

A normal ONIX command should first try to be static/static-PIE musl.

These packages are different: they *are* library surfaces.

The acceptance rule is therefore:

```text
dynamic musl is allowed
glibc is still forbidden
/nix/store runtime paths are still forbidden
every shared object must be package-owned
```

The Phase 502 audit helper is run with:

```sh
vm/phase5/audit-stone-payload.sh --allow-dynamic-musl ...
```

That does not weaken the policy. It switches from "no shared libraries" to
"shared libraries are expected here, so prove they are clean and owned."

## Build model

Phase 510 uses this model:

```text
host Nix
  -> locate pinned linux-pam/libseccomp sources from nixpkgs_2

forge VM
  -> installs build tools needed for Meson/autotools
  -> builds musl from source
  -> builds linux-pam from source on musl
  -> builds libseccomp from source on musl
  -> creates payload archives
  -> boulder cuts .stone packages
  -> moss installs them into a scratch root

host
  -> copies stones back
  -> refreshes artifacts/onix-local-repo
  -> installs both stones with host moss
  -> audits the scratch target as an intentional dynamic-musl surface
```

The build tools may come from the forge environment, but the installed payload
must not contain `/nix/store`, glibc, or random host paths.

## What this phase proves

Phase 510 proves:

- `musl` has package metadata under `packages/libs/musl/`;
- `linux-pam` has package metadata under `packages/libs/linux-pam/`;
- `libseccomp` has package metadata under `packages/libs/libseccomp/`;
- both are listed in `packages/STONES.md`;
- all three build in the musl forge VM;
- boulder can cut all three into `.stone` packages;
- moss can inspect and install all three packages;
- the installed proof target contains:

  ```text
  /usr/lib/ld-musl-x86_64.so.1
  /usr/lib/libpam.so.0
  /usr/lib/libseccomp.so.2
  ```

- the Phase 502 audit passes with dynamic musl explicitly allowed.

## Result locations

Generated stones:

```text
artifacts/onix-stones/linux-pam-*.stone
artifacts/onix-stones/libseccomp-*.stone
artifacts/onix-stones/musl-*.stone
```

Local repo copies:

```text
artifacts/onix-local-repo/linux-pam-*.stone
artifacts/onix-local-repo/libseccomp-*.stone
artifacts/onix-local-repo/musl-*.stone
artifacts/onix-local-repo/stone.index
```

Proof target:

```text
artifacts/onix-phase5-work/510/install-target/
```

## What comes next

After Phase 510, RootAsRole is no longer blocked on missing dependency stones.

The next step is:

```text
511 — build RootAsRole against ONIX-owned linux-pam + libseccomp
```

That step should build and install:

```text
/usr/bin/dosr
/usr/bin/chsr
```

and audit the result with this expected shared surface:

```text
libpam.so.0       owner: linux-pam
libseccomp.so.2   owner: libseccomp
ld-musl-*.so.1    owner: musl/base runtime
```
