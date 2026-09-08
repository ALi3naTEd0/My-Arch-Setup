# Máquinas virtuales

Dos caminos. **libvirt** es el clásico y el que está documentado aquí desde
siempre; **`dockurr/windows`** es lo que usa Omarchy por debajo de su instalador
de un clic, y no depende de Omarchy en absoluto.

---

## Opción A · libvirt + virt-manager

```bash
paru -S qemu-full virt-manager virt-viewer dmidecode dnsmasq bridge-utils \
        libguestfs ebtables vde2 openbsd-netcat
```

### Servicios

```bash
sudo systemctl enable --now libvirtd.service
sudo systemctl enable --now libvirtd.socket
```

### Red «default»

```bash
sudo usermod -aG libvirt $(whoami)
sudo virsh net-define /etc/libvirt/qemu/networks/default.xml
sudo virsh net-start default
sudo virsh net-autostart default
sudo systemctl restart libvirtd
sudo virsh net-list --all
```

El `usermod` requiere cerrar sesión para que tome efecto.

---

## Opción B · Windows en contenedor (`dockurr/windows`)

Lo que hay detrás del «instalador de Windows de un clic» de Omarchy no es código
suyo: es la imagen **[`dockurr/windows`](https://github.com/dockur/windows)** más
un script envoltorio ([`bin/omarchy-windows-vm`](https://github.com/basecamp/omarchy/blob/master/bin/omarchy-windows-vm), MIT).
Corre Windows con KVM **dentro de un contenedor**, descarga el ISO sola, y se
accede **por RDP**.

Ventaja sobre libvirt: cero configuración de red y de disco. Desventaja: hace
falta Docker y el contenedor va **privilegiado** (KVM, `/dev/net/tun`,
`NET_ADMIN`).

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
      - 8006:8006    # consola web durante la instalación
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

Instalación en `http://localhost:8006`; después, RDP a `localhost:3389`.

> **Ojo con el 3389:** es el mismo puerto que usa `hypr-rdp`. Si tienes el
> servidor RDP de Hyprland corriendo, cambia uno de los dos o chocan.

### Lo que sí vale la pena copiar de Omarchy

Su script tiene una decisión de seguridad bien pensada y documentada en el
propio código: el `docker-compose.yml` vive en un **directorio de root**
(`/var/lib/omarchy/windows`), no en `$HOME`.

> *«un `docker compose up` invocado por root nunca debe consumir un archivo que
> un proceso corriendo como el usuario pudo haber reescrito para montar `/`
> dentro del contenedor»*

Es el mismo tipo de fallo que corregimos en
[`harden-ii-sddm.sh`](../scripts/harden-ii-sddm.sh): un objetivo privilegiado que
el usuario puede reescribir. Si montas el compose a mano, tenlo en cuenta —
sobre todo si lo lanzas con `sudo`.

Y el grupo `docker` es **equivalente a root**. Omarchy no mete al usuario en él
por defecto; usa un prompt de polkit por invocación.
