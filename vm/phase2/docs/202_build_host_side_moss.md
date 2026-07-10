# Phase 202 — build host-side Moss

## At a glance

| Field | Value |
|---|---|
| Phase family | Phase 2 — bootable image |
| Run command | `make phase 202` |
| Underlying make target/script | `vm/phase2/build-host-moss.sh` |
| Runs on | host |
| Main proof/artifact | Builds artifacts/host-tools/bin/moss from pinned os-tools. |


Phase 202 is the next bootstrap cleanup.

Phase 201 proved that the exported repo can become a root tree, but it still
used Moss inside the forge:

```text
host repo artifact -> forge moss -> host root tree
```

That is useful, but it is not where we want to stay. The forge is temporary
bootstrap scaffolding. Image assembly should become host-native:

```text
host repo artifact -> host moss -> host root tree -> disk image
```

### Why the host needs its own moss

The forge exists to *bootstrap*, not to be a permanent dependency. Every time
image assembly reaches across SSH into the forge, ONIX is coupled to a throwaway
Alpine VM being up, reachable, and in the right state. That is fragile and, worse,
conceptually wrong: the endgame is an ONIX that builds its own images with its own
tools. The blocker was simple — only moss can unpack a `.stone`, and the host did
not have moss. Phase 202 removes exactly that blocker and nothing else. It does
not yet rebuild the root tree (that is 203); it just makes the tool available on
the host so 203 *can*.

> **What moss and boulder are.** Both are Rust binaries from AerynOS's `os-tools`
> — the one external dependency ONIX pins. **moss** is the atomic package/state
> manager (install, remove, roll back transactions). **boulder** is the `.stone`
> builder. ONIX uses this *tooling* but none of AerynOS's packages. Building moss
> here is ordinary Rust compilation; it needs no AerynOS system underneath it,
> which is the whole reason it can run on a plain dev host.

Phase 202 builds a host-side `moss` binary from the same pinned `os-tools`
source used by Phase 0:

```text
artifacts/host-tools/bin/moss
```

The build is a `cargo build --profile onboarding -p moss` against the pinned
checkout; the resulting binary is installed to `artifacts/host-tools/bin/moss`
and its `--version` is smoke-tested. Using the *same* pin as Phase 0 is the point:
host moss and forge moss must agree byte-for-byte on the `.stone` format, or a
tree built by one could be misread by the other. Step 203 even asserts that host
moss reports the expected `OS_TOOLS_REF` before it trusts it.

It requires Rust `>= 1.91`. The ONIX flake provides a new enough toolchain. If
your shell still reports an older `rustc`, reload the dev shell:

```sh
direnv reload
```

or run the phase explicitly through Nix:

```sh
nix develop --impure -c make phase 202
```

It also records the source pin at:

```text
artifacts/host-tools/os-tools.source
artifacts/host-tools/os-tools.git-deps
```

That file is generated and gitignored with the rest of `artifacts/`.

#### Source policy

ONIX currently treats AerynOS `os-tools` as pinned bootstrap tooling.

> **What "pinning" means.** A pin is an exact commit hash, not a branch or a tag.
> Branches move; tags can be re-pointed; a commit hash is immutable. Pinning
> `os-tools` means every ONIX build compiles the *identical* source, so a moss
> binary built today behaves like one built next year. This is the same
> reproducibility discipline that lets an image build record a "snapshot triple"
> (os-tools commit + repo commit + resulting transaction id).

The current source of truth is still:

```text
OS_TOOLS_REPO=https://github.com/AerynOS/os-tools.git
OS_TOOLS_REF=36f78e5bcfa9d594d65d1c6d2e332e950f3e4d0e
```

The pinned commit protects ONIX from upstream code changes.

It does **not** protect ONIX from source availability problems such as:

- upstream repository deletion
- upstream repository rename
- GitHub outage
- git dependency disappearing

So the future source-control policy should be:

```text
1. mirror/fork os-tools into github.com/onix-os/os-tools
2. keep the exact same commit first
3. switch OS_TOOLS_REPO to the ONIX mirror
4. only diverge on an ONIX branch when ONIX needs patches
```

That means the first ONIX mirror step is boring on purpose. It is availability
insurance, not a fork-war.

`os-tools` may also contain git dependencies such as boot tooling crates. When
we switch to ONIX mirrors, we must audit the `Cargo.toml`/`Cargo.lock` graph and
mirror every git dependency that matters for reproducible bootstrap.

At the current pin, Phase 202 records these git dependencies:

```text
https://github.com/AerynOS/blsforme.git?rev=680720545303e123e47e0df07a8a85178c9f5c19
https://github.com/AerynOS/disks-rs?rev=d08bc11dcfb2ad4d031e2adccb97139f9d42c2b8
https://github.com/AerynOS/ent.git?rev=42416ecae36c0f29e07647747147672448241f85
https://github.com/AerynOS/os-info?rev=26b39c1d49c3b4f30d778729fb56958824c069de
https://github.com/kdl-org/kdl-rs?rev=e9df058c25cd4486df8fe568d2ff24ea2c4ed0e8
```

The ONIX mirror priority should be the AerynOS-owned dependencies first:

```text
os-tools
blsforme
disks-rs
ent
os-info
```

`kdl-rs` is not AerynOS-owned, but it is still a pinned git dependency. We can
leave it upstream for now or mirror it later if we want fully independent
bootstrap availability.

#### What Phase 202 proves

Phase 202 proves:

- the host dev shell has enough Rust/build tooling to compile Moss
- the host can fetch and checkout the exact same pinned `os-tools` ref
- the resulting host binary runs
- ONIX has a generated host-tool location for future phases

It does **not** yet replace Phase 201.

That replacement should be a separate phase so the learning step is obvious:

```text
203 = rebuild root tree using host Moss only
```

At that point the flow becomes:

```text
artifacts/onix-publish/
   │
   ▼
artifacts/host-tools/bin/moss install --to artifacts/onix-root-tree
```

No SSH, no forge copy, no forge Moss.

