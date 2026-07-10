# 512 — live RootAsRole policy stone

Run:

```sh
make phase 512
```

Phase 511 built the RootAsRole binaries:

```text
/usr/bin/dosr
/usr/bin/chsr
```

But a privilege tool is not useful until the machine has live policy. Phase 512
adds that policy as a package:

```text
rootasrole-policy
```

## Why this is a separate stone

The `rootasrole` package is software. It owns binaries and safe defaults:

```text
/usr/bin/dosr
/usr/bin/chsr
/usr/share/defaults/rootasrole/rootasrole.json
/usr/share/defaults/pam.d/sr
/usr/share/defaults/pam.d/dosr
```

The live policy is machine state:

```text
/etc/security/rootasrole.json
/etc/security/rootasrole.d/policy.json
/etc/pam.d/sr
/etc/pam.d/dosr
```

ONIX keeps those separate so policy changes are deliberate. This is the same
reason we do not hide service policy inside random image-assembly shell code.
If a file controls machine privilege, it should be visible as a package-owned
artifact.

There is one important packaging detail: current Boulder stone payloads are
`/usr` payloads. When a payload contains direct `/etc` files, Boulder ignores
them as non-`/usr` files. So Phase 512 owns the factory source here:

```text
/usr/share/factory/etc/security/rootasrole.json
/usr/share/factory/etc/security/rootasrole.d/policy.json
/usr/share/factory/etc/pam.d/sr
/usr/share/factory/etc/pam.d/dosr
```

A later image/system materialization step copies those files into live `/etc`.
That keeps the source package-owned while respecting the current stone format.

## The first policy is a bootstrap development policy

RootAsRole has two config paths in this build:

```text
/etc/security/rootasrole.json           root settings file
/etc/security/rootasrole.d/policy.json  actual authorization policy
```

The settings file points RootAsRole at the policy-data directory. Without that
split, `dosr` can find the settings file but then looks for policy data under
`/etc/security/rootasrole.d/` and fails at runtime.

The first live ONIX policy contains these bootstrap actors:

```text
actor: uid 0    (root)
actor: uid 1000 (onix)
```

The policy uses numeric IDs because RootAsRole's optimized runtime finder
matches actors by resolved IDs. That means the default development login can run
`dosr` in the VM. This is not the final account/admin design. It is the first
runtime proof that ONIX's chosen sudo-class tool actually executes, not only
that the files exist.

This matters because privilege work has two separate parts:

1. can ONIX package and install the privilege system?
2. what policy should a real machine enable for normal users?

Phase 512 answers the first question and gives the bootstrap VM one useful admin
actor. Later phases can replace that with a real user/group policy.

## PAM policy

The package installs:

```text
/etc/pam.d/sr
/etc/pam.d/dosr
```

The user-facing command is `dosr`, but RootAsRole opens the PAM service named
`sr` internally. If ONIX ships only `/etc/pam.d/dosr`, PAM falls through looking
for the generic `other` service and `dosr` reports a runtime "System error".
So the real service file is `/etc/pam.d/sr`; `/etc/pam.d/dosr` is kept as a
human-readable companion for the visible command name.

The first PAM file uses `pam_permit.so`. That sounds scary, so the important
detail is this:

```text
PAM is authentication here.
RootAsRole JSON policy is authorization.
```

Because the JSON policy is still the authorization layer, `pam_permit.so` alone
does not define who can become root. The RootAsRole policy has to match the
caller and command. In this bootstrap VM, `onix` deliberately matches so Phase
514 can run `dosr /usr/bin/busybox id` and require `uid=0(root)`.

This is a bootstrap choice. A later real login/user-management phase should
replace it with a policy that matches the final ONIX account model.

## What gets built

Phase 512 builds:

```text
rootasrole-policy
```

It owns:

```text
/usr/share/factory/etc/security/rootasrole.json
/usr/share/factory/etc/security/rootasrole.d/policy.json
/usr/share/factory/etc/pam.d/sr
/usr/share/factory/etc/pam.d/dosr
/usr/share/onix/packages/rootasrole-policy.md
```

It depends on:

```text
rootasrole
linux-pam
```

Installing the policy therefore pulls in `dosr`, `chsr`, and the PAM module
surface.

## What the phase proves

The phase proves:

- the policy stone builds through Boulder;
- host Moss can inspect it;
- the local repo is refreshed;
- installing `rootasrole-policy` pulls in `rootasrole`;
- `/usr/bin/dosr` exists in the install target;
- `/usr/share/factory/etc/security/rootasrole.json` exists;
- `/usr/share/factory/etc/security/rootasrole.d/policy.json` exists;
- `/usr/share/factory/etc/pam.d/sr` exists;
- `/usr/share/factory/etc/pam.d/dosr` exists;
- `rootasrole.json` is mode `0600`;
- the policy contains root UID `0`;
- the policy contains ONIX bootstrap UID `1000`;
- the policy does not contain `ROOTADMINISTRATOR`;
- no `/nix/store` path leaks into the policy payload.

## What this phase does not do

It does not decide the final ONIX admin model.

Open questions for later:

- Should ONIX have a `wheel` style admin group?
- Should final ONIX use a named admin group instead of the bootstrap `onix`
  actor?
- Should `dosr` ask for a password?
- Should policy live in JSON forever, or should ONIX convert it to another
  RootAsRole storage mode?

Phase 512 gives ONIX a package-owned live policy and a bootstrap admin path.
