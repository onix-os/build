# Introduction

ONIX is an experiment in building a small, atomic, musl-based Linux
distribution with:

- **Moss** as the package/state manager
- **Boulder** as the `.stone` package builder
- **systemd** as PID 1, if the musl path keeps working
- **systemd-boot** as the bootloader for the real ONIX image
- **Nix** as the development toolbox, not as the target package manager

This book is the canonical learning document for the repository.

The root `README.md` stays short on purpose. The detailed explanations live
here, because each build step now needs room for:

- what the step does
- why it exists
- what files it reads and writes
- what host/guest boundary it crosses
- what it proves
- what it intentionally does **not** prove yet

## The most important mental model

We are not installing a distro by running one magic installer.

We are building it layer by layer:

```text
temporary forge VM
  -> package tools
  -> first packages
  -> package repo
  -> root tree
  -> disk image
  -> bootloader
  -> kernel/initramfs
  -> init system
  -> booting ONIX machine
```

Every phase is a small proof. When one phase succeeds, the next phase is allowed
to depend on that proof.

## Branding rule

The project name is written as:

```text
ONIX
onix
```

Do not use mixed-case spelling.
