# Phase 514 — booted Phase 5 runtime proof

Phase 514 is the first Phase 5 step that turns the Phase 5 package/repository
work into a booted runtime proof.

It asks:

```text
Did the package/repository work actually become the live ONIX runtime?
```

Earlier Phase 5 steps build and audit packages on the host or in scratch Moss
install roots. That is necessary, but it is not the whole story. A distribution
package is only truly useful after the image consumes it and the booted system
can execute it from its real runtime path.

Phase 514 therefore performs the whole runtime path in one step:

```text
refresh canonical repo -> install Phase 5 packages into image -> boot VM -> SSH proof
```

Run it with:

```sh
make phase 514
```

Phase 514 boots the VM itself. It uses the same SSH path used by Phase 424/425:

```text
user: onix
host: 127.0.0.1
port: 7630
key : vm/state/id_ed25519
```

## Why this phase is separate from `make phase 5`

`make phase 5` runs the build/repository gates through Phase 513. Those steps can
run without leaving a VM alive.

Phase 514 is different. It is a live-machine proof. It needs a booted VM, SSH, a
forwarded QEMU port, and mutable image state. For that reason it is an explicit
command:

```sh
make phase 514
```

This mirrors Phase 4's live steps, but Phase 514 does not require you to run
Phase 424 first. It stops any existing native ONIX probe, mutates the image,
boots the VM again, and then runs the proof.

## What the script checks

The script is:

```text
vm/phase5/phase5-runtime-proof.sh
```

It has two modes:

```sh
vm/phase5/phase5-runtime-proof.sh --check
vm/phase5/phase5-runtime-proof.sh --apply
```

`--check` is cheap. It only verifies that the local documentation, package
contracts, and materializer wiring exist. `make doctor` can run this without
mounting an image or booting a VM.

`--apply` is the real Phase 514 flow. It does four things:

```text
1. assemble artifacts/onix-repo/unstable/x86_64 from the latest stones;
2. stop any currently running native ONIX VM;
3. restore the native systemd runtime into artifacts/onix-image/onix.raw;
4. install the Phase 5 runtime package set into that image;
5. boot the image and SSH into it for the runtime proof;
6. stop the VM after the proof unless `ONIX_PHASE514_KEEP_RUNNING=1` is set.
```

The package set installed into the image is:

```text
busybox
uutils-coreutils
musl
linux-pam
libseccomp
libgcc-runtime
rootasrole
rootasrole-policy
moss
```

`busybox` is included because Phase 513 changed its command ownership. The
image needs the reduced BusyBox package and uutils package together; otherwise
old BusyBox command links could remain in the live filesystem.

The `musl` package is included because it is the canonical owner of the dynamic
musl loader/libc family:

```text
/usr/lib/ld-musl-x86_64.so.1
/usr/lib/libc.so
/usr/lib/libc.musl-x86_64.so.1
```

This is important for the long-term package model. `systemd` still uses the
interpreter path:

```text
/lib/ld-musl-x86_64.so.1
```

Because ONIX uses merged `/usr`, that resolves to the real file under
`/usr/lib`. But `systemd` must not carry its own private musl copy. The
native `systemd` stone declares `musl` as a runtime dependency, and the
`musl` stone owns the loader/libc paths above.

So Phase 514 is also a regression test for package ownership:

```text
systemd -> depends on musl
musl         -> owns the loader/libc files
Phase 514    -> copies the combined moss install target into the image
```

If the systemd stone accidentally bundles musl again, the local repository will
hit file-ownership collisions or the boot proof will fail. That is intentional:
there must be one canonical musl owner.

## uutils proof

Phase 513 moved normal coreutils command ownership away from BusyBox and into
uutils.

Phase 514 proves that this is true in the booted VM:

```text
/usr/bin/coreutils exists
/usr/share/onix/packages/uutils-coreutils.commands exists
/usr/bin/ls    -> coreutils
/usr/bin/cp    -> coreutils
/usr/bin/mv    -> coreutils
/usr/bin/rm    -> coreutils
/usr/bin/mkdir -> coreutils
/usr/bin/[     -> coreutils
```

Then it walks the command manifest:

```text
/usr/share/onix/packages/uutils-coreutils.commands
```

For every command listed there, the corresponding `/usr/bin/<command>` path must
point at `coreutils`.

This matters because uutils is a multicall binary. The binary is one file:

```text
/usr/bin/coreutils
```

but the user expects normal command names:

```text
ls
cp
rm
mkdir
[
```

Those command names are usually symlinks to the multicall binary. Phase 514
proves that the symlinks exist and that they no longer point back at BusyBox.

BusyBox is still allowed to own recovery shell paths such as:

```text
/usr/bin/sh -> busybox
```

The point is not to remove BusyBox completely. The point is to stop using BusyBox
as the owner of normal coreutils behavior once ONIX has a Rust-first replacement.

## RootAsRole proof

RootAsRole is ONIX's selected sudo-class privilege path.

The important user-facing binary is:

```text
/usr/bin/dosr
```

Phase 514 checks:

```text
/usr/bin/dosr exists and is executable
/usr/bin/chsr exists and is executable
/usr/bin/dosr is setuid
/usr/share/onix/packages/rootasrole.md exists
```

`dosr` is setuid because a privilege tool has to cross from an ordinary user
context into a controlled privileged context. Setuid is powerful and dangerous,
so ONIX does not treat "the file exists" as enough. The file must be package-owned,
its policy must be present, and the library surface it depends on must also be
ONIX-owned.

## Policy proof

The RootAsRole package owns binaries. The `rootasrole-policy` package owns
the factory source for live machine policy.

Phase 514 checks:

```text
/usr/share/factory/etc/security/rootasrole.json
/usr/share/factory/etc/security/rootasrole.d/policy.json
/usr/share/factory/etc/pam.d/sr
/usr/share/factory/etc/pam.d/dosr
/etc/security/rootasrole.json
/etc/security/rootasrole.d/policy.json
/etc/pam.d/sr
/etc/pam.d/dosr
/usr/share/onix/packages/rootasrole-policy.md
```

RootAsRole's ONIX build uses a split config layout:

```text
/etc/security/rootasrole.json           root settings file
/etc/security/rootasrole.d/policy.json  actual authorization policy
```

The root settings file points at the policy-data directory. This matters because
the binaries were compiled with `RAR_CFG_DATA_PATH=/etc/security/rootasrole.d/`.
If ONIX installs only `/etc/security/rootasrole.json`, `dosr` starts but fails at
runtime because it cannot find the actual policy data.

The bootstrap policy should mention both actors by numeric UID:

```text
"id": 0
"id": 1000
```

RootAsRole's optimized finder resolves users to IDs while scanning policy, so
the bootstrap proof uses IDs directly instead of relying on user-name matching.

It must not mention the upstream legacy actor:

```text
ROOTADMINISTRATOR
```

The PAM service detail is easy to miss: the visible command is `dosr`, but the
RootAsRole binary opens the PAM service named `sr`. That means the runtime must
have:

```text
/etc/pam.d/sr
```

ONIX also keeps `/etc/pam.d/dosr` next to it because that is the command users
see and the name people naturally inspect first.

RootAsRole also writes timeout cookies. The build's storage path is:

```text
/var/run/rar/ts
```

On a modern system `/var/run` should be a compatibility symlink to `/run`.
That is extra important for ONIX because the root filesystem is mounted
read-only in this boot path, while `/run` is writable tmpfs. Phase 514 therefore
requires:

```text
/var/run -> ../run
```

Without that link, `dosr` can find the policy and pass PAM, but then fails while
trying to update its timeout cookie under read-only `/var`.

This is not the final ONIX admin model. It is the first useful proof that policy
is owned by packages, materialized into live `/etc`, and capable of authorizing
the bootstrap login user.

The later SSH proof runs as the normal `onix` user, so it does **not** read the
`0600` JSON policy files. Instead it proves they exist and are not readable by
the unprivileged login user. The sensitive content check belongs to the rootful
image-materialization step, not to an ordinary SSH session.

Then the SSH proof runs the real privilege command:

```sh
dosr /usr/bin/busybox id
```

and requires:

```text
uid=0(root)
```

So Phase 514 no longer accepts "dosr exists" as enough. It must actually execute
a command as root. The proof uses BusyBox `id` because the current
`uutils-coreutils` package owns the commands listed in its manifest, and `id` is
not part of that manifest in this bootstrap version.

## Shared-library surface proof

ONIX is static-first, not static-only.

RootAsRole currently needs a small dynamic-musl surface:

```text
dosr -> libpam.so.0
chsr -> libseccomp.so.2
both -> libgcc_s.so.1 and musl
```

Phase 514 checks that those files exist in the running VM:

```text
/usr/lib/libpam.so.0
/usr/lib/libseccomp.so.2
/usr/lib/libgcc_s.so.1
/usr/lib/ld-musl-x86_64.so.1
```

It also checks their package notes:

```text
/usr/share/onix/packages/linux-pam.md
/usr/share/onix/packages/libseccomp.md
/usr/share/onix/packages/libgcc-runtime.md
/usr/share/onix/packages/musl.md
```

This is the "minimal shared-library surface" rule in practice. Shared libraries
are allowed only when they are deliberate, documented, and owned by ONIX stones.
They are not allowed to be random libraries leaked from the host or from Nix.

## Runtime-clean proof

Phase 514 checks obvious text surfaces for `/nix/store`:

```text
/usr/share/onix/packages/*.md
/etc/moss/repo.d/onix-image.kdl
/usr/share/factory/etc/pam.d/sr
/usr/share/factory/etc/pam.d/dosr
/etc/pam.d/sr
/etc/pam.d/dosr
/usr/share/onix/bootstrap/phase5-runtime.txt
```

This does not replace the ELF-level audit from earlier steps. It is a live-system
sanity check: the booted machine should not advertise or configure Phase 5
packages through Nix runtime paths.

The deeper ELF checks happen before this:

- Phase 502 defines the payload audit helper.
- Phase 509 audits uutils.
- Phase 510 audits PAM/seccomp.
- Phase 511 audits RootAsRole and libgcc runtime.

Phase 514 asks a simpler but important live question:

```text
Are the accepted package files present in the actual booted system?
```

After Phase 515 exists, this includes `/usr/bin/moss`. Phase 514 also
initializes the live root's moss metadata:

```text
/.moss/db
/.moss/repo
/etc/moss/repo.d/onix-image.kdl
```

That means the booted VM must be able to run:

```sh
moss list available
moss li
```

directly against `/`, without a scratch `-D /tmp/...` root.

Those two commands prove different things:

- `moss list available` proves the live system knows about the ONIX repository.
- `moss li` proves the live system's Moss database knows which packages are
  installed into `/`, including the earlier boot-critical packages such as
  `systemd`.

This distinction matters because `moss install --to SOME_DIR` only blits files
into a target tree. It intentionally does **not** capture an installed package
state. Phase 514 therefore does two operations:

1. it uses `--to` in a scratch target so the Phase 5 payload can be audited
   safely before touching the image;
2. it then builds Moss's installed-state metadata in a scratch root using the
   full current ONIX package set;
3. it copies only the Moss metadata (`/.moss`, `/etc/moss`,
   `/usr/.stateID`, and `/usr/lib/system-model.kdl`) into the image.

That third step is important. A real Moss install against the mounted image root
would treat the selected package set as the whole managed system state. That is
too destructive while ONIX still has a few boot-critical borrowed/generated
files, such as the Phase 3-deferred kernel/module payload. Copying metadata lets
`moss li` tell the truth about the package-owned system surface without letting
Moss prune bootstrap files that are not packaged yet.

Phase 515 still performs the stronger proof that in-VM `moss` can consume a
copied ONIX repository and scratch-install packages from it.

## Expected success marker

On success the remote command prints:

```text
ONIX_PHASE514_REMOTE_OK ...
```

The host-side script requires that marker before it accepts the phase.

## If this phase fails

There are two common failure classes.

First, the canonical repo may be missing one of the required stones. In that case
rerun the earlier package phases that build the missing stone, then run Phase 514
again.

Second, the image may fail to boot after consuming the Phase 5 package set. In
that case the serial and boot logs live under:

```text
vm/state/phase514.ssh-boot.log
vm/state/phase514.ssh-serial.log
```

Third, the VM may boot but the runtime proof may find a missing or wrong path.
That tells us the install/materialization logic is wrong, not that we need another
new phase.

By default Phase 514 stops the VM after the proof so it does not leave a QEMU
process behind. For manual inspection:

```sh
ONIX_PHASE514_KEEP_RUNNING=1 make phase 514
```
