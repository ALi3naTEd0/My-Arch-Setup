# My Arch Linux Setup

### **OS**: [Arch](https://archlinux.org/)
### **DE**: [Hyprdots](https://github.com/prasanthrangan/hyprdots)

## Install programs
```
paru -S alarm-clock-applet android-studio anydesk-bin appimagelauncher btop deemix-fix-gui-git discord element-desktop enpass-bin filelight firefox firefox-pwa flutter-bin fsearch git github-cli gnome-disk-utility gwenview hypnotix htop kdeconnect kate kid3 konsole linutil localsend mediainfo mkvtoolnix-gui nano neofetch net-tools nordvpn-bin notion-app-electron obsidian onlyoffice-bin plex-media-player plex-media-server-plexpass python-pipx python-pypresence qbittorrent rclone rssguard rsync sox soulseekqt subtitleedit syncthing tauon-music-box telegram-desktop thunderbird uget visual-studio-code-bin webapp-manager -y
```

## Fonts
```
paru -S noto-fonts-cjk ttf-dejavu noto-fonts-emoji
```

## Install KVM/QEMU
```
paru -S qemu-full virt-manager virt-viewer dnsmasq bridge-utils libguestfs ebtables vde2 openbsd-netcat -y
```

## Fix VSCode Terminal
Fonts: [Cascadia Code, Cascadia Mono](https://www.nerdfonts.com/font-downloads)
```
terminal.integrated.fontFamily": CaskaydiaCove Nerd Font
```
