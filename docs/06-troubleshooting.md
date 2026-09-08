# Troubleshooting

Fallos reales de estas tres máquinas. Cada uno incluye **el síntoma tal como se
percibe**, que casi nunca apunta a la causa.

---

## La sesión se cae en bucle · OOM por el generador de miniaturas

**Síntomas percibidos:** «no detecta el teclado», «el mouse va lentísimo», «no
funcionan los keybinds», la máquina se reinicia sola.

Los tres primeros son **el mismo fallo**: no hay compositor. Perseguimos el
greeter de SDDM un buen rato antes de mirar el journal de systemd.

**Causa.** `~/.config/quickshell/ii/scripts/thumbnails/generate-thumbnails-magick.sh`
lanza un `magick` por archivo **sin límite de concurrencia**:

```bash
for f in "$TARGET"/*; do
    generate_thumbnail "$f" &      # 954 wallpapers = 954 procesos
done
wait
```

ImageMagick se autoconfigura para poder usar **toda la RAM** del equipo
(`magick -list resource` reporta `Memory: 7.53GiB` en una máquina de 7.5 GB). El
OOM killer elige `qs` porque el slice de sesión lleva `oom_score_adj=200`, y al
morir quickshell cae la sesión entera.

```
kernel: magick invoked oom-killer
kernel: Out of memory: Killed process 4283 (qs)
systemd: wayland-wm@hyprland.desktop.service: Failed with result 'oom-kill'
```

**Diagnóstico rápido:**
```bash
journalctl -b | grep -iE "oom-kill|Killed process"
systemctl --user status wayland-wm@hyprland.desktop.service
```

**Arreglo** (lo aplica `end4-post-install.sh`): acotar a un trabajo por núcleo y
poner techo a ImageMagick. Afectó también a la máquina de 15 GiB — no basta con
tener RAM de sobra.

> El archivo lo sobrescribe `./setup install`. Sin reaplicar el parche, vuelve.

---

## btrfs: «No space left» con gigas libres

`df` miente. Lo que importa es **`Device unallocated`**:

```bash
btrfs filesystem usage /
```

Si `unallocated` se acerca a cero, los metadatos no pueden crecer aunque `Free
(estimated)` diga decenas de gigas. Sospechosos habituales, todos regenerables:

| Ruta | Qué es |
|---|---|
| `~/.cache/paru`, `~/.cache/yay`, `~/.cache/Shelly` | compilaciones del AUR |
| `~/.cache/hyde`, `~/.cache/dots-hyprland` | cachés de los dotfiles |
| `/var/cache/pacman/pkg` | paquetes descargados |
| `~/.local/share/Trash` | papelera (**datos tuyos**, revisar antes) |

```bash
paru -Sc --noconfirm
rm -rf ~/.cache/{paru,yay,Shelly,hyde,dots-hyprland}
sudo paccache -r        # conserva las 3 últimas versiones
sudo btrfs balance start -dusage=50 /
```

El `balance` es lo que devuelve espacio a `unallocated`.

---

## uwsm

**Sin uwsm, `graphical-session.target` nunca se activa** y ningún servicio de
usuario arranca — wayvnc, hypr-rdp y cualquier cosa con
`WantedBy=graphical-session.target` quedan muertos sin explicación.

```bash
systemctl --user is-active graphical-session.target   # debe decir "active"
```

En SDDM hay que elegir la sesión **«Hyprland (uwsm-managed)»**, no la simple. Y
`uwsm` es dependencia *opcional* de Hyprland: en un Arch limpio no está, aunque
`/usr/share/wayland-sessions/hyprland-uwsm.desktop` sí exista. Ese `.desktop` lo
trae el paquete `hyprland` y apunta a un binario que puede no existir.

### Variables de entorno de la sesión

uwsm **no lee directorios `.d` por su cuenta**. Lo que los habilita es un bucle
dentro de `~/.config/uwsm/env-hyprland`, que en las máquinas con HyDE creó él:

```sh
for f in "${XDG_CONFIG_HOME:-$HOME/.config}"/uwsm/env-hyprland.d/*.sh; do
  [ -r "$f" ] && source "$f"
done
```

En una máquina sin HyDE hay que crearlo a mano. Después, cada variable va en su
propio `~/.config/uwsm/env-hyprland.d/NN-loquesea.sh`.

---

## SDDM

### Pantalla negra al arrancar

**Causa:** tema sin `metadata.desktop`. Sin ese archivo SDDM no sabe qué versión
de Qt usar y cae al greeter **Qt5** (`/usr/bin/sddm-greeter`), que en un Arch
moderno no tiene sus librerías:

```
sddm[566]: Auth: sddm-helper exited with 127
ldd /usr/bin/sddm-greeter | grep "not found"    # libQt5Quick.so.5
```

Pasó con el tema `Corners` de HyDE. Los temas que funcionan declaran
`QtVersion=6` en su `metadata.desktop`.

**Recuperación** (por SSH desde otra máquina):
```bash
ssh -t x@IP "sudo rm /etc/sddm.conf.d/TEMA.conf && sudo systemctl restart sddm"
```

> El `-t` es lo que permite que `sudo` pida contraseña por SSH.

### Probar un tema ANTES de activarlo

Este es **el paso que evita la pantalla negra**:

```bash
QML2_IMPORT_PATH=/usr/share/sddm/themes/TEMA/Components/ \
QT_QPA_PLATFORM=wayland \
sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/TEMA
```

Las dos variables importan. `QML2_IMPORT_PATH` normalmente lo inyecta SDDM vía
`GreeterEnvironment` y **no existe al lanzar el greeter a mano** — sin ella el
tema se queda colgado en «Iniciando». Y `QT_QPA_PLATFORM=wayland` evita que Qt
intente el plugin `xcb` y aborte con «could not connect to display».

### Varios archivos definiendo el tema

SDDM lee `/etc/sddm.conf.d/*.conf` en **orden alfabético y el último gana**. En
máquinas que pasaron por HyDE, su `the_hyde_project.conf` trae `Current=Corners`
y se lee después que un `ii-sddm-theme.conf`. Solución: prefijo `zz-`.

```bash
ls /etc/sddm.conf.d/           # ver el orden real
grep -h Current= /etc/sddm.conf.d/*.conf
```

### Distribución de teclado del greeter

El indicador muestra `en` porque el greeter no lee tu layout. `Xsetup` corre como
root antes del login y **está en el array `backup` de pacman**, así que editarlo
sobrevive a las actualizaciones:

```bash
echo 'setxkbmap -model pc105 -layout latam -option terminate:ctrl_alt_bksp' \
  | sudo tee -a /usr/share/sddm/scripts/Xsetup
```

El código que verás después es `es` (el `shortDescription` que xkb asigna a
*Spanish (Latin American)*), no `latam`.

---

## Acceso remoto

### VNC: la ñ y los acentos no funcionan

Los clientes VNC mandan **keysyms**, y wayvnc los traduce con **su propio
keymap**, independiente del que tenga Hyprland. Sin `-k` usa el de fábrica (US).

```bash
wayvnc -k latam -o eDP-1 0.0.0.0 5900
```

### RDP: el teclado de la sesión se pone en US

hypr-rdp crea un teclado virtual y, con `keyboard_layout_policy = "client"`, le
aplica el layout **que reporta el cliente**. Ese teclado virtual queda
`main=True` y tapa al físico: la sesión entera pasa a US.

```toml
keyboard_layout_policy = "compositor"   # usa el layout de esta máquina
```

Comprobar:
```bash
hyprctl devices -j | python3 -c "
import json,sys
for k in json.load(sys.stdin)['keyboards']:
    print(k['name'], k['layout'], k['active_keymap'], k['main'])"
```

### Se ve borroso / con lag

Dos palancas distintas:

- **wayvnc sin `-g`** comprime en CPU. Con `-g -f 60` mejora de forma notable.
- **RDP con `egfx_codec = "avc420"`** usa croma 4:2:0 — el color se muestrea a
  un cuarto de resolución y el **texto sale con halos**. `avc444` lo arregla.

### …pero primero mide la red

El culpable suele ser el enlace, no el protocolo:

```bash
ping -c 40 -i 0.05 -q IP
```

Lo que importa no es el ancho de banda sino el **jitter** (`mdev`). Medido en
estas máquinas:

| | latencia media | pico | mdev |
|---|---|---|---|
| Lenovo | 1.8 ms | 25 ms | 3.9 ms |
| HP | 19.2 ms | **182 ms** | **39.8 ms** |

Ambas con ~276 Mbit/s de caudal. La HP se sentía mal por **estar en otro punto
de acceso**, con un salto extra entre routers. A 60 fps cada fotograma debe
llegar cada 16.7 ms; con picos de 182 ms no hay códec que lo arregle.

Sunshine/Moonlight es el **más** sensible al jitter porque sincroniza por
tiempo: descarta el fotograma que llega tarde. VNC es más tosco y más tolerante.

Ver también: `iwlmvm power_scheme` en 2 (equilibrado) hace dormir la radio —
firma típica: mínimo 0.8 ms pero media 19 ms.

---

## Residuos de HyDE

Tras migrar a end-4 quedan cosas de HyDE. **No todas estorban:**

| Ruta | Veredicto |
|---|---|
| `~/.local/lib/hyde/wallbash.sh` + plantillas `.dcol` | **útil** — lo usa `wallbash-kitty.sh` |
| `/usr/share/sddm/themes/{Corners,MacOS,…}` | sueltos, sin dueño (`pacman -Qo` no los reconoce) |
| `~/.config/zsh/conf.d/hyde/prompt.zsh` | **no borrar** — es quien sourcea `~/.config/zsh/prompt.zsh` |
| `~/.config/fish/conf.d/hyde.fish` | inofensivo si existe `functions/bind_M_n_history.fish` |
| `/etc/sddm.conf.d/the_hyde_project.conf` | causa el conflicto de temas de arriba |
| `~/.config/qt6ct.conf`, `~/.config/dunst/` | inertes; end-4 usa `kdeglobals` y su propio servicio |

### El prompt

HyDE sourcea `~/.config/zsh/prompt.zsh` y **respeta lo que devuelva**: con
`return 1` cede el turno a su propio prompt. Para que mande el de end-4:

```bash
sed -i 's|^return 1 # TODO|# return 1 # TODO|' ~/.config/zsh/prompt.zsh
sed -i 's|^# eval "$(starship init zsh)"|eval "$(starship init zsh)"|' ~/.config/zsh/prompt.zsh
```

**Dejar `STARSHIP_CONFIG` comentado a propósito** — apunta al `.toml` de HyDE y
volvería a secuestrar el prompt. Sin esa variable, starship lee
`~/.config/starship.toml`, que es el de end-4.

Para saber cuál está activo: `cmd_duration` solo existe en el toml de end-4.

---

## kitty

### No toma los colores nuevos al cambiar de wallpaper

`applycolor.sh` de end-4 escribía el tema con `>` (truncando) y luego lanzaba
`sed` sobre el archivo ya vacío. [PR #3627](https://github.com/end-4/dots-hyprland/pull/3627)
lo corrige con escritura atómica.

### El `include` no funciona

kitty **no admite comentarios en la misma línea** que un `include`: se traga el
resto de la línea como parte del nombre del archivo.

```
# mal:   include wallbash-theme.conf   # comentario
# bien:
# comentario en su propia línea
include wallbash-theme.conf
```

### `sequences.txt` pisa los colores

end-4 emite `sequences.txt` a **todas** las `/dev/pts` abiertas desde
`apply_anyterm`, después de que kitty haya cargado su config. `wallbash-kitty.sh`
reescribe ese archivo con la misma paleta para que gane quien gane, el resultado
sea idéntico.

---

## Miscelánea

**Hyprland no lleva `WAYLAND_DISPLAY` en su propio environ** (él crea el
display). En scripts y cron hay que leerlo del runtime dir:

```bash
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
WAYLAND_DISPLAY=$(ls "$XDG_RUNTIME_DIR" | grep -E '^wayland-[0-9]+$' | head -1)
```

**La instancia de Hyprland «más reciente» no siempre es la viva.** Quedan
directorios obsoletos en `$XDG_RUNTIME_DIR/hypr/`; hay que probar el socket:

```bash
for d in "$XDG_RUNTIME_DIR"/hypr/*/; do s=$(basename "$d")
  hyprctl -i "$s" version >/dev/null 2>&1 && SIG="$s" && break
done
```

**Los binds de `custom/keybinds.lua` solo se cargan al ARRANCAR Hyprland.**
`hyprctl reload` no los toma.

**`pkexec` no propaga la terminal** a comandos interactivos. Por eso el
`apps.update` de serie de end-4 no funciona y hay que cambiarlo por `sudo` o
`yay` en una kitty.

**El indicador de updates no aparece** si no hay actualizaciones pendientes:
`shouldShow: Updates.available && Updates.count > 0`. Comprobar con
`{ checkupdates; yay -Qua; } | wc -l` antes de darlo por roto.

**Teclado retroiluminado:** si `brightnessctl --list` y `/sys/class/leds/` no
muestran ningún `kbd_backlight`, el firmware no lo expone. El Pavilion 13-an1xxx
carga `hp_wmi` correctamente (als, display, dock, tablet) pero no ofrece teclado.
