# Phase 512 — prove RootAsRole integrated policy

Phase 512 no longer builds a second RootAsRole policy package.

The ONIX decision is:

```text
rootasrole owns the binaries
rootasrole owns the bootstrap factory policy
there is no separate policy stone
```

## Why this changed

At first, Phase 511 built `rootasrole` and Phase 512 built a separate policy
stone. That worked, but it made the base privilege story harder to read:

```text
rootasrole        -> dosr/chsr
policy package    -> factory /etc security and PAM policy
```

For ONIX bootstrap, the policy is not an optional plugin. Without the policy,
the privilege tool is not useful in the VM. So the cleaner early distro model is
one package:

```text
rootasrole
```

That package owns:

```text
/usr/bin/dosr
/usr/bin/chsr
/usr/share/factory/etc/security/rootasrole.json
/usr/share/factory/etc/security/rootasrole.d/policy.json
/usr/share/factory/etc/pam.d/sr
/usr/share/factory/etc/pam.d/dosr
/usr/share/onix/packages/rootasrole.md
```

## Factory policy versus live `/etc`

Linux programs normally read configuration from `/etc`.

Packages should avoid blindly overwriting `/etc`, because `/etc` is also where
machine-local admin choices live. ONIX therefore uses a factory-source pattern:

```text
/usr/share/factory/etc/...   package-owned source
/etc/...                     live machine policy
```

The stone owns the factory files. The image/runtime materializer copies those
files into `/etc` when ONIX assembles the current development VM.

## What the integrated policy contains

The first policy is only a bootstrap development policy:

- `root` is an actor;
- the normal development user `onix` is an actor;
- the bootstrap task can run commands as root;
- `chsr` remains controlled by RootAsRole policy.

That lets Phase 514 prove:

```text
dosr /usr/bin/busybox id
```

executes as root inside the booted VM.

This is not the final ONIX admin/security model. It is the first package-owned
policy that makes the selected sudo-class tool usable.

## What `make phase 512` does

`make phase 512` runs:

```text
vm/phase5/check-rootasrole-integration.sh
```

The check:

1. removes stale local split-policy build artifacts from artifact
   directories;
2. reindexes the local Moss repo;
3. verifies `packages/STONES.md` no longer lists a separate policy stone;
4. installs `rootasrole` into a disposable Moss target;
5. checks the factory policy files are present;
6. checks sensitive factory JSON files are mode `0600`;
7. checks the package note documents the integrated policy.

The important proof is:

```text
moss install rootasrole
```

must produce both:

```text
/usr/bin/dosr
/usr/share/factory/etc/security/rootasrole.json
```

from the same package.

## Why the JSON is mode `0600`

The RootAsRole JSON files describe privilege policy. Even in a bootstrap VM, we
should not train ourselves to make privilege policy world-readable.

The package therefore installs:

```text
/usr/share/factory/etc/security/rootasrole.json          0600
/usr/share/factory/etc/security/rootasrole.d/policy.json 0600
```

and Phase 514 checks the live copies under `/etc/security` are also not readable
by the unprivileged `onix` SSH user.

## What this phase does not do

Phase 512 does not design final role policy.

It does not decide:

- how many admin roles ONIX will have;
- whether there will be a `sudo` compatibility command;
- whether normal users can edit RootAsRole policy;
- how production images should seed first-user admin access.

It only fixes the package boundary: policy belongs to the `rootasrole` stone for
the bootstrap distro.
