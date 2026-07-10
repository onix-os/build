# Phase 101 — build `onix-branding`

## At a glance

| Field | Value |
|---|---|
| Phase family | Phase 1 — first stones |
| Run command | `make phase 101` |
| Underlying make target/script | `vm/phase1/build-branding-stone.sh` |
| Runs on | guest over SSH |
| Main proof/artifact | Builds and verifies the onix-branding stone. |


Builds the recipe at:

```text
recipes/onix-branding/stone.yaml
```

inside the forge, then verifies:

- the `.stone` passes `moss inspect --check`
- `/usr/lib/os-info.json` exists
- Moss generates `/usr/lib/os-release` from that metadata during install
- `/usr/share/onix/branding/logo.txt` contains the plain terminal ONIX logo
- `/usr/share/onix/branding/logo.ansi` contains the ANSI-colored terminal logo
- default `/etc` text lives under `/usr/share/defaults/etc/`
- installing into a disposable target root works

## Why `onix-branding` is the first real stone

A distribution has to be able to say what it is. `cat /etc/os-release` is how
every tool — from a login prompt to a bug tracker to `systemd` — learns the
name, ID, version, and homepage of the running system. Before ONIX can boot,
before it can even be assembled into an image, it needs a package that *owns*
that identity. `onix-branding` is that package, and because it is pure text and
metadata (no compiler, no dependencies) it is the cleanest possible first real
stone: it exercises the whole boulder→moss→repo pipeline without dragging in a
musl toolchain.

## Background: what boulder and a recipe actually do

**boulder** is the `.stone` builder. A recipe (`stone.yaml`) is a small YAML file
with package metadata (`name`, `version`, `release`, `summary`, `license`,
`homepage`, `description`) and one or more build phases written as shell. For a
data package like this one there is only an **`install`** phase: a script whose
job is to lay files down under a staging directory that boulder exposes as
`%(installroot)`. Whatever ends up under `%(installroot)` becomes the package
payload.

Boulder then compresses that payload into a single content-addressed `.stone`
file. **moss** later reads that file, verifies it, and unpacks the payload into a
real root filesystem — recording the operation as a rollback-able state.

Here is the shape of the branding recipe's install phase (from
`recipes/onix-branding/stone.yaml`), abbreviated:

```yaml
install     : |
    install -dm00755 %(installroot)/usr/lib
    install -dm00755 %(installroot)/usr/share/onix/branding
    install -dm00755 %(installroot)/usr/share/defaults/etc

    cat > %(installroot)/usr/lib/os-info.json <<'EOF_OS_INFO'
    { ... "identity": { "id": "onix", "name": "ONIX", ... } ... }
    EOF_OS_INFO
    # ...writes logo.txt, derives logo.ansi + logo.motd, issue, motd...
```

## `os-info.json` → moss-generated `os-release`

This is the single most important idea on the page. The package does **not** ship
`/usr/lib/os-release` directly. Instead it ships `/usr/lib/os-info.json`, a
structured metadata file (following the AerynOS `os-info` schema) that describes
the distro's identity, version model, boot setup, and resources:

```json
"identity": {
  "id": "onix",
  "name": "ONIX",
  "display": "ONIX (atomic musl base + Nix toolbox)",
  "ansi_color": "38;2;79;110;145"
}
```

During install, **moss reads `os-info.json` and generates the standard
`/usr/lib/os-release`** from it. That is why the build script, after installing
into a throwaway target root, asserts on the *generated* file:

```text
PRETTY_NAME="ONIX (atomic musl base + Nix toolbox)"
ID="onix"
HOME_URL="https://onix-os.com"
ANSI_COLOR="38;2;79;110;145"
```

Why go through a JSON file instead of just shipping `os-release`? Because
`os-release` is a flat, lossy, human-oriented format, while `os-info.json` is the
rich source of truth other tooling (image builders, update logic, an eventual
`onix status`) can read directly. moss owning the `os-release` *generation* also
means the machine plane, not a hand-edited file, is the authority on identity.

## Background: `.stone` layout and `moss inspect`

Before installing anything, the script proves the artifact is well-formed:

```sh
moss inspect --check <stone>   # integrity: payload hashes match the manifest
moss inspect        <stone>    # human-readable layout: files, sizes, metadata
```

`moss inspect --check` recomputes the content hashes inside the `.stone` and
compares them to what the manifest claims — if a byte were corrupted or a layout
entry were malformed, this fails. It is the packaging equivalent of `fsck` for a
single package. The script then `moss extract`s the payload into a scratch
directory and greps individual files to confirm the recipe produced what it
should (the `os-info.json` identity keys, the logo glyphs, the color escapes).

## Boulder currently ignores non-`/usr` payload files

Boulder currently ignores non-`/usr` payload files in this layout. That means
`onix-branding` ships the canonical input metadata at `/usr/lib/os-info.json`.
Moss uses that to generate `/usr/lib/os-release` during install. Later image
assembly or first-boot glue creates the compatibility symlink:

```text
/etc/os-release -> ../usr/lib/os-release
```

This is a real constraint, not a preference: ONIX stones are `/usr`-centric, so
anything the package needs to persist must live under `/usr`. The familiar
`/etc/os-release` path is created *outside* the `.stone`, by image assembly, as a
compatibility symlink pointing back into the moss-owned `/usr` copy.

## The logo assets and ONIX colors

The branding colors come from the real ONIX logo assets:

```text
orange: #e7590f  /  38;2;231;89;15
blue:   #4f6e91  /  38;2;79;110;145
```

`ANSI_COLOR` in `os-release` uses the ONIX blue. The default MOTD includes the
terminal logo with orange on the left and blue on the right.

The recipe writes one plain-text logo (`logo.txt`, built from `▓` and `▒`
block glyphs) and then *derives* two variants from it with `sed`:

- **`logo.ansi`** — the same shape, with 24-bit true-color escape sequences
  wrapping the `▓` runs in orange and the `▒` runs in blue. This is the pretty
  version shown to an interactive terminal.
- **`logo.motd`** — a copy of the *plain* logo (no color escapes) used as the
  message-of-the-day body, because the login banner path has a tight byte budget
  and must not carry escape sequences (see the Dropbear note below).

The build asserts the exact escape bytes are present in `logo.ansi`
(`\033[38;2;231;89;15m` for orange, `\033[38;2;79;110;145m` for blue), that the
block glyphs survived, and that `motd` stays under 2048 bytes and contains the
line `moss controls the machine`.

## Why defaults under `/usr/share/defaults/etc`?

The final ONIX contract is:

```text
moss owns the machine plane
local admin/user changes live outside the immutable package payload
```

So for mutable configuration text like `issue` and `motd`, the package ships
defaults under:

```text
/usr/share/defaults/etc/
```

Later boot/install glue can copy or merge those into `/etc` if needed. The
package still ships the canonical `/usr/lib/os-info.json`; Moss generates
`/usr/lib/os-release`, and image assembly creates the standard `/etc/os-release`
compatibility symlink outside the `.stone`.

### Why this pattern matters (stateless `/usr`, drift control)

ONIX's whole reason for existing is that `/usr` is **stateless and atomic**: moss
swaps the entire `/usr` tree as one transaction and can roll it back. If packages
wrote directly into `/etc`, an admin editing `/etc/motd` would either be clobbered
on every update or would silently diverge from what the package shipped — the
classic *configuration drift* that makes long-lived systems un-reproducible.

The `/usr/share/defaults/etc` pattern breaks that dilemma. The package ships an
immutable, versioned *default* under `/usr` (which moss owns and can roll back).
Live `/etc` is materialized *from* those defaults by image/boot glue and is then
free to be edited locally. Because the shipped default still exists under `/usr`,
tooling can always diff live `/etc` against it and report exactly what an admin
changed. Config is a copy of a known baseline, not an unmanaged original.

### The setgid gotcha, in this recipe

Boulder runs its install phase inside build directories that carry the setgid
bit (`g+s`). If a package-created directory keeps `g+s`, boulder may record a
special `/usr/` layout entry that moss later refuses to install. The recipe
guards against this at the end of its install phase by clearing the bit on every
directory it created:

```yaml
chmod g-s \
    %(installroot)/usr \
    %(installroot)/usr/lib \
    %(installroot)/usr/share \
    ...
```

If you ever author a new ONIX data package and moss rejects it at extract/install
time with a layout complaint, this is the first thing to check.

## What this step proves vs what it does not

It **proves**: the branding recipe builds a valid `.stone`; the artifact passes
`moss inspect --check`; the payload contains the expected identity, logo, and
default-config files; moss generates a correct `os-release` from `os-info.json`;
and a real `moss install --to` into a disposable target root succeeds.

It does **not** prove: that anything boots, that `/etc/os-release` exists on a
live system (that symlink is made later by image assembly), or that this stone
coexists with others — that composition proof is step 102. It also does not put
the stone in a named repository yet; that is step 103.
