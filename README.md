# My Arch Linux Setup

Reproducible configuration for three Arch machines running **Hyprland + end-4
(illogical-impulse)**, plus the scripts that survive the project's updates and
the lessons that were expensive to find.

> **Desktop change (2026-08/09):** this repo used to document HyDE. All three
> machines migrated to [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland).
> **Nothing of HyDE's is load-bearing any more.** Its zsh framework is still the
> login shell on the Titan (`ZDOTDIR=~/.config/zsh`); everything else is inert
> files. Both are listed in
> [troubleshooting](docs/06-troubleshooting.md#hyde-leftovers).

---

## The machines

| | **Titan** | **nomad** (Lenovo) | **pavilion** (HP) |
|---|---|---|---|
| Model | custom build | ThinkPad 20HR000FUS | Pavilion 13-an1xxx |
| CPU | Ryzen 7 8700F | i7-7600U | i5-1035G1 |
| RAM | 30 GiB | 15 GiB | 7.5 GiB |
| GPU | RTX 5060 Ti | HD Graphics 620 | Iris Plus G1 |
| Disk | 953 G | 915 G | 238 G |
| Network | ethernet | wifi | wifi |
| Keyboard | `es` | `latam` | `latam` |
| Autologin | yes | yes | no |
| SDDM theme | [ii-sddm](docs/01-base-install.md#sddm-theme--ii-sddm) | [ii-sddm](docs/01-base-install.md#sddm-theme--ii-sddm) | [ii-sddm](docs/01-base-install.md#sddm-theme--ii-sddm) |
| Swap | zram 4G | zram 4G + 16G partition | zram 3.8G |

All three are on the same tailnet, so they're reachable by Tailscale IP from any
network. See [remote access](docs/03-remote-access.md).

---

## Install order

1. [Base: Arch + partitions](docs/01-base-install.md)
2. [end-4 and the post-install](docs/02-end4.md) ← **the step that matters**
3. [Remote access](docs/03-remote-access.md): SSH, VNC, RDP, Tailscale
4. [Swap and hibernation](docs/04-swap-hibernate.md)
5. [KVM/QEMU](docs/05-kvm-qemu.md) (optional)
6. [Bar widgets](docs/07-bar-widgets.md): updates and AI agent usage

And when something breaks: [troubleshooting](docs/06-troubleshooting.md), which
collects the real failures of these three machines — not the causes that looked
obvious at first.

---

## Scripts

| Script | What it does |
|---|---|
| [`end4-post-install.sh`](scripts/end4-post-install.sh) | Reapplies the 21 steps that end-4's `./setup install` overwrites. **Idempotent**; run after every end-4 update. |
| [`end4-termscheme`](scripts/end4-termscheme) | Fills `scheme-base.json` with the wallpaper's **own** dominant colours, so end-4's generator produces a palette that actually comes from the image. Hooked into `switchwall.sh`. |
| [`wallbash-kitty.sh`](scripts/wallbash-kitty.sh) | **Superseded** by `end4-termscheme`, which does the same k-means extraction without running a second pipeline. Kept for reference. |
| [`end4-update`](scripts/end4-update) | Coloured system update: what is pending per source (repo / AUR / flatpak), then the upgrade. Wired to `apps.update`, so the bar's indicator runs it. |
| [`harden-ii-sddm.sh`](scripts/harden-ii-sddm.sh) | Fixes the insecure `NOPASSWD` sudoers rule that ii-sddm-theme installs. |
| [`scheme-hue-span.py`](scripts/scheme-hue-span.py) | Degrees of hue that `scheme-base.json` actually covers. Upstream's gruvbox base: 210. Under 60 means the palette cannot be anything but monochrome. |
| [`term-hues.py`](scripts/term-hues.py) | Prints what each ansi hue becomes for a given `harmony`/`harmonizeThreshold`. Run with the illogical-impulse venv python. |
| [`agent-usage-claude`](scripts/agent-usage-claude), [`agent-usage-codex`](scripts/agent-usage-codex) | Print one JSON usage record per AI coding agent. Vendored from Omarchy (MIT); feed the [bar widget](docs/07-bar-widgets.md). |

```bash
# After every end-4 `./setup install`:
KB_LAYOUT=latam ~/.local/bin/end4-post-install.sh
```

`KB_LAYOUT` defaults to `es`; the laptops use `latam`.

---

## Packages

### Fonts
```bash
paru -S ttf-cascadia-code-nerd noto-fonts-cjk ttf-dejavu noto-fonts-emoji
```

### Programs
```bash
paru -S alarm-clock-applet android-studio appimagelauncher arrpc btop deemix-gui \
  discord enpass-bin flutter-bin freerdp fsearch git gnome-disk-utility gparted \
  gwenview htop kdeconnect kate kid3 konsole libvncserver localsend mediainfo-gui \
  mkvalidator mkvtoolnix-gui nano net-tools obsidian onlyoffice-bin partitionmanager \
  plex-desktop plex-media-server-plexpass python-pipx python-pypresence qalculate-gtk \
  qbittorrent remmina rclone rsync sox soulseekqt spice-gtk subtitleedit syncthing \
  tauon-music-box telegram-desktop thunderbird visual-studio-code-bin zen-browser-bin
```

### Desktop and remote access
```bash
paru -S uwsm wayvnc rustdesk-bin hypr-rdp matugen fastfetch starship tailscale \
  pacman-contrib
```

`uwsm` is an **optional dependency** of Hyprland, so it is never pulled in
automatically — but without it `graphical-session.target` never activates and no
user service starts. See [why it matters](docs/06-troubleshooting.md#uwsm).

`pacman-contrib` provides `checkupdates`, which the bar's updates counter and
[`end4-update`](scripts/end4-update) both use. It is missing on a clean Arch, and
its absence is silent: the counter just never leaves zero.

### Services
```bash
systemctl enable --now plexmediaserver.service
systemctl enable --now syncthing@x.service
systemctl enable --now sshd.service
systemctl enable --now tailscaled.service
```

---

## VS Code

```json
"terminal.integrated.fontFamily": "CaskaydiaCove Nerd Font"
```
