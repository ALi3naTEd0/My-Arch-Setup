# My Arch Linux Setup

### **OS**: [Arch](https://archlinux.org/)
### **DE**: [HyDE](https://github.com/prasanthrangan/hyprdots)

## Fonts
```
paru -S noto-fonts-cjk ttf-dejavu noto-fonts-emoji
```

## Install programs
```
paru -S alarm-clock-applet android-studio anydesk-bin appimagelauncher btop deemix-fix-gui-git discord element-desktop enpass-bin filelight firefox firefox-pwa flutter-bin freerdp fsearch git gnome-disk-utility gparted gwenview hypnotix htop kdeconnect kate kid3 konsole libvncserver linutil localsend mediainfo-gui mkvalidator mkvtoolnix-gui nano neofetch net-tools nordvpn-bin notion-app-electron obsidian onlyoffice-bin partitionmanager plex-media-player plex-media-server-plexpass python-pipx python-pypresence qalculate-gtk qbittorrent remmina rclone rssguard rsync sox soulseekqt spice-gtk subtitleedit syncthing tauon-music-box telegram-desktop thunderbird uget visual-studio-code-bin webapp-manager -y
```

## Install KVM/QEMU
```
paru -S qemu-full virt-manager virt-viewer dmidecode dnsmasq bridge-utils libguestfs ebtables vde2 openbsd-netcat -y
```

## Fix VSCode Terminal
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

## Services
- `systemctl enable plexmediaserver.service`
- `systemctl start plexmediaserver.service`
- `systemctl enable syncthing@x.service`
- `systemctl start syncthing@x.service`
- `systemctl enable libvirtd.service`
- `systemctl enable libvirtd.socket`
- `systemctl start libvirtd.service`
- `systemctl start libvirtd.socket`

Configure "default" network
- `sudo usermod -aG libvirt $(whoami)`
- `sudo virsh net-define /etc/libvirt/qemu/networks/default.xml`
- `sudo virsh net-start default`
- `sudo virsh net-autostart default`
- `sudo systemctl restart libvirtd`
- `sudo systemctl status libvirtd`
- `sudo virsh net-list --all`
