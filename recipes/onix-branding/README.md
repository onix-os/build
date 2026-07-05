# onix-branding

First real ONIX stone.

It installs:

- `/usr/lib/os-info.json`
- `/usr/share/onix/branding/logo.txt`
- `/usr/share/onix/branding/logo.ansi`
- `/usr/share/defaults/etc/issue`
- `/usr/share/defaults/etc/motd`

Moss reads `/usr/lib/os-info.json` and generates `/usr/lib/os-release` during
install. If `os-info.json` is missing, Moss intentionally generates an
"Unbranded OS" fallback.

This package is intentionally source-less: Boulder can build a package that only
materializes static files in the `install` step.

The terminal logo is embedded in `stone.yaml` for now. Boulder does not expose
files beside a source-less recipe inside the build container, so embedding keeps
the branding stone reproducible without inventing a separate generated recipe
step.

It intentionally does not ship `/etc/os-release`: Boulder ignores non-`/usr`
payload in this layout. Later image assembly should create:

```text
/etc/os-release -> ../usr/lib/os-release
```
