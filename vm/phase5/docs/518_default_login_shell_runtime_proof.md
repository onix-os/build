# 518 — default login shell runtime proof

This step installs the fish stone into the ONIX image and proves the shell
decision in a booted VM.

## What changes in the image

Phase 518 uses the existing Phase 4 image materializer because that script is
already the rootful image assembly point. It installs the `fish` stone from the
ONIX image repository and then materializes live shell policy:

```text
/usr/bin/fish exists
/etc/shells contains /bin/sh, /usr/bin/sh, and /usr/bin/fish
onix user's passwd shell is /usr/bin/fish
/usr/bin/sh still points at busybox
/usr/share/onix/defaults/etc/fish/conf.d/branding.fish exists
/etc/fish/conf.d/branding.fish exists
```

The root account stays non-interactive. The normal `onix` user gets fish.

## Why the SSH proof still uses BusyBox `sh`

When an SSH server receives a command, it normally asks the user's login shell to
run that command. After Phase 518, that login shell is fish.

To avoid accidentally testing fish syntax in our proof script, the remote
command starts with:

```text
/usr/bin/busybox sh -c '...'
```

That means:

1. SSH successfully entered through the user's default fish shell.
2. The proof deliberately switches to BusyBox `sh` for POSIX-style test logic.
3. ONIX proves both parts of the policy at once.

## Runtime evidence

The booted VM proof checks:

- PID 1 is native source-built `systemd`;
- `/usr/bin/fish --version` works;
- `/usr/bin/fish -c 'echo ...'` works;
- the packaged fish greeting hook configures the ONIX greeting;
- `/usr/bin/sh` is still BusyBox;
- the `onix` user shell in `/etc/passwd` is `/usr/bin/fish`;
- `/etc/shells` lists fish;
- live Moss metadata lists the `fish` package as installed.

This is the important difference between "we built a package" and "the running
machine actually uses the package."

One proof detail is worth knowing: the SSH proof runs without a real terminal,
so it does not rely on `fish -i` auto-start behavior. Instead it starts fish
with a clean temporary home and calls `fish_greeting`. fish has already sourced
`/etc/fish/conf.d/branding.fish` during startup. The hook sets fish's global
`fish_greeting` variable; fish's own greeting function then prints that value.
Normal interactive fish sessions use the same mechanism automatically.
