# 516 — BusyBox `sh` and fish shell policy

This step defines the policy before we build anything.

## Basic shell model

Linux does not require one shell. A machine normally has:

- a scripting shell for `/bin/sh`;
- one or more interactive shells for users;
- a list of accepted login shells in `/etc/shells`;
- each user's default shell stored in `/etc/passwd`.

The last field in an `/etc/passwd` line is the login shell:

```text
name:x:uid:gid:comment:home:shell
```

For example, after Phase 518 the normal ONIX user should look like:

```text
onix:x:1000:100:ONIX Bootstrap User:/home/onix:/usr/bin/fish
```

That does **not** mean scripts run with fish. Scripts choose their interpreter
from their shebang:

```sh
#!/bin/sh
```

or from the explicit command that starts them:

```sh
/usr/bin/busybox sh -c 'echo hello'
```

## Why fish is not `/bin/sh`

fish is a Rust-written interactive shell. It has a different syntax from POSIX
`sh`. That is a feature for humans, but it is the wrong contract for system
scripts.

Examples:

- POSIX `sh` uses `VAR=value command`; fish uses different variable syntax.
- POSIX `sh` uses `export PATH=...`; fish uses `set -gx PATH ...`.
- Many upstream build and install scripts assume `/bin/sh` syntax.

So ONIX keeps:

```text
/bin/sh      system script compatibility
/usr/bin/sh  system script compatibility
/usr/bin/fish interactive login shell
```

## Package boundary

Both shells must be package-owned:

- BusyBox is the `busybox` stone.
- fish is the `fish` stone.

No finished ONIX shell path may point into `/nix/store`.

nix can still help obtain pinned source code or provide build tooling during the
bootstrap. That does not make nix the runtime owner.

## What `make phase 516` checks

`make phase 516` is a policy/check step. It verifies that the repository has:

- Phase 5 documentation;
- a fish package contract;
- a fish Boulder recipe template;
- Phase 4 materializer support for the Phase 5 shell runtime;
- Phase 5 proof scripts.

It does not mutate the image.
