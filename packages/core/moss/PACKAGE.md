# moss

## Role

`moss` is the ONIX package/state manager.

Earlier phases used a host-side or forge-side `moss` binary as bootstrap
tooling. Phase 515 turns `moss` into an ONIX-owned system package so a booted
ONIX machine can inspect and consume an ONIX repository from inside the VM.

## Implementation language

Rust.

## Rust alternative considered

Not needed. `moss` is already Rust and is the package manager used by the
AerynOS package format ONIX currently builds on.

## Why this implementation

ONIX already uses the `.stone` package format and `moss` transactions. Shipping
the same tool inside ONIX is the smallest honest step from "host-assembled
image" toward "self-managing distro".

`boulder` is intentionally not included here. `boulder` is a forge/build tool;
`moss` is the runtime package manager the installed system needs first.

## Musl/runtime-clean status

The Phase 515 build compiles `moss` inside the Alpine/musl forge from the pinned
`os-tools` source used by the rest of ONIX bootstrap tooling.

The accepted payload must pass:

```text
no /nix/store reference
no glibc interpreter
no RPATH/RUNPATH into /nix/store
static/static-pie musl binary
```

## Runtime dependencies

None for the accepted Phase 515 payload.

The package is built static/static-pie. If a future `moss` update needs a shared
runtime surface, that surface must become explicit ONIX-owned stones first.

## Static attempt/result

Static/static-pie musl is the required result for Phase 515.

## Allowed shared-library surface

None.

## Installed paths

```text
/usr/bin/moss
/usr/share/onix/packages/moss.md
```

## Source policy

Source comes from the pinned `os-tools` commit in `vm/phase0/config.sh`.

ONIX currently treats upstream `os-tools` as pinned bootstrap tooling. When the
ONIX mirror is ready, the source URL can switch to `https://github.com/onix-os`
while keeping the same commit first.
