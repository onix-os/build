# 502 — runtime-clean stone payload audit helper

Run:

```sh
make phase 502
```

Phase 502 adds the first enforcement tool for the Phase 5 package law.

The helper is:

```text
vm/phase5/audit-stone-payload.sh
```

It audits a prepared package payload directory before ONIX accepts that payload
as a canonical system package.

## Why this phase exists

Phase 500 defined the law:

```text
Rust-first, musl-only, and runtime-clean.
```

Phase 501 defined where packages live:

```text
packages/
```

Phase 502 starts enforcing the runtime-clean part.

Without an audit helper, package policy stays as prose. Prose is easy to forget.

The helper turns part of the policy into a repeatable command.

### Why audit the payload directory, not the finished `.stone`

The audit deliberately runs on the *install root* — the plain directory tree boulder
produces — rather than on the compressed `.stone` file. That is the last moment the
files are lying around as ordinary files you can `grep`, `file`, and `readelf`
directly, before they are packed into an archive. Checking here means the helper needs
no knowledge of the `.stone` format and no unpack step; it is just filesystem tools
pointed at a directory. (Later phases will unpack real stones with `moss extract` and
re-run the same idea, but the core check is simplest at the payload stage.)

The mindset is a customs checkpoint: nothing enters the canonical package set without
its payload being inspected first. The law from Phase 500 said "these are the bad
signs"; Phase 502 is the officer who actually looks.

## What is a payload directory?

Boulder recipes install files into an install root.

Before that install root becomes a `.stone`, it is just a directory tree.

Example:

```text
payload/
  usr/
    bin/
      foo
    share/
      onix/
        packages/
          foo.md
```

That directory is the package payload.

The audit helper checks that tree.

## Basic use

```sh
vm/phase5/audit-stone-payload.sh path/to/payload
```

Default mode is strict:

```text
static/static-PIE musl by default
no runtime /nix/store
no glibc loader
no unexpected shared libraries
documented ONIX-owned shared surface only when explicitly allowed
```

## Self-test

Phase 502 includes a self-test:

```sh
vm/phase5/audit-stone-payload.sh --self-test
```

The self-test creates two temporary payloads:

```text
clean payload -> should pass
bad payload with /nix/store shebang -> should fail
```

This proves the helper can catch the most important class of mistake before we
point it at real packages.

The self-test matters more than it looks. An audit tool that silently *passes
everything* is worse than no tool — it gives false confidence. So the helper proves
itself on two fixtures it constructs in a temp directory: a clean payload (a `#!/bin/sh`
script plus a well-formed `hello.service`) that must pass, and a deliberately poisoned
payload (a script whose shebang is `#!/nix/store/bad/bin/bash`) that must fail. If the
bad fixture ever passes, the self-test aborts. In short: *test the smoke detector by
holding a match to it.* `make phase 502` runs this self-test every time, so a
regression in the checker is caught before the checker is trusted.

## What the helper checks

### `/nix/store` references

The helper scans the payload for:

```text
/nix/store
```

That catches:

- copied Nix wrapper scripts,
- Nix shebangs,
- Nix paths embedded in text files,
- Nix paths embedded in binaries,
- systemd units calling Nix paths.

This matters because ONIX allows Nix as a bootstrap builder, not as the runtime
owner of system packages.

## Shebangs

Bad:

```sh
#!/nix/store/.../bin/bash
```

Good:

```sh
#!/bin/sh
```

or, better for system tools, no script wrapper at all.

The audit helper reports Nix shebangs explicitly.

## Systemd units

Service packages are risky because unit files can quietly call host or Nix paths.

Bad:

```ini
ExecStart=/nix/store/.../bin/foo
```

Good:

```ini
ExecStart=/usr/bin/foo
```

The helper scans common systemd unit file types:

```text
*.service
*.socket
*.timer
*.mount
*.path
```

## ELF interpreter checks

ELF executables may declare a runtime interpreter.

Bad:

```text
/lib64/ld-linux-x86-64.so.2
```

That is the glibc loader.

Bad:

```text
/nix/store/.../ld-musl-x86_64.so.1
```

That means the binary still depends on the build environment.

Acceptable:

```text
/lib/ld-musl-x86_64.so.1
```

But for core packages, static or static-pie musl must be tried first by default.

## Dynamic dependency checks

By default, the helper rejects ELF files with `NEEDED` dynamic library entries.

Why?

Because the ONIX system package rule is intentionally strict:

```text
no shared runtime dependency surprises
minimal package-owned shared surface by exception
```

If a package genuinely needs dynamic musl linkage, use:

```sh
vm/phase5/audit-stone-payload.sh --allow-dynamic-musl path/to/payload
```

That should be a documented exception in `PACKAGE.md`: list each soname, why it
is needed, and which ONIX stone owns it.

Default acceptance should remain static/static-PIE.

Why reject dynamic linkage *by default* rather than warn about it? Because a `NEEDED`
entry is exactly where surprises hide. A dynamically linked binary works on the build
host — where its shared libraries happen to be present — and then fails or, worse,
silently loads the *wrong* library on the installed system. Making the default answer
"no" means every shared-library dependency has to be a conscious, written decision
(`--allow-dynamic-musl` plus an `Exceptions` note in the contract), not an accident
nobody noticed. The exception is allowed only for a minimal ONIX-owned surface, not
for random host libraries. This is the same reasoning that made `onix-systemd`
carry an explicit documented exception rather than quietly slipping its shared
libraries past the gate.

## RPATH and RUNPATH

Bad:

```text
RPATH=/nix/store/...
RUNPATH=/nix/store/...
```

Those make the runtime loader search the Nix store.

The helper rejects Nix RPATH/RUNPATH entries.

## What Phase 502 does not check yet

Phase 502 is the first audit helper, not the final package QA system.

It does not yet:

- unpack `.stone` files automatically,
- inspect Moss metadata,
- verify package dependency declarations,
- prove license correctness,
- verify upstream source reproducibility,
- compare package files against `PACKAGE.md`.

Those can come later.

Phase 502 gives us the first hard gate before copying real package recipes into
the canonical layout.

## How the helper reports

The script does not stop at the first problem. It walks the whole payload, counts
every issue it finds (`failures`), and only at the end decides pass or fail. That is
deliberate: when you are fixing a package you want the *full* list of leaks in one
run, not a whack-a-mole where each fix reveals the next error. Alongside the failure
count it tracks three numbers it prints in the summary:

```text
files scanned : every regular file it looked at
ELF files     : how many of those were actual binaries
dynamic ELF   : how many binaries carried NEEDED entries
```

Reading a failure is a matter of matching the error line to the check that produced
it — `Nix shebang:` came from the script scan, `glibc ELF interpreter:` from the
`readelf -l` loader check, `Nix RPATH/RUNPATH in ...` from the `readelf -d` dynamic
scan, and `dynamic shared-library dependency in strict mode:` from the `NEEDED`
count. Each names the exact offending file, so the fix is usually "rebuild that one
binary static", "document and package-own the minimal shared surface", or "stop
shipping that wrapper script."

## Expected output

Successful self-test output includes:

```text
==> self-test : clean payload should pass
==> self-test : bad payload should fail
==> self-test : OK
```

Successful real payload output includes:

```text
==> success
payload audit passed

Summary:
  files scanned : ...
  ELF files     : ...
  dynamic ELF   : ...
  /nix/store    : none
```

## What comes next

After Phase 502, ONIX can start copying real recipes into:

```text
packages/
```

The next likely step is:

```text
503 — copy existing package recipes into canonical layout
```

When a builder starts consuming a copied recipe, its payload should pass the
Phase 502 audit before we treat it as canonical.
