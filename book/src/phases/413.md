# Phase 413 — install/use `onix-dropbear`

| Item | Value |
|---|---|
| Command | `make phase 413` |
| Underlying make target/scripts | `vm/phase4/materialize-etc.sh --dropbear-stone`, then `vm/phase4/stone-dropbear-probe.sh` |
| Requires | Phase 410 `onix-busybox` installed in the image, Phase 412 `onix-dropbear` present in the local Phase 4 moss repo |
| Mutates disk/image? | Yes |
| Boots QEMU? | Yes |
| Main proof | The booted image accepts SSH while the systemd service starts `/usr/sbin/dropbear` from the `onix-dropbear` stone. |

## Why this phase exists

Phase 406 made SSH work.

Phase 412 built a real ONIX package:

```text
onix-dropbear-...stone
```

Phase 413 connects those two facts.

It changes the boot image from this temporary arrangement:

```text
systemd service
  starts /nix/store/...-dropbear.../bin/dropbear
```

to this ONIX-owned arrangement:

```text
systemd service
  starts /usr/sbin/dropbear

/usr/sbin/dropbear
  comes from onix-dropbear.stone
```

That is the important learning point.

Building a package is not enough.

The live operating system must actually use it.

## The ownership rule

ONIX is using this boundary:

```text
machine-plane software = moss/.stone packages
user toolbox software  = Nix
```

Dropbear is machine-plane software because it:

- starts as a system service,
- listens on the machine's network interface,
- controls remote access to the machine,
- depends on host keys under `/etc/dropbear`,
- participates in user/login policy.

So Dropbear must not remain a random copied Nix payload.

It needs to be package-owned.

Phase 413 makes that true for the active SSH path.

## What gets installed

The phase installs the `onix-dropbear` package from:

```text
artifacts/onix-local-repo/stone.index
```

into a scratch Moss target first.

That scratch target is not the final image. It is a safe staging area:

```text
local moss repo
        |
        v
scratch install target
        |
        v
copy verified package payload into mounted ONIX image
```

The package payload copied into the image is:

```text
/usr/sbin/dropbear
/usr/bin/dropbearkey
/usr/share/onix/packages/onix-dropbear.md
```

The image keeps its normal filesystem meaning:

- `/usr` is package-owned operating-system content,
- `/etc` is live machine configuration and identity,
- `/persist` is durable state that survives image rebuild patterns.

## Why `/usr/sbin/dropbear`

Historically, Unix-like systems split command locations roughly like this:

```text
/bin       essential user commands
/sbin      essential system/admin commands
/usr/bin   normal user commands from packages
/usr/sbin  normal system/admin commands from packages
```

ONIX is moving toward merged `/usr`, but the distinction is still useful:

```text
dropbearkey = command/tool, goes in /usr/bin
dropbear    = system daemon, goes in /usr/sbin
```

Dropbear is not something a regular user runs as a daily command.

It is the SSH server daemon.

So the package installs:

```text
/usr/sbin/dropbear
```

and the unit starts exactly that path.

## What happens to the host key

SSH servers need a host key.

For this bootstrap image, the key is:

```text
/etc/dropbear/dropbear_ed25519_host_key
```

That key is not package content.

It is machine identity.

So it belongs in `/etc`, not `/usr`.

Phase 413 generates it with:

```text
/usr/bin/dropbearkey
```

if it does not already exist.

If the key already exists, the phase preserves it.

That distinction matters:

```text
/usr/bin/dropbearkey
  package-owned tool

/etc/dropbear/dropbear_ed25519_host_key
  machine-local identity
```

Packages can be replaced. Machine identity should not be silently replaced.

## What happens to the systemd unit

Phase 406 wrote a bootstrap Dropbear unit so systemd could start SSH.

Phase 413 writes that unit with a new `ExecStart`:

```text
ExecStart=/usr/sbin/dropbear -F -E -e -m -s -w -j -k -p 0.0.0.0:22 -r /etc/dropbear/dropbear_ed25519_host_key -P /run/dropbear.pid
```

Important flags:

- `-F`: stay in the foreground, which is what systemd wants for a simple service.
- `-E`: log to stderr, so systemd can capture logs.
- `-e`: log to stderr instead of syslog.
- `-m`: do **not** print the MOTD (message-of-the-day) banner. This flag matters
  more than it looks. Dropbear has a small internal buffer for the login banner, and
  ONIX's login branding is a large colored ASCII logo. If Dropbear tried to print it,
  the logo would be truncated. So ONIX tells Dropbear to stay quiet with `-m` and
  lets the login *shell* print the full colored banner from `/etc/profile` instead.
  This split — Dropbear authenticates, `/etc/profile` greets — is exactly what the
  Phase 425 acceptance gate checks later.
- `-s`: disable password logins.
- `-w`: disable root logins.
- `-j`: disable local port forwarding.
- `-k`: disable remote port forwarding.
- `-p 0.0.0.0:22`: listen on guest TCP port 22.
- `-r /etc/dropbear/dropbear_ed25519_host_key`: use the machine host key.
- `-P /run/dropbear.pid`: write runtime pid state under `/run`.

The security policy from Phase 406 stays intact:

```text
password login: disabled
root login:     disabled
remote login:   public key only
user:           onix
```

## Why this phase still talks about old Nix payloads

Phase 413 changes the active service path.

It does not yet delete every older copied Nix file from the image.

That is deliberate.

There are two separate questions:

```text
1. What does the booted system actually execute?
2. Are old unused payload files still present on disk?
```

Phase 413 answers the first question:

```text
SSH executes /usr/sbin/dropbear from onix-dropbear.
```

A later audit phase answers the second question:

```text
No temporary Nix-sourced system payload remains.
```

Keeping those as separate phases makes debugging easier.

If SSH breaks in Phase 413, we know the problem is the active Dropbear switch.

If cleanup breaks later, we know the problem is garbage collection or ownership
audit, not the first service switch.

## What the materializer verifies

Before booting QEMU, `materialize-etc.sh --dropbear-stone` checks the mounted
image.

It verifies:

- `/usr/sbin/dropbear` exists and is executable,
- `/usr/bin/dropbearkey` exists and is executable,
- both binaries are static for this bootstrap phase,
- `dropbearkey` can generate an Ed25519 key,
- `/usr/share/onix/packages/onix-dropbear.md` exists,
- the `onix` SSH user exists,
- `/persist/home/onix/.ssh/authorized_keys` exists,
- `/etc/dropbear/dropbear_ed25519_host_key` exists,
- the bootstrap SSH status scripts exist,
- the systemd unit starts `/usr/sbin/dropbear`,
- password and root-login disabling flags are still present.

This is disk-level verification.

It proves the image is shaped correctly before boot.

## What the QEMU proof verifies

The second half of the phase boots QEMU.

The probe:

1. boots the ONIX image,
2. waits for bootstrap networking,
3. waits for Dropbear to listen on guest port 22,
4. checks from inside the serial proof that `/usr/sbin/dropbear` is running,
5. connects from the host through QEMU port forwarding,
6. authenticates as the `onix` user with the generated SSH key,
7. runs a remote command,
8. verifies the remote command can see the package-owned Dropbear files.

The serial-side proof marker is:

```text
ONIX_STONE_DROPBEAR_SERIAL_OK dropbear=/usr/sbin/dropbear key=/usr/bin/dropbearkey
```

The SSH-side proof marker is:

```text
ONIX_STONE_DROPBEAR_SSH_OK user=onix uid=1000 dropbear=/usr/sbin/dropbear key=/usr/bin/dropbearkey package=present
```

Those markers prove two things:

- systemd started an SSH service from the package-owned path,
- a real authenticated SSH client session still works.

## What this phase does not solve

Phase 413 is still bootstrap work.

It does not decide:

- final user-management UX,
- final authorized-key provisioning,
- final SSH configuration format,
- whether Dropbear or OpenSSH is the long-term default,
- package-owned systemd unit ownership outside the borrowed systemd tree,
- removal of old copied Nix payloads.

Those are later problems.

This phase has one job:

```text
make SSH run from an ONIX stone
```

## Expected output shape

Run:

```sh
make phase 413
```

You should see the materializer install `onix-dropbear`, then QEMU boot and the
SSH probe succeed.

At the end, the important lines are:

```text
==> success
Phase 413 proved the booted ONIX image can use onix-dropbear for
authenticated SSH.
```

Logs are written under:

```text
vm/state/phase413.*.log
```

## Next step

After Phase 413, the active BusyBox and Dropbear paths are ONIX package paths:

```text
/usr/bin/busybox
/usr/sbin/dropbear
/usr/bin/dropbearkey
```

The next question is:

```text
what temporary system payloads still come from Nix?
```

That leads into the next ownership audit before we move toward packaging
systemd itself.
