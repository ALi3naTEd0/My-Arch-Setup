#!/usr/bin/env bash
# Post-install tweaks for end-4 (illogical-impulse), derived from migrating
# the Lenovo on 2026-08-29. Run AFTER `./setup install` and BEFORE restarting
# the session. Idempotent: safe to run repeatedly.
#
# Reverts the things end-4 overwrites that these machines want differently.
set -u

KB_LAYOUT="${KB_LAYOUT:-es}"   # Titan uses "es"; the laptops use "latam"
C="$HOME/.config"

echo "== 1. HYPRLAND_CONFIG: keep HyDE from hijacking startup =="
# HyDE injects it from TWO places: the zsh hook and the uwsm one.
if [ -d "$C/zsh/conf.d" ] && [ ! -f "$C/zsh/conf.d/99-end4.zsh" ]; then
    cat > "$C/zsh/conf.d/99-end4.zsh" <<'ZSH'
# end-4: Hyprland must read ~/.config/hypr/hyprland.lua, not HyDE's hyde.lua.
# (HyDE sets it in conf.d/hyde/env.zsh via ~/.local/lib/hyde/shell/activate)
# To go back to HyDE: delete this file.
typeset -gx HYPRLAND_CONFIG="$HOME/.config/hypr/hyprland.lua"
ZSH
    echo "   [ok] created zsh/conf.d/99-end4.zsh"
else echo "   [skip] zsh override already present (or no conf.d)"; fi

if [ -d "$C/uwsm/env-hyprland.d" ] && [ ! -f "$C/uwsm/env-hyprland.d/99-end4.sh" ]; then
    cat > "$C/uwsm/env-hyprland.d/99-end4.sh" <<'SH'
#!/usr/bin/env sh
# end-4 under uwsm. Loads after 00-hyde.sh and redirects the config.
# IMPORTANT: KEEP uwsm -- without it graphical-session.target never activates
# and user services (wayvnc, hypr-rdp) never start.
export HYPRLAND_CONFIG="$HOME/.config/hypr/hyprland.lua"
SH
    echo "   [ok] created uwsm/env-hyprland.d/99-end4.sh"
else echo "   [skip] uwsm override already present (or no uwsm)"; fi

echo "== 2. Keyboard ($KB_LAYOUT) =="
if [ -f "$C/hypr/custom/general.lua" ] && ! grep -q 'kb_layout' "$C/hypr/custom/general.lua"; then
    cat >> "$C/hypr/custom/general.lua" <<LUA

-- Local keyboard (end-4 ships "us" in hyprland/general.lua, its own file,
-- overwritten on every update; this one persists).
hl.config({
    input = {
        kb_layout = "$KB_LAYOUT",
    },
})
LUA
    echo "   [ok] kb_layout = $KB_LAYOUT"
else echo "   [skip] already set (or custom/general.lua missing)"; fi

echo "== 3. Idle: lock and screen-off, but never suspend =="
# Locking does NOT touch the session: Hyprland, quickshell, wayvnc and hypr-rdp
# keep running behind the lock surface, so a remote client just sees the
# lockscreen and types the password. Suspending drops the machine off the
# network entirely, and Wake-on-LAN over wifi generally does not work -- which
# is why only that listener is removed instead of disabling hypridle wholesale.
#
# Set NO_IDLE=1 to get the old behaviour (no lock at all) on an always-on box.
# Set NO_DPMS=1 where the display is an external TV over HDMI: those often do
# not come back from DPMS on their own, leaving a black screen that no keypress
# recovers. Internal laptop panels (eDP) wake reliably, so this is per-machine.
HI="$C/hypr/hypridle.conf"
if [ "${NO_IDLE:-0}" = "1" ]; then
    if [ -f "$C/hypr/custom/execs.lua" ] && ! grep -q 'pkill -x hypridle' "$C/hypr/custom/execs.lua"; then
        cat >> "$C/hypr/custom/execs.lua" <<'LUA'

-- NO_IDLE: no dim/lock/suspend at all. end-4 launches hypridle in
-- hyprland/execs.lua; this stops it right after startup.
hl.on("hyprland.start", function()
    hl.exec_cmd("sleep 3 && pkill -x hypridle")
end)
LUA
        echo "   [ok] hypridle disabled (NO_IDLE=1)"
    else echo "   [skip] hypridle already disabled"; fi
elif [ -f "$HI" ]; then
    # hypridle.conf belongs to end-4, so `./setup install` restores the suspend
    # listener on every update. This has to run again each time.
    if grep -q 'timeout = 900' "$HI" || grep -q 'on-timeout = loginctl lock-session' "$HI" \
       || { [ "${NO_DPMS:-0}" = "1" ] && grep -q 'timeout = 600' "$HI"; }; then
        cp "$HI" "$HI.bak"
        python3 - "$HI" <<'PYEOF'
import os, re, sys
p = sys.argv[1]
s = open(p).read()
orig = s
# a) Drop the 15-minute suspend listener: suspending takes the machine off the
#    network entirely, and Wake-on-LAN over wifi generally does not work.
s = re.sub(r"listener \{\s*\n\s*timeout = 900.*?\n\}\n?", "", s, flags=re.S)
# b) The 5-minute listener ships as `loginctl lock-session`, which is a no-op
#    here: nothing answers logind's Lock signal, so the timer fires and nothing
#    locks. $lock_cmd uses the quickshell global, which does work. The symptom
#    is a machine that simply never locks, with no error anywhere.
s = s.replace("    timeout = 300 # 5mins\n    on-timeout = loginctl lock-session",
              "    timeout = 300 # 5mins\n    on-timeout = $lock_cmd")
# c) Optional: drop the screen-off listener too. An HDMI TV may not return from
#    DPMS without being switched on by hand.
if os.environ.get("NO_DPMS") == "1":
    s = re.sub(r"listener \{\s*\n\s*timeout = 600.*?\n\}\n?", "", s, flags=re.S)
open(p, "w").write(s)
print("   [ok] suspend listener dropped, 5-min lock rewired to $lock_cmd"
      + (", DPMS listener dropped" if os.environ.get("NO_DPMS") == "1" else "")
      if s != orig else "   [FAIL] neither pattern matched - check by hand")
PYEOF
    else echo "   [skip] already adjusted"; fi
    # Undo the old rule if a previous run of this script left it behind.
    if [ -f "$C/hypr/custom/execs.lua" ] && grep -q 'pkill -x hypridle' "$C/hypr/custom/execs.lua"; then
        cp "$C/hypr/custom/execs.lua" "$C/hypr/custom/execs.lua.bak"
        python3 - "$C/hypr/custom/execs.lua" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
s2 = re.sub(r"\n?--[^\n]*\n(--[^\n]*\n)*hl\.on\(\"hyprland\.start\", function\(\)\s*\n\s*hl\.exec_cmd\(\"sleep 3 && pkill -x hypridle\"\)\s*\nend\)\n?", "\n", s)
open(p, "w").write(s2)
print("   [ok] removed the old rule that killed hypridle"
      if s2 != s else "   [FAIL] could not remove it - check by hand")
PY
    fi
else echo "   [skip] no hypridle.conf"; fi

echo "== 4. Cheatsheet shortcut (SUPER+Slash is unreachable on es/latam) =="
if [ -f "$C/hypr/custom/keybinds.lua" ] && ! grep -q 'cheatsheetToggle' "$C/hypr/custom/keybinds.lua"; then
    cat >> "$C/hypr/custom/keybinds.lua" <<'LUA'

-- Shortcut cheatsheet on SUPER+H.
-- SUPER+Slash (end-4's own) is unreachable on es/latam: "/" needs Shift.
-- Uses hl.dsp.global like the native binds so the panel takes keyboard focus
-- and Esc closes it.
hl.bind("SUPER + H", hl.dsp.global("quickshell:cheatsheetToggle"),
    { description = "Shell: Toggle cheatsheet" })
LUA
    echo "   [ok] SUPER+H opens the cheatsheet"
else echo "   [skip] already set"; fi

echo "== 5. kitty: do not force fish (end-4 imposes it and you lose history) =="
# 'shell .' = the shell from /etc/passwd. Preferred over a bare "zsh":
# on a machine without zsh installed (a clean Arch with no HyDE) kitty would
# fail to open any terminal. This way it follows the user after a chsh.
if [ -f "$C/kitty/kitty.conf" ] && grep -qE '^shell (fish|zsh)$' "$C/kitty/kitty.conf"; then
    cp "$C/kitty/kitty.conf" "$C/kitty/kitty.conf.end4-bak"
    sed -i -E 's/^shell (fish|zsh)$/shell ./' "$C/kitty/kitty.conf"
    echo "   [ok] kitty -> login shell ($(getent passwd "$USER" | cut -d: -f7)); backup in kitty.conf.end4-bak"
else echo "   [skip] kitty already uses the login shell (or is not configured)"; fi

QS="$C/quickshell/ii"

echo "== 6. Notification popups expanded (not collapsed to one line) =="
NG="$QS/modules/common/widgets/NotificationGroup.qml"
if [ -f "$NG" ] && ! grep -q 'expanded: popup' "$NG"; then
    sed -i 's/^\( *\)property bool expanded: false$/\1property bool expanded: popup \/\/ Popups start expanded; the notification centre stays collapsed/' "$NG"
    grep -q 'expanded: popup' "$NG" \
        && echo "   [ok] popups expanded (the centre stays compact)" \
        || echo "   [FAIL] 'property bool expanded: false' not found -- check by hand"
else echo "   [skip] already applied (or NotificationGroup.qml missing)"; fi

echo "== 7. SUPER+A opens the launcher (a bare SUPER tap does not travel over VNC) =="
KB="$C/hypr/hyprland/keybinds.lua"
if [ -f "$KB" ] && ! grep -q 'SUPER + A", hl.dsp.global("quickshell:searchToggle"' "$KB"; then
    sed -i 's|^hl.bind("SUPER + A", hl.dsp.global("quickshell:sidebarLeftToggle").*$|-- SUPER+A opens search: tapping SUPER alone (SUPER+SUPER_L) is not transmitted\n-- over VNC. The left sidebar stays on SUPER+B and SUPER+O, which did the same.\nhl.bind("SUPER + A", hl.dsp.global("quickshell:searchToggle"), { description = "Shell: Toggle search" })|' "$KB"
    grep -q 'SUPER + A", hl.dsp.global("quickshell:searchToggle"' "$KB" \
        && echo "   [ok] SUPER+A = launcher (sidebar remains on SUPER+B / SUPER+O)" \
        || echo "   [FAIL] original bind not found -- check by hand"
else echo "   [skip] already applied"; fi

echo "== 8. kitty colors =="
# end-4 generates the terminal palette itself (scripts/colors/), and that is what
# these machines use. There used to be a wallbash pipeline here -- HyDE's k-means
# extractor writing a second theme file that kitty included AFTER end-4's so it
# would win. It worked, but it was a parallel pipeline fighting the built-in one,
# and it kept a HyDE dependency alive long after the migration.
#
# Set WALLBASH=1 to reinstate it (the scripts must already be in
# ~/.local/bin/wallbash-kitty.sh and ~/.local/lib/wallbash/).
if [ "${WALLBASH:-0}" = "1" ]; then
    if [ -f "$C/kitty/kitty.conf" ] && ! grep -q 'wallbash-theme.conf' "$C/kitty/kitty.conf"; then
        sed -i '/user\/generated\/terminal\/kitty-theme.conf/a # wallbash: goes AFTER end-4\x27s so it wins. No trailing comment:\n# kitty takes the rest of the line as part of the filename.\ninclude wallbash-theme.conf' "$C/kitty/kitty.conf"
        echo "   [ok] wallbash include added (WALLBASH=1)"
    else echo "   [skip] include already present"; fi
    AC="$QS/scripts/colors/applycolor.sh"
    if [ -f "$AC" ] && ! grep -q 'wallbash-kitty' "$AC"; then
        printf '\n# wallbash palette, hooked to the wallpaper change.\nif [ -x "$HOME/.local/bin/wallbash-kitty.sh" ]; then\n  "$HOME/.local/bin/wallbash-kitty.sh" >/dev/null 2>&1 &\nfi\n' >> "$AC"
        echo "   [ok] wallbash hook added"
    else echo "   [skip] hook already present"; fi
else
    # Default: make sure no wallbash leftovers override end-4's own palette.
    removed=0
    if grep -q 'wallbash-theme.conf' "$C/kitty/kitty.conf" 2>/dev/null; then
        cp "$C/kitty/kitty.conf" "$C/kitty/kitty.conf.bak-wallbash"
        python3 - <<'PYEOF'
import os, re
p = os.path.expanduser("~/.config/kitty/kitty.conf")
s = open(p).read()
s = re.sub(r"(?m)^# wallbash:.*\n(^# kitty takes.*\n)?", "", s)
s = re.sub(r"(?m)^include wallbash-theme\.conf\n", "", s)
open(p, "w").write(s)
PYEOF
        removed=1
    fi
    AC="$QS/scripts/colors/applycolor.sh"
    if grep -q 'wallbash-kitty' "$AC" 2>/dev/null; then
        cp "$AC" "$AC.bak-wallbash"
        python3 - "$AC" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r"\n# (kitty palette, wallbash style|wallbash palette|Paleta de kitty).*?\nfi\n", "\n", s, flags=re.S)
open(p, "w").write(s)
PYEOF
        removed=1
    fi
    rm -f "$C/kitty/wallbash-theme.conf"
    [ "$removed" = "1" ] && echo "   [ok] wallbash removed; end-4's palette wins" \
                         || echo "   [skip] already using end-4's palette"
fi

echo "== 9. Updates indicator in the bar (the ii panel family ships none) =="
UI="$QS/modules/ii/bar/UpdatesIndicator.qml"
if [ -d "$QS/modules/ii/bar" ] && [ ! -f "$UI" ]; then
    cat > "$UI" <<'QML'
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

// Pending-updates indicator for the `ii` panel family.
// The `waffle` family already has its UpdatesButton; the Updates service is
// shared, so only the presentation is needed here.
Item {
    id: root

    property color color: Appearance.colors.colOnLayer1
    // Visible with any pending update. waffle only shows it past
    // adviseUpdateThreshold (75): you don't find out until you've gone weeks
    // without updating. The thresholds are still used for the color.
    readonly property bool shouldShow: Updates.available && Updates.count > 0
    readonly property color effectiveColor: Updates.updateStronglyAdvised ? Appearance.colors.colOnSecondaryContainer : root.color

    implicitWidth: rowLayout.implicitWidth
    implicitHeight: rowLayout.implicitHeight

    RowLayout {
        id: rowLayout
        anchors.centerIn: parent
        spacing: 4

        MaterialSymbol {
            text: "sync"
            iconSize: Appearance.font.pixelSize.larger
            color: root.effectiveColor
        }

        StyledText {
            text: Updates.count
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.effectiveColor
        }
    }

    // After launching the update the counter is stale until the next
    // checkInterval. Re-query so the icon disappears on its own.
    Timer {
        id: recheckTimer
        interval: 30000
        repeat: true
        property int remaining: 0
        onTriggered: {
            Updates.refresh();
            remaining--;
            if (remaining <= 0) stop();
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                Updates.refresh(); // right click: check now
                return;
            }
            Quickshell.execDetached(["bash", "-c", Config.options.apps.update]);
            recheckTimer.remaining = 20; // ~10 min of re-checks
            recheckTimer.restart();
        }
    }
}
QML
    echo "   [ok] UpdatesIndicator.qml created"
else echo "   [skip] already exists (or modules/ii/bar missing)"; fi

# Insert it into the bar indicator row
python3 - "$QS" <<'PY'
import os, sys
p = os.path.join(sys.argv[1], "modules/ii/bar/BarContent.qml")
if not os.path.isfile(p):
    print("   [skip] BarContent.qml missing"); raise SystemExit
s = open(p).read()
old = """                    HyprlandXkbIndicator {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.rightMargin: indicatorsRowLayout.realSpacing
                        color: rightSidebarButton.colText
                    }"""
new = """                    Revealer {
                        reveal: updatesIndicator.shouldShow
                        Layout.fillHeight: true
                        Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
                        implicitHeight: reveal ? updatesIndicator.implicitHeight : 0
                        implicitWidth: reveal ? updatesIndicator.implicitWidth : 0
                        Behavior on Layout.rightMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        UpdatesIndicator {
                            id: updatesIndicator
                            color: rightSidebarButton.colText
                        }
                    }
""" + old
if "UpdatesIndicator" in s:
    print("   [skip] already inserted into BarContent.qml")
elif old not in s:
    print("   [FAIL] pattern not found in BarContent.qml - check by hand")
else:
    open(p, "w").write(s.replace(old, new, 1))
    print("   [ok] inserted into BarContent.qml")
PY

echo "== 10. The updates counter ignores the AUR =="
python3 - "$QS" <<'PY'
import os, shutil, sys
p = os.path.join(sys.argv[1], "services/Updates.qml")
if not os.path.isfile(p):
    print("   [skip] Updates.qml missing"); raise SystemExit
s = open(p).read()
old = 'command: ["bash", "-c", "checkupdates | wc -l"]'
new = 'command: ["bash", "-c", "{ checkupdates; yay -Qua 2>/dev/null; } | wc -l"]'
if new in s:
    print("   [skip] already counts the AUR")
elif old not in s:
    print("   [FAIL] pattern not found - check by hand")
else:
    shutil.copy(p, p + ".bak-aur")
    open(p, "w").write(s.replace(old, new, 1))
    print("   [ok] counter now sums repos + AUR")
PY
command -v yay >/dev/null || echo "   [WARN] yay is not installed; the AUR count will return 0"

echo "== 11. Prompt: use end-4's, not HyDE's =="
# HyDE sources ~/.config/zsh/prompt.zsh and honours what it returns: with
# 'return 1' it hands the turn to its own prompt. Commenting it out lets this
# file win.
# NOTE: the STARSHIP_CONFIG line is left commented on purpose -- it points at
# HyDE's toml and would hijack the prompt again.
P="$C/zsh/prompt.zsh"
if [ -f "$P" ] && grep -q '^return 1' "$P"; then
    cp "$P" "$P.bak"
    sed -i 's|^return 1 # TODO|# return 1 # DISABLED so end-4's prompt is used # TODO|' "$P"
    sed -i 's|^# eval "$(starship init zsh)"|eval "$(starship init zsh)"|' "$P"
    echo "   [ok] end-4 prompt enabled (backup in prompt.zsh.bak)"
else echo "   [skip] already applied (or prompt.zsh missing)"; fi

echo "== 12. .zshrc on machines without HyDE =="
# HyDE ships its own zsh startup chain. On a clean Arch there is nothing:
# zsh starts with the bare stock prompt.
if [ -f "$HOME/.zshrc" ] || [ -f "$C/zsh/.zshrc" ]; then
    echo "   [skip] a .zshrc already exists"
elif ! command -v zsh >/dev/null; then
    echo "   [skip] zsh is not installed"
else
    cat > "$HOME/.zshrc" <<'ZRC'
# Generated by end4-post-install.sh (machine without HyDE).
HISTFILE=~/.local/state/zsh/history
HISTSIZE=50000
SAVEHIST=50000
mkdir -p "${HISTFILE:h}"
setopt HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE HIST_VERIFY SHARE_HISTORY EXTENDED_HISTORY
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS

autoload -Uz compinit
compinit -d "${XDG_CACHE_HOME:-$HOME/.cache}/zcompdump"
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[3~' delete-char

# end-4 pieces, one by one. auto-Hypr.sh is LEFT OUT: it runs
# 'exec start-hyprland' if you log in on tty1, which under SDDM starts a
# second session on top of the one you already have.
[ -f ~/.config/zshrc.d/dots-hyprland.zsh ] && source ~/.config/zshrc.d/dots-hyprland.zsh
[ -f ~/.config/zshrc.d/shortcuts.zsh ] && source ~/.config/zshrc.d/shortcuts.zsh

# starship reads ~/.config/starship.toml, which is end-4's. STARSHIP_CONFIG is
# deliberately left unset: pointing it elsewhere hijacks the prompt.
command -v starship >/dev/null && eval "$(starship init zsh)"

[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ] && \
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && \
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
ZRC
    echo "   [ok] ~/.zshrc created"
fi

echo "== 13. Browser: Zen instead of Chrome =="
V="$C/hypr/custom/variables.lua"
if [ -f "$V" ] && grep -q '^browser' "$V"; then
    echo "   [skip] custom/variables.lua already defines browser"
elif [ -d "$C/hypr/custom" ]; then
    cat >> "$V" <<'LUA'

-- Browser: Zen instead of Chrome (end-4 prioritises google-chrome-stable in
-- hyprland/variables.lua, its own file, overwritten on updates).
browser = "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'zen-browser' 'google-chrome-stable' 'firefox' 'brave' 'chromium'"
LUA
    echo "   [ok] SUPER+W -> zen-browser"
else echo "   [skip] hypr/custom missing"; fi

# $BROWSER for command-line tools. uwsm does NOT read .d directories on its
# own: a loop inside env-hyprland enables them, and on HyDE machines HyDE
# created that file. Without HyDE it has to be created here.
mkdir -p "$C/uwsm/env-hyprland.d"
if [ ! -f "$C/uwsm/env-hyprland" ]; then
    cat > "$C/uwsm/env-hyprland" <<'EOF'
# Sourced by uwsm. This loop is what enables the .d directory.
for f in "${XDG_CONFIG_HOME:-$HOME/.config}"/uwsm/env-hyprland.d/*.sh; do
  [ -r "$f" ] && source "$f"
done
EOF
    echo "   [ok] created uwsm/env-hyprland with the .d loop"
fi
if [ ! -f "$C/uwsm/env-hyprland.d/70-browser.sh" ]; then
    printf '#!/usr/bin/env sh\n# Browser for CLI tools (git web--browse, python webbrowser). GUI apps use\n# mimeapps.list.\nexport BROWSER=zen-browser\n' > "$C/uwsm/env-hyprland.d/70-browser.sh"
    echo "   [ok] BROWSER=zen-browser"
else echo "   [skip] 70-browser.sh already exists"; fi

echo "== 14. Update command and check interval (config.json) =="
python3 - <<'PY'
import json, os, shutil
p = os.path.expanduser("~/.config/illogical-impulse/config.json")
if not os.path.isfile(p):
    print("   [skip] config.json missing"); raise SystemExit
d = json.load(open(p))
# --hold keeps the window open whatever happens inside: if yay fails
# instantly you see the error instead of a flash. The stock command is
# `pkexec pacman -Syu` inside fish, which cannot prompt for a password
# because pkexec does not pass a terminal, and ignores the AUR besides.
cmd = 'kitty --hold zsh -ic "yay -Syu"' 
changed = []
# The stock one is `pkexec pacman -Syu` inside fish and does NOT work: pkexec
# does not pass a terminal to an interactive command. It also ignores the AUR.
if d.get("apps", {}).get("update") != cmd:
    d.setdefault("apps", {})["update"] = cmd; changed.append("apps.update")
# 120 min leaves the counter so stale it looks broken.
if d.get("updates", {}).get("checkInterval") != 30:
    d.setdefault("updates", {})["checkInterval"] = 30; changed.append("checkInterval")
if changed:
    shutil.copy(p, p + ".bak-updates")
    json.dump(d, open(p, "w"), indent=2)
    print("   [ok] " + ", ".join(changed))
else:
    print("   [skip] already set")
PY

echo "== 15. Concurrency limit for the thumbnail generator =="
# THE IMPORTANT ONE. end-4 spawns one `magick` per file with no cap; with a few
# hundred wallpapers that exhausts RAM, the OOM killer takes out `qs`
# (oom_score_adj=200) and the whole session falls in a loop. Happened on the HP
# on 2026-09-07: five logins and a spontaneous reboot.
python3 - <<'PY'
import os, shutil
p = os.path.expanduser(
    "~/.config/quickshell/ii/scripts/thumbnails/generate-thumbnails-magick.sh")
if not os.path.isfile(p):
    print("   [skip] script missing"); raise SystemExit
s = open(p).read()
if "MAGICK_MEMORY_LIMIT" in s:
    print("   [skip] already patched"); raise SystemExit
old = """        for f in "$TARGET"/*; do
            [ -f "$f" ] || continue
            generate_thumbnail "$f" &
        done
        wait"""
new = """        # One job per core. With no cap, N wallpapers = N `magick` processes,
        # and since ImageMagick configures itself to be allowed ALL of RAM, the
        # OOM killer takes quickshell down and the session with it.
        export MAGICK_MEMORY_LIMIT="${MAGICK_MEMORY_LIMIT:-256MiB}"
        export MAGICK_MAP_LIMIT="${MAGICK_MAP_LIMIT:-512MiB}"
        jobs_max="$(nproc 2>/dev/null || echo 4)"
        for f in "$TARGET"/*; do
            [ -f "$f" ] || continue
            while [ "$(jobs -rp | wc -l)" -ge "$jobs_max" ]; do
                wait -n || true
            done
            generate_thumbnail "$f" &
        done
        wait"""
if old not in s:
    print("   [FAIL] pattern not found - check by hand")
else:
    shutil.copy(p, p + ".bak-oom")
    open(p, "w").write(s.replace(old, new, 1))
    print("   [ok] concurrency capped at nproc (backup .bak-oom)")
PY

echo "== 16. AI agent usage indicator =="
# Collectors live in ~/.local/bin/agent-usage-* and are vendored from Omarchy
# (MIT). The QML side is ours and follows the UpdatesIndicator pattern, so
# `./setup install` wipes it like everything else under quickshell/ii.
AU="$QS/services/AgentUsage.qml"
AI_IND="$QS/modules/ii/bar/AgentUsageIndicator.qml"
if [ ! -x "$HOME/.local/bin/agent-usage-claude" ] && [ ! -x "$HOME/.local/bin/agent-usage-codex" ]; then
    echo "   [skip] no collectors in ~/.local/bin/agent-usage-*"
elif [ -f "$AU" ] && [ -f "$AI_IND" ] && grep -q 'AgentUsageIndicator' "$QS/modules/ii/bar/BarContent.qml" 2>/dev/null; then
    echo "   [skip] already installed"
else
    echo "   [AVISO] falta reinstalar los QML: copialos de otra maquina o del repo"
    echo "           services/AgentUsage.qml, modules/ii/bar/AgentUsage{Indicator,Popup}.qml"
fi

# Insert into the bar indicator row, right after the updates indicator.
python3 - "$QS" <<'PYEOF'
import os, sys
p = os.path.join(sys.argv[1], "modules/ii/bar/BarContent.qml")
if not os.path.isfile(p):
    print("   [skip] BarContent.qml missing"); raise SystemExit
s = open(p).read()
if "AgentUsageIndicator" in s:
    print("   [skip] already in BarContent.qml"); raise SystemExit
if not os.path.isfile(os.path.join(sys.argv[1], "modules/ii/bar/AgentUsageIndicator.qml")):
    print("   [skip] AgentUsageIndicator.qml not present"); raise SystemExit
anchor = """                        UpdatesIndicator {
                            id: updatesIndicator
                            color: rightSidebarButton.colText
                        }
                    }
"""
block = anchor + """                    Revealer {
                        reveal: agentUsageIndicator.shouldShow
                        Layout.fillHeight: true
                        Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
                        implicitHeight: reveal ? agentUsageIndicator.implicitHeight : 0
                        implicitWidth: reveal ? agentUsageIndicator.implicitWidth : 0
                        Behavior on Layout.rightMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        AgentUsageIndicator {
                            id: agentUsageIndicator
                            color: rightSidebarButton.colText
                        }
                    }
"""
if anchor not in s:
    print("   [FAIL] UpdatesIndicator block not found - run step 9 first")
else:
    open(p, "w").write(s.replace(anchor, block, 1))
    print("   [ok] inserted into BarContent.qml")
PYEOF

echo "== 17. fastfetch: one config on every machine, coloured by end-4 =="
# Three machines, three different results before this:
#   Titan   - no config at all (HyDE's was renamed away) -> builtin layout
#   Lenovo  - HyDE's config still in place, calling `fastfetch.sh logo`
#   HP      - fresh install, no config -> default Arch logo, two colours
#
# The layout below is HyDE's, minus its two dependencies. Everything is a NAMED
# ansi colour (red/green/yellow/blue/magenta/cyan = palette slots 1..6), which
# is precisely what applycolor.sh repaints from the wallpaper -- so it tracks
# the theme by itself. Hardcoding hex is what would freeze it.
FF="$C/fastfetch/config.jsonc"
mkdir -p "$C/fastfetch"
if [ -f "$FF" ] && grep -q 'fastfetch.sh logo' "$FF"; then
    cp "$FF" "$FF.bak-hyde"
    echo "   backing up HyDE's config -> $(basename "$FF").bak-hyde"
fi
if [ -f "$FF" ] && ! grep -q 'fastfetch.sh logo' "$FF" && grep -q 'hyprctl splash' "$FF"; then
    echo "   [skip] already installed"
else
    cat > "$FF" <<'FFEOF'
/*
fastfetch for end-4 (illogical-impulse).

Layout is HyDE's, with its two dependencies removed:
  - the logo came from `fastfetch.sh logo` (a HyDE script) -> builtin logo
  - nothing here reads ~/.config/hyde or wallbash any more

Every colour is a NAMED ansi colour (red/green/yellow/blue/magenta/cyan =
palette slots 1..6). end-4 repaints exactly those slots from the wallpaper in
scripts/colors/applycolor.sh, so this config follows the theme on its own and
never needs regenerating. Hardcoding hex here is what would freeze it.
*/
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": {
    "type": "small",
    "padding": { "top": 1, "right": 3 }
  },
  "display": {
    "separator": " : "
  },
  "modules": [
    {
      "type": "command",
      "key": "  ",
      "keyColor": "blue",
      "text": "[ -n \"$HYPRLAND_INSTANCE_SIGNATURE\" ] && hyprctl splash 2>/dev/null || true"
    },
    {
      "type": "custom",
      "format": "┌──────────────────────────────────────────┐"
    },
    {
      "type": "chassis",
      "key": "  󰇺 Chassis",
      "format": "{1} {2} {3}"
    },
    {
      "type": "os",
      "key": "  󰣇 OS",
      "format": "{2}",
      "keyColor": "red"
    },
    {
      "type": "kernel",
      "key": "   Kernel",
      "format": "{2}",
      "keyColor": "red"
    },
    {
      "type": "packages",
      "key": "  󰏗 Packages",
      "keyColor": "green"
    },
    {
      "type": "display",
      "key": "  󰍹 Display",
      "format": "{1}x{2} @ {3}Hz [{7}]",
      "keyColor": "green"
    },
    {
      "type": "terminal",
      "key": "   Terminal",
      "keyColor": "yellow"
    },
    {
      "type": "wm",
      "key": "  󱗃 WM",
      "format": "{2}",
      "keyColor": "yellow"
    },
    {
      "type": "custom",
      "format": "└──────────────────────────────────────────┘"
    },
    "break",
    {
      "type": "title",
      "key": "  ",
      "format": "{6} {7} {8}"
    },
    {
      "type": "custom",
      "format": "┌──────────────────────────────────────────┐"
    },
    {
      "type": "cpu",
      "format": "{1} @ {7}",
      "key": "   CPU",
      "keyColor": "blue"
    },
    {
      "type": "gpu",
      "format": "{1} {2}",
      "key": "  󰊴 GPU",
      "keyColor": "blue"
    },
    {
      "type": "gpu",
      "format": "{3}",
      "key": "   GPU Driver",
      "keyColor": "magenta"
    },
    {
      "type": "memory",
      "key": "   Memory ",
      "keyColor": "magenta"
    },
    {
      "type": "disk",
      "key": "  󱦟 OS Age ",
      "folders": "/",
      "keyColor": "red",
      "format": "{days} days"
    },
    {
      "type": "uptime",
      "key": "  󱫐 Uptime ",
      "keyColor": "red"
    },
    {
      "type": "custom",
      "format": "└──────────────────────────────────────────┘"
    },
    {
      "type": "colors",
      "paddingLeft": 2,
      "symbol": "circle"
    },
    "break"
  ]
}
FFEOF
    echo "   [ok] $FF"
fi

# The palette only exists once applycolor.sh has run. On a machine where the
# wallpaper has not been changed since the install it never has, and the
# generated files sit there stale -- which is why the Lenovo still showed
# wallbash colours weeks later. Force one pass.
if [ -f "$C/quickshell/ii/scripts/colors/applycolor.sh" ]; then
    if bash "$C/quickshell/ii/scripts/colors/applycolor.sh" 2>/dev/null; then
        echo "   [ok] palette reapplied"
    else
        echo "   [AVISO] applycolor.sh failed: no material_colors.scss yet?"
        echo "           change the wallpaper once and rerun this step"
    fi
fi

echo
echo "== Reminders =="
echo "  - Binds in custom/keybinds.lua are ONLY loaded when Hyprland STARTS."
echo "    'hyprctl reload' does not pick them up: restart the session."
echo "  - Keep the 'hyprland-uwsm' session in SDDM (not the plain one)."
echo "  - Clean ~/.cache/yay after installing: the build leaves tens of GB."
echo "  - Two-line prompt: adjust in ~/.config/starship.toml if it bothers you."
echo "Done."
