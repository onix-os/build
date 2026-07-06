# Phase 2 overview — first bootable ONIX image

Phase 2 takes the ONIX package repo artifact from Phase 1 and starts turning it
into a bootable disk image.

The Phase 2 learning arc is:

```text
exported package repo
  -> host-side moss
  -> root tree
  -> disk image
  -> systemd-boot skeleton
  -> kernel/initramfs payload
  -> first QEMU boot probe
```

## About `make phase 2`

`make phase 2` runs the canonical host-native Phase 2 path:

```text
200 -> 202 -> 203 -> 204 -> 205 -> 206 -> 207 -> 208 -> 209 -> 210 -> 211 -> 212
```

It intentionally skips Phase 201 because Phase 201 is the older bridge step
that uses the forge VM over SSH. Phase 203 is the normal host-native root-tree
assembly path.

## Steps

- [200 — image assembly readiness](./200.md)
- [201 — assemble the first ONIX root tree](./201.md)
- [202 — build host-side Moss](./202.md)
- [203 — assemble the root tree with host-side Moss only](./203.md)
- [204 — define image/disk assembly contract](./204.md)
- [205 — create first non-booting disk/root skeleton](./205.md)
- [206 — install the systemd-boot/BLS skeleton](./206.md)
- [207 — kernel + initramfs contract](./207.md)
- [208 — systemd userspace contract](./208.md)
- [209 — systemd-on-musl feasibility gate](./209.md)
- [210 — init path decision contract](./210.md)
- [211 — first kernel + initramfs payload](./211.md)
- [212 — first QEMU boot probe](./212.md)

Running:

```sh
make phase 2
```

runs the canonical host-native Phase 2 path.
