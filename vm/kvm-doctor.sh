#!/usr/bin/env bash
# vm/kvm-doctor.sh — explain whether ONIX QEMU can use KVM acceleration.
set -euo pipefail

blue() { printf '\033[34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarn:\033[0m %s\n' "$*"; }
bad()  { printf '\033[31mno:\033[0m %s\n' "$*"; }
ok()   { printf '\033[32mok:\033[0m %s\n' "$*"; }

have() {
  command -v "$1" >/dev/null 2>&1
}

blue "ONIX KVM acceleration check"

warn "run this from your normal host terminal, not from inside the ONIX guest"

blue "CPU virtualization exposure"
if grep -Eq '(^flags|^Features).* (vmx|svm)( |$)' /proc/cpuinfo 2>/dev/null; then
  flag="$(grep -m1 -E '(^flags|^Features)' /proc/cpuinfo | tr ' ' '\n' | grep -E '^(vmx|svm)$' | head -n1)"
  ok "CPU exposes virtualization flag: $flag"
else
  warn "CPU virtualization flag vmx/svm is not visible in this shell"
  warn "possible causes: disabled in BIOS/UEFI or not exposed to this shell"
fi

blue "/dev/kvm device"
if [[ -e /dev/kvm ]]; then
  ls -l /dev/kvm
  if [[ -w /dev/kvm ]]; then
    ok "/dev/kvm is writable; QEMU should use accel=kvm and -cpu host"
    exit 0
  fi

  bad "/dev/kvm exists but is not writable by this user"
  if have id; then
    printf 'current user/groups: '
    id
  fi
  if have getent && getent group kvm >/dev/null 2>&1; then
    printf 'kvm group: '
    getent group kvm
  fi
  cat <<'EOF'

Likely fix on Ubuntu/Debian-style hosts:

  sudo usermod -aG kvm "$USER"

Then fully log out and back in, or reboot.

For a temporary same-terminal test, this may work:

  newgrp kvm

Then verify:

  test -w /dev/kvm && echo KVM_OK

EOF
  exit 1
fi

bad "/dev/kvm does not exist in this shell"
cat <<'EOF'

If this is the real Linux host, try loading the KVM module:

  # Intel CPU:
  sudo modprobe kvm_intel

  # AMD CPU:
  sudo modprobe kvm_amd

Then check:

  ls -l /dev/kvm

If /dev/kvm still does not appear:

  1. Enable Intel VT-x / AMD-V / SVM in BIOS/UEFI.
  2. Make sure the host kernel has loaded the correct KVM module.

After /dev/kvm exists and is writable, ONIX launch scripts will automatically
switch from slow TCG to fast KVM.

EOF
exit 1
