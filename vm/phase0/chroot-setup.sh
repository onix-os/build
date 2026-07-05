#!/bin/sh
# vm/phase0/chroot-setup.sh — runs INSIDE the target rootfs (busybox ash) via chroot.
# build-disk.sh copies this in, writes /root/onix.env with the injected
# values, then runs:  chroot "$MNT" /bin/sh -e /root/chroot-setup.sh
#
# Turns a bare Alpine minirootfs into a bootable, SSH-able musl forge with the
# full toolchain needed to build AerynOS os-tools (moss + boulder).
set -e
. /root/onix.env

echo ">> apk: base system + kernel + bootloader + toolchain"
apk update
apk add --no-cache \
    alpine-base linux-"$KERNEL_FLAVOR" linux-firmware-none mkinitfs \
    openrc busybox-openrc \
    grub grub-efi efibootmgr \
    openssh doas shadow shadow-uidmap \
    e2fsprogs dosfstools \
    ca-certificates \
    bash build-base git just rust cargo clang llvm-dev binutils cpio \
    libarchive-tools musl-dev linux-headers pkgconf openssl-dev zlib-dev xz-dev

echo ">> identity: hostname + hosts"
echo "$HOSTNAME_" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost $HOSTNAME_
::1         localhost $HOSTNAME_
EOF

echo ">> fstab (label-based, matches ONIX.md volume labels)"
cat > /etc/fstab <<EOF
LABEL=onix-root  /      ext4  rw,relatime            0 1
LABEL=ONIX-ESP   /efi   vfat  rw,relatime,noatime    0 2
EOF

echo ">> initramfs: ensure virtio + ext4 so it can mount the root disk"
mkdir -p /etc/mkinitfs
echo 'features="ata base ext4 keymap kms mmc scsi usb virtio nvme"' > /etc/mkinitfs/mkinitfs.conf
KVER="$(ls /lib/modules | head -n1)"
mkinitfs "$KVER"

echo ">> bootloader: grub-efi (removable, so OVMF finds \\EFI\\BOOT\\BOOTX64.EFI)"
grub-install --target=x86_64-efi --efi-directory=/efi --boot-directory=/boot \
             --removable --no-nvram
mkdir -p /efi/EFI/BOOT
cat > /boot/grub/grub.cfg <<EOF
set timeout=1
set default=0
insmod all_video
menuentry "ONIX forge (quarry)" {
    search --no-floppy --label onix-root --set=root
    linux /boot/vmlinuz-$KERNEL_FLAVOR root=LABEL=onix-root rootfstype=ext4 rw modules=ext4,virtio_blk,virtio_pci,virtio_net console=tty0 console=ttyS0,115200
    initrd /boot/initramfs-$KERNEL_FLAVOR
}
EOF
if [ ! -s /efi/EFI/BOOT/BOOTX64.EFI ]; then
  echo "!! grub-install did not create /efi/EFI/BOOT/BOOTX64.EFI; building standalone loader"
  grub-mkstandalone -O x86_64-efi \
    -o /efi/EFI/BOOT/BOOTX64.EFI \
    "boot/grub/grub.cfg=/boot/grub/grub.cfg"
fi
[ -s /efi/EFI/BOOT/BOOTX64.EFI ] || {
  echo "!! missing removable EFI loader after GRUB setup"
  exit 1
}

echo ">> users: root + build user '$BUILD_USER' (wheel/doas, subuid/subgid for rootless boulder)"
echo "root:$ROOT_PW" | chpasswd
adduser -D -s /bin/sh "$BUILD_USER"
echo "$BUILD_USER:$ROOT_PW" | chpasswd
addgroup "$BUILD_USER" wheel 2>/dev/null || true
# subuid/subgid ranges — moss/boulder use user namespaces for sandboxed builds
grep -q "^$BUILD_USER:" /etc/subuid || echo "$BUILD_USER:100000:65536" >> /etc/subuid
grep -q "^$BUILD_USER:" /etc/subgid || echo "$BUILD_USER:100000:65536" >> /etc/subgid
mkdir -p /etc/doas.d
echo "permit nopass :wheel" > /etc/doas.d/wheel.conf

echo ">> ssh: authorized_keys for root + $BUILD_USER (passwordless from the host)"
install -d -m700 /root/.ssh "/home/$BUILD_USER/.ssh"
printf '%s\n' "$SSH_PUBKEY" | tee /root/.ssh/authorized_keys "/home/$BUILD_USER/.ssh/authorized_keys" >/dev/null
chmod 600 /root/.ssh/authorized_keys "/home/$BUILD_USER/.ssh/authorized_keys"
chown -R "$BUILD_USER":"$BUILD_USER" "/home/$BUILD_USER/.ssh"
set_sshd_config() {
  key="$1"
  value="$2"
  if grep -q "^#\?${key}[[:space:]]" /etc/ssh/sshd_config; then
    sed -i "s/^#\?${key}[[:space:]].*/$key $value/" /etc/ssh/sshd_config
  else
    echo "$key $value" >> /etc/ssh/sshd_config
  fi
}
set_sshd_config PermitRootLogin prohibit-password
set_sshd_config PasswordAuthentication no
set_sshd_config KbdInteractiveAuthentication no
set_sshd_config ChallengeResponseAuthentication no

echo ">> network: dhcp on eth0"
cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

echo ">> serial getty on ttyS0 (so headless --display none/vnc shows a login)"
grep -q '^ttyS0:' /etc/inittab || \
  echo 'ttyS0::respawn:/sbin/getty -L 115200 ttyS0 vt100' >> /etc/inittab

echo ">> OpenRC services"
for svc in devfs dmesg mdev hwdrivers; do rc-update add "$svc" sysinit 2>/dev/null || true; done
for svc in modules sysctl hostname bootmisc syslog hwclock swap seedrng; do rc-update add "$svc" boot 2>/dev/null || true; done
for svc in networking sshd local crond; do rc-update add "$svc" default 2>/dev/null || true; done
for svc in mount-ro killprocs savecache; do rc-update add "$svc" shutdown 2>/dev/null || true; done

echo ">> place provision script (builds moss + boulder on first login)"
if [ -f /root/provision.sh ]; then
  install -m755 /root/provision.sh "/home/$BUILD_USER/provision.sh"
  chown "$BUILD_USER":"$BUILD_USER" "/home/$BUILD_USER/provision.sh"
fi
cat > /etc/onix-forge.env <<EOF
OS_TOOLS_REPO='$OS_TOOLS_REPO'
OS_TOOLS_REF='$OS_TOOLS_REF'
EOF

# PATH for the build user's ~/.local/bin (where os-tools installs moss/boulder)
grep -q 'HOME/.local/bin' "/home/$BUILD_USER/.profile" 2>/dev/null || \
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "/home/$BUILD_USER/.profile"

echo ">> chroot setup complete"
