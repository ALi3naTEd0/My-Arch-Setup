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

### Autologin vs. seeing the greeter

These pull in opposite directions and you cannot have both:

| | greeter visible | remote access after boot |
|---|---|---|
| Autologin on | no — it never draws | yes |
| Autologin off | yes | **no, until someone logs in physically** |

**You cannot log in remotely through the greeter.** wayvnc and hypr-rdp are
*user* services bound to `graphical-session.target`, and the greeter runs as the
`sddm` user in its own session — so neither server exists yet. Nothing listens on
5900 or 3389 until your session starts. Only SSH works at that point.

So a machine you power on and reach remotely needs autologin, full stop.

---

## SDDM theme · ii-sddm

[3d3f/ii-sddm-theme](https://github.com/3d3f/ii-sddm-theme) mirrors end-4's
lockscreen and can sync its colors with the wallpaper through matugen. Neither
end-4 nor HyDE theme the login screen from the wallpaper, so this is the only
piece that closes that gap.

> On a machine with autologin this is **invisible work** — the greeter never
> draws. And you already see the same design at lock time, since the theme
> imitates end-4's hyprlock, not the other way round.

```bash
git clone --depth=1 https://github.com/3d3f/ii-sddm-theme ~/src/ii-sddm-theme
cd ~/src/ii-sddm-theme && ./setup.sh     # pick "ii + Matugen"
```

### Test before enabling it

`setup.sh` writes `Current=` on its own. **Test before rebooting** — this is the
step that prevents a black screen:

```bash
QML2_IMPORT_PATH=/usr/share/sddm/themes/ii-sddm-theme/Components/ \
QT_QPA_PLATFORM=wayland \
sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/ii-sddm-theme
```

Both variables are required — see
[troubleshooting](06-troubleshooting.md#test-a-theme-before-enabling-it).

### Harden it

```bash
sudo ~/src/harden-ii-sddm.sh
```

The installer creates `/etc/sudoers.d/sddm-theme-$USER` granting **NOPASSWD** on
a script it copies into `$HOME` — user-writable, i.e. a straight path to root for
anything running as you. The script moves that binary to `/usr/local/bin` owned
by root and repoints both the sudoers rule and matugen's `post_hook`.

Observed on two machines: the installer **skips the sudoers step entirely** but
still leaves the `post_hook` calling `sudo`, so the wallpaper sync fails silently
until you run the hardening. It fixes the feature and the hole at once.

### On machines that came from HyDE

Rename the config so it is read last, otherwise HyDE's `Current=Corners` wins:

```bash
sudo mv /etc/sddm.conf.d/ii-sddm-theme.conf /etc/sddm.conf.d/zz-ii-sddm-theme.conf
```

### Notes

- `InputMethod=qtvirtualkeyboard` in the generated conf is unnecessary on a
  laptop with a physical keyboard and fills the log with warnings about a
  missing `hunspell` dictionary. Setting it empty is harmless.
- The apply script exits with code **1** even on success: its last line is
  `[ "$IS_VIDEO" = true ] && …`, which returns 1 for an image wallpaper. The
  work is done; the status is misleading.

---

## Next

1. [end-4 and the post-install](02-end4.md)
2. [Remote access](03-remote-access.md) — enable SSH **first**
