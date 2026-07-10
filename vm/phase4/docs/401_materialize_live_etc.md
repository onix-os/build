# Phase 401 — materialize live `/etc`

| Item | Value |
|---|---|
| Command | `make phase 401` |
| Underlying make target/script | `vm/phase4/materialize-etc.sh` |
| Mutates disk/image? | Yes, it mounts `artifacts/onix-image/onix.raw` and updates the root filesystem |
| Boots QEMU? | No |
| Main proof | Live `/etc` is created from package-owned defaults without overwriting local overrides. |

## The basic Linux idea

Most Linux programs look in `/etc` for machine configuration.

Examples:

```text
/etc/fstab
/etc/profile
/etc/hostname
/etc/os-release
/etc/profile.d/*.sh
/etc/machine-id
```

But ONIX does not want random packages to own live mutable machine state
directly.

So ONIX separates two ideas:

```text
/usr/share/defaults   packaged defaults
/etc                  live machine configuration
```

That means a package can say:

```text
Here is the default fstab template.
```

without claiming:

```text
I own your live /etc/fstab forever.
```

That distinction becomes important later when a user changes networking,
hostname, SSH keys, Nix config, or anything else machine-local.

## Background: how a host script edits the guest's `/etc`

Phase 401 runs on the *host*, but it edits files inside the *guest's* root
filesystem, which lives inside a single file: `artifacts/onix-image/onix.raw`.
That file is a full disk image — a byte-for-byte picture of a disk, including its
GPT partition table and every partition. To reach the files inside it without
booting a VM, the script uses a **loop device**.

A loop device (`/dev/loop0`, `/dev/loop1`, …) is a kernel feature that makes an
ordinary file *look like a block device* — a disk. Once `onix.raw` is attached to
a loop device, the kernel reads its partition table and exposes each partition as
`/dev/loopNp1`, `/dev/loopNp2`, and so on, exactly as if you had plugged in a real
disk. The script then `mount`s the ONIX root partition onto a directory on the
host, edits `/etc` through that mount point, and unmounts and detaches when done.

This is why the "At a glance" table says the phase *mutates the disk/image*: it is
not running the guest, it is surgically editing the guest's filesystem from
outside. `materialize-etc.sh` also mounts the real `ONIX-PERSIST` partition when a
step needs it, because — as later steps learn the hard way — files written only to
the root tree's placeholder `/persist` directory get hidden once the real persist
partition mounts over it at boot.

## What Phase 2 already did

Phase 2 already copied some defaults into the root tree so the first boot could
work.

For example, the boot image needs:

```text
/etc/fstab
```

before systemd can mount:

```text
/boot
/efi
/persist
/home
/nix
```

That Phase 2 behavior was necessary, but it was still image-assembly glue.

Phase 401 turns it into an explicit policy.

## What Phase 401 materializes

Phase 401 reads packaged defaults from:

```text
/usr/share/defaults/etc/
```

and ensures these live files exist:

```text
/etc/issue
/etc/motd
/etc/fstab
/etc/profile
/etc/profile.d/onix-path.sh
```

It also enforces:

```text
/etc/os-release -> ../usr/lib/os-release
```

That symlink is the normal compatibility path. The actual identity file remains
package-generated under:

```text
/usr/lib/os-release
```

A **symlink** (symbolic link) is a tiny file whose contents are just a path;
opening it transparently redirects to that path. Here `/etc/os-release` is a
symlink pointing at `../usr/lib/os-release`, so any program that reads the
traditional `/etc/os-release` location actually gets the package-owned identity
file. This keeps the real, immutable identity in stateless `/usr` while still
honoring the conventional `/etc` path — the split from the previous section in
action. The script refuses to clobber it if a real (non-symlink) file is already
there, which is the same "preserve local overrides" instinct applied to a link.

## Preserve local overrides

The script does **not** blindly overwrite live `/etc` files.

The rule is:

```text
if missing:
    create from /usr/share/defaults
if present and same as default:
    OK
if present and different:
    preserve as local override
```

That is the seed of the future ONIX drift model.

Later, `onix status` should be able to say:

```text
/etc/fstab differs from packaged default
```

without calling that a failure.

## Why `/etc/machine-id` is different

`/etc/machine-id` is not a package default.

It identifies one installed machine. systemd may create or persist it during
boot.

So Phase 401 only ensures the file exists. It does not replace it.

That is why the script reports:

```text
preserve : /etc/machine-id exists as machine-local state
```

## What the script writes as proof

Phase 401 writes:

```text
/usr/share/onix/bootstrap/etc-materialization.txt
```

That file records the temporary bootstrap policy:

- defaults live in `/usr/share/defaults`
- live config lives in `/etc`
- missing files may be created from defaults
- differing files are preserved as overrides
- machine identity is not overwritten

This proof file is not the final architecture. Later ONIX should probably have
a small first-boot materializer or systemd unit owned by an ONIX stone.

## Run it

From the repo root:

```sh
make phase 401
```

Expected output includes lines like:

```text
symlink  : /etc/os-release -> ../usr/lib/os-release
default  : /etc/fstab already matches packaged default
preserve : /etc/machine-id exists as machine-local state
proof    : /usr/share/onix/bootstrap/etc-materialization.txt
```

Then the phase verifies:

- `/usr/lib/os-release` says `NAME="ONIX"` and `ID="onix"`
- `/etc/os-release` points to `../usr/lib/os-release`
- packaged defaults exist under `/usr/share/defaults/etc`
- live files exist under `/etc`
- `/etc/fstab` still contains the ONIX volume labels
- `/etc/motd` keeps a safe no-color fallback logo
- `/etc/profile` sources `/etc/profile.d`
- `/etc/profile.d/onix-path.sh` exports a PATH
- `/etc/profile.d/onix-path.sh` defines small interactive aliases like `ll`
- `/etc/profile.d/onix-login.sh` prints the colored login logo for interactive
  shells

## Why the MOTD is compact

The full ONIX logo exists as package-owned branding data, including the colored
ANSI version:

```text
/usr/share/onix/branding/logo.txt
/usr/share/onix/branding/logo.ansi
```

But the login banner shown by the bootstrap Dropbear SSH server has a small byte
budget. A large UTF-8/ANSI MOTD can be truncated in the middle of a block
character, which produces a replacement character like:

```text
�
```

So the live `/etc/motd` uses the original Unicode logo shape without ANSI color
escape sequences as a fallback:

```text
/usr/share/onix/branding/logo.motd
```

The bootstrap Dropbear service is started with:

```text
-m
```

which disables Dropbear's own MOTD printing. Then the login shell sources:

```text
/etc/profile.d/onix-login.sh
```

That script prints:

```text
/usr/share/onix/branding/logo.ansi
```

for interactive terminals. This gives us the colored logo without letting
Dropbear truncate it.

## What this phase does not do

Phase 401 does not create users yet.

That belongs in the next users/groups/shell-policy phase.

It also does not replace the borrowed Alpine kernel payload. That remains
reserved for Phase 3.
