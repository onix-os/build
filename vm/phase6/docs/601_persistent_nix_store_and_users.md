# 601 — persistent `/nix` store and users

This phase prepares the filesystem and accounts that multi-user nix needs.

## The `/nix` problem

nix is different from a normal command package because the store is part of its
runtime model.

The important directory is:

```text
/nix/store
```

Every nix-built or nix-downloaded object lives there as an immutable store path.
For example:

```text
/nix/store/<hash>-hello-2.12.2
```

ONIX images should not lose that store on every boot. The store must be
persistent machine state.

## ONIX layout

The current filesystem policy already has persistent storage:

```text
/persist
```

So Phase 601 should make `/nix` persistent using the existing ONIX model:

```text
/persist/nix  -> backing storage
/nix          -> mounted or bound view used by nix
```

The exact implementation can be a bind mount or a systemd mount unit, but the
runtime result should be simple:

```text
test -d /nix/store
test -d /nix/var/nix
findmnt /nix
```

## Build users

Multi-user nix normally builds as dedicated unprivileged users. ONIX should add:

```text
group: nixbld
users: nixbld1, nixbld2, ..., nixbldN
```

These accounts are not human login accounts. They should use:

```text
/usr/sbin/nologin
```

## Permissions

The store must be safe:

```text
/nix/store      root-owned, not user-writable
/nix/var/nix    writable only where nix needs it
nixbld users    isolated build actors
```

Normal users should not be able to write arbitrary files into `/nix/store`.
They ask the daemon to realize store paths.

## Planned proof

Phase 601 should boot and prove:

```sh
test -d /nix/store
test -d /nix/var/nix
getent group nixbld
getent passwd nixbld1
test "$(getent passwd nixbld1 | cut -d: -f7)" = /usr/sbin/nologin
```

It should not prove `nix build` yet. That comes after the nix package and
daemon exist.
