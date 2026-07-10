# Phase 203 — assemble the root tree with host-side Moss only

## At a glance

| Field | Value |
|---|---|
| Phase family | Phase 2 — bootable image |
| Run command | `make phase 203` |
| Underlying make target/script | `vm/phase2/build-root-tree-host.sh` |
| Runs on | host |
| Main proof/artifact | Assembles artifacts/onix-root-tree/ with host-side Moss only. |


Phase 203 is the replacement for Phase 201.

This is the step where the same idea from 201 — turn the repo into a root tree —
is finally done *entirely on the host*, using the moss that step 202 built. Same
output, no forge, no SSH. It is the moment image assembly stops being a two-machine
dance and becomes a plain host build.

It consumes the same Phase 1 exported repo artifact:

```text
artifacts/onix-publish/
```

and the host-side Moss binary from Phase 202:

```text
artifacts/host-tools/bin/moss
```

Then it builds the canonical root tree directly on the host:

```text
artifacts/onix-root-tree/
```

The Phase 203 flow is:

```text
host artifacts/onix-publish/
   │
   ▼
host artifacts/host-tools/bin/moss install --to root-tree
   │
   ▼
host materializes image-owned /etc glue
   │
   ▼
host artifacts/onix-root-tree/
```

There is no SSH. There is no forge copy. There is no forge Moss.

Mechanically, the script re-runs the Phase 200 readiness gate, checksums the input
stones against `SHA256SUMS`, adds the local repo to a scratch moss root with
`repo add ... file://.../stone.index`, runs `repo update`, then
`install --to <root-tree> onix-branding onix-filesystem`. After the install it
materializes the same root-level `/etc` glue that Phase 201 did (the `os-release`
symlink, `issue`/`motd`/`fstab`/`profile` copies, `/etc/hostname`, the mount-point
directories, sticky `/tmp`). The only thing that changed versus 201 is *who* ran
moss — the host, not the forge.

#### Why Phase 203 matters

This is the point where image assembly becomes host-native.

Before Phase 203, the host could hold artifacts, but the forge still understood
the package format. After Phase 203, the host understands the package format
too.

That changes the role of the forge:

```text
before 203: forge is needed for root tree assembly
after 203:  forge is only bootstrap/build scaffolding
```

Future disk-image steps should consume the host-built root tree from Phase 203,
not the bridge root tree from Phase 201.

#### Phase 201 vs Phase 203

Both phases produce:

```text
artifacts/onix-root-tree/
```

But the assembly path is different:

```text
201: host repo -> forge moss -> host root tree
203: host repo -> host moss  -> host root tree
```

Phase 203 intentionally overwrites the same canonical artifact path because the
disk builder should not care how the tree was assembled. It only cares that the
root tree contract is satisfied. This is a small but important design idea: the
*contract* (a tree with the right files, symlinks, and permissions) is the
interface, and the *producer* (forge moss or host moss) is an implementation
detail behind it. Swapping the producer is invisible to everything downstream.

#### What Phase 203 verifies

Phase 203 verifies:

- Phase 200 readiness still passes
- Phase 1 exported repo artifact is clean
- host Moss exists and matches the pinned `OS_TOOLS_REF`
- `SHA256SUMS` validates
- host Moss can add the local repo index
- host Moss can install `onix-branding` and `onix-filesystem`
- `/usr/lib/system-model.kdl` records the installed packages
- `/etc/os-release` points to `../usr/lib/os-release`
- `/etc/fstab` contains `onix-root` and `ONIX-PERSIST`
- `/tmp` has sticky `1777` permissions
- no Moss assembly state leaks into the root tree
- no forbidden mixed-case brand spelling appears

The generated `system-model.kdl` should now mention:

```text
ONIX Phase 203 host image assembly repo
```

> **What `system-model.kdl` is.** moss records what it installed into a tree as a
> KDL document under `/usr/lib/system-model.kdl` — it names the repo the packages
> came from and the packages themselves. It is the tree's own account of how it
> was built. Here the repo comment string is set to "ONIX Phase 203 host image
> assembly repo" when host moss adds the repo, so its presence is proof the
> host-native path produced this tree.

That tells us the root tree was produced by the host-native path, not the
earlier forge path.

#### What Phase 203 proves vs does not prove

Phase 203 proves the host can now assemble a byte-identical root tree with no
forge involvement — the last hard dependency on the Alpine VM for image work is
gone. It still proves nothing about *disk* or *boot*: there is no partition table,
no filesystem, no bootloader, no kernel. Those begin at step 204 (the contract)
and 205 (the first real disk). After 203, the forge is pure build scaffolding, and
the disk lane can consume a known-good, host-produced tree.

