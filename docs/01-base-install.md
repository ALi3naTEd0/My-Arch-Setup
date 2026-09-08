# Base install

Arch on **btrfs** with subvolumes, `systemd-boot`, and SDDM as the session
manager.

---

## Partitioning

Titan's layout:

| Partition | Size | Use |
|---|---|---|
| `nvme0n1p1` | 1 G | `/boot`, vfat |
| `nvme0n1p2` | rest | btrfs |

**Leave unallocated space if you plan to use a swap partition.** Titan ran out
of room and had to fall back to a
[btrfs swapfile](04-swap-hibernate.md#option-b--btrfs-swapfile-when-theres-no-room-for-a-partition):
you cannot shrink a mounted btrfs root without a live USB.

### Subvolumes

```
@       →  /
@home   →  /home
@log    →  /var/log
@pkg    →  /var/cache/pacman/pkg
```

`@log` and `@pkg` are separate so they stay out of snapshots — they hold data
you never want to restore.

### Mount options

```
rw,relatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@
```

---

## Watching btrfs space

`df` is not enough. What matters is **`Device unallocated`**:

```bash
btrfs filesystem usage /
```

If it approaches zero, metadata cannot grow and you get "No space left" with
gigabytes apparently free. A balance returns space to the pool:

```bash
sudo btrfs balance start -dusage=50 /
```

Caches that grow silently: `~/.cache/{paru,yay,Shelly,hyde,dots-hyprland}`,
`/var/cache/pacman/pkg`, and the **trash**.

> The trash can hold orphaned files: if a file exists in
> `~/.local/share/Trash/files/` but its `.trashinfo` doesn't in `info/`, **the
> graphical manager won't list it** and the space is invisible. Check with
> `du -sh`, not the UI.

---

## Keyboard

```bash
sudo localectl set-x11-keymap latam pc105 "" terminate:ctrl_alt_bksp
```

This writes `/etc/X11/xorg.conf.d/00-keyboard.conf` and `/etc/vconsole.conf`.
The SDDM greeter **does not inherit it automatically** — see
[troubleshooting](06-troubleshooting.md#greeter-keyboard-layout).

---

## Autologin

Used by Titan and the Lenovo. Without it, **no graphical service starts until
someone signs in** — including VNC and RDP.

```bash
sudo mkdir -p /etc/sddm.conf.d
printf '[Autologin]\nUser=x\nSession=hyprland-uwsm\nRelogin=false\n' \
  | sudo tee /etc/sddm.conf.d/zz-autologin.conf
```

The `zz-` prefix matters: SDDM reads that directory alphabetically and **the
last file wins**.

> Verify `uwsm` is installed **before** pointing autologin at `hyprland-uwsm`.
> If the session doesn't exist, SDDM ends up in a retry loop.

---

## Next

1. [end-4 and the post-install](02-end4.md)
2. [Remote access](03-remote-access.md) — enable SSH **first**
