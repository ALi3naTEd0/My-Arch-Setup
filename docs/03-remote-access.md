# Acceso remoto

Tres vías en paralelo, a propósito: si una se rompe, quedan dos.

| Vía | Puerto | Para qué |
|---|---|---|
| **SSH** | 22 | la red de seguridad — funciona sin sesión gráfica |
| **RDP** (hypr-rdp) | 3389 | trabajo diario: H.264, casi sin lag |
| **VNC** (wayvnc) | 5900 | respaldo, clientes que solo hablan VNC |

> **SSH es lo que hace reversible todo lo demás.** Habilítalo y verifica que
> entras **antes** de tocar la sesión gráfica. Si Hyprland, el greeter o el
> autologin se rompen, SSH sigue entrando. Salvó estas máquinas tres veces en un
> solo día.

---

## Tailscale

Con el tailnet, las máquinas se alcanzan desde cualquier red sin abrir puertos
en el router.

```bash
sudo systemctl enable --now tailscaled
sudo tailscale up
tailscale status
```

Se pierde al reinstalar el sistema — hay que volver a hacer `tailscale up`.

---

## SSH

```bash
sudo systemctl enable --now sshd
```

Autorizar una clave desde otra máquina:

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo 'ssh-ed25519 AAAA…' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Para comandos con `sudo` a través de SSH hace falta **`-t`**, que asigna una
terminal para que pueda pedir la contraseña:

```bash
ssh -t x@192.168.1.248 "sudo systemctl restart sddm"
```

---

## RDP · hypr-rdp

[MuNeNICK/hypr-rdp](https://github.com/MuNeNICK/hypr-rdp) — servidor RDP nativo
para Hyprland, en Rust. Requiere Hyprland 0.54+.

No necesita el portal `RemoteDesktop` (que
`xdg-desktop-portal-hyprland` **no implementa**): captura con
`wlr-screencopy-v1` e inyecta entrada con los protocolos de teclado y puntero
virtuales de Wayland. Por eso funciona donde `krdp` no.

```bash
paru -S hypr-rdp
```

### `~/.config/hypr-rdp/config.toml`

```toml
bind = "0.0.0.0:3389"

username = "x"
password = "…"          # texto plano -> chmod 600

output = "eDP-1"        # sin esto crea una pantalla virtual aparte
capture_mode = "wlr"

fps = 60                # el default es 30
bitrate = 20000000      # 30000000 si vas por cable
quality = 20            # menor = mejor
egfx_codec = "avc444"   # 4:4:4; "avc420" hace el texto borroso
h264_backend = "auto"

keyboard_layout_policy = "compositor"   # ver aviso abajo
audio_mode = "redirect"
```

```bash
chmod 600 ~/.config/hypr-rdp/config.toml
```

> **`keyboard_layout_policy` debe ir en `"compositor"`.** Con `"client"` aplica
> el layout que reporte el cliente al teclado virtual, ese teclado queda
> `main=True` y **tapa al físico**: la sesión entera se pone en US.

### Servicio

```ini
# ~/.config/systemd/user/hypr-rdp.service
[Unit]
Description=hypr-rdp
After=graphical-session.target
PartOf=graphical-session.target

[Service]
ExecStart=/usr/bin/hypr-rdp
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
```

```bash
systemctl --user enable --now hypr-rdp
```

Genera un certificado TLS autofirmado en `~/.config/hypr-rdp/` al arrancar; el
cliente avisará de que no es de confianza la primera vez.

### Codificación por hardware

`h264_backend = "auto"` intenta VA-API y cae a software.

| GPU | Resultado |
|---|---|
| Intel (QuickSync) | VA-API real, codifica por hardware |
| NVIDIA + `libva-nvidia-driver` | **solo decodifica** — acaba en software |

```bash
journalctl --user -u hypr-rdp.service -f    # dice cuál eligió al conectar
```

---

## VNC · wayvnc

```bash
paru -S wayvnc
```

```ini
# ~/.config/systemd/user/wayvnc.service
[Unit]
Description=WayVNC
After=graphical-session.target
PartOf=graphical-session.target

[Service]
ExecStart=/usr/bin/wayvnc -g -f 60 -p -k latam -o eDP-1 0.0.0.0 5900
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
```

Los cuatro flags importan:

| Flag | Por qué |
|---|---|
| `-g` | codificación acelerada por GPU. **Sin esto todo se comprime en CPU** y se nota muchísimo |
| `-f 60` | tope de fotogramas; el default deja las animaciones a tirones |
| `-k <layout>` | wayvnc traduce keysyms con **su propio** keymap, no el de Hyprland. Sin esto la ñ no funciona |
| `-p` | contadores de rendimiento al log |

> `wayvnc` no se autentica por defecto. Escuchando en `0.0.0.0`, cualquiera en
> la red llega al escritorio. En una red propia puede ser aceptable; en una wifi
> ajena no. Alternativa: enlazar solo a la IP del tailnet.

---

## RustDesk

```bash
paru -S rustdesk-bin
```

Códecs de vídeo modernos (VP8/VP9/H.264) y pasa la tecla `Super` sin
configuración — útil porque en end-4 casi todos los atajos son `SUPER+algo`. Con
Tailscale se conecta directo por IP, sin pasar por sus servidores públicos.

---

## Depende de uwsm

**Los tres servicios cuelgan de `graphical-session.target`**, que solo se activa
bajo uwsm. Sin uwsm ninguno arranca.

```bash
systemctl --user is-active graphical-session.target
```

Y sin autologin, la máquina se queda en el login: **ningún servicio gráfico
existe hasta que alguien inicie sesión**. Si vas a encender un equipo y
conectarte en remoto, necesitas autologin. Solo SSH funciona sin sesión.

---

## Antes de culpar al protocolo, mide la red

```bash
ping -c 40 -i 0.05 -q <ip>
```

Lo que arruina la fluidez no es el caudal sino el **jitter** (`mdev`). Ver los
números medidos y las causas en
[troubleshooting](06-troubleshooting.md#pero-primero-mide-la-red).
