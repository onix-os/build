# 508 — local public repository layout

Run:

```sh
make phase 508
```

Phase 508 takes the canonical local package repository from Phase 505/506/507
and reshapes it into the layout ONIX can later serve from:

```text
https://repo.onix-os.com
```

This phase still does **not** upload anything.

It is a local-only publishing rehearsal.

The output is:

```text
artifacts/onix-public-repo/
```

The important idea is:

```text
same package content, more realistic public repository shape
```

Phase 507 proved:

```text
canonical local repo -> image assembly -> boot proof
```

Phase 508 now proves:

```text
canonical local repo -> public-shaped repo -> moss install proof
```

## Why this phase exists

Phase 505 created a simple local repository:

```text
artifacts/onix-repo/unstable/x86_64/
  stone.index
  *.stone
```

That is easy to understand and good for local image assembly.

But a public distro repository needs a little more structure.

If every client points directly at:

```text
unstable/x86_64/stone.index
```

then we have fewer tools for future repository management.

Later we will need to answer questions such as:

- what is the current `unstable` snapshot?
- can a stream move forward while old snapshots stay downloadable?
- can a user pin a known history?
- can we keep package files in a shared pool instead of duplicating them?
- can a client discover the correct index through one stable base URI?

Phase 508 prepares that shape locally before any server exists.

The rule is:

```text
make the repository shape boring locally before putting it on the internet
```

### Background: why real distro repos look like this

The pool/history/stream shape is not invented here; it is the pattern battle-tested
distributions converged on. Debian keeps every package file in a shared `pool/`
addressed by first letter (`pool/main/o/openssh/...`) and lets multiple releases point
into it, so the same file is stored once no matter how many suites reference it. Many
atomic and image-based systems keep **immutable snapshots** and a moving pointer to
"the current one," so a client can pin an exact past state for reproducible installs or
rollback. ONIX's `pool` (shared package objects), `history/<id>` (immutable snapshot
indexes), and `stream/unstable` (the moving pointer) are the same three ideas under
moss-flavored names. Building them now — even with a single architecture and a small
essential package set — means the shape that eventually sits behind `repo.onix-os.com` is already
the one that has been exercised locally.

The single most important property is **indirection through the root index**. A client
is told only a base URI and a version (`stream/unstable`); it discovers the concrete
index and package paths by reading metadata, not by hard-coding directory layout. That
is what lets the repository reorganize its internals later — add architectures, retire
old histories, move the pool — without every client breaking. Phase 505's flat
`stone.index` had no such indirection; Phase 508 adds the layer that makes future
repository management possible.

## The public-shaped layout

Phase 508 writes:

```text
artifacts/onix-public-repo/
  README.txt
  repo.json
  main/
    moss-root-index.json
    SHA256SUMS
    MANIFEST.tsv
    stream/
      unstable/
        MANIFEST.tsv
        x86_64/
          stone.index
    history/
      <history-id>/
        MANIFEST.tsv
        x86_64/
          stone.index
    pool/
      v0/
        l/
          libseccomp/
            libseccomp-*.stone
          linux-pam/
            linux-pam-*.stone
        m/
          moss/
            moss-*.stone
          musl/
            musl-*.stone
        o/
          branding/
            branding-*.stone
          filesystem/
            filesystem-*.stone
          busybox/
            busybox-*.stone
          dropbear/
            dropbear-*.stone
          systemd/
            systemd-*.stone
          bootstrap/
            bootstrap-*.stone
        r/
          rootasrole/
            rootasrole-[0-9]*.stone
        u/
          uutils-coreutils/
            uutils-coreutils-*.stone
```

The future public base URI is:

```text
https://repo.onix-os.com
```

The local base URI is:

```text
file://$PWD/artifacts/onix-public-repo
```

Moss can consume the local version with the same root-index model that a public
host will use later.

## Basic vocabulary

This phase introduces a few repository words.

### Base URI

The base URI is the root address of the repository.

For the local proof:

```text
file:///home/.../bedrock/artifacts/onix-public-repo
```

For the future server:

```text
https://repo.onix-os.com
```

The client should not need to know every internal file path by hand.

It should start from the base URI and the desired version.

### Channel

The root-index channel is the top-level metadata channel.

In Phase 508 it is:

```text
main
```

That means Moss looks for:

```text
main/moss-root-index.json
```

The word `main` here does **not** mean the package stream is stable.

It is the metadata channel used to find repository history.

### Stream

The package stream is the moving package line.

In Phase 508 it is:

```text
unstable
```

The stream answers:

```text
what is the current unstable package set?
```

The root index maps:

```text
stream/unstable -> history/<history-id>
```

So clients can ask for the moving stream, but the repository can still record
which exact history that stream currently points to.

### History

A history is an immutable-ish snapshot identifier.

Phase 508 uses a generated history id.

That creates:

```text
main/history/<history-id>/x86_64/stone.index
```

The stream index is copied to:

```text
main/stream/unstable/x86_64/stone.index
```

The history path matters because later ONIX can keep old histories around.

That gives us room for rollback, debugging, and reproducible installs.

### Pool

The pool stores the actual `.stone` files:

```text
main/pool/v0/o/systemd/systemd-*.stone
```

The index files do not need to sit beside every package file.

The index records relative package paths that point back into the pool.

This is closer to how a real distro repository is managed:

```text
metadata points to package objects
package objects live in a shared pool
```

## How Moss resolves the repository

The root-index proof uses:

```text
moss repo add onix-public file://.../artifacts/onix-public-repo \
  --root-index version=stream/unstable
```

That tells Moss:

```text
base URI = file://.../artifacts/onix-public-repo
version  = stream/unstable
channel  = main by default
arch     = x86_64 by default
```

Moss then resolves the repository in steps.

### Step 1: read the root index

Moss fetches:

```text
<base URI>/main/moss-root-index.json
```

In the local proof, that becomes:

```text
file://.../artifacts/onix-public-repo/main/moss-root-index.json
```

### Step 2: resolve the stream to a history

Inside `moss-root-index.json`, Phase 508 writes a map like:

```json
{
  "streams": {
    "unstable": {
      "format": "v0",
      "history": "<history-id>",
      "tag": "snapshot-<history-id>"
    }
  }
}
```

So:

```text
stream/unstable
```

resolves to:

```text
history/<history-id>
```

### Step 3: read the history index

Moss then reads:

```text
<base URI>/main/history/<history-id>/x86_64/stone.index
```

That file is the package index for that architecture and history.

### Step 4: download package files from the pool

The history index contains package metadata and package file paths.

Because Phase 508 builds the index from the pool and writes the index into the
history directory, package paths resolve back to:

```text
main/pool/v0/...
```

That proves the important public hosting shape:

```text
root index -> history index -> pooled stones
```

## Why there is also a stream index

Phase 508 writes both:

```text
main/history/<history-id>/x86_64/stone.index
main/stream/unstable/x86_64/stone.index
```

The root-index model uses the history index.

The direct stream index is kept for inspection and compatibility with the
simpler mental model from Phase 505:

```text
moss repo add onix-public-stream file://.../main/stream/unstable/x86_64/stone.index
```

Phase 508 proves both paths:

1. root-index consumption,
2. direct stream-index consumption.

The root-index path is the more important future public path.

The direct stream path is useful while learning and debugging.

## What `make phase 508` does

The helper is:

```text
vm/phase5/assemble-local-public-repo.sh
```

It does five groups of work.

### 1. Check the canonical input repo

It reads:

```text
artifacts/onix-repo/unstable/x86_64/
```

and verifies:

```text
stone.index
SHA256SUMS
MANIFEST.tsv
```

It also checks that exactly one stone exists for each current essential package:

```text
branding
filesystem
busybox
uutils-coreutils
dropbear
systemd
bootstrap
musl
linux-pam
libseccomp
rootasrole
moss
```

Each stone is checked with:

```text
moss inspect --check
```

### 2. Copy stones into the pool

The script copies those stones into:

```text
artifacts/onix-public-repo/main/pool/v0/<first-letter>/<package>/
```

The bucket is the first letter of the package name. For example:

```text
systemd      -> pool/v0/o/systemd/
uutils-coreutils  -> pool/v0/u/uutils-coreutils/
moss              -> pool/v0/m/moss/
rootasrole        -> pool/v0/r/rootasrole/
```

It leaves room for a wider package pool later.

### 3. Build history and stream indexes

The script runs Moss indexing over the pool:

```text
moss index main/pool/v0 -o main/history/<history-id>/x86_64
```

Then it copies that index to:

```text
main/stream/unstable/x86_64/stone.index
```

This gives us both the root-index history path and the easier direct stream
path.

### 4. Write human and machine metadata

The script writes:

```text
README.txt
repo.json
main/MANIFEST.tsv
main/SHA256SUMS
main/moss-root-index.json
```

`README.txt` explains the generated tree.

`repo.json` records the local root, future base URI, channel, stream,
architecture, and history.

`MANIFEST.tsv` maps package names to stone filenames and pool paths.

`SHA256SUMS` checks the generated metadata and package files.

`moss-root-index.json` is the key future-public metadata file.

### 5. Prove Moss can consume the public-shaped repo

The phase installs the package set twice into scratch roots:

```text
artifacts/onix-phase5-work/508/root-index/install-target/
artifacts/onix-phase5-work/508/direct-stream/install-target/
```

The first proof uses:

```text
file://.../artifacts/onix-public-repo
--root-index version=stream/unstable
```

The second proof uses:

```text
file://.../artifacts/onix-public-repo/main/stream/unstable/x86_64/stone.index
```

Both proofs install:

```text
branding
filesystem
busybox
uutils-coreutils
dropbear
systemd
bootstrap
musl
linux-pam
libseccomp
rootasrole
moss
```

Then they check for expected files such as:

```text
/usr/lib/os-release
/usr/bin/busybox
/usr/bin/coreutils
/usr/bin/moss
/usr/sbin/dropbear
/usr/lib/systemd/systemd
/usr/lib/ld-musl-x86_64.so.1
/usr/lib/libseccomp.so.2
/usr/bin/dosr
/usr/share/factory/etc/security/rootasrole.json
/usr/share/onix/packages/bootstrap.md
/usr/share/onix/packages/moss.md
```

If Moss cannot install from the local public-shaped repo, Phase 508 fails.

## What this phase does not do

Phase 508 does not:

- upload to a server,
- require DNS,
- require `repo.onix-os.com` to exist,
- sign repository metadata,
- define stable release promotion,
- define package retention policy,
- define mirror/CDN policy.

Those are later publishing and release-engineering steps.

Phase 508 only answers:

```text
Can ONIX build a public-shaped repo locally, and can Moss consume it?
```

## How to inspect the result

After running:

```sh
make phase 508
```

inspect the tree:

```sh
find artifacts/onix-public-repo -maxdepth 5 -type f | sort
```

Read the root index:

```sh
cat artifacts/onix-public-repo/main/moss-root-index.json
```

Read the manifest:

```sh
column -t -s $'\t' artifacts/onix-public-repo/main/MANIFEST.tsv
```

Check generated checksums:

```sh
(cd artifacts/onix-public-repo/main && sha256sum -c SHA256SUMS)
```

Run only the verification/proof mode:

```sh
vm/phase5/assemble-local-public-repo.sh --check
```

## Mental model

Phase 505:

```text
*.stone files + one local stone.index
```

Phase 507:

```text
that local stone.index feeds image assembly
```

Phase 508:

```text
same package set becomes a public-shaped repository tree
```

So the flow is now:

```text
canonical package recipes
  -> essential .stone artifacts
  -> canonical local repo
  -> image consumes canonical local repo
  -> public-shaped local repo
  -> Moss consumes public-shaped repo through root index
```

This is still not a finished package ecosystem.

But it is the first ONIX repository shape that looks like something we can put
behind a real domain later.

## What comes next

After Phase 508, ONIX has a local public repository layout.

The next package-plane work should stay local until the package set becomes
more useful.

Good next steps are:

- add the first Rust-first external system package, probably `uutils-coreutils`;
- make that package pass the runtime-clean payload audit;
- add it to the canonical repo;
- add it to the public-shaped repo proof;
- only after the local loop is boring, design real upload/signing for
  `repo.onix-os.com`.
