# Phase 412 — build `dropbear.stone`

| Item | Value |
|---|---|
| Command | `make phase 412` |
| Underlying make target/script | `vm/phase4/build-dropbear-stone.sh` |
| Recipe template | `vm/phase4/stone-recipes/dropbear/stone.yaml.in` |
| Mutates disk/image? | No |
| Boots QEMU? | No |
| Main proof | ONIX can build Dropbear from source into a local `.stone`, verify it with moss, and add it to the local Phase 4 moss repo. |

## Why this phase exists

Phase 406 proved authenticated SSH access.

But it did that with a temporary payload:

```text
pkgsMusl.dropbear from Nix
```

That was good enough to answer:

```text
Can the booted ONIX image accept an SSH key and run a remote command?
```

The answer was yes.

But it does not satisfy the ONIX ownership rule:

```text
machine-plane software = moss/.stone packages
user toolbox software  = Nix
```

Dropbear is machine-plane software.

It starts as a system service. It listens on a network port. It gives access to
the machine. It is part of the operating system, not a personal user toolbox.

So Dropbear needs to become an ONIX stone.

Phase 412 builds that package:

```text
dropbear-...stone
```

Phase 413 will install/use it in the image and boot-prove SSH again.

## What Dropbear is

Dropbear is a small SSH server and client implementation.

In this phase we care about the server side:

```text
/usr/sbin/dropbear
```

and the host-key generator:

```text
/usr/bin/dropbearkey
```

The server accepts SSH connections.

The key generator creates the machine's SSH host key:

```text
/etc/dropbear/dropbear_ed25519_host_key
```

That host key is how a client can recognize the machine it is connecting to.

Without a host key, SSH cannot provide its normal server identity check.

### Background: Dropbear vs OpenSSH

Most Linux systems run **OpenSSH** as their SSH server. It is full-featured and
battle-tested, but it is also large and pulls in a wide set of dependencies (PAM,
its own crypto stack, privilege-separation helpers, config machinery). **Dropbear**
is a much smaller SSH server originally written for embedded systems and routers. It
implements the parts of the SSH protocol you need to log in and run commands, in a
fraction of the code and with far fewer build-time dependencies.

For a from-scratch musl base that is still tiny, Dropbear is the pragmatic choice:
one small daemon (`dropbear`) and one key generator (`dropbearkey`) get you
authenticated remote access without dragging OpenSSH's dependency tree into the base
set. ONIX has not committed to Dropbear forever — whether Dropbear stays the default
or OpenSSH replaces it is an open Phase-4-and-beyond decision — but it is the right
tool to *prove* remote access while the package set is small.

### Background: what an SSH host key is

Every SSH server proves its identity with a **host key** — an asymmetric key pair.
The public half is what your client remembers (the "known hosts" fingerprint) so it
can detect if it is ever talking to a different machine. ONIX uses an **ed25519**
host key, a modern elliptic-curve key type that is small and fast. `dropbearkey`
generates it. Crucially, the host key is *machine identity*, not package content: it
is generated per machine and must live in `/etc`, never inside a `.stone` (Phase 413
enforces this distinction).

## What SSH proves in ONIX right now

The Phase 4 SSH path is still a bootstrap proof, not the final user story.

It currently proves:

- the guest has a network address,
- QEMU forwards a host TCP port to the guest,
- Dropbear starts inside the guest,
- password login is disabled,
- root SSH login is disabled,
- a non-root bootstrap user can authenticate with a public key,
- the host can run a command through SSH.

That is enough to make the image inspectable without relying only on a serial
console.

It is not yet the final ONIX remote access design.

Later ONIX still needs decisions about:

- final user creation,
- authorized key provisioning,
- host key lifecycle,
- whether Dropbear remains the default or OpenSSH replaces it,
- how SSH configuration becomes package-owned policy.

## Why this phase only packages `dropbear` and `dropbearkey`

Dropbear can also build client-side tools such as:

```text
dbclient
scp
```

Phase 412 does not package those yet.

The current ONIX machine-plane proof only needs:

```text
/usr/sbin/dropbear
/usr/bin/dropbearkey
```

Keeping the package small is useful while we are learning.

It means the package's purpose is clear:

```text
provide the SSH server needed by the booted base image
```

Client tools can become a later package or a later expansion if ONIX decides
they belong in the base system.

## Why this package is static for now

### Background: static vs dynamic linking

A **dynamically linked** program does not contain the library code it needs. When it
starts, a small program called the **dynamic loader** (for musl,
`/lib/ld-musl-x86_64.so.1`) finds and maps the shared libraries (`.so` files) it
depends on. This saves disk and RAM because many programs share one copy of libc,
but it means the program will not run unless every one of those shared objects — and
the correct loader — is present at exactly the expected path.

A **statically linked** program bundles everything it needs into the single
executable file. It is bigger, but it has no external runtime dependencies: copy the
one file anywhere and it runs. For a base system that does not yet own its shared
libraries as packages, static linking removes a whole category of "file exists but
won't execute" failures. This is the same reason `busybox` was built static.

Just like `busybox`, this phase builds static musl binaries.

A dynamic SSH server would need runtime library ownership sorted out:

```text
dynamic loader
libc
crypto libraries
zlib
other shared objects
```

ONIX will need to package those properly.

But Phase 412 is trying to prove one narrower thing:

```text
Can we build and package a source-built Dropbear SSH server as a stone?
```

So the phase builds:

```text
static musl dropbear
static musl dropbearkey
```

This avoids runtime library ambiguity while the base-system package set is still
tiny.

## Important distinction: Nix source, musl build, boulder stone

This phase uses Nix only to find the pinned Dropbear source tarball.

That means:

```text
Nix is source acquisition
Nix is not the installed payload
```

The actual source build runs in the Alpine/musl forge VM:

```text
Dropbear source tarball
        |
        v
build Dropbear in Alpine/musl forge
        |
        v
create prepared payload tarball
        |
        v
boulder packages payload into .stone
        |
        v
dropbear-...stone
        |
        v
local Phase 4 moss repo
```

That matches the BusyBox replacement pattern from Phase 409.

## Build choices

Phase 412 configures Dropbear with:

```text
--enable-static
--enable-bundled-libtom
--disable-zlib
--disable-pam
--disable-lastlog
--disable-utmp
--disable-utmpx
--disable-wtmp
--disable-wtmpx
--disable-loginfunc
--disable-pututline
--disable-pututxline
```

What those mean:

- `--enable-static`: produce self-contained binaries for this bootstrap phase.
- `--enable-bundled-libtom`: use Dropbear's bundled crypto/math libraries
  instead of depending on separate packaged libraries.
- `--disable-zlib`: skip SSH compression support for now.
- `--disable-pam`: do not depend on PAM while ONIX user/auth policy is still
  small.
- `--disable-*utmp*`, `--disable-lastlog`, and login accounting options: avoid
  old login database integration until ONIX chooses that policy deliberately.

These are bootstrap choices, not eternal rules.

The purpose is to make the first package understandable and boot-testable.

## What the script does

Run:

```sh
make phase 412
```

The host-side script:

```text
vm/phase4/build-dropbear-stone.sh
```

does this:

1. Reads the pinned `nixpkgs_2` revision from `flake.lock`.
2. Asks Nix for the matching Dropbear source tarball path.
3. Computes the source tarball SHA-256.
4. Copies the recipe template and source tarball into the forge VM.
5. Configures Dropbear for static musl bootstrap use.
6. Builds:

   ```text
   dropbear
   dropbearkey
   ```

7. Verifies both binaries look static.
8. Verifies `dropbearkey` can generate an ed25519 host key.
9. Creates a prepared payload tarball containing:

   ```text
   /usr/sbin/dropbear
   /usr/bin/dropbearkey
   /usr/share/onix/packages/dropbear.md
   ```

10. Generates a concrete `stone.yaml` from:

    ```text
    vm/phase4/stone-recipes/dropbear/stone.yaml.in
    ```

11. Runs `boulder build` inside the forge VM.
12. Runs `moss inspect --check` on the produced `.stone`.
13. Extracts the `.stone` and verifies the payload.
14. Installs the package into a disposable moss target.
15. Copies the `.stone` back to the host.
16. Adds it to:

    ```text
    artifacts/onix-local-repo/
    ```

## What the recipe does

The recipe packages a prepared payload.

The important payload paths are:

```text
/usr/sbin/dropbear
/usr/bin/dropbearkey
/usr/share/onix/packages/dropbear.md
```

Why `/usr/sbin/dropbear`?

Dropbear is a system daemon.

Historically, system daemons often live in `sbin` paths. In a modern merged
`/usr` layout, `/usr/sbin` is the package-owned place for that kind of binary.

Why `/usr/bin/dropbearkey`?

`dropbearkey` is an administrative command that generates host keys. It is not
the daemon itself, but it must be present before the SSH service starts for the
first time.

## Expected output

You should see the source policy first:

```text
==> Phase 412 source-built Dropbear stone
source      : /nix/store/...-dropbear-2025.89.tar.bz2
version     : 2025.89
sha256      : ...
nix role    : source acquisition only
source build: Alpine/musl forge VM
stone cut   : boulder packages the musl-static payload into a .stone
```

Then the forge builds Dropbear, prints the generated recipe, cuts the `.stone`,
and verifies the result.

The important success lines are:

```text
==> success
dropbear stone: artifacts/onix-stones/dropbear-...
local repo index    : artifacts/onix-local-repo/stone.index
```

## What this phase proves

Phase 412 proves:

- we can build Dropbear from source in the musl forge,
- the outputs are static or static-PIE,
- `dropbearkey` can generate an ed25519 host key,
- boulder can package the prepared payload,
- moss accepts and verifies the `.stone`,
- the package installs into a disposable moss target,
- the host local repo now contains `dropbear`.

That is the package-production half of replacing the temporary Nix Dropbear
payload.

## What this phase does not prove

Phase 412 does not install Dropbear into the ONIX disk image.

It also does not boot QEMU.

That is intentional.

The safe order is:

```text
412 — build and verify dropbear.stone
413 — install/use dropbear in the image
414 — boot-prove SSH with dropbear
```

If Phase 412 fails, the booting image remains unchanged.

## How to inspect the result

After success, inspect the host artifacts:

```sh
ls -lh artifacts/onix-stones/
ls -lh artifacts/onix-local-repo/
```

You can inspect the package with host Moss:

```sh
artifacts/host-tools/bin/moss inspect artifacts/onix-stones/dropbear-*.stone
```

You can check that the local repo now has both BusyBox and Dropbear:

```sh
ls artifacts/onix-local-repo/*.stone
```

The next phase should consume this package from the local repo and switch the
running image's SSH service away from the Nix Dropbear path.

