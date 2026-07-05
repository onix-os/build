# onix-branding

First real ONIX stone.

It installs:

- `/usr/lib/os-info.json`
- `/usr/share/defaults/etc/issue`
- `/usr/share/defaults/etc/motd`

Moss reads `/usr/lib/os-info.json` and generates `/usr/lib/os-release` during
install. If `os-info.json` is missing, Moss intentionally generates an
"Unbranded OS" fallback.

This package is intentionally source-less: Boulder can build a package that only
materializes static files in the `install` step.

It intentionally does not ship `/etc/os-release`: Boulder ignores non-`/usr`
payload in this layout. Later image assembly should create:

```text
/etc/os-release -> ../usr/lib/os-release
```
