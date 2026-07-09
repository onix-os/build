# Phase 406 — authenticated SSH proof

| Item | Value |
|---|---|
| Command | `make phase 406` |
| Underlying make target/scripts | `vm/phase4/materialize-etc.sh --ssh`, then `vm/phase4/ssh-probe.sh` |
| Mutates disk/image? | Yes, it mounts `artifacts/onix-image/onix.raw` and installs a bootstrap SSH server, user, keys, and service |
| Boots QEMU? | Yes, it runs an automated SSH proof through QEMU port forwarding |
| Main proof | The host authenticates with an SSH key to `onix@127.0.0.1:7626` and receives `ONIX_SSH_OK user=onix uid=1000`. |

## What this phase proves

Phase 405 proved host-to-guest TCP reachability, but it was not authenticated.

Phase 406 proves a stronger thing:

```text
the host can authenticate to the booted ONIX VM over SSH using a public key
```

This is the first real remote-access proof.

## Why Dropbear, not OpenSSH yet?

Both `pkgsMusl.dropbear` and `pkgsMusl.openssh` exist in the pinned Nix world.

Phase 406 chooses Dropbear because it is small and good for bootstrap systems.

That fits the current image better:

```text
tiny booted base
temporary bootstrap services
prove the concept first
final policy later
```

OpenSSH may still be the final choice later. This phase does not decide that
forever.

**Dropbear vs OpenSSH.** Both are SSH implementations that speak the same wire
protocol, so any SSH client can talk to either. OpenSSH is the full-featured
reference server most desktops and servers run; it is large and has many options.
Dropbear is a single small binary designed for embedded and bootstrap systems —
routers, initramfses, tiny images. For a minimal musl base that just needs to
prove "authenticated remote login works," Dropbear's small footprint fits the
Phase 4 spirit of proving the concept before committing to the heavier final
choice.

### Background: how public-key authentication works

SSH can authenticate you by password or by **key pair**, and ONIX chooses keys.

A key pair is two mathematically linked files: a **private key** you keep secret,
and a **public key** you may hand out freely. Data the private key signs can be
verified by anyone holding the public key, but the public key cannot be used to
forge that signature or reconstruct the private key. To authenticate, the client
proves it possesses the private key without ever transmitting it.

The mechanics are simple to follow here:

```text
client private key   vm/state/id_ed25519        (host keeps this secret)
client public key    vm/state/id_ed25519.pub     (installed on the guest)
guest authorized set /home/onix/.ssh/authorized_keys
```

At login, the guest's SSH server checks whether the client's key is listed in that
user's `authorized_keys`. If the client can then prove it holds the matching
private key, access is granted — no password ever crosses the wire, so there is
nothing to brute-force or phish. This is why the phase installs the *public* key
into the image and keeps the private key only on the host. (`ed25519` names the
elliptic-curve signature algorithm used; it is the modern default.)

**Host keys are the other half.** The server also has its own key pair
(`/etc/dropbear/dropbear_ed25519_host_key`). That one proves the *server's*
identity to clients, so a client can detect if it is being redirected to an
impostor. Client keys authenticate the user to the server; host keys authenticate
the server to the user.

## Authentication policy

Phase 406 is intentionally stricter than Phase 405.

The Dropbear service is started with:

```text
-s    disable password logins
-w    disallow root logins
-j    disable local port forwarding
-k    disable remote port forwarding
```

So the proof is:

```text
public-key auth only
non-root user only
no password auth
no root SSH login
```

The bootstrap user is:

```text
user   onix
uid    1000
gid    100
home   /home/onix
shell  /bin/sh
```

The root account remains non-interactive from the normal account database point
of view:

```text
root ... /usr/sbin/nologin
```

That means Phase 406 does not silently undo the safety decision from Phase 402.

## Where the key lives

The host-side proof key is:

```text
vm/state/id_ed25519
vm/state/id_ed25519.pub
```

If the key does not exist, Phase 406 generates it.

The guest-side authorized key is installed under the persistent home tree:

```text
/persist/home/onix/.ssh/authorized_keys
```

Why `/persist/home` instead of `/home` while building the image?

Because at boot ONIX bind-mounts:

```text
/persist/home -> /home
```

So if we wrote only to the root filesystem's `/home`, it would be hidden after
the real persistent home mount appears.

This is the same kind of mount lesson we learned earlier with `/persist/nix`.

## Host keys

SSH servers need host keys too.

The host key identifies the guest server to clients.

Phase 406 generates:

```text
/etc/dropbear/dropbear_ed25519_host_key
```

If that file already exists, it is preserved.

This is still bootstrap policy. A final installed system needs a better story
for host-key lifecycle and persistence.

## QEMU forwarding

The guest listens on the normal SSH port:

```text
guest 0.0.0.0:22
```

QEMU forwards a host-local test port:

```text
host 127.0.0.1:7626 -> guest :22
```

So the host proof command uses:

```sh
ssh -i vm/state/id_ed25519 -p 7626 onix@127.0.0.1 ...
```

## The automated proof

`make phase 406` first installs the pieces:

```text
./materialize-etc.sh --ssh
```

That installs:

```text
pkgsMusl.dropbear closure
/usr/lib/sysusers.d/onix-ssh.conf
/persist/home/onix/.ssh/authorized_keys
/etc/dropbear/dropbear_ed25519_host_key
/usr/lib/onix/bootstrap-ssh-status
/usr/lib/onix/bootstrap-ssh-proof
onix-bootstrap-dropbear.service
```

Then it boots QEMU:

```text
./ssh-probe.sh
```

The probe uses the serial shell first to ask the guest:

```sh
/usr/lib/onix/bootstrap-network-proof &&
/usr/lib/onix/bootstrap-ssh-proof
```

The guest must answer:

```text
ONIX_SSH_READY user=onix port=22
```

Then the host runs SSH:

```sh
ssh -i vm/state/id_ed25519 -p 7626 onix@127.0.0.1 \
  'printf "ONIX_SSH_OK user=$(/bin/id -un) uid=$(/bin/id -u) ...\n"'
```

The host must receive:

```text
ONIX_SSH_OK user=onix uid=1000
```

That proves:

- Dropbear started in the guest,
- QEMU forwarded the host port to the guest,
- the `onix` user exists,
- `/home/onix/.ssh/authorized_keys` is visible through `/persist/home`,
- password auth is not needed,
- public-key auth succeeds.

## Run it

From the repo root:

```sh
make phase 406
```

Expected output includes:

```text
policy   : /usr/lib/sysusers.d/onix-ssh.conf
ssh-auth : /persist/home/onix/.ssh/authorized_keys
ssh-host : /etc/dropbear/dropbear_ed25519_host_key generated
unit     : /nix/store/.../onix-bootstrap-dropbear.service
unit     : /persist/nix/store/.../onix-bootstrap-dropbear.service
```

Expected proof output includes:

```text
ONIX_SSH_READY user=onix port=22
ONIX_SSH_OK user=onix uid=1000 home=/home/onix shell=/bin/sh host=onix kernel=Linux

==> success
Phase 406 proved authenticated SSH access through QEMU port forwarding.
```

## What this phase does not do

Phase 406 does not finalize remote administration.

Still open:

- whether final ONIX uses Dropbear or OpenSSH,
- how users are created on first boot,
- where user-provided SSH keys come from,
- whether root SSH is always forbidden,
- where persistent host keys should live long-term,
- firewall policy,
- SSH hardening policy,
- whether remote access is enabled by default.

Phase 406 proves the essential mechanism:

```text
authenticated key-based SSH into the booted ONIX image works
```
