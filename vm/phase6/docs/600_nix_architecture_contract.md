# 600 — nix architecture contract

This is the design gate before ONIX starts installing nix.

## Why this matters

ONIX will have two package/state systems:

```text
moss  -> system package/state manager
nix   -> user/toolbox package manager
```

That can work cleanly only if the ownership boundary is explicit.

Without a boundary, nix could accidentally become a second system package
manager for ONIX itself. That would make the distro hard to reason about:

- Which tool owns `/usr/bin/foo`?
- Which tool owns systemd units?
- Which tool owns `/etc` defaults?
- Which tool can roll back system state?

ONIX's answer should be simple:

```text
moss owns the machine.
nix owns the toolbox.
```

## Ownership boundary

moss owns:

```text
/usr/bin/nix
/usr/bin/nix-daemon
/usr/lib/systemd/system/nix-daemon.service
/usr/lib/systemd/system/nix-daemon.socket
/etc/nix/nix.conf
/etc/profile.d/nix.sh
/usr/share/fish/vendor_conf.d/onix-nix.fish
/usr/share/onix/packages/nix.md
```

nix owns:

```text
/nix/store
/nix/var/nix
/nix/var/nix/profiles
/nix/var/nix/daemon-socket
```

Normal users own their profile selection state through nix:

```text
~/.nix-profile
~/.local/state/nix
```

The exact user-profile layout may change during implementation, but the
principle does not: user/toolbox state is not ONIX base-system state.

## What nix must not own

nix must not install or mutate:

```text
/usr/lib/os-release
/usr/bin/systemctl
/usr/lib/systemd/system/*.service except its own nix units
/etc/passwd
/etc/group
/etc/shadow
/etc/security
```

Those paths are ONIX system state.

## Naming policy

In ONIX docs, package metadata, and phase names, write `nix` lowercase.

This is a project style decision. It keeps the ONIX text visually consistent
with `moss`, `fish`, `systemd`, and package ids.

## Planned deliverables

Phase 600 should eventually provide:

- an ONIX nix architecture proof note under `/usr/share/onix/bootstrap`;
- package contract skeletons for nix-related stones;
- a check that docs do not describe nix as the system package manager;
- a check that the spelling style in new ONIX docs is lowercase `nix`.

This phase should not yet install nix. It is the contract.
