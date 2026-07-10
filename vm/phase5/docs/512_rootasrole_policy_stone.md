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
onix-rootasrole-policy
```

## Why this is a separate stone

The `rootasrole` package is software. It owns binaries and safe defaults:

```text
/usr/bin/dosr
/usr/bin/chsr
/usr/share/defaults/rootasrole/rootasrole.json
/usr/share/defaults/pam.d/dosr
```

The live policy is machine state:

```text
/etc/security/rootasrole.json
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
/usr/share/factory/etc/pam.d/dosr
```

A later image/system materialization step copies those files into live `/etc`.
That keeps the source package-owned while respecting the current stone format.

## The first policy is intentionally conservative

The first live RootAsRole policy grants no normal user privilege.

It contains only:

```text
actor: root
```

That means the policy is useful for proving installation and layout, but it does
not yet turn the default login user into an administrator.

This matters because privilege work has two separate parts:

1. can ONIX package and install the privilege system?
2. what policy should a real machine enable for normal users?

Phase 512 answers the first question. Later phases can answer the second.

## PAM policy

The package installs:

```text
/etc/pam.d/dosr
```

The first PAM file uses `pam_permit.so`. That sounds scary, so the important
detail is this:

```text
PAM is authentication here.
RootAsRole JSON policy is authorization.
```

Because the JSON policy only has the `root` actor, `pam_permit.so` does not by
itself grant the default ONIX user an admin role. The authorization policy still
has to match.

This is a bootstrap choice. A later real login/user-management phase should
replace it with a policy that matches the final ONIX account model.

## What gets built

Phase 512 builds:

```text
onix-rootasrole-policy
```

It owns:

```text
/usr/share/factory/etc/security/rootasrole.json
/usr/share/factory/etc/pam.d/dosr
/usr/share/onix/packages/onix-rootasrole-policy.md
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
- installing `onix-rootasrole-policy` pulls in `rootasrole`;
- `/usr/bin/dosr` exists in the install target;
- `/usr/share/factory/etc/security/rootasrole.json` exists;
- `/usr/share/factory/etc/pam.d/dosr` exists;
- `rootasrole.json` is mode `0600`;
- the policy contains `root`;
- the policy does not contain `ROOTADMINISTRATOR`;
- the policy does not grant `onix`;
- no `/nix/store` path leaks into the policy payload.

## What this phase does not do

It does not decide the final ONIX admin model.

Open questions for later:

- Should ONIX have a `wheel` style admin group?
- Should the default `onix` user be allowed to use `dosr`?
- Should `dosr` ask for a password?
- Should policy live in JSON forever, or should ONIX convert it to another
  RootAsRole storage mode?

Phase 512 gives ONIX a package-owned live policy. It does not yet give normal
users admin rights.
