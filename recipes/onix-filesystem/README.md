# onix-filesystem

Filesystem layout policy for ONIX.

This package intentionally ships policy/defaults under `/usr`, not live mutable
root directories.

It installs:

- `/usr/share/onix/filesystem-layout.md`
- `/usr/share/defaults/etc/fstab`
- `/usr/share/defaults/etc/profile.d/onix-path.sh`

Why no direct `/etc/fstab`?

Boulder/Moss package payloads are `/usr`-centric in this layout. Live `/etc`
state is created by image assembly or boot/install glue from defaults under:

```text
/usr/share/defaults/etc/
```
