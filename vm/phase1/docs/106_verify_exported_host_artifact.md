# Phase 106 — verify exported host artifact

## At a glance

| Field | Value |
|---|---|
| Phase family | Phase 1 — first stones |
| Run command | `make phase 106` |
| Underlying make target/script | `vm/phase1/verify-exported-repo.sh` |
| Runs on | host |
| Main proof/artifact | Verifies the exported repo artifact, checksums, metadata, and gitignore protection. |


Phase 106 is host-only. It does not SSH into the forge VM.

## Why a separate, host-only verification

Step 105 already checked the artifact as it copied it — but that check ran as
part of the *producer*. Step 106 is a deliberately independent *auditor*: it
takes nothing on faith from the export, opens no SSH connection, and re-derives
every claim purely from the bytes now sitting under `artifacts/onix-publish/`.
This separation matters because the artifact is the thing a future upload phase
will push to the internet. Before anything can be published, an auditor that
depends on *only* the local files — not on a live VM, not on the build that made
them — has to sign off. Step 106 is that auditor, and it is the real gate at the
end of the build-and-export chain.

## What it verifies

It verifies:

- `artifacts/onix-publish/repo.json` exists and names ONIX correctly
- homepage is `https://onix-os.com`
- source is `https://github.com/onix-os`
- future repo hint is `https://repo.onix-os.com/unstable/x86_64/stone.index`
- exactly one `branding` stone exists
- exactly one `filesystem` stone exists
- `SHA256SUMS` validates
- no Moss test state (`.moss`, `moss-root`, `moss-cache`, `install-target`) leaked into the artifact
- `artifacts/` is gitignored

### Reading the checks, grouped

The script (`verify-exported-repo.sh`) runs four kinds of check, and it is worth
knowing what each one is really guarding against:

- **Presence** — `README.txt`, `repo.json`, `stone.index`, and `SHA256SUMS` must
  all exist. A missing file means the export was incomplete.
- **Identity** — it greps `repo.json` for the exact ONIX name, id, homepage,
  source, and `repo_url_hint`. This catches branding drift (the project rule is
  the name is only ever `ONIX` or `onix`) and guarantees the public-facing URLs
  are correct *before* they are ever advertised.
- **Cardinality** — *exactly one* `branding-*.stone` and *exactly one*
  `filesystem-*.stone`. This is subtle and important: an old build left
  behind next to a new one would put two versions of the same package in the
  repo, and a client could resolve the wrong one. "Exactly one" keeps the channel
  unambiguous.
- **Integrity** — `sha256sum -c SHA256SUMS` re-validates every stone and the
  index against their recorded hashes, from the host, with no trust in the export
  step.

### The negative checks: no test state, and gitignored

Two checks assert the *absence* of things:

- **No leaked moss test state.** It walks the tree for `.moss`, `moss-root`,
  `moss-cache`, or `install-target` and fails if any exist. Those are the scratch
  roots used to prove installs; they must never be part of a published repo (they
  would leak local paths and bloat the upload).
- **`artifacts/` is gitignored.** Using `git check-ignore`, it confirms the
  exported tree is excluded from version control — enforcing the "built artifacts
  are regenerable, not committed" rule from step 105. If someone accidentally
  removed the ignore rule, this catches it.

## What it gives us

This gives us a clean gate before any future upload/publish phase.

Concretely: after a green step 106 you have a host-side repository tree that is
*proven* complete, correctly branded, unambiguous (one stone per package),
integrity-checked, free of local test debris, and safely outside git. That is
precisely the set of properties a real upload must not violate — which is why the
later publish-plan and dry-run steps (107, 108) both *begin* by re-running this
exact verification.

## What it proves vs what it does not

It **proves**: the exported artifact is self-consistent and publish-clean, judged
from the host alone.

It does **not** prove: that the artifact has been or should be uploaded. It makes
zero network requests and changes no DNS. Turning this verified artifact into an
explicit, written, still-no-upload publication *plan* is step 107; previewing the
exact upload mapping without running it is step 108.
