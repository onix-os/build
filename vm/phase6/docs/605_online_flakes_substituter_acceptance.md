# 605 — online flakes and substituter acceptance

This is the final Phase 6 acceptance proof for nix.

## What this phase adds

Phase 604 proves local multi-user mechanics. Phase 605 proves real-world nix
usage:

- DNS works;
- TLS certificates work;
- substituters work;
- flakes work;
- user profiles work with downloaded packages;
- garbage collection behaves safely.

## Example acceptance flow

As the normal `onix` user:

```sh
nix --version
nix flake metadata nixpkgs
nix profile install nixpkgs#hello
hello
nix profile list
nix store gc
hello
```

The exact package may change, but it should be small and obvious.

## Why this is last

Online flakes pull in many moving parts. By the time this phase runs, ONIX
should already know:

- `/nix` is persistent;
- nix build users exist;
- nix daemon is active;
- shell integration works;
- local/offline builds work.

Then any online failure is much easier to debug.

## Acceptance criteria

Phase 605 should pass only when:

```text
root can use nix
onix can use nix
another normal user can use nix
flakes are enabled
the default substituter path works
installed profile binaries survive a GC
```

After this, Phase 6 can be considered complete and Phase 7xx can focus on more
ONIX system packages.
