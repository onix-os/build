# 517 — fish shell stone

This step builds fish as an ONIX system package.

## Source

The source comes from the pinned `nixpkgs_2` input already used by ONIX. The
build script asks that pinned tree for `fish.src`, archives the source, and
sends that archive into the Alpine/musl forge.

This is still compatible with ONIX package policy:

- nix is only a source acquisition helper here.
- The build happens inside the musl forge.
- The installed runtime files come from a `.stone`.
- The final payload is audited for `/nix/store` leakage.

## Build model

fish 4.x is a Rust program. The Phase 517 build uses Cargo in the forge and
tries a static musl build first:

```text
RUSTFLAGS="-C target-feature=+crt-static"
PCRE2_SYS_STATIC=1
cargo rustc --release --locked --bin fish --no-default-features \
  --features embed-manpages -- -C target-feature=+crt-static
```

The builder repeats that `cargo rustc` command for `fish_indent` and
`fish_key_reader`, because Cargo only allows extra final `rustc` flags for one
binary target at a time.

fish still needs some shell-world data files, such as functions and
completions. The stone therefore owns both:

```text
/usr/bin/fish
/usr/bin/fish_indent
/usr/bin/fish_key_reader
/usr/share/fish/...
/usr/share/onix/defaults/etc/fish/conf.d/branding.fish
/usr/share/onix/packages/fish.md
/usr/share/onix/shells/fish-policy.txt
```

## ONIX-branded fish greeting

fish does not read POSIX `/etc/profile` or `/etc/profile.d/*.sh`. That means the
normal shell login banner used by BusyBox `sh` would not run for fish users.

Phase 517 fixes that inside the fish package by installing:

```text
/usr/share/onix/defaults/etc/fish/conf.d/branding.fish
```

Phase 518 materializes that package-owned default into:

```text
/etc/fish/conf.d/branding.fish
```

That file sets fish's global `fish_greeting` variable. fish's built-in greeting
function then prints the ONIX value instead of creating the default
"Welcome to fish" text. If the `branding` stone is installed, fish prints:

```text
/usr/share/onix/branding/logo.ansi
```

If the branding asset is missing in a scratch install target, fish still has a
small colored `ONIX` fallback. The hook respects:

```text
ONIX_LOGIN_BANNER=0
ONIX_LOGIN_BANNER_SHOWN=1
TERM=dumb
```

So scripts and nested shells can avoid repeated banners.

## Why the stone includes notes

The files under `/usr/share/onix/...` are small proof notes. They make the image
self-explaining. When you SSH into the machine later, you can inspect why fish is
there and what policy it is meant to satisfy.

## What `make phase 517` proves

Phase 517 proves the package before touching the boot image:

1. build the fish payload in the forge;
2. cut the `fish` `.stone` with Boulder;
3. inspect the stone with Moss;
4. install it into a scratch root with Moss;
5. run `/usr/bin/fish --version`;
6. run a tiny fish command;
7. prove the ONIX fish branding hook is packaged;
8. audit the payload for runtime cleanliness;
9. refresh the local ONIX repository index.

Only after that does Phase 518 install the package into the boot image.
