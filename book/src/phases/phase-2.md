# Phase 2 overview — first bootable ONIX image

Phase 2 takes the ONIX package repo artifact from Phase 1 and starts turning it
into a bootable disk image.

Phase 2 is a boot proof, not the final kernel ownership story. It intentionally
uses the Alpine forge's virt kernel/initramfs/module payload so we can prove the
image layout and systemd-on-musl userspace before spending a full phase on
kernel building.

The Phase 2 learning arc is:

```text
exported package repo
  -> host-side moss
  -> root tree
  -> disk image
  -> systemd-boot skeleton
  -> kernel/initramfs payload
  -> first musl systemd userspace payload
  -> first kernel module/kmod payload
  -> first QEMU boot probe
```

The borrowed payload boundary is explicit:

```text
Phase 2: boot with borrowed Alpine kernel payload
Phase 3: later replace that with ONIX-owned kernel/initramfs/modules
Phase 4: continue now with booted ONIX base userspace
```

## About `make phase 2`

`make phase 2` runs the canonical host-native Phase 2 path:

```text
200 -> 202 -> 203 -> 204 -> 205 -> 206 -> 207 -> 208 -> 209 -> 210 -> 211 -> 213 -> 214 -> 212
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
- [213 — first musl systemd userspace payload](./213.md)
- [214 — first kernel module/kmod payload](./214.md)

Running:

```sh
make phase 2
```

runs the canonical host-native Phase 2 path.

After this passes, the immediate next implementation lane is Phase 4:

```sh
make phase 400
```

Phase 3 is reserved for later kernel ownership work:

```sh
make phase 300
```
