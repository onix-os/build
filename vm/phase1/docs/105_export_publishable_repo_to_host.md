# Phase 105 — export publishable repo to the host

## At a glance

| Field | Value |
|---|---|
| Phase family | Phase 1 — first stones |
| Run command | `make phase 105` |
| Underlying make target/script | `vm/phase1/export-publishable-repo.sh` |
| Runs on | host plus guest over SSH |
| Main proof/artifact | Copies the publishable repo artifact to artifacts/onix-publish/. |


Phase 104 creates the publishable repo inside the forge VM. Phase 105 copies it
back to the host:

```text
forge: ~/stone-lab/onix-publish/
host:  artifacts/onix-publish/
```

## Why cross the host/guest boundary now

Everything through step 104 lived inside the throwaway forge VM. That is fine for
*building*, but a forge is scaffolding — it gets destroyed and rebuilt. Anything
meant to outlive a single forge, or to eventually be uploaded, has to come back
to the **host** (your real working machine, where this git repository lives).
Step 105 is that hand-off: it moves the publishable tree from a disposable place
to a durable one, and — importantly — proves it survives the trip intact.

## How the copy works, and why it is careful

The export script does not use a naive `scp -r`. It streams a `tar` over SSH into
a temporary directory, checks it, and only then atomically swaps it into place.
Walking the mechanism:

1. **Remote pre-check and checksum.** Over SSH, the forge first confirms the
   publishable tree from step 104 exists (`repo.json`, `README.txt`,
   `unstable/<arch>/stone.index`) and re-runs `sha256sum -c SHA256SUMS` *inside
   the VM*, before sending anything. If the source is incomplete it stops and
   tells you to run `make phase 104`.
2. **Stream over SSH as a tar.** The forge does `tar -cf -` of exactly
   `README.txt`, `repo.json`, and `unstable/`, piped over the SSH channel and
   unpacked on the host into a `mktemp` scratch directory — not straight into the
   destination. Streaming a tar preserves the tree structure in one pass and
   never leaves a half-copied destination.
3. **Host-side re-verification.** On the host the script re-checks the expected
   files exist and runs `sha256sum -c SHA256SUMS` *again*. The checksums are
   verified on both sides of the wire, so a corrupted transfer is caught, not
   inherited.
4. **Refuse to import test state.** It scans the staged tree for any moss test
   leftovers (`.moss`, `moss-root`, `moss-cache`, `install-target`) and aborts if
   it finds any — the published artifact must contain *only* repo files, never
   the scratch roots used to prove installs.
5. **Atomic swap into place.** Only after all checks pass does it `rm -rf` the old
   `artifacts/onix-publish/` and `mv` the staged directory into place. An
   interrupted run leaves the previous good artifact untouched.

## The host artifact

The host artifact is gitignored because it contains generated `.stone` package
files and checksums.

After this phase, the important host files are:

```text
artifacts/onix-publish/repo.json
artifacts/onix-publish/README.txt
artifacts/onix-publish/unstable/x86_64/stone.index
artifacts/onix-publish/unstable/x86_64/SHA256SUMS
artifacts/onix-publish/unstable/x86_64/*.stone
```

### Why it is gitignored

`.stone` files are *build outputs* — large, binary, and reproducible from the
recipes. Committing them would bloat history and, worse, invite the anti-pattern
of a repo whose packages drift from its recipes. ONIX's rule is that source of
truth is the recipe under `packages/` (or `recipes/`); the built artifact under
`artifacts/` is disposable and regenerable, so it stays out of git. Step 106
explicitly *verifies* this gitignore protection is in force.

## Still no publishing

This still does **not** publish anything. It gives us a local host-side artifact
that a later phase can upload to `repo.onix-os.com` or another static host.

The distinction being drawn, and held for the rest of Phase 1, is:
**"export to the host" is not "publish to the internet."** The artifact now sits
on your disk in exactly the byte-for-byte shape a web server would serve — but no
server, no network request, and no DNS is involved. That gap is intentional and
is what steps 107 and 108 formalize into a written, refuse-to-upload plan.

## What it proves vs what it does not

It **proves**: the publishable tree can leave the forge and land on the host with
its checksums intact on both sides, containing only repo files (no leaked moss
test state), placed atomically into a gitignored location.

It does **not** prove: the artifact's *independent* correctness from the host's
point of view (that is step 106, which re-checks it with no SSH at all), nor
anything about actual hosting. It is the plumbing step between "built in the VM"
and "auditable on the host."
