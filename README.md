# My Arch Linux Setup

Configuración reproducible de tres máquinas Arch con **Hyprland + end-4
(illogical-impulse)**, más los scripts que sobreviven a las actualizaciones del
proyecto y las lecciones que costaron encontrar.

> **Cambio de escritorio (2026-08/09):** este repo documentaba HyDE. Las tres
> máquinas migraron a [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland).
> Quedan residuos de HyDE a propósito — algunos siguen siendo útiles
> ([wallbash](docs/02-end4.md#colores-de-kitty), los temas de SDDM), otros están
> anotados en [troubleshooting](docs/06-troubleshooting.md#residuos-de-hyde).

---

## Las máquinas

| | **Titan** | **nomad** (Lenovo) | **pavilion** (HP) |
|---|---|---|---|
| Modelo | build propio | ThinkPad 20HR000FUS | Pavilion 13-an1xxx |
| CPU | Ryzen 7 8700F | i7-7600U | i5-1035G1 |
| RAM | 30 GiB | 15 GiB | 7.5 GiB |
| GPU | RTX 5060 Ti | HD Graphics 620 | Iris Plus G1 |
| Disco | 953 G | 915 G | 238 G |
| Red | ethernet | wifi | wifi |
| Teclado | `es` | `latam` | `latam` |
| Autologin | sí | no | no |
| Tema SDDM | Corners (HyDE) | ii-sddm | ii-sddm |
| Swap | zram 4G | zram 4G + 16G partición | zram 3.8G |

Todas en el mismo tailnet, así que se alcanzan por IP de Tailscale desde
cualquier red. Ver [acceso remoto](docs/03-remote-access.md).

---

## Orden de instalación

1. [Base: Arch + particiones](docs/01-base-install.md)
2. [end-4 y el post-install](docs/02-end4.md) ← **el paso que importa**
3. [Acceso remoto](docs/03-remote-access.md): SSH, VNC, RDP, Tailscale
4. [Swap e hibernación](docs/04-swap-hibernate.md)
5. [KVM/QEMU](docs/05-kvm-qemu.md) (opcional)

Y cuando algo falle: [troubleshooting](docs/06-troubleshooting.md), que recoge
los fallos reales de estas tres máquinas y no las causas que parecían obvias.

---

## Scripts

| Script | Qué hace |
|---|---|
| [`end4-post-install.sh`](scripts/end4-post-install.sh) | Reaplica los 11 ajustes que `./setup install` de end-4 sobrescribe. **Idempotente**, correr después de cada actualización de end-4. |
| [`wallbash-kitty.sh`](scripts/wallbash-kitty.sh) | Paleta de kitty derivada del wallpaper con k-means (4 tonos), en vez del acento único de end-4. |
| [`harden-ii-sddm.sh`](scripts/harden-ii-sddm.sh) | Corrige la regla `NOPASSWD` insegura que instala ii-sddm-theme. |

```bash
# Después de cada `./setup install` de end-4:
KB_LAYOUT=latam ~/.local/bin/end4-post-install.sh
```

`KB_LAYOUT` por defecto es `es`; las laptops usan `latam`.

---

## Paquetes

### Fuentes
```bash
paru -S ttf-cascadia-code-nerd noto-fonts-cjk ttf-dejavu noto-fonts-emoji
```

### Programas
```bash
paru -S alarm-clock-applet android-studio appimagelauncher arrpc btop deemix-gui \
  discord enpass-bin flutter-bin freerdp fsearch git gnome-disk-utility gparted \
  gwenview htop kdeconnect kate kid3 konsole libvncserver localsend mediainfo-gui \
  mkvalidator mkvtoolnix-gui nano net-tools obsidian onlyoffice-bin partitionmanager \
  plex-desktop plex-media-server-plexpass python-pipx python-pypresence qalculate-gtk \
  qbittorrent remmina rclone rsync sox soulseekqt spice-gtk subtitleedit syncthing \
  tauon-music-box telegram-desktop thunderbird visual-studio-code-bin zen-browser-bin
```

### Escritorio y acceso remoto
```bash
paru -S uwsm wayvnc rustdesk-bin hypr-rdp matugen fastfetch starship tailscale
```

`uwsm` es **dependencia opcional** de Hyprland, así que no se instala sola —
pero sin ella `graphical-session.target` no se activa y ningún servicio de
usuario arranca. Ver [por qué importa](docs/06-troubleshooting.md#uwsm).

### Servicios
```bash
systemctl enable --now plexmediaserver.service
systemctl enable --now syncthing@x.service
systemctl enable --now sshd.service
systemctl enable --now tailscaled.service
```

---

## Configuración de VS Code

```json
"terminal.integrated.fontFamily": "CaskaydiaCove Nerd Font"
```
