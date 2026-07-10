# 604 — offline multi-user nix proof

This phase proves nix without the network.

## Why offline first

If the first nix proof uses the internet, failures become ambiguous:

- DNS failure?
- TLS/certificate failure?
- substituter unavailable?
- flakes registry issue?
- actual nix daemon issue?

Phase 604 should avoid all of that. It should prove the local mechanics first.

## What to prove

The offline proof should show that:

- root can talk to nix;
- the `onix` user can talk to nix;
- a second normal user can talk to nix;
- `/nix/store` gets real store paths;
- user profiles are separate;
- garbage collection does not remove active profile roots.

## Possible local derivation

Use a tiny local derivation or fixed-output-free build that needs no network:

```nix
derivation {
  name = "onix-nix-offline-proof";
  system = builtins.currentSystem;
  builder = "/usr/bin/busybox";
  args = [ "sh" "-c" "mkdir -p $out/bin; echo ok > $out/proof.txt" ];
}
```

This is deliberately boring. It proves the store and daemon, not the internet.

## Planned runtime checks

As root:

```sh
nix store ping
nix-store --gc --print-roots
```

As `onix`:

```sh
nix store ping
nix build --file ./local-proof.nix
test -e result/proof.txt
```

As another user:

```sh
nix store ping
nix profile list
```

The second user matters because "works for the bootstrap user" is not the same
as "works for all users."
