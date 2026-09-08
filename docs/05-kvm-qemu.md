# Virtual machines

Two routes. **libvirt** is the classic one, documented here from the start;
**`dockurr/windows`** is what sits underneath Omarchy's one-click installer, and
it does not depend on Omarchy at all.

---

## Option A · libvirt + virt-manager

```bash
paru -S qemu-full virt-manager virt-viewer dmidecode dnsmasq bridge-utils \
        libguestfs ebtables vde2 openbsd-netcat
```

### Services

```bash
sudo systemctl enable --now libvirtd.service
sudo systemctl enable --now libvirtd.socket
```

### The "default" network

```bash
sudo usermod -aG libvirt $(whoami)
sudo virsh net-define /etc/libvirt/qemu/networks/default.xml
sudo virsh net-start default
sudo virsh net-autostart default
sudo systemctl restart libvirtd
sudo virsh net-list --all
```

The `usermod` needs a logout to take effect.

---

## Option B · Windows in a container (`dockurr/windows`)

What powers Omarchy's "one-click Windows installer" isn't their code: it's the
**[`dockurr/windows`](https://github.com/dockur/windows)** image plus a wrapper
script ([`bin/omarchy-windows-vm`](https://github.com/basecamp/omarchy/blob/master/bin/omarchy-windows-vm), MIT).
It runs Windows with KVM **inside a container**, downloads the ISO by itself,
and you connect **over RDP**.

Advantage over libvirt: no network or disk setup at all. Downside: it needs
Docker, and the container runs **privileged** (KVM, `/dev/net/tun`, `NET_ADMIN`).

```yaml
# docker-compose.yml
services:
  windows:
    image: dockurr/windows
    container_name: windows
    environment:
      VERSION: "11"
      RAM_SIZE: "8G"
      CPU_CORES: "4"
      DISK_SIZE: "64G"
    devices:
      - /dev/kvm
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
    ports:
      - 8006:8006    # web console during install
      - 3389:3389/tcp
      - 3389:3389/udp
    volumes:
      - ./storage:/storage
    restart: on-failure
    stop_grace_period: 2m
```

```bash
docker compose up -d
```

Install at `http://localhost:8006`; afterwards, RDP to `localhost:3389`.

> **Careful with port 3389:** it's the same one `hypr-rdp` uses. If you run the
> Hyprland RDP server too, change one of them or they clash.

### Worth copying from Omarchy

Their script makes one security decision that's well reasoned and documented in
the code itself: the `docker-compose.yml` lives in a **root-owned directory**
(`/var/lib/omarchy/windows`), not in `$HOME`.

> *"a root-invoked `docker compose up` must never consume a file that a process
> running as the user could have rewritten to bind-mount `/` into the
> container"*

It's the same class of bug fixed in
[`harden-ii-sddm.sh`](../scripts/harden-ii-sddm.sh): a privileged target the
user can rewrite. If you assemble the compose file by hand, keep that in mind —
especially if you launch it with `sudo`.

And the `docker` group is **root-equivalent**. Omarchy does not add the user to
it by default; it uses a polkit prompt per invocation instead.
