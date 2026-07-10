# Phase 100 — forge readiness

## At a glance

| Field | Value |
|---|---|
| Phase family | Phase 1 — first stones |
| Run command | `make phase 100` |
| Underlying make target/script | `vm/phase1 ready target` |
| Runs on | guest over SSH |
| Main proof/artifact | Confirms the forge has working moss and boulder before real recipe work. |


Checks that the running forge is reachable and that these tools exist inside it:

- `moss`
- `boulder`

If this fails, Phase 0 is not ready. Run:

```sh
make phase 003
make phase 004
```

## Why this step exists

Every later Phase 1 step assumes two things are true: the forge VM is *up and
reachable over SSH*, and the two AerynOS tools are *installed and runnable inside
it*. If either assumption is false, a step like 101 would fail deep inside a
build with a confusing error. Step 100 is a cheap pre-flight check that fails
early and points you at the exact fix.

It is the Phase 1 equivalent of a smoke alarm: it proves nothing about ONIX
itself, but it proves the workshop is open before you carry in the materials.

## What it actually runs

The `ready` make target opens one SSH session into the forge and runs a short
command:

```sh
export PATH="$HOME/.local/bin:$PATH"
command -v moss;    moss --version
command -v boulder; boulder --version
```

Two details matter here:

- **`PATH` is extended to include `$HOME/.local/bin`.** Phase 0's provisioning
  step (`make phase 004`) builds moss and boulder from the pinned `os-tools`
  Rust sources and installs the resulting binaries under the build user's
  `~/.local/bin`, not a system directory. A fresh non-login shell would not have
  that on `PATH`, so the check adds it explicitly — exactly as every real Phase 1
  build script does.
- **`command -v` plus `--version`** proves two separate things: that the binary
  is *found* on `PATH`, and that it actually *executes* (a broken or
  wrong-architecture binary would be found but fail to run). Printing the version
  also records, in the build log, precisely which moss/boulder you built against.

The build user defaults to `mason` (the `BUILD_USER` in the Phase 0 config). SSH
into the guest is handled by the shared `vm/phase0/ssh.sh` helper that every
Phase 1 script reuses.

## Reading the result

A healthy run prints the path and version of each tool, for example a line from
`command -v` followed by a `moss x.y.z` / `boulder x.y.z` banner. If instead you
see:

```text
moss: command not found
```

the forge booted but was never provisioned — the tools do not exist yet. If the
SSH connection itself times out or is refused, the VM is not running. The
remedy is the same in both cases and is printed on the page:

```sh
make phase 003   # boot the forge VM
make phase 004   # build + install moss and boulder inside it
```

## What it proves vs what it does not

It proves the **environment** is ready: VM reachable, `moss` and `boulder`
present and executable. It deliberately proves **nothing about ONIX packaging**
— no recipe is built, no repo is created, no file is installed. Those begin in
step 101. Think of step 100 as asserting the preconditions for the rest of the
phase so that any later failure is unambiguously about ONIX, not about a missing
tool.
