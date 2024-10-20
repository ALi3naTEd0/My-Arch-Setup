# My Arch Linux Setup

### **OS**: [Arch](https://archlinux.org/)
### **DE**: [Hyprdots](https://github.com/prasanthrangan/hyprdots)

## Install programs
```
paru -S alarm-clock-applet android-studio anydesk-bin appimagelauncher btop deemix-fix-gui-git discord element-desktop enpass-bin filelight firefox firefox-pwa flutter-bin fsearch git gnome-disk-utility gparted gwenview hypnotix htop kdeconnect kate kid3 konsole linutil localsend mediainfo-gui mkvalidator mkvtoolnix-gui nano neofetch net-tools nordvpn-bin notion-app-electron obsidian onlyoffice-bin partitionmamager plex-media-player plex-media-server-plexpass python-pipx python-pypresence qbittorrent rclone rssguard rsync sox soulseekqt subtitleedit syncthing tauon-music-box telegram-desktop thunderbird uget visual-studio-code-bin webapp-manager -y
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

## Make SWAP (with hibernate)
- Create a partition for your SWAP using Gparted or Partition Manager
- Format it as "linux-swap"
- Activate the swap partition: `sudo swapon /dev/nvme0n1p3`
- Make sure is active: `swapon --show`
- Edit `/etc/mkinitcpio.conf` = `HOOKS=(base udev autodetect modconf block filesystems resume keyboard fsck)`
- Find UUID from SWAP partition: `blkid`
- Edit `/boot/loader/entries/file.conf` = `options root=PARTUUID=779638dc-ccb2-48d0-8f7f-b246471896b9 zswap.enabled=0 rootflags=subvol=@ rw rootfstype=btrfs resume=UUID=78acba64-6959-4382-91ca-773199f00af3`
- Regenerate mkinitcpio = `sudo mkinitcpio -P`
- Test it's working: `systemctl hibernate`
