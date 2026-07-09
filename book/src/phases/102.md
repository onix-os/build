# Phase 102 — build `onix-filesystem`

## At a glance

| Field | Value |
|---|---|
| Phase family | Phase 1 — first stones |
| Run command | `make phase 102` |
| Underlying make target/script | `vm/phase1/build-filesystem-stone.sh` |
| Runs on | guest over SSH |
| Main proof/artifact | Builds onix-filesystem and proves it composes with onix-branding. |


Builds the recipe at:

```text
recipes/onix-filesystem/stone.yaml
```

This package does **not** own live `/etc`, `/var`, `/run`, `/dev`, `/proc`, or
`/sys`. Instead, it installs policy and templates under `/usr`:

```text
/usr/share/onix/filesystem-layout.md
/usr/share/defaults/etc/fstab
/usr/share/defaults/etc/profile
/usr/share/defaults/etc/profile.d/onix-path.sh
/usr/share/defaults/etc/profile.d/onix-login.sh
```

## Why a "filesystem" package that owns no live filesystem

The name is a little counterintuitive at first: `onix-filesystem` is the package
that documents and templates ONIX's filesystem *policy*, but it deliberately
touches none of the live, mutable, runtime directories. `/etc`, `/var`, `/run`,
`/dev`, `/proc`, and `/sys` are all **machine state**, not package payload — they
are created and populated at image-assembly or boot time, not shipped inside a
`.stone`. What `onix-filesystem` ships is the *authoritative description* of how
those directories are meant to be laid out and owned, plus ready-to-materialize
default templates. It is policy-as-a-package.

This is the second half of the `/usr/share/defaults/etc` idea introduced in step
101. `onix-branding` shipped default *identity* text there; `onix-filesystem`
ships default *layout and shell* text there. Neither writes to live `/etc`.

## What the payload actually contains

### `filesystem-layout.md` — the ownership boundary, written down

The package ships a documentation file (`/usr/share/onix/filesystem-layout.md`)
that states the ONIX ownership contract in plain terms — the same contract from
the architecture plan, now travelling *inside the base itself* so a running
system carries its own constitution:

```text
- moss owns /usr, boot artifacts, and the machine plane.
- Nix owns /nix and user-selected toolbox software.
- local/admin state lives outside immutable package payloads.
```

It also enumerates the important paths: `/usr` (moss-managed, transactional),
`/.moss` (moss's content/state store), `/persist` and its bind mounts
(`/persist/home -> /home`, `/persist/nix -> /nix`), and the runtime filesystems
that are never packaged. The build asserts this file exists and contains the line
`moss owns /usr`.

### `fstab` — the default mount table template

`/usr/share/defaults/etc/fstab` is the template image assembly copies into
`/etc/fstab`. It encodes the ONIX partition scheme by **filesystem label**, which
is why the build greps it for `LABEL=ONIX-PERSIST` and, in the installed target,
for `LABEL=onix-root`:

```text
LABEL=ONIX-ESP      /efi      vfat  ...
LABEL=ONIX-BOOT     /boot     vfat  ...
LABEL=onix-root     /         xfs   ...
LABEL=ONIX-PERSIST  /persist  xfs   ...
/persist/home       /home     none  bind   0 0
/persist/nix        /nix      none  bind   0 0
```

Mounting by label rather than by device node (`/dev/sda2`) is what lets the same
`fstab` work regardless of how the disk enumerates — a requirement for an image
that has to boot on many machines. The bind mounts fold `/home` and `/nix` onto a
single persistent partition, so exactly one surface (`/persist`) needs backing up.

### The login shell chain

`/usr/share/defaults/etc/profile` is the login-shell entry point. It sources
`/etc/profile.d/*.sh`.

That indirection is the point: keep the top-level `profile` tiny and put policy
in small, individually-owned drop-in scripts under `profile.d/`. The build checks
that `profile` references `/etc/profile.d`. Note the recipe comment that BusyBox
`ash` reads `/etc/profile` for login shells — this is the musl/BusyBox base, not
bash.

`onix-path.sh` currently owns:

- the base PATH policy,
- small interactive aliases such as `ll`.

Its PATH logic is written defensively — it prepends `/usr/bin` and `/usr/sbin`
only if they are not already present, so re-sourcing the file cannot corrupt
`PATH`. The aliases (`ll`, `la`, `l`) are guarded by `[ -n "${PS1:-}" ]` so they
are defined only for interactive shells. The build asserts both `export PATH` and
`alias ll='ls -laF'` appear.

`onix-login.sh` prints the colored ONIX login logo for interactive shells. This
keeps large ANSI art out of Dropbear's MOTD path.

### Background: why the logo lives in a profile script, not MOTD

**Dropbear** is the tiny SSH server ONIX uses in the forge (a lightweight
alternative to OpenSSH, sized for embedded/musl systems). Dropbear's MOTD banner
has a small byte budget and does not handle large ANSI-colored art well, so it is
started with `-m` to *suppress* `/etc/motd` entirely. The colored logo therefore
has to be printed somewhere else — and `onix-login.sh` is that place. It:

- returns immediately for non-interactive or `dumb`/non-tty shells,
- respects an `ONIX_LOGIN_BANNER=0` opt-out,
- guards against printing twice per session with `ONIX_LOGIN_BANNER_SHOWN`,
- prefers `/usr/share/onix/branding/logo.ansi` (the colored asset from
  `onix-branding`), falling back to `/etc/motd`.

That last point is the quiet payoff: `onix-login.sh` reads the very logo asset
`onix-branding` shipped. The two packages are designed to interlock — which is
exactly what step 102 sets out to prove.

## Proving composition

The Phase 102 test installs both `onix-branding` and `onix-filesystem` into the
same disposable target root, so we prove the first two real ONIX stones compose.

"Compose" here means something specific: two independently-built stones install
into the *same* root without a file collision, and the result is internally
consistent. The script indexes both stones into a small local repo, then runs a
single moss transaction:

```sh
moss ... install --to <target> onix-branding onix-filesystem
```

and afterward asserts files from *both* packages are present in the one target —
`onix-branding`'s generated `os-release` (`ID="onix"`) alongside
`onix-filesystem`'s `fstab` and `profile.d` scripts. Because both packages write
only under `/usr` and into disjoint subtrees (`/usr/lib` and
`/usr/share/onix/branding` vs `/usr/share/onix/filesystem-layout.md` and the
`profile.d` scripts), they slot together cleanly. This is the miniature version
of what image assembly will do with the full base set.

## What this proves vs what it does not

It **proves**: the filesystem-policy recipe builds a valid `.stone`; its payload
carries the layout doc, `fstab`, and login-shell scripts; and it installs
alongside `onix-branding` into one root with no conflict. That two-package
install is the first evidence of a real, if tiny, ONIX base *set* rather than a
lone package.

It does **not** prove: that any of these templates are actually in force on a
live system (nothing here materializes `/etc`), that the login banner renders on
a real tty, or that the packages live in a *named, reusable* repository. That
last gap is closed next, in step 103, where the loose stones become the
`onix-local` repo and are installed by name.
