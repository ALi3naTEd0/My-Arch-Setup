# Remote access

Three paths in parallel, on purpose: if one breaks, two remain.

| Path | Port | For what |
|---|---|---|
| **SSH** | 22 | the safety net — works with no graphical session |
| **RDP** (hypr-rdp) | 3389 | daily work: H.264, nearly no lag |
| **VNC** (wayvnc) | 5900 | fallback, clients that only speak VNC |

> **SSH is what makes everything else reversible.** Enable it and verify you can
> get in **before** touching the graphical session. If Hyprland, the greeter or
> autologin break, SSH still works. It saved these machines three times in a
> single day.

---

## Tailscale

With the tailnet, machines are reachable from any network without opening ports
on the router.

```bash
sudo systemctl enable --now tailscaled
sudo tailscale up
tailscale status
```

It is lost when reinstalling the OS — you have to run `tailscale up` again.

---

## SSH

```bash
sudo systemctl enable --now sshd
```

Authorize a key from another machine:

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo 'ssh-ed25519 AAAA…' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Running `sudo` commands over SSH needs **`-t`**, which allocates a terminal so
it can prompt for the password:

```bash
ssh -t x@192.168.1.248 "sudo systemctl restart sddm"
```

---

## RDP · hypr-rdp

[MuNeNICK/hypr-rdp](https://github.com/MuNeNICK/hypr-rdp) — native RDP server
for Hyprland, written in Rust. Requires Hyprland 0.54+.

It does not need the `RemoteDesktop` portal (which
`xdg-desktop-portal-hyprland` **does not implement**): it captures with
`wlr-screencopy-v1` and injects input through Wayland's virtual keyboard and
pointer protocols. That's why it works where `krdp` cannot.

```bash
paru -S hypr-rdp
```

### `~/.config/hypr-rdp/config.toml`

```toml
bind = "0.0.0.0:3389"

username = "x"
password = "…"          # plaintext -> chmod 600

output = "eDP-1"        # without this it creates a separate virtual display
capture_mode = "wlr"

fps = 60                # default is 30
bitrate = 20000000      # 30000000 on wired
quality = 20            # lower = better
egfx_codec = "avc420"   # see the codec note below
h264_backend = "auto"

keyboard_layout_policy = "compositor"   # see warning below
audio_mode = "redirect"
```

```bash
chmod 600 ~/.config/hypr-rdp/config.toml
```

> **`keyboard_layout_policy` must be `"compositor"`.** With `"client"` it
> applies whatever layout the client reports to the virtual keyboard, that
> keyboard becomes `main=True` and **shadows the physical one**: the whole
> session switches to US.

### Codec: pick per GPU

| GPU | H.264 encoding | Codec |
|---|---|---|
| Intel (QuickSync) | VA-API, **4:2:0 only** | `avc420` |
| NVIDIA + `libva-nvidia-driver` | **decode only** → software | `avc444` works |

`avc444` gives crisp text (full chroma) but **no Intel encoder supports it**.
Check before choosing:

```bash
vainfo | grep -iE "H264.*Enc"
```

On Intel, `avc420` is also the better performance choice: it keeps encoding on
QuickSync instead of falling back to libx264 on the CPU.

### Service

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

It generates a self-signed TLS certificate in `~/.config/hypr-rdp/` on startup;
the client will warn about it the first time.

```bash
journalctl --user -u hypr-rdp.service -f    # says which encoder it picked
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

All four flags matter:

| Flag | Why |
|---|---|
| `-g` | GPU-accelerated encoding. **Without it everything is compressed on the CPU** and the difference is obvious |
| `-f 60` | frame cap; the default leaves animations stuttering |
| `-k <layout>` | wayvnc translates keysyms with **its own** keymap, not Hyprland's. Without this, ñ doesn't work |
| `-p` | performance counters in the log |

> `wayvnc` does not authenticate by default. Listening on `0.0.0.0`, anyone on
> the network reaches the desktop. Acceptable on your own network, not on
> someone else's wifi. Alternative: bind only to the tailnet IP.

### Running VNC and RDP at the same time

Both capture the same output through `wlr-screencopy-v1` and **they coexist
fine** — all three machines run both services enabled. If frames stall, look at
the codec (see above) before suspecting a capture conflict.

---

## RustDesk

```bash
paru -S rustdesk-bin
```

Modern video codecs (VP8/VP9/H.264) and it passes the `Super` key without
configuration — handy because nearly every end-4 shortcut is `SUPER+something`.
With Tailscale it connects directly by IP, never touching their public relays.

---

## Everything depends on uwsm

**All three services hang off `graphical-session.target`**, which only activates
under uwsm. Without uwsm none of them start.

```bash
systemctl --user is-active graphical-session.target
```

And without autologin the machine sits at the login screen: **no graphical
service exists until someone signs in**. If you plan to power on a machine and
connect remotely, you need autologin. Only SSH works without a session.

Same applies to suspend: a suspended machine is **off the network entirely**,
not merely locked. Wake-on-LAN over wifi generally does not work.

---

## Before blaming the protocol, measure the network

```bash
ping -c 40 -i 0.05 -q <ip>
```

What ruins smoothness is not throughput but **jitter** (`mdev`). Measured
numbers and causes in
[troubleshooting](06-troubleshooting.md#but-measure-the-network-first).
