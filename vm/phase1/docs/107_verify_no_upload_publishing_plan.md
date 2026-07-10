# Phase 107 — verify no-upload publishing plan

## At a glance

| Field | Value |
|---|---|
| Phase family | Phase 1 — first stones |
| Run command | `make phase 107` |
| Underlying make target/script | `vm/phase1/prepare-publish-plan.sh` |
| Runs on | host |
| Main proof/artifact | Verifies the no-upload publishing contract in this page. |


Phase 107 is also host-only. It does not SSH into the forge VM and does not
publish anything.

## Why the plan is verified as a document

This is an unusual step: the artifact it checks is *this very book page*. The
idea is that the publication procedure — the URLs, the required checks, the rule
that no phase uploads — should be **written down, versioned, and machine-checked**
rather than living in someone's head or in a shell script that might quietly gain
an upload command. The script `prepare-publish-plan.sh` literally greps this page
for the exact strings the contract must contain (the homepage, the source, the
future index URL, `make phase 106`, the "No phase currently changes" clause, and
the do-not-publish-prematurely rule). If someone edited the plan into an unsafe
shape — or misspelled the brand — the check fails. The document is treated as
part of the system, because it is.

This is also why the page's headings and key phrases are load-bearing and must
not be reworded: the verification depends on them.

## What it verifies

It verifies two things:

1. the exported artifact still passes Phase 106 checks
2. this book page contains the current publication contract

In other words it first re-runs the entire step 106 verification (so the plan is
never certified against a stale or dirty artifact), and only then checks that the
written contract below is present and correctly branded. It also rejects the
forbidden mixed-case spelling of the brand — the project rule is the name is only
ever `ONIX` or `onix`.

The publication contract records:

- homepage: `https://onix-os.com`
- source: `https://github.com/onix-os`
- future repo root: `https://repo.onix-os.com`
- future Moss index: `https://repo.onix-os.com/unstable/x86_64/stone.index`
- local artifact source: `artifacts/onix-publish/`
- the rule that no current phase uploads or changes DNS

This gives us a safe stopping point before any future real hosting work.

#### Phase 107 publication contract

This is the safe publication plan for the package repo artifact produced by
Phase 1.

It is intentionally a plan, not an upload script. No phase currently changes
DNS, pushes to a server, or publishes packages to the internet.

Canonical project locations:

```text
homepage: https://onix-os.com
source:   https://github.com/onix-os
repo:     https://repo.onix-os.com
```

The host-side artifact is produced by:

```sh
make phase 105
```

and verified by:

```sh
make phase 106
```

The clean local publish root is:

```text
artifacts/onix-publish/
```

Expected files:

```text
artifacts/onix-publish/README.txt
artifacts/onix-publish/repo.json
artifacts/onix-publish/unstable/x86_64/SHA256SUMS
artifacts/onix-publish/unstable/x86_64/stone.index
artifacts/onix-publish/unstable/x86_64/onix-branding-*.stone
artifacts/onix-publish/unstable/x86_64/onix-filesystem-*.stone
```

The future public Moss index URL is:

```text
https://repo.onix-os.com/unstable/x86_64/stone.index
```

Before any real upload, run:

```sh
make phase 104
make phase 105
make phase 106
```

Those checks must prove:

- `SHA256SUMS` validates
- the artifact contains only publish files
- no `.moss`, `moss-root`, `moss-cache`, or `install-target` directories leaked
- `repo.json` says homepage is `https://onix-os.com`
- `repo.json` says source is `https://github.com/onix-os`
- `repo.json` hints `https://repo.onix-os.com/unstable/x86_64/stone.index`

Any hosting target must serve this directory tree byte-for-byte:

```text
repo root/
  unstable/
    x86_64/
      stone.index
      SHA256SUMS
      *.stone
```

The host must allow direct HTTP GET for:

```text
/unstable/x86_64/stone.index
/unstable/x86_64/SHA256SUMS
/unstable/x86_64/*.stone
```

The repo can be hosted on any static file host. Candidate paths:

- a dedicated static host behind `repo.onix-os.com`
- GitHub Pages for a future repo such as `github.com/onix-os/repo`
- an object bucket or VPS static directory

When ready, create DNS for:

```text
repo.onix-os.com
```

pointing at the chosen static host.

Do not point DNS at a host until the uploaded tree can serve:

```text
https://repo.onix-os.com/unstable/x86_64/stone.index
```

A future phase may add a real upload command, but it must be explicit and
separate from the build/verify phases.

Good shape:

```text
make phase 108   # dry-run upload / publish preview; no network, no upload
make phase 109   # real upload, only after explicit confirmation
```

The real upload phase should:

1. run `make phase 106`
2. upload `artifacts/onix-publish/` to the chosen static host
3. fetch the public `stone.index`
4. compare its checksum with the local `stone.index`
5. fetch public `SHA256SUMS`
6. verify every listed file is reachable
7. print the exact repo add command users will run later

Once the repo is live, the user-facing repo command shape should be:

```sh
moss repo add onix-unstable https://repo.onix-os.com/unstable/x86_64/stone.index -c "ONIX unstable"
moss repo update
```

Do not publish this as an installation instruction until the public URL is live
and verified.

## Why static hosting is enough (and why that is the point)

Notice the contract only ever asks a host to serve **static files over plain HTTP
GET** — an index, a checksum manifest, and some `.stone` blobs. There is no
database, no server-side package logic, no special "repo software" to run. That
is a deliberate design property of moss repositories: because the index and the
stones are just files, an ONIX mirror can live on GitHub Pages, an object bucket,
or a VPS directory with equal ease. It also means the "publish" operation reduces
to *an ordinary file copy* (`rsync` of the tree), which is exactly why it can be
made safe, explicit, and separable from building — the whole thrust of this step.

## Why "no upload" is a feature, not a limitation

It would be easy to bolt an `rsync` onto the end of step 105 and call the repo
"published." Phase 1 refuses to, on purpose. Uploading is irreversible in effect
(users may add the repo the moment it appears) and it touches shared state (DNS,
a live host) that a build step must never mutate as a side effect. By freezing the
procedure into a checked *contract* and keeping the actual upload as a future,
explicitly-confirmed phase (`make phase 109` in the sketch above), ONIX keeps a
hard wall between "I built and verified an artifact" and "I changed what the world
can download." Step 108 then lets you *preview* that upload — printing every
source→URL mapping and even the `rsync`/`curl` commands — while still running none
of them.

## What it proves vs what it does not

It **proves**: the exported artifact still passes step 106, and the written
publication plan on this page is present, correctly branded, and self-consistent.

It does **not** prove: that anything is hosted. It makes no network request,
changes no DNS, and uploads nothing — and it is designed so that it *cannot*
accidentally do so.
