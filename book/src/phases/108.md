# Phase 108 — preview publication without upload

## At a glance

| Field | Value |
|---|---|
| Phase family | Phase 1 — first stones |
| Run command | `make phase 108` |
| Underlying make target/script | `vm/phase1/publish-dry-run.sh` |
| Runs on | host |
| Main proof/artifact | Prints the future publication mapping without uploading or touching the network. |


Phase 108 is still host-only and still safe. It does **not** upload anything,
does **not** contact the network, and does **not** change DNS.

## What a dry run is, and why it closes Phase 1

A **dry run** is a rehearsal: it computes and prints exactly what a real
operation *would* do, then stops short of doing it. Step 108 is the dry run for
publishing the ONIX repo. It is the natural close of Phase 1 because it makes the
future upload concrete and inspectable — you can read the precise source→URL
mapping and the very commands a real publish would run — while guaranteeing, by
construction, that nothing leaves your machine. It turns "we have a plan" (step
107) into "here is that plan resolved against the actual files, ready to eyeball."

## What it does

It verifies the Phase 107 plan, then prints:

- local artifact root
- future public root
- every file that would be published
- the future public URL for every file
- critical URLs to check after a real upload
- the `rsync`/`curl` commands that a future real publish phase might run, but
  refuses to run them
- the future user-facing `moss repo add` command

Walking the mechanism: the script (`publish-dry-run.sh`) first runs the step 107
plan verification (which itself re-runs step 106), so a dry run is never produced
against an unverified artifact. It then walks every file under
`artifacts/onix-publish/` and, for each, prints the relative path beside the
public URL it would map to under `https://repo.onix-os.com` — this is the literal
translation from your local tree to the web namespace. It surfaces the two
critical URLs a real upload must serve (`.../stone.index` and `.../SHA256SUMS`),
then *prints but does not execute* the `rsync -av --delete` upload command and the
`curl` fetch-and-compare commands. Finally it prints the future user-facing
`moss repo add onix-unstable ... -c "ONIX unstable"` line — the command an end
user will eventually run once the repo is live.

The key detail is that every dangerous command is emitted as **text on your
terminal**, never handed to a shell. You can read the exact `rsync` that a future
`make phase 109` would run and satisfy yourself it is correct, without a single
byte being sent.

## Previewing a concrete destination (still without using it)

You can optionally preview a concrete upload destination without using it:

```sh
ONIX_REPO_UPLOAD_TARGET='user@host:/srv/repo.onix-os.com' make phase 108
```

It will print the target, but still not upload.

This lets you dry-run against the *real* server address you intend to use, so the
printed `rsync` command shows the actual `user@host:/path` rather than a
placeholder — a last sanity check before a real publish phase exists. Setting the
variable changes only what is *printed*; the safety result at the end still
reports that no upload was performed, no DNS changed, and no network was
contacted.

## What it proves vs what it does not

It **proves**: the full publication mapping is computable from the verified host
artifact and the Phase 107 contract — every file has a known destination URL, and
the exact upload/verify commands are known — all with zero network activity.

It does **not** prove: that the repo is reachable on the internet, because
nothing was uploaded. That final step is intentionally left to a future,
explicitly-confirmed upload phase (sketched as `make phase 109`), kept separate
from every build, export, verify, and preview step in Phase 1.

## Where Phase 1 leaves us

With step 108 green, the Phase 1 gate is met: the `onix` repo carries a
self-consistent base stone set (`onix-branding` + `onix-filesystem`), moss can
install it by name into a fresh root, and that repo has been shaped, exported,
verified, and rehearsed for publication — without a single unsafe side effect.
What is deliberately still missing is a *running* system: nothing here boots.
Building the first bootable, moss-managed, atomic musl ONIX image — kernel,
initrd, systemd-on-musl, and BLS boot entries — is the work of Phase 2.
