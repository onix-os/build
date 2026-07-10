# 603 — nix daemon, config, and shell integration

This phase turns the packaged nix binaries into a working multi-user service.

## Why daemon mode

ONIX wants nix working for all users, not only root.

The normal model is:

```text
user nix command -> nix daemon -> /nix/store mutation
```

That lets normal users request builds while keeping the store itself protected.

## systemd units

The nix package or policy package should own:

```text
/usr/lib/systemd/system/nix-daemon.socket
/usr/lib/systemd/system/nix-daemon.service
```

The socket should be enabled so nix can start on demand.

## `/etc/nix/nix.conf`

Initial ONIX config should probably include:

```text
experimental-features = nix-command flakes
build-users-group = nixbld
trusted-users = root @wheel
allowed-users = *
```

We may adjust this during implementation, but the intent is:

- flakes work by default;
- normal users can use nix;
- trusted privileged users can configure more advanced behavior;
- builds happen through `nixbld` users.

## Shell integration

ONIX now has both the system `sh` contract and the interactive fish login shell.

Shell integration must support both:

```text
/etc/profile.d/nix.sh
/usr/share/fish/vendor_conf.d/onix-nix.fish
```

The goal is that all users get useful nix profile paths in both shell worlds.

## Planned proof

Phase 603 should boot and prove:

```sh
systemctl is-active nix-daemon.socket
nix --version
nix store ping
```

As the `onix` user, the proof should also show:

```sh
echo $PATH
test -S /nix/var/nix/daemon-socket/socket
```

This phase still should not depend on the public internet. Online proof comes in
Phase 605.
