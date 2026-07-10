# 602 — nix stone package

This phase packages nix itself as ONIX system software.

## Important rule

nix is allowed to manage `/nix/store`.

But nix itself must be installed by ONIX:

```text
moss installs nix.
nix then manages /nix/store.
```

That means `/usr/bin/nix` must not be a symlink into a host store path.

Bad:

```text
/usr/bin/nix -> /nix/store/.../bin/nix
```

Good:

```text
/usr/bin/nix
/usr/bin/nix-daemon
```

## Rust-first exception

nix is not Rust. It is a C++ package with a large dependency surface.

For ONIX this is acceptable only because nix has no fully compatible serious
Rust replacement today. The `PACKAGE.md` must state that clearly as a
Rust-first exception.

## musl and shared libraries

This package may be a dynamic-musl exception. That is okay if every shared
library is:

- necessary;
- documented;
- packaged as an ONIX-owned stone;
- free of glibc;
- free of runtime host `/nix/store` references.

The first implementation should still try the static/static-pie path first, but
we should expect nix to need a managed shared-library surface.

## Likely package split

The first pass may need more than one stone:

```text
nix
nix-policy
nix-libs or explicit dependency libs, if needed
ca-certificates, if not already owned well enough
```

We should not decide the exact split blindly. Phase 602 should inspect the real
build output and let the dependency facts decide.

## Planned proof

Phase 602 should prove in a scratch install target:

```sh
/usr/bin/nix --version
/usr/bin/nix-daemon --version
vm/phase5/audit-stone-payload.sh --allow-dynamic-musl install-target
```

It should also reject:

```text
glibc loader paths
/nix/store references baked into /usr/bin/nix
/nix/store RPATH/RUNPATH
```
