# 513 — uutils command ownership

Run:

```sh
make phase 513
```

Phase 509 built a Rust `uutils-coreutils` stone, but it only installed:

```text
/usr/bin/coreutils
```

That was deliberate. At the time, `onix-busybox` still owned command names like:

```text
/usr/bin/ls
/usr/bin/cp
/usr/bin/mv
/usr/bin/rm
```

If `uutils-coreutils` also owned those paths, Moss would see package ownership
collisions. Phase 513 is the explicit ownership migration.

## The key idea

ONIX does not remove BusyBox yet.

BusyBox still matters for:

- `/usr/bin/sh`;
- early bootstrap scripts;
- serial/recovery shells;
- networking helpers that uutils does not provide;
- compact emergency tooling.

What changes is normal coreutils command ownership.

Before Phase 513:

```text
/usr/bin/ls -> busybox
/usr/bin/cp -> busybox
/usr/bin/coreutils
```

After Phase 513:

```text
/usr/bin/[ -> coreutils
/usr/bin/ls -> coreutils
/usr/bin/cp -> coreutils
/usr/bin/coreutils
/usr/bin/sh -> busybox
/usr/bin/busybox
```

So the model becomes:

```text
uutils = normal core command provider
BusyBox = bootstrap/recovery provider
```

## Why command-name links matter

`uutils-coreutils` is a multicall binary. The same executable can behave as many
commands depending on the name used to invoke it.

For example:

```text
/usr/bin/coreutils
/usr/bin/[ -> coreutils
/usr/bin/ls -> coreutils
/usr/bin/cp -> coreutils
```

When the kernel runs `/usr/bin/ls`, the process sees its command name as `ls`,
so uutils dispatches to the `ls` implementation.

That is the same general trick BusyBox uses. The difference is package
ownership: Moss needs exactly one package to own each path.

## What Phase 513 rebuilds

Phase 513 rebuilds two stones:

```text
onix-busybox
uutils-coreutils
```

`onix-busybox` release 3 keeps:

```text
/usr/bin/busybox
/usr/bin/sh -> busybox
```

and other bootstrap/recovery applet links.

It stops owning common coreutils applets that uutils can own.

`uutils-coreutils` release 2 keeps:

```text
/usr/bin/coreutils
```

and adds command-name links for every applet reported by:

```text
/usr/bin/coreutils --list
```

The command manifest is generated from the compiled binary, not maintained by
hand. That matters because uutils includes special command names like `[`, and
we do not want ONIX to accidentally expose only a partial command set.

Examples from that generated manifest:

```text
/usr/bin/[ -> coreutils
/usr/bin/ls -> coreutils
/usr/bin/cp -> coreutils
/usr/bin/mv -> coreutils
/usr/bin/rm -> coreutils
```

## What the phase proves

The phase installs both packages into a scratch Moss target:

```text
onix-busybox
uutils-coreutils
```

Then it proves:

- Moss reports no duplicate path ownership;
- `/usr/bin/busybox` exists;
- `/usr/bin/sh -> busybox`;
- `/usr/bin/coreutils` exists;
- every command in `uutils-coreutils.commands` exists as `command -> coreutils`;
- `/usr/bin/[ -> coreutils`;
- `/usr/bin/ls -> coreutils`;
- `/usr/bin/cp -> coreutils`;
- the `[` applet runs;
- uutils `ls --version` runs;
- BusyBox `sh` still runs as a recovery shell.

## Why this is not "remove BusyBox"

Removing BusyBox completely would require replacing more than coreutils:

- shell;
- networking applets;
- mount/umount helpers;
- module tools;
- simple recovery tools;
- bootstrap scripts that still call BusyBox paths.

Phase 513 is narrower and safer:

```text
move what uutils can honestly own now
keep BusyBox for the rest
```

Later phases can replace more BusyBox applets with Rust or dedicated native
packages one family at a time.
