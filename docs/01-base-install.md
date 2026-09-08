# Instalación base

Arch con **btrfs** y subvolúmenes, `systemd-boot`, y SDDM como gestor de sesión.

---

## Particionado

Esquema de la Titan:

| Partición | Tamaño | Uso |
|---|---|---|
| `nvme0n1p1` | 1 G | `/boot`, vfat |
| `nvme0n1p2` | resto | btrfs |

**Deja espacio sin asignar si piensas usar swap en partición.** La Titan se
quedó sin hueco y hubo que ir a un [swapfile en btrfs](04-swap-hibernate.md#opción-b--swapfile-en-btrfs-cuando-no-hay-hueco-para-partición):
encoger una raíz btrfs montada no se puede sin un USB live.

### Subvolúmenes

```
@       →  /
@home   →  /home
@log    →  /var/log
@pkg    →  /var/cache/pacman/pkg
```

`@log` y `@pkg` aparte para que no entren en los snapshots — son datos que no
quieres restaurar.

### Opciones de montaje

```
rw,relatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@
```

---

## Vigilar el espacio en btrfs

`df` no basta. Lo que importa es **`Device unallocated`**:

```bash
btrfs filesystem usage /
```

Si se acerca a cero, los metadatos no pueden crecer y da «No space left» con
gigas aparentemente libres. Un `balance` devuelve espacio al pool:

```bash
sudo btrfs balance start -dusage=50 /
```

Cachés que engordan sin avisar: `~/.cache/{paru,yay,Shelly,hyde,dots-hyprland}`,
`/var/cache/pacman/pkg`, y la **papelera**.

> La papelera puede tener archivos huérfanos: si existe el archivo en
> `~/.local/share/Trash/files/` pero no su `.trashinfo` en `info/`, **el gestor
> gráfico no lo lista** y ocupa espacio invisible. Comprobar con `du -sh`, no con
> la interfaz.

---

## Teclado

```bash
sudo localectl set-x11-keymap latam pc105 "" terminate:ctrl_alt_bksp
```

Escribe `/etc/X11/xorg.conf.d/00-keyboard.conf` y `/etc/vconsole.conf`. El
greeter de SDDM **no lo hereda automáticamente**, ver
[troubleshooting](06-troubleshooting.md#distribución-de-teclado-del-greeter).

---

## Autologin

Lo usan la Titan y (opcionalmente) las laptops. Sin él, **ningún servicio
gráfico arranca hasta que alguien inicie sesión** — incluidos VNC y RDP.

```bash
sudo mkdir -p /etc/sddm.conf.d
printf '[Autologin]\nUser=x\nSession=hyprland-uwsm\nRelogin=false\n' \
  | sudo tee /etc/sddm.conf.d/zz-autologin.conf
```

El prefijo `zz-` importa: SDDM lee ese directorio en orden alfabético y **gana el
último**.

> Verifica que `uwsm` esté instalado **antes** de apuntar el autologin a
> `hyprland-uwsm`. Si la sesión no existe, SDDM entra en bucle de reintentos.

---

## Después

1. [end-4 y el post-install](02-end4.md)
2. [Acceso remoto](03-remote-access.md) — habilita SSH **primero**
