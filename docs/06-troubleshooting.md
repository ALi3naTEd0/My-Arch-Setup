# Troubleshooting

Real failures from these three machines. Each one lists **the symptom as it is
actually perceived**, which almost never points at the cause.

---

## Session dies in a loop · OOM from the thumbnail generator

**Perceived symptoms:** "the keyboard isn't detected", "the mouse is super
slow", "the keybinds don't work", the machine reboots on its own.

The first three are **the same failure**: there is no compositor. We chased the
SDDM greeter for a while before looking at the systemd journal.

**Cause.** `~/.config/quickshell/ii/scripts/thumbnails/generate-thumbnails-magick.sh`
spawns one `magick` per file with **no concurrency limit**:

```bash
for f in "$TARGET"/*; do
    generate_thumbnail "$f" &      # 954 wallpapers = 954 processes
done
wait
```

ImageMagick configures itself to be allowed **all of the machine's RAM**
(`magick -list resource` reports `Memory: 7.53GiB` on a 7.5 GB box). The OOM
killer picks `qs` because the session slice carries `oom_score_adj=200`, and
when quickshell dies the whole session goes with it.

```
kernel: magick invoked oom-killer
kernel: Out of memory: Killed process 4283 (qs)
systemd: wayland-wm@hyprland.desktop.service: Failed with result 'oom-kill'
```

**Quick diagnosis:**
```bash
journalctl -b | grep -iE "oom-kill|Killed process"
systemctl --user status wayland-wm@hyprland.desktop.service
```

**Fix** (applied by `end4-post-install.sh`): cap at one job per core and put a
ceiling on ImageMagick. This also hit the 15 GiB machine — having plenty of RAM
is not enough.

> `./setup install` overwrites this file. Without reapplying the patch, it
> comes back.

---

## The screen never locks

hypridle runs, the config looks right, and nothing ever happens. `loginctl
show-session N -p LockedHint` stays `no` and no lock surface appears.

end-4's `hypridle.conf` ships the 5-minute listener as:

```
listener {
    timeout = 300 # 5mins
    on-timeout = loginctl lock-session
}
```

That asks logind to lock the session, and **nothing answers logind's Lock
signal** here — so the timer fires into the void. Meanwhile the file also
defines a `$lock_cmd` that does work, but only wires it to `general.lock_cmd`,
which hypridle runs when logind asks *it* to lock. A request that never comes.

Test the two paths apart:

```bash
loginctl lock-session 2                                    # no-op
hyprctl dispatch 'hl.dsp.global("quickshell:lock")'        # locks
```

Fix: point the listener at the command that works.

```
    on-timeout = $lock_cmd
```

`hypridle.conf` belongs to end-4, so `./setup install` restores the broken
version. Step 3 of the post-install reapplies it.

> Pick the session by `Type=wayland`, not `list-sessions | head -1` — the first
> row is usually the systemd user manager, and locking it returns
> *"Session does not support lock screen"*.

---

## Screen goes black and nothing brings it back

An external TV over HDMI may not return from DPMS on its own. hypridle's
10-minute listener turns the output off, and no keypress wakes it — you have to
switch the TV on or re-pick the input by hand. Internal laptop panels don't have
this problem.

Drop that listener where the display is a TV:

```bash
NO_DPMS=1 ~/.local/bin/end4-post-install.sh
```

Check what you're driving with `hyprctl monitors -j`: `eDP-1` is an internal
panel, `HDMI-A-1` or `DP-1` an external display.

> Locking is unaffected — the lock surface keeps the output on, so you still get
> the 5-minute lock without risking a screen you cannot wake.

---

## btrfs: "No space left" with gigabytes free

`df` lies. What matters is **`Device unallocated`**:

```bash
btrfs filesystem usage /
```

If `unallocated` approaches zero, metadata cannot grow even though `Free
(estimated)` reports tens of gigabytes. Usual suspects, all regenerable:

| Path | What it is |
|---|---|
| `~/.cache/paru`, `~/.cache/yay`, `~/.cache/Shelly` | AUR build trees |
| `~/.cache/hyde`, `~/.cache/dots-hyprland` | dotfiles caches |
| `/var/cache/pacman/pkg` | downloaded packages |
| `~/.local/share/Trash` | trash (**your data** — review first) |

```bash
paru -Sc --noconfirm
rm -rf ~/.cache/{paru,yay,Shelly,hyde,dots-hyprland}
sudo paccache -r        # keeps the last 3 versions
sudo btrfs balance start -dusage=50 /
```

The `balance` is what returns space to `unallocated`.

---

## uwsm

**Without uwsm, `graphical-session.target` never activates** and no user service
starts — wayvnc, hypr-rdp and anything with `WantedBy=graphical-session.target`
sits dead with no explanation.

```bash
systemctl --user is-active graphical-session.target   # must say "active"
```

In SDDM you must pick the **"Hyprland (uwsm-managed)"** session, not the plain
one. And `uwsm` is an *optional* dependency of Hyprland: on a clean Arch it is
absent even though `/usr/share/wayland-sessions/hyprland-uwsm.desktop` exists.
That `.desktop` ships with the `hyprland` package and points at a binary that
may not be installed.

### Session environment variables

uwsm **does not read `.d` directories on its own**. What enables them is a loop
inside `~/.config/uwsm/env-hyprland`, which on HyDE machines HyDE itself created:

```sh
for f in "${XDG_CONFIG_HOME:-$HOME/.config}"/uwsm/env-hyprland.d/*.sh; do
  [ -r "$f" ] && source "$f"
done
```

On a machine without HyDE you have to create it. After that, each variable goes
in its own `~/.config/uwsm/env-hyprland.d/NN-whatever.sh`.

---

## SDDM

### Black screen at boot

**Cause:** a theme with no `metadata.desktop`. Without that file SDDM cannot
tell which Qt version to use and falls back to the **Qt5** greeter
(`/usr/bin/sddm-greeter`), which on a modern Arch has no libraries:

```
sddm[566]: Auth: sddm-helper exited with 127
ldd /usr/bin/sddm-greeter | grep "not found"    # libQt5Quick.so.5
```

This happened with HyDE's `Corners` theme. Working themes declare
`QtVersion=6` in their `metadata.desktop`.

**Recovery** (over SSH from another machine):
```bash
ssh -t x@IP "sudo rm /etc/sddm.conf.d/THEME.conf && sudo systemctl restart sddm"
```

> The `-t` is what lets `sudo` prompt for a password over SSH.

### Test a theme BEFORE enabling it

This is **the step that prevents the black screen**:

```bash
QML2_IMPORT_PATH=/usr/share/sddm/themes/THEME/Components/ \
QT_QPA_PLATFORM=wayland \
sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/THEME
```

Both variables matter. `QML2_IMPORT_PATH` is normally injected by SDDM through
`GreeterEnvironment` and **does not exist when launching the greeter by hand** —
without it the theme hangs at "Starting". And `QT_QPA_PLATFORM=wayland` keeps Qt
from trying the `xcb` plugin and aborting with "could not connect to display".

### Several files setting the theme

SDDM reads `/etc/sddm.conf.d/*.conf` in **alphabetical order, and the last one
wins**. On machines that came from HyDE, its `the_hyde_project.conf` carries
`Current=Corners` and is read after an `ii-sddm-theme.conf`. Fix: a `zz-` prefix.

```bash
ls /etc/sddm.conf.d/           # see the real order
grep -h Current= /etc/sddm.conf.d/*.conf
```

### Greeter keyboard layout

The indicator shows `en` because the greeter does not read your layout. `Xsetup`
runs as root before the login and **is in pacman's `backup` array**, so editing
it survives updates:

```bash
echo 'setxkbmap -model pc105 -layout latam -option terminate:ctrl_alt_bksp' \
  | sudo tee -a /usr/share/sddm/scripts/Xsetup
```

The code you'll see afterwards is `es` — the `shortDescription` xkb assigns to
*Spanish (Latin American)* — not `latam`.

---

## Remote access

### VNC: ñ and accents don't work

VNC clients send **keysyms**, and wayvnc translates them with **its own
keymap**, independent of Hyprland's. Without `-k` it uses the built-in default
(US).

```bash
wayvnc -k latam -o eDP-1 0.0.0.0 5900
```

### RDP: the session keyboard switches to US

hypr-rdp creates a virtual keyboard and, with
`keyboard_layout_policy = "client"`, applies **the layout the client reports**.
That virtual keyboard ends up `main=True` and shadows the physical one: the
whole session goes US.

```toml
keyboard_layout_policy = "compositor"   # use this machine's layout
```

Check with:
```bash
hyprctl devices -j | python3 -c "
import json,sys
for k in json.load(sys.stdin)['keyboards']:
    print(k['name'], k['layout'], k['active_keymap'], k['main'])"
```

### RDP: white screen

`egfx_codec = "avc444"` is 4:4:4 chroma, and **Intel's H.264 encoder is 4:2:0
only**. Check what the hardware actually supports:

```bash
vainfo | grep -iE "H264.*Enc"
```

On the HP, VA-API AVC444 fails and falls back cleanly to software libx264; on
the Lenovo the fallback does not work and you get a white screen. Use `avc420`
on Intel — it's also the better performance choice, since it keeps encoding on
QuickSync instead of the CPU.

### Blurry or laggy

Two different levers:

- **wayvnc without `-g`** compresses on the CPU. `-g -f 60` is a large
  improvement.
- **RDP with `egfx_codec = "avc420"`** uses 4:2:0 chroma — color is sampled at
  quarter resolution and **text gets colored fringes**. `avc444` fixes it, but
  only where the encoder supports it (see above).

### …but measure the network first

The culprit is usually the link, not the protocol:

```bash
ping -c 40 -i 0.05 -q IP
```

What matters is not bandwidth but **jitter** (`mdev`). Measured on these
machines:

| | avg latency | peak | mdev |
|---|---|---|---|
| Lenovo | 1.8 ms | 25 ms | 3.9 ms |
| HP | 19.2 ms | **182 ms** | **39.8 ms** |

Both at ~276 Mbit/s of throughput. The HP felt bad because it sits on **a
different access point**, with an extra hop between routers. At 60 fps a frame
must arrive every 16.7 ms; with 182 ms peaks no codec can save you.

Sunshine/Moonlight is the **most** jitter-sensitive of all, because it
synchronises by time and discards frames that arrive late. VNC is cruder and
more tolerant.

Also worth checking: `iwlmvm power_scheme` at 2 (balanced) puts the radio to
sleep — typical signature is a 0.8 ms minimum against a 19 ms average.

---

## HyDE leftovers

After migrating to end-4 some HyDE pieces remain. **Not all of them are in the
way:**

| Path | Verdict |
|---|---|
| `~/.local/lib/hyde/wallbash.sh` + `.dcol` templates | **useful** — `wallbash-kitty.sh` uses them |
| `/usr/share/sddm/themes/{Corners,MacOS,…}` | loose, unowned (`pacman -Qo` doesn't know them) |
| `~/.config/zsh/conf.d/hyde/prompt.zsh` | **do not delete** — it is what sources `~/.config/zsh/prompt.zsh` |
| `~/.config/fish/conf.d/hyde.fish` | harmless as long as `functions/bind_M_n_history.fish` exists |
| `/etc/sddm.conf.d/the_hyde_project.conf` | causes the theme conflict above |
| `~/.config/qt6ct.conf`, `~/.config/dunst/` | inert; end-4 uses `kdeglobals` and its own service |

### The prompt

HyDE sources `~/.config/zsh/prompt.zsh` and **honours whatever it returns**:
with `return 1` it hands the turn to its own prompt. To let end-4's win:

```bash
sed -i 's|^return 1 # TODO|# return 1 # TODO|' ~/.config/zsh/prompt.zsh
sed -i 's|^# eval "$(starship init zsh)"|eval "$(starship init zsh)"|' ~/.config/zsh/prompt.zsh
```

**Leave `STARSHIP_CONFIG` commented out on purpose** — it points at HyDE's
`.toml` and would hijack the prompt again. Without that variable, starship reads
`~/.config/starship.toml`, which is end-4's.

To tell which one is active: `cmd_duration` only exists in end-4's toml.

---

## kitty

### Doesn't pick up new colors on wallpaper change

end-4's `applycolor.sh` wrote the theme with `>` (truncating) and then ran `sed`
against the already-empty file. [PR #3627](https://github.com/end-4/dots-hyprland/pull/3627)
fixes it with an atomic write.

### The `include` doesn't work

kitty **does not accept comments on the same line** as an `include`: it swallows
the rest of the line as part of the filename.

```
# wrong:  include wallbash-theme.conf   # comment
# right:
# comment on its own line
include wallbash-theme.conf
```

### `sequences.txt` overrides the colors

end-4 emits `sequences.txt` to **every** open `/dev/pts` from `apply_anyterm`,
after kitty has already loaded its config. So the escape sequences, not
`kitty-theme.conf`, are what you end up looking at in an already-open terminal.

While wallbash was still in the chain, `wallbash-kitty.sh` deliberately rewrote
that file with its own palette so the two couldn't disagree. **After removing
wallbash that rewrite is what freezes the old colors**: nothing regenerates
`sequences.txt` until `applycolor.sh` runs again, and `applycolor.sh` only runs
on a wallpaper change. The Lenovo sat on a wallbash palette from 2026-09-08 for
three days that way — `kitty-theme.conf` said `#181B1E`, `sequences.txt` said
`#293952`, and the sequences won.

Tell them apart without guessing: end-4's file carries the 232–255 slots and an
`]1;0;` entry right after `]4;0;`; wallbash's has neither and stops at 15.

```bash
wc -c ~/.local/state/quickshell/user/generated/terminal/sequences.txt
# 726 = end-4's   ·   288 = wallbash's
```

Force one pass without touching the wallpaper:

```bash
bash ~/.config/quickshell/ii/scripts/colors/applycolor.sh
```

---

## fastfetch

### Two colors on a fresh install, HyDE's colors on an old one

Three machines gave three different results for the same command:

| | `~/.config/fastfetch/config.jsonc` | what you see |
|---|---|---|
| Titan | renamed to `.bak-hyde` | fastfetch's builtin layout |
| Lenovo | **still HyDE's** | HyDE layout, calls `fastfetch.sh logo` |
| HP | never existed | default Arch logo — two colors |

The "two colors" on a new install is not a theming failure: with no config,
fastfetch draws its builtin Arch logo, which is cyan plus the default key color.
Nothing is reading the wallpaper palette because nothing asked it to.

Step 17 of [`end4-post-install.sh`](../scripts/end4-post-install.sh) installs one
[`config.jsonc`](../config/fastfetch/config.jsonc) on all three: HyDE's layout
with its two dependencies removed (`fastfetch.sh logo` → builtin logo, nothing
under `~/.config/hyde`).

**Every color in it is a named ansi color** — `red`, `green`, `yellow`, `blue`,
`magenta`, `cyan` — which are palette slots 1–6, exactly the slots
`applycolor.sh` repaints from the wallpaper. So the config follows the theme on
its own and never needs regenerating. Hardcoding hex is what would freeze it,
which is the same mistake that froze `sequences.txt` above.

### Same config, different logo

The Titan kept drawing the large Arch logo after the shared config was in place,
while the Lenovo drew the small one from the same file. The config was not the
problem — the shell was:

```bash
grep -rn "alias fastfetch" ~/.config/zsh/conf.d/hyde/terminal.zsh
# alias fastfetch='fastfetch --logo-type kitty'
```

`--logo-type kitty` overrides `logo.type` in the config. It comes from **HyDE's
zsh framework**, which the Titan still runs (see below); the laptops don't have
it, so they never saw the override. Step 1 appends `unalias fastfetch` to
`conf.d/99-end4.zsh`, which is sourced after `conf.d/hyde/*`.

> Worth knowing when reading any zsh problem on these machines: the Titan's
> `ZDOTDIR` is `~/.config/zsh` (set in `~/.zshenv`), so **`~/.zshrc` is never
> sourced there** — it's a leftover oh-my-zsh file that looks live and isn't.
> The live one is `~/.config/zsh/.zshrc`.

The `hyprctl splash` module is guarded on `$HYPRLAND_INSTANCE_SIGNATURE`:
unguarded it prints *"is hyprland running?"* as the first line of every fastfetch
over SSH, and `2>/dev/null` does not catch it — `hyprctl` writes that to stdout.

---

## Miscellaneous

**Hyprland does not carry `WAYLAND_DISPLAY` in its own environ** (it creates the
display). In scripts and cron, read it from the runtime dir:

```bash
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
WAYLAND_DISPLAY=$(ls "$XDG_RUNTIME_DIR" | grep -E '^wayland-[0-9]+$' | head -1)
```

**The "most recent" Hyprland instance is not always the live one.** Stale
directories linger in `$XDG_RUNTIME_DIR/hypr/`; probe the socket instead:

```bash
for d in "$XDG_RUNTIME_DIR"/hypr/*/; do s=$(basename "$d")
  hyprctl -i "$s" version >/dev/null 2>&1 && SIG="$s" && break
done
```

**Binds in `custom/keybinds.lua` are only loaded when Hyprland STARTS.**
`hyprctl reload` does not pick them up.

**`pkexec` does not pass a terminal** to interactive commands. That's why
end-4's stock `apps.update` doesn't work and has to be swapped for `sudo` or
`yay` inside a kitty.

**The updates indicator doesn't appear** when there is nothing pending:
`shouldShow: Updates.available && Updates.count > 0`. Check with
`{ checkupdates; yay -Qua; } | wc -l` before assuming it's broken.

**Keyboard backlight:** if `brightnessctl --list` and `/sys/class/leds/` show no
`kbd_backlight`, the firmware doesn't expose it. The Pavilion 13-an1xxx loads
`hp_wmi` correctly (als, display, dock, tablet) but offers no keyboard control.

**Orphaned trash files:** if a file exists in `~/.local/share/Trash/files/` but
its `.trashinfo` does not in `info/`, **the graphical file manager will not list
it** and the space is invisible. Check with `du -sh`, not the UI.
