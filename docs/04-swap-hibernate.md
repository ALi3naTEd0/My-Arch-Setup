# Swap e hibernación

Dos caminos según el sistema de archivos. La **partición** es lo que está
probado en la Lenovo (16 G en `/dev/nvme0n1p3`); el **swapfile en btrfs** es la
alternativa cuando el disco ya está todo asignado y no puedes repartir.

---

## Cuánto swap

| Caso | Tamaño |
|---|---|
| Solo red de seguridad tras zram | 8 GiB |
| Uso normal (VMs, compilaciones) | 16 GiB |
| **Con hibernación** | ≥ RAM, en la práctica RAM + 10% |

Con zram ya en marcha, el swap en disco es un **segundo escalón**, no el
primero. Ponle prioridad más baja para que el kernel comprima en RAM antes de
bajar al disco:

```
/swap/swapfile  none  swap  defaults,pri=10  0 0
```

zram suele estar en `pri=100`. Comprobar con `swapon --show`.

> **Swap lleno ≠ falta de memoria.** Mira `/proc/pressure/memory`: si `some` y
> `full` están en 0.00, el sistema no está sufriendo — son páginas frías que el
> kernel sacó y no tiene motivo para traer de vuelta. Lo que sí es peligroso es
> **no tener segundo escalón**: cuando zram se llena, el siguiente pico va
> directo al OOM killer.

---

## Opción A · Partición (probado en la Lenovo)

1. Crear la partición con GParted o Partition Manager, formato **linux-swap**
2. Activarla: `sudo swapon /dev/nvme0n1p3`
3. Verificar: `swapon --show`
4. Añadir el hook `resume` a `/etc/mkinitcpio.conf`:

```
HOOKS=(base udev autodetect modconf block filesystems resume keyboard fsck)
```

5. Sacar el UUID de la partición: `blkid`
6. Añadir `resume=UUID=…` en `/boot/loader/entries/*.conf`:

```
options root=PARTUUID=… zswap.enabled=0 rootflags=subvol=@ rw rootfstype=btrfs resume=UUID=78acba64-6959-4382-91ca-773199f00af3
```

7. Regenerar: `sudo mkinitcpio -P`
8. Probar: `systemctl hibernate`

> El orden importa: `resume` va **después** de `filesystems`. Y `zswap.enabled=0`
> evita que zswap y zram se pisen.

---

## Opción B · Swapfile en btrfs (cuando no hay hueco para partición)

Caso de la Titan: `nvme0n1p1` (1 G `/boot`) + `nvme0n1p2` (952.9 G btrfs) = disco
completo. Cero espacio sin asignar, y no se puede encoger la raíz montada sin un
USB live. Desde el kernel 5.0 btrfs soporta swapfiles.

### Subvolumen dedicado

Al nivel superior, para que Timeshift no lo meta en los snapshots:

```bash
sudo mkdir -p /mnt/btrfs-top
sudo mount -o subvolid=5 /dev/nvme0n1p2 /mnt/btrfs-top
sudo btrfs subvolume create /mnt/btrfs-top/@swap
sudo umount /mnt/btrfs-top && sudo rmdir /mnt/btrfs-top
```

### fstab

```
UUID=<uuid-de-p2>  /swap  btrfs  rw,noatime,subvol=/@swap  0 0
/swap/swapfile     none   swap   defaults,pri=10           0 0
```

### Crear y activar

```bash
sudo mkdir -p /swap
sudo systemctl daemon-reload
sudo mount /swap
sudo btrfs filesystem mkswapfile --size 16g --uuid clear /swap/swapfile
sudo swapon /swap/swapfile
```

`btrfs filesystem mkswapfile` (btrfs-progs 6.1+) se encarga solo del
**NODATACOW**, la no-compresión y la preasignación. A mano con `fallocate` +
`mkswap`, el `swapon` falla por el CoW y la compresión `zstd` heredada del
montaje.

### Hibernación con swapfile

Además del `resume=UUID=` necesitas `resume_offset`:

```bash
sudo btrfs inspect-internal map-swapfile -r /swap/swapfile
```

Ese número va como `resume_offset=` en las opciones del bootloader, junto al
`resume=UUID=` del **dispositivo**, no del archivo.

---

## Comprobar que la hibernación es viable

```bash
cat /sys/power/resume          # "0:0" = no configurada
grep -o 'resume=[^ ]*' /proc/cmdline
free -h                        # el swap debe superar la RAM usada
```

Consideración de seguridad: la imagen de hibernación contiene **toda la RAM en
claro**. En un disco sin cifrar, eso incluye claves y contraseñas que estuvieran
en memoria.

---

## zram

Ya viene configurado por `zram-generator`. Ver y ajustar:

```bash
swapon --show
cat /etc/systemd/zram-generator.conf
```

Las tres máquinas llevan ~4 G de zram. La Titan lo tuvo **al 100%** durante días
sin que fuera un problema (presión de memoria en 0.00) — pero sin segundo
escalón, cualquier pico se convierte en OOM. Ver
[el caso del thumbnailer](06-troubleshooting.md#la-sesión-se-cae-en-bucle--oom-por-el-generador-de-miniaturas).
