# Phase 6 — nix toolbox plane

Phase 6 starts after ONIX has a booted machine with package-owned base tools,
uutils command ownership, packaged `moss`, and the Phase 5 shell policy.

Phase 6 is nix-only.

That means this phase does **not** grow the system package set in general. It
does not decide more shells, networking policy, editors, compilers, or desktop
packages. Those belong to later base-package phases. Phase 6 has one job:

```text
make nix a real ONIX-owned multi-user toolbox plane
```

## Why nix is its own phase

Most ONIX system packages are ordinary machine files. A package like `fish` or
`uutils-coreutils` installs files under `/usr`, moss records them, and moss owns
their state.

nix is different. nix has its own persistent object store:

```text
/nix/store
/nix/var/nix
/nix/var/nix/profiles
```

If we blur that line, ONIX becomes confusing:

- does moss own this file?
- does nix own this file?
- does a moss rollback affect a nix profile?
- does nix get to replace systemd units or `/etc`?

So Phase 6 exists to make the boundary boring and explicit:

```text
moss owns the machine.
nix owns the toolbox.
```

## The ownership rule

moss installs nix itself:

```text
/usr/bin/nix
/usr/bin/nix-daemon
/usr/lib/systemd/system/nix-daemon.service
/usr/lib/systemd/system/nix-daemon.socket
/etc/nix/nix.conf
/etc/profile.d/nix.sh
/usr/share/fish/vendor_conf.d/onix-nix.fish
```

nix then owns only its toolbox state:

```text
/nix/store
/nix/var/nix
per-user nix profiles
```

Short version:

```text
nix may own /nix/store.
nix must not own ONIX system paths such as /usr, /etc, or systemd policy.
```

nix must not own ONIX system state:

```text
/usr except nix's own installed files
/etc except nix's own config
systemd units except nix's own units
accounts except nix build-user policy installed by ONIX
```

## Lowercase spelling

ONIX docs and package metadata write `nix` lowercase.

The upstream project often writes the name with a capital letter. ONIX uses
lowercase because it matches `moss`, `fish`, `systemd`, package names, and the
two-plane slogan.

## Phase 6 roadmap

| Phase | Chapter | Purpose |
| ---: | --- | --- |
| 600 | [nix architecture contract](./600_nix_architecture_contract.md) | define the moss/nix boundary before mutating the image |
| 601 | [persistent `/nix` store and users](./601_persistent_nix_store_and_users.md) | create persistent `/nix`, `nixbld` group, and build users |
| 602 | [nix stone package](./602_nix_stone_package.md) | package nix itself as ONIX-owned system files |
| 603 | [nix daemon, config, and shell integration](./603_nix_daemon_config_shell_integration.md) | enable multi-user nix for all users |
| 604 | [offline multi-user nix proof](./604_offline_multi_user_nix_proof.md) | prove nix works without network first |
| 605 | [online flakes and substituter acceptance](./605_online_flakes_substituter_acceptance.md) | prove real-world flakes/substituters/profile use |
