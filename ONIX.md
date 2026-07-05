# ONIX — Architecture & Build Plan

**An atomic, moss-managed machine with a persistent Nix toolbox — built from scratch on musl.**
ONIX is the hard machine layer everything else sits on. The moss-managed machine plane is the foundation; the Nix toolbox is the living soil on top. It borrows AerynOS's *tooling* (moss, boulder, the `.stone` format) and its naming world — you're extending the geology, not breaking it.

**Core rule:** *moss controls the machine. Nix controls the toolbox.*

> **Direction change (2026-07).** ONIX does **not** consume AerynOS's ISO or its glibc package repos. Their live image is desktop-first (GNOME) and their whole `volatile` repo is glibc; neither fits. ONIX keeps only the *tooling* — **moss** (atomic package/state manager) and **boulder** (the `.stone` builder) — and bootstraps its **own smallest-possible base on musl, from scratch**. **Alpine** is the throwaway *forge*: a tiny musl host where moss+boulder are built and the first stones are cut. The endgame is our own musl distro, managed by moss, with Nix supplying the (glibc) software long tail on top.

> Naming note: this project was renamed from Bedrock to **ONIX** to avoid colliding with the existing Bedrock Linux project. Public branding is always `ONIX`; machine IDs and package names use `onix`.

---

## 0. Identity & naming conventions

Locked in up front so every later artifact is consistent.

| Thing | Name | Notes |
|---|---|---|
| Distro name | `ONIX` | Pretty name |
| Machine-readable ID | `onix` | Lowercase everywhere machine-readable |
| C library | **musl** | Non-negotiable; the whole base is musl. Nix apps bring their own glibc (see §3) |
| Magic number | `6649` | "ONIX" on a phone keypad — nixbld GID, VM MAC suffix, port offsets |
| Git org | `onix-os` | Repos: `image`, `recipes` (musl `.stone` recipes), `nix-integration`, `docs` (check org availability; fallback `onixos`) |
| Package namespace | `onix-*` | All custom .stone packages: `onix-base`, `onix-nix-integration`, `onix-cli`, `onix-branding`, `onix-desktop` |
| Moss repo | `onix` | `moss repo add onix <url>` — the **only** repo; there is no upstream repo beneath it |
| Upstream tooling | `os-tools` | `github.com/AerynOS/os-tools` — moss + boulder, pinned. The one external dependency |
| CLI wrapper | `onix` | Thin wrapper over moss + nix (see §6). `onix update`, `onix rollback`, `onix status` |
| Boot entry token | `onix` | BLS Type #1 entries: `onix-<txid>.conf` |
| Volume labels | `ONIX-ESP`, `ONIX-BOOT`, `onix-root`, `ONIX-PERSIST` | |
| Forge | Alpine musl VM, hostname `quarry` | Throwaway bootstrap host — builds moss+boulder and the first stones. |

**/usr/lib/os-release** (shipped by `onix-branding`):

```ini
NAME="ONIX"
ID=onix
PRETTY_NAME="ONIX (atomic musl base + Nix toolbox)"
VERSION_ID=rolling
BUILD_ID=<txid injected at image build>
HOME_URL="https://github.com/onix-os"
ANSI_COLOR="38;2;140;120;100"
```

No `ID_LIKE`: ONIX is not a downstream of any distro's package set — it shares AerynOS's *tooling*, not its packages, and its libc (musl) diverges from AerynOS (glibc). It stands on its own foundation.

---

## 1. Architecture overview

Two planes with a hard ownership contract:

```
┌─────────────────────────────────────────────────────────┐
│  USER TOOLBOX PLANE (persistent, user-driven)           │
│  /nix  ·  nix-daemon  ·  per-user profiles              │
│  nix shell / develop / profile · home-manager (opt)     │
│  GUI leaf apps, dev environments, the long tail         │
│  (nixpkgs is glibc — apps are self-contained, run on    │
│   the musl base because they carry their own libc)      │
├─────────────────────────────────────────────────────────┤
│  INTEGRATION SEAM (owned by onix-* stone packages)      │
│  /etc/nix/nix.conf · nixbld sysusers · nix-daemon unit  │
│  /run/opengl-driver · XDG/fontconfig/locale glue        │
├─────────────────────────────────────────────────────────┤
│  MACHINE PLANE (moss-owned, transactional, atomic)      │
│  MUSL base · /usr (stateless, renameat2-swapped)        │
│  /.moss store · kernel + initrd + BLS entries (blsforme)│
│  init, udev, Mesa/DRM, PipeWire, portals, compositor    │
│  — all built from our own musl .stone recipes           │
└─────────────────────────────────────────────────────────┘
```

### Ownership contract (the constitution)

| Surface | Owner | Never touched by |
|---|---|---|
| `/usr`, kernel, initrd, boot entries | moss | Nix |
| `/.moss` content store & fstx history | moss | Nix |
| Mesa/libdrm/firmware, compositor, D-Bus, PipeWire, portals | moss (base packages, musl-built) | Nix (system-wide) |
| `/etc` baseline defaults | moss via `/usr/share/defaults` | Nix |
| `/etc/nix/*` | `onix-nix-integration` stone seeds it; nix daemon reads it | manual drift |
| `/nix`, `/nix/store`, `/nix/var` | Nix | moss |
| Per-user profiles, dev shells, user services | Nix | moss |
| setuid/setcap binaries, kernel modules | moss only | Nix — hard rule |

The single most important consequence: **a moss rollback and a Nix profile rollback are independent operations that must never corrupt each other.** Phase 4 validation exists specifically to prove this.

---

## 2. Bootstrapping the machine plane

This is the section the pivot rewrote most. There is no upstream to consume — the base is built from zero on musl, with boulder.

### 2.1 The forge (Alpine musl bootstrap host)

You cannot build `.stone` packages without moss + boulder, and you can't run them meaningfully without a musl host to build *in*. Alpine is that host:

1. **Build a minimal Alpine/musl VM from scratch** — from the 3.7 MB minirootfs tarball, not their ISO — into a bootable disk (`vm/` in this repo already does this). Hostname `quarry`.
2. **Build moss + boulder** from `github.com/AerynOS/os-tools` (`just get-started`). They're ordinary Rust binaries; they build and run on musl. boulder explicitly supports non-AerynOS hosts (`--data-dir`, `--config-dir`, `--moss-root`).
3. Alpine is **scaffolding, thrown away.** Nothing Alpine ships (apk, its kernel, its packages) ends up in ONIX. The forge only provides a musl toolchain + userns to run boulder.

### 2.2 Bootstrap the musl base as `.stone` packages

No AerynOS recipe is musl — a musl base is a **genuine bootstrap**, and that is the point of the project.

1. **Author `.stone` recipes** (`stone.yaml`) for the core musl userland: musl, a compiler toolchain, the base command set, the handful of packages `onix-base` needs. Use Alpine's `APKBUILD`s as a reference for the musl-specific patches; keep the base set *short* — the long tail is Nix's job (§3).
   - **Coreutils strategy (Rust-first, matches the moss/boulder ethos):** ship **busybox** as the working base first — it's what boots the forge today and is the reliable fallback. Then bring in [**uutils/coreutils**](https://github.com/uutils/coreutils) (Rust) alongside it. Once uutils is proven, the plain tool names (`ls`, `cp`, …) resolve to **uutils**, and busybox stays *reachable but not default* — invoked as `busybox <tool>`, not removed. Sequenced for Phase 1, after the forge builds stones.
2. boulder supports bootstrapping explicitly: a shared control file can disable tests during initial rounds, then be removed for final builds with tests re-enabled.
3. **Stand up the `onix` moss repo** — a static, locally-served index of your boulder-built stones. Start as `file:///var/lib/onix/repo/` on the forge; graduate to static HTTPS (any dumb file server; no vessel needed at this scale). It is the *only* repo — nothing sits beneath it.
4. **Pin `os-tools`.** The one external dependency is the tooling. The forge records this as `OS_TOOLS_REF` in `vm/phase0/config.sh`; an `onix mirror` habit later hedges against upstream churn.

### 2.3 Image building

Assemble a bootable image from the musl base stones (an `onix-os/image` repo):

- moss-install `onix-base` + `onix-branding` (os-release above) into a fresh root: kernel, initrd tooling, init, udev, dbus, a network stack, busybox/coreutils, filesystem tools (xfsprogs, dosfstools), moss itself.
- Keep a QEMU/OVMF smoke-test — that's CI from day one (the `vm/` harness generalizes to boot the built image).
- Every image build records: `os-tools` commit, `onix` repo commit, resulting fstx ID. That triple is the reproducible build pin for a rolling personal distro.

### 2.4 Boot artifacts

Target **BLS Type #1 entries** exactly as moss/blsforme do: entries named `onix-<txid>.conf`, kernel+initrd promoted to `$BOOT` (XBOOTLDR), transaction ID on the kernel cmdline, old entries pruned by moss. blsforme is a bootloader-spec tool and does not itself require systemd as PID 1 — but the surrounding glue (sysusers/tmpfiles) is systemd-flavored, which forces the **init decision** below. UKI + Secure Boot is Phase 7+ future work.

> **The open architectural question — init on musl.** The preferred ONIX target is **systemd as PID 1** plus **systemd-boot/BLS** rather than GRUB, because moss/Nix integration already speaks the systemd vocabulary (`sysusers.d`, `tmpfiles.d`, `nix-daemon.service`). The hard part is that upstream systemd does not support musl. Two paths, decided by Phase 2:
> - **(a) preferred: systemd-on-musl + systemd-boot** — carry a musl patchset (as Adélie/others do). Keeps every AerynOS/NixOS assumption intact; ongoing maintenance cost.
> - **(b) fallback: non-systemd** (OpenRC / dinit / s6) — musl-native and small, but you reimplement the *small* integration surface: sysusers→a boot script, tmpfiles→an alternative, unit files→native service files. blsforme boot entries still work.
> The Phase 0 Alpine forge can keep OpenRC + GRUB as throwaway scaffolding; this preference applies to the real ONIX image.

---

## 3. The Nix plane and the integration seam

### 3.1 Do not run the Nix installer

Neither the official curl installer nor the Determinate installer fits a stateless-`/usr` system: they mutate `/etc`, drop init units imperatively, and `useradd`. That's exactly the drift ONIX exists to avoid. (They also assume glibc/systemd — doubly wrong here.)

Instead, the linchpin deliverable is one package:

### 3.2 `onix-nix-integration` (.stone)

Ships everything Nix needs, declaratively, through the machine plane:

| Component | Path | Content |
|---|---|---|
| Nix binaries | via `/nix` | One-time seed `/nix` from a Nix release; Nix then upgrades itself. The stone ships *integration*, not Nix — keeps moss out of tracking Nix releases. Default profile `bin` on PATH. |
| Build users | `sysusers.d` (or boot-script equiv. under init-(b)) | `g nixbld 6649` + `u nixbld1..32 -:nixbld` (GID 6649 — "ONIX"). Materialized every boot; survives an ephemeral-/etc future. |
| Daemon unit | `nix-daemon.service` + `.socket` (or native service) | Ordering hardened: after `/nix` mount, `ConditionPathIsDirectory=/nix/store`. |
| Mount unit | `nix.mount` | Or generated from fstab — see §4. |
| Runtime dirs | `tmpfiles.d` (or equiv.) | `/nix/var/nix/daemon-socket`, gcroots dirs, `profiles/per-user`. |
| System config | `/usr/share/defaults/nix/nix.conf` → `/etc/nix/nix.conf` overrides | `build-users-group = nixbld`, `sandbox = true`, `auto-optimise-store = true`, `allowed-users = @users`, `trusted-users = root`, `experimental-features = nix-command flakes`. |
| Shell hooks | `/usr/share/defaults/etc/profile.d/onix-nix.sh` | PATH, `NIX_REMOTE=daemon` fallback, `XDG_DATA_DIRS`, `LOCALE_ARCHIVE` guard, fontconfig include. |

### 3.3 Graphics: `/run/opengl-driver` as a first-class feature

The classic failure mode of Nix GUI apps on foreign distros: they load nixpkgs' Mesa, which mismatches the host kernel/DRM stack → llvmpipe or crashes. **ONIX fixes this at the machine layer** — the distro's genuinely distinguishing feature:

- `onix-opengl-driver` glue in `onix-nix-integration` populates `/run/opengl-driver/lib` at boot with symlinks into the **moss-managed** Mesa/libdrm/Vulkan ICDs under `/usr`.
- Nixpkgs apps honor the NixOS `/run/opengl-driver` convention, so they pick up host-matched userspace drivers with zero per-app wrapping.
- Because the symlink farm is rebuilt each boot from active `/usr` state, **a moss rollback of the graphics stack re-coheres the Nix GUI world on next boot.** No nixGL, no per-app hacks.
- Same glue handles `/run/opengl-driver/share/vulkan/icd.d` and EGL vendor files.

**musl-specific caveat (bigger than the original glibc-skew note).** Our base Mesa is **musl-built**; nixpkgs GL apps are **glibc**. Nix apps carry their own glibc and most libraries from the store, so they *run* on a musl base — but the `/run/opengl-driver` seam is exactly where a musl-built Mesa meets a glibc GL app, and that boundary can break (symbol/ABI mismatch). Mitigation to carry forward: the opengl-driver bridge may need to expose a **glibc-built Mesa variant** for the Nix world (built as its own stone, or pulled from nixpkgs), rather than symlinking the musl base Mesa directly. Resolve in Phase 6; keep it in mind from Phase 3.

### 3.4 Optional: home-manager standalone

Fine from Phase 4 onward, standalone mode only — manages `~/.config` and user services, never system state. Composes cleanly with the contract. Personal preference, not architecture.

---

## 4. Filesystem layout & persistence

### 4.1 Partitions (VM prototype; same shape on hardware)

| Partition | FS | Size (VM) | Label | Mount |
|---|---|---|---|---|
| ESP | FAT32 | 512 MiB | `ONIX-ESP` | `/efi` |
| XBOOTLDR | FAT32 | 2 GiB | `ONIX-BOOT` | `/boot` |
| Root | **XFS** | 40 GiB+ | `onix-root` | `/` (holds `/.moss`; bigger = more rollback states) |
| Persist | XFS or ext4 | rest | `ONIX-PERSIST` | `/persist` |

- `/nix` = bind mount from `/persist/nix` (mount unit ordered before local-fs, nix-daemon after it as in §3.2). One persistence surface to snapshot/back up.
- `/home` = bind from `/persist/home`.

(The **forge** disk is simpler — a plain GPT ESP + ext4 root; the table above is the *ONIX* image target.)

### 4.2 Persistence policy — Phase-appropriate

**Phases 2–6: fully persistent `/etc` and `/var`.** The `/usr/share/defaults` + `/etc`-overrides model bounds drift; ephemeral overlays add early-boot ordering complexity for marginal gain now. Add drift *visibility* instead: `onix status` diffs `/etc` against shipped defaults and reports every override.

**Phase 7 (optional, post-daily-driver):** ephemeral `/etc`+`/var` overlays with an explicit allowlist. Must-persist set, documented now:

`/etc/machine-id` · `/etc/ssh/ssh_host_*` · `/etc/nix/` · init/service state (`/var/lib/…`) · NetworkManager/bluetooth state · `/var/log` (your choice) · `/home` · `/nix` · `/.moss`

---

## 5. Phased roadmap

Each phase has an exit gate. Don't advance until the gate passes — the gates are the real deliverable.

### Phase 0 — The forge (musl tooling host)  ← current
Build a minimal Alpine/musl VM from the minirootfs (this repo's `vm/`). Build **moss + boulder** from `os-tools`. Cut a trivial first `.stone` with boulder; install/remove it with moss into a test root; inspect `moss state list`.
**Gate:** moss + boulder run on musl; you can boulder-build a hello-world `.stone`, moss-install it, roll the moss state back, and remove it — cleanly.

Current smoke-test command:

```sh
make doctor     # common health check
make phase 004  # once per fresh forge image: build moss + boulder
make phase 005  # build/check/extract/index/install/run onix-hello
make phase 006  # real moss state install/remove/rollback smoke test
```

Recipe gotcha learned in the forge: Boulder build directories inherit `g+s`.
If a recipe creates `/usr`/`/usr/bin` with the setgid bit still present, Boulder
treats those directories as special and emits a `/usr/` layout entry. Moss
currently rejects that path during extract/install. For simple recipes that
install directly into `/usr/bin`, clear setgid in `install`:

```yaml
install     : |
    install -Dm00755 my-tool %(installroot)%(bindir)/my-tool
    chmod g-s %(installroot)/usr %(installroot)%(bindir)
```

### Phase 1 — Bootstrap the musl base stones
Author `stone.yaml` recipes for the core musl userland (musl, toolchain, busybox/coreutils, essentials). Stand up the `onix` moss repo (`file://` then static HTTPS). Keep the base set short.
**Gate:** the `onix` repo carries a self-consistent base stone set; moss installs it into a fresh root that chroots and runs a shell + coreutils.

### Phase 2 — First bootable ONIX image
Decide **init** (§2.4: systemd-on-musl vs OpenRC/dinit/s6) and implement the minimal integration glue for it. Add a kernel stone + initrd tooling + blsforme BLS entries. Assemble and boot a moss-managed, atomic musl image in QEMU/OVMF.
**Gate:** `cat /etc/os-release` says ONIX (musl); `moss state list` shows transactions; break the system with an update and recover via boot menu + state activation, from memory, twice.

### Phase 3 — Nix plane (the critical phase)
Ship `onix-nix-integration`; seed `/persist/nix` from a Nix release tarball; verify daemon-mode multi-user builds, `nix shell`/`develop`/`profile install`. Confirm glibc nixpkgs apps run on the musl base.
**Gate — the composition matrix, all green:**

| Test | Expected |
|---|---|
| `nix profile install nixpkgs#ripgrep` → reboot | tool still on PATH, runs on musl base |
| Install Nix tool → **moss rollback** → reboot | machine state rolled back, Nix tool untouched |
| moss update → **nix profile rollback** | both planes at chosen generations, no interference |
| `moss state prune` + `nix store gc` back-to-back | no cross-corruption, both stores intact |
| Kill nix-daemon mid-build → restart | store consistent |

### Phase 4 — Recipe set & overlay matures
boulder workflow for the growing musl recipe set (`onix-cli`, base additions — keep short; the long tail is Nix). Static HTTPS hosting; `onix mirror` snapshot habit (mirror `os-tools` + your stones).
**Gate:** clean-room rebuild from the pinned snapshot triple (§2.3) boots identically.

### Phase 5 — Desktop
Pick one desktop (start minimal — a Wayland compositor). All of: compositor, Mesa, PipeWire + WirePlumber, xdg-desktop-portal backend, fonts — from the **machine plane** (musl-built). Enable the `/run/opengl-driver` glue.
**Gate:** a Nix-installed GL app renders hardware-accelerated with no wrapper (this is where the musl-Mesa vs glibc-app seam of §3.3 gets solved); portals work from a Nix app; `~/.nix-profile` desktop entries appear; then **roll back a Mesa update** and confirm the Nix app still renders on the previous stack after reboot.

### Phase 6 — Hardware
AMD/Intel graphics strongly preferred (NVIDIA complicates both musl and the `/run/opengl-driver` story). Dedicated drive — no same-disk dual boot at this maturity. Migrate `/persist` by restore-from-backup, not disk surgery.
**Gate:** two weeks of daily driving with at least one rollback drill and one restore-from-backup drill of `/persist`.

### Later / optional
Init decision revisited & musl recipes contributed upstream · UKI + Secure Boot · disk encryption (initrd unlock) · ephemeral `/etc` allowlist mode · `onix` from shell script to small Rust binary.

---

## 6. The `onix` CLI

Thin, honest wrapper — it must never hide which plane a command touches:

```
onix update      # moss sync + report pending reboot
onix rollback    # moss state activation to previous, prints boot instructions
onix status      # active fstx, boot entry, /etc drift vs defaults, nix-daemon health,
                 # /run/opengl-driver coherence check
onix gc          # moss state prune + nix store gc, sequenced, with guardrails
onix mirror      # snapshot os-tools + depended-on stones to /persist/mirror
onix doctor      # runs the Phase 3 composition matrix as an automated self-test
```

Ships as `onix-cli` from the `onix` repo. Start as ~200 lines of shell; rewrite in Rust when it stops being embarrassing to. (`onix solid` as an alias for a fully-green `onix doctor` run is optional but encouraged.)

---

## 7. Risks & maintenance posture

| Risk | Exposure | Mitigation |
|---|---|---|
| **From-scratch musl bootstrap is a large effort** | **High — this is the whole project now** | Phase gates; Alpine forge does the heavy lifting for the toolchain; keep the base *tiny* — Nix covers the long tail so the base recipe set stays small |
| **No musl `.stone` recipes exist upstream** | High | Author/port them, using Alpine `APKBUILD`s as the musl-patch reference; ruthless minimalism on the base set |
| **init on musl: systemd doesn't support musl** | High / structural | Preferred Phase 2 path is systemd-on-musl + systemd-boot/BLS; fallback is OpenRC/dinit/s6 with reimplemented sysusers/tmpfiles/unit glue. §2.4 |
| moss/boulder are alpha & glibc-tested | Medium | They're open Rust you can read/patch; pin `os-tools`; fix any glibc assumptions and upstream them |
| glibc skew: musl base Mesa vs glibc Nix apps | Medium, intermittent | Nix apps are self-contained so most run; concentrate the fix at the `/run/opengl-driver` seam — possibly a glibc Mesa variant for the Nix world (§3.3) |
| Old-name drift after rename | Medium during early development | Keep public names as ONIX; grep for stale Bedrock references when changing docs/scripts |
| NVIDIA | High if chosen | Don't. AMD/Intel for this project |
| Solo-maintainer burden | Real, and higher than a derivative would be | Budget honestly; keep base scope minimal; if it trends high, cut base scope and lean harder on Nix |
| **Data loss** | **Transactional /usr protects nothing you care about** | `/persist` (= `/home` + `/nix` + configs) gets real backups — borg/restic to external target — from Phase 3, not Phase 6. moss rollback is not a backup |

---

## 8. What ONIX is, in one paragraph

A small, auditable, atomic base you build yourself on **musl** — using AerynOS's excellent tooling (moss + boulder) but none of its packages — that you can always roll back; a huge optional software universe on top through persistent multi-user Nix (glibc apps riding on a musl base, carrying their own libc); and a machine-layer `/run/opengl-driver` bridge that makes Nix GUI apps first-class in a way almost no foreign distro manages. Alpine is the forge where the tooling is built and the first stones are cut, then discarded. The machine plane is the foundation; everything you actually live in grows on top of it — and the ground never shifts under you without your say-so. The machine manager controls the machine. Nix controls the toolbox.
