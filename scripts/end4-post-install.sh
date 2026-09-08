#!/usr/bin/env bash
# Ajustes post-instalación de end-4 (illogical-impulse), derivados de migrar
# la Lenovo el 2026-08-29. Corregir DESPUÉS de `./setup install` y ANTES de
# reiniciar la sesión. Idempotente: se puede correr varias veces.
#
# Revierte las cosas que end-4 pisa y que en este equipo se quieren distintas.
set -u

KB_LAYOUT="${KB_LAYOUT:-es}"   # Titan usa "es"; la Lenovo usaba "latam"
C="$HOME/.config"

echo "== 1. HYPRLAND_CONFIG: evitar que HyDE secuestre el arranque =="
# HyDE lo inyecta desde DOS sitios: el hook de zsh y el de uwsm.
if [ -d "$C/zsh/conf.d" ] && [ ! -f "$C/zsh/conf.d/99-end4.zsh" ]; then
    cat > "$C/zsh/conf.d/99-end4.zsh" <<'ZSH'
# end-4: Hyprland debe leer ~/.config/hypr/hyprland.lua, no el hyde.lua de HyDE.
# (HyDE lo define en conf.d/hyde/env.zsh vía ~/.local/lib/hyde/shell/activate)
# Para volver a HyDE: borra este archivo.
typeset -gx HYPRLAND_CONFIG="$HOME/.config/hypr/hyprland.lua"
ZSH
    echo "   [ok] creado zsh/conf.d/99-end4.zsh"
else echo "   [skip] zsh override ya existe (o no hay conf.d)"; fi

if [ -d "$C/uwsm/env-hyprland.d" ] && [ ! -f "$C/uwsm/env-hyprland.d/99-end4.sh" ]; then
    cat > "$C/uwsm/env-hyprland.d/99-end4.sh" <<'SH'
#!/usr/bin/env sh
# end-4 bajo uwsm. Se carga después de 00-hyde.sh y redirige la config.
# IMPORTANTE: conviene MANTENER uwsm — sin él graphical-session.target no se
# activa y los servicios de usuario (p.ej. wayvnc) nunca arrancan.
export HYPRLAND_CONFIG="$HOME/.config/hypr/hyprland.lua"
SH
    echo "   [ok] creado uwsm/env-hyprland.d/99-end4.sh"
else echo "   [skip] uwsm override ya existe (o no hay uwsm)"; fi

echo "== 2. Teclado ($KB_LAYOUT) =="
if [ -f "$C/hypr/custom/general.lua" ] && ! grep -q 'kb_layout' "$C/hypr/custom/general.lua"; then
    cat >> "$C/hypr/custom/general.lua" <<LUA

-- Teclado local (end-4 trae "us" en hyprland/general.lua, archivo suyo que se
-- sobrescribe en cada update; aquí sí persiste).
hl.config({
    input = {
        kb_layout = "$KB_LAYOUT",
    },
})
LUA
    echo "   [ok] kb_layout = $KB_LAYOUT"
else echo "   [skip] ya configurado (o falta custom/general.lua)"; fi

echo "== 3. Sin suspensión por inactividad =="
if [ -f "$C/hypr/custom/execs.lua" ] && ! grep -q 'pkill -x hypridle' "$C/hypr/custom/execs.lua"; then
    cat >> "$C/hypr/custom/execs.lua" <<'LUA'

-- Sin dim/lock/suspend por inactividad (equivale al "modo-casa" de este equipo).
-- end-4 lanza hypridle en hyprland/execs.lua; aquí lo detenemos tras arrancar.
hl.on("hyprland.start", function()
    hl.exec_cmd("sleep 3 && pkill -x hypridle")
end)
LUA
    echo "   [ok] hypridle desactivado"
else echo "   [skip] ya configurado"; fi

echo "== 4. Atajo de la chuleta (SUPER+Slash es inalcanzable en es/latam) =="
if [ -f "$C/hypr/custom/keybinds.lua" ] && ! grep -q 'cheatsheetToggle' "$C/hypr/custom/keybinds.lua"; then
    cat >> "$C/hypr/custom/keybinds.lua" <<'LUA'

-- Chuleta de atajos en SUPER+H.
-- SUPER+Slash (nativo de end-4) es inalcanzable en es/latam: "/" requiere
-- Shift. Se usa hl.dsp.global igual que los binds nativos, para que el panel
-- reciba foco de teclado y Esc lo cierre.
hl.bind("SUPER + H", hl.dsp.global("quickshell:cheatsheetToggle"),
    { description = "Shell: Toggle cheatsheet (chuleta)" })
LUA
    echo "   [ok] SUPER+H para la chuleta"
else echo "   [skip] ya configurado"; fi

echo "== 5. kitty: no forzar fish (end-4 lo impone y pierdes el historial) =="
# 'shell .' = el shell de /etc/passwd. Se prefiere sobre poner "zsh" a pelo:
# en un equipo sin zsh instalado (p.ej. un Arch limpio sin HyDE) kitty no
# abriria ninguna terminal. Asi sigue al usuario si algun dia haces chsh.
if [ -f "$C/kitty/kitty.conf" ] && grep -qE '^shell (fish|zsh)$' "$C/kitty/kitty.conf"; then
    cp "$C/kitty/kitty.conf" "$C/kitty/kitty.conf.end4-bak"
    sed -i -E 's/^shell (fish|zsh)$/shell ./' "$C/kitty/kitty.conf"
    echo "   [ok] kitty -> shell de login ($(getent passwd "$USER" | cut -d: -f7)); respaldo en kitty.conf.end4-bak"
else echo "   [skip] kitty ya usa el shell de login (o no está configurado)"; fi

QS="$C/quickshell/ii"

echo "== 6. Notificaciones emergentes abiertas (no colapsadas a una línea) =="
NG="$QS/modules/common/widgets/NotificationGroup.qml"
if [ -f "$NG" ] && ! grep -q 'expanded: popup' "$NG"; then
    sed -i 's/^\( *\)property bool expanded: false$/\1property bool expanded: popup \/\/ Popups nacen abiertas; el centro de notificaciones sigue colapsado/' "$NG"
    grep -q 'expanded: popup' "$NG" \
        && echo "   [ok] popups abiertas (el centro sigue compacto)" \
        || echo "   [FALLO] no se encontró 'property bool expanded: false' — revisar a mano"
else echo "   [skip] ya aplicado (o falta NotificationGroup.qml)"; fi

echo "== 7. SUPER+A abre el lanzador (SUPER solo no viaja por VNC) =="
KB="$C/hypr/hyprland/keybinds.lua"
if [ -f "$KB" ] && ! grep -q 'Toggle search (lanzador)' "$KB"; then
    sed -i 's|^hl.bind("SUPER + A", hl.dsp.global("quickshell:sidebarLeftToggle").*$|-- SUPER+A abre la busqueda: pulsar SUPER solo (SUPER+SUPER_L) no se transmite\n-- por VNC. La barra lateral sigue en SUPER+B y SUPER+O, que hacian lo mismo.\nhl.bind("SUPER + A", hl.dsp.global("quickshell:searchToggle"), { description = "Shell: Toggle search (lanzador)" })|' "$KB"
    grep -q 'Toggle search (lanzador)' "$KB" \
        && echo "   [ok] SUPER+A = lanzador (barra lateral queda en SUPER+B / SUPER+O)" \
        || echo "   [FALLO] no se encontró el bind original — revisar a mano"
else echo "   [skip] ya aplicado"; fi

echo "== 8. Colores de kitty al estilo wallbash (4 tonos del wallpaper) =="
# Copias propias del extractor y la plantilla: sin esto se depende de que HyDE
# siga instalado. Se toman de HyDE solo si aún no existen las copias.
mkdir -p "$HOME/.local/lib/wallbash"
for pair in "wallbash.sh:$HOME/.local/lib/hyde/wallbash.sh" \
            "kitty.dcol:$HOME/HyDE/Configs/.local/share/wallbash/theme/kitty.dcol"; do
    dst="$HOME/.local/lib/wallbash/${pair%%:*}"; src="${pair#*:}"
    if [ ! -f "$dst" ] && [ -f "$src" ]; then cp "$src" "$dst"; echo "   [ok] copiado $(basename "$dst") desde HyDE"; fi
done
[ -f "$HOME/.local/lib/wallbash/wallbash.sh" ] && chmod +x "$HOME/.local/lib/wallbash/wallbash.sh"

# a) include en kitty.conf, DESPUES del de end-4 para ganarle.
#    Sin comentario al final: kitty se traga el resto de la línea como nombre.
if [ -f "$C/kitty/kitty.conf" ] && ! grep -q 'wallbash-theme.conf' "$C/kitty/kitty.conf"; then
    sed -i '/user\/generated\/terminal\/kitty-theme.conf/a # wallbash: va DESPUES del de end-4 para ganarle. Sin comentario al final:\n# kitty toma el resto de la linea como parte del nombre del archivo.\ninclude wallbash-theme.conf' "$C/kitty/kitty.conf"
    echo "   [ok] include añadido a kitty.conf"
else echo "   [skip] include ya presente"; fi

# b) engancharlo al cambio de wallpaper
AC="$QS/scripts/colors/applycolor.sh"
if [ -f "$AC" ] && ! grep -q 'wallbash-kitty' "$AC"; then
    cat >> "$AC" <<'EOF'

# Paleta de kitty al estilo wallbash (4 colores dominantes del wallpaper en vez
# de una paleta fija rotada hacia un solo acento). Se ejecuta al final para que
# su include gane. Si el script no existe, no pasa nada.
if [ -x "$HOME/.local/bin/wallbash-kitty.sh" ]; then
  "$HOME/.local/bin/wallbash-kitty.sh" >/dev/null 2>&1 &
fi
EOF
    echo "   [ok] hook añadido a applycolor.sh"
else echo "   [skip] hook ya presente"; fi

if [ ! -x "$HOME/.local/bin/wallbash-kitty.sh" ]; then
    echo "   [AVISO] falta ~/.local/bin/wallbash-kitty.sh — sin él kitty usa la paleta de end-4"
fi

echo "== 9. Indicador de actualizaciones en la barra (la familia ii no trae) =="
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

// Indicador de actualizaciones pendientes para la familia de paneles `ii`.
// La familia `waffle` ya tiene su UpdatesButton; el servicio Updates es
// compartido, asi que aqui solo hace falta la presentacion.
Item {
    id: root

    property color color: Appearance.colors.colOnLayer1
    // Visible con cualquier actualizacion pendiente. waffle solo lo muestra al
    // pasar adviseUpdateThreshold (75): no te enteras hasta llevar semanas sin
    // actualizar. Los umbrales siguen usandose para el color.
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

    // Tras lanzar la actualizacion el contador queda obsoleto hasta el siguiente
    // checkInterval (120 min). Se re-consulta para que el icono desaparezca solo.
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
                Updates.refresh(); // clic derecho: comprobar ahora
                return;
            }
            Quickshell.execDetached(["bash", "-c", Config.options.apps.update]);
            recheckTimer.remaining = 20; // ~10 min de re-comprobaciones
            recheckTimer.restart();
        }
    }
}
QML
    echo "   [ok] UpdatesIndicator.qml creado"
else echo "   [skip] ya existe (o falta modules/ii/bar)"; fi

# Insertarlo en la fila de indicadores de la barra
python3 - "$QS" <<'PY'
import os, sys
p = os.path.join(sys.argv[1], "modules/ii/bar/BarContent.qml")
if not os.path.isfile(p):
    print("   [skip] falta BarContent.qml"); raise SystemExit
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
    print("   [skip] ya insertado en BarContent.qml")
elif old not in s:
    print("   [FALLO] patron no encontrado en BarContent.qml - revisar a mano")
else:
    open(p, "w").write(s.replace(old, new, 1))
    print("   [ok] insertado en BarContent.qml")
PY

echo "== 10. El contador de updates ignora el AUR =="
python3 - "$QS" <<'PY'
import os, shutil, sys
p = os.path.join(sys.argv[1], "services/Updates.qml")
if not os.path.isfile(p):
    print("   [skip] falta Updates.qml"); raise SystemExit
s = open(p).read()
old = 'command: ["bash", "-c", "checkupdates | wc -l"]'
new = 'command: ["bash", "-c", "{ checkupdates; yay -Qua 2>/dev/null; } | wc -l"]'
if new in s:
    print("   [skip] ya cuenta el AUR")
elif old not in s:
    print("   [FALLO] patron no encontrado - revisar a mano")
else:
    shutil.copy(p, p + ".bak-aur")
    open(p, "w").write(s.replace(old, new, 1))
    print("   [ok] el contador suma repos + AUR")
PY
command -v yay >/dev/null || echo "   [AVISO] yay no esta instalado; el conteo AUR devolvera 0"

echo "== 11. Prompt: usar el de end-4, no el de HyDE =="
# HyDE sourcea ~/.config/zsh/prompt.zsh y respeta lo que devuelva: con 'return 1'
# cede el turno a su propio prompt. Comentandolo, manda este archivo.
# OJO: la linea de STARSHIP_CONFIG se deja comentada a proposito — apunta al
# toml de HyDE y volveria a secuestrar el prompt.
P="$C/zsh/prompt.zsh"
if [ -f "$P" ] && grep -q '^return 1' "$P"; then
    cp "$P" "$P.bak"
    sed -i 's|^return 1 # TODO|# return 1 # DESACTIVADO para usar el prompt de end-4 # TODO|' "$P"
    sed -i 's|^# eval "$(starship init zsh)"|eval "$(starship init zsh)"|' "$P"
    echo "   [ok] prompt de end-4 activado (respaldo en prompt.zsh.bak)"
else echo "   [skip] ya aplicado (o falta prompt.zsh)"; fi

echo "== 12. .zshrc en maquinas sin HyDE =="
# HyDE trae su propia cadena de arranque de zsh. En un Arch limpio no hay nada:
# zsh arranca con el prompt pelon de serie.
if [ -f "$HOME/.zshrc" ] || [ -f "$C/zsh/.zshrc" ]; then
    echo "   [skip] ya existe un .zshrc"
elif ! command -v zsh >/dev/null; then
    echo "   [skip] zsh no esta instalado"
else
    cat > "$HOME/.zshrc" <<'ZRC'
# Generado por end4-post-install.sh (maquina sin HyDE).
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

# Piezas de end-4, una por una. auto-Hypr.sh queda FUERA: hace
# 'exec start-hyprland' si entras por tty1 y con SDDM lanza una segunda sesion.
[ -f ~/.config/zshrc.d/dots-hyprland.zsh ] && source ~/.config/zshrc.d/dots-hyprland.zsh
[ -f ~/.config/zshrc.d/shortcuts.zsh ] && source ~/.config/zshrc.d/shortcuts.zsh

# starship lee ~/.config/starship.toml, que es el de end-4. No se define
# STARSHIP_CONFIG a proposito: apuntarlo a otro lado secuestra el prompt.
command -v starship >/dev/null && eval "$(starship init zsh)"

[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ] && \
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && \
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
ZRC
    echo "   [ok] ~/.zshrc creado"
fi

echo "== 13. Navegador: Zen en vez de Chrome =="
V="$C/hypr/custom/variables.lua"
if [ -f "$V" ] && grep -q '^browser' "$V"; then
    echo "   [skip] custom/variables.lua ya define browser"
elif [ -d "$C/hypr/custom" ]; then
    cat >> "$V" <<'LUA'

-- Navegador: Zen en vez de Chrome (end-4 prioriza google-chrome-stable en
-- hyprland/variables.lua, que es archivo suyo y se sobrescribe en updates).
browser = "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'zen-browser' 'google-chrome-stable' 'firefox' 'brave' 'chromium'"
LUA
    echo "   [ok] SUPER+W -> zen-browser"
else echo "   [skip] falta hypr/custom"; fi

# $BROWSER para herramientas de linea de comandos. uwsm NO lee directorios .d por
# su cuenta: lo habilita un bucle dentro de env-hyprland, que en maquinas con
# HyDE creo el. Sin HyDE hay que crearlo.
mkdir -p "$C/uwsm/env-hyprland.d"
if [ ! -f "$C/uwsm/env-hyprland" ]; then
    cat > "$C/uwsm/env-hyprland" <<'EOF'
# Sourceado por uwsm. Este bucle es lo que habilita el directorio .d.
for f in "${XDG_CONFIG_HOME:-$HOME/.config}"/uwsm/env-hyprland.d/*.sh; do
  [ -r "$f" ] && source "$f"
done
EOF
    echo "   [ok] creado uwsm/env-hyprland con el bucle .d"
fi
if [ ! -f "$C/uwsm/env-hyprland.d/70-browser.sh" ]; then
    printf '#!/usr/bin/env sh\n# Navegador para CLI (git web--browse, python webbrowser). Las apps graficas\n# usan mimeapps.list.\nexport BROWSER=zen-browser\n' > "$C/uwsm/env-hyprland.d/70-browser.sh"
    echo "   [ok] BROWSER=zen-browser"
else echo "   [skip] 70-browser.sh ya existe"; fi

echo "== 14. Comando de actualizar e intervalo (config.json) =="
python3 - <<'PY'
import json, os, shutil
p = os.path.expanduser("~/.config/illogical-impulse/config.json")
if not os.path.isfile(p):
    print("   [skip] falta config.json"); raise SystemExit
d = json.load(open(p))
cmd = ("kitty zsh -ic 'yay -Syu; echo; echo \"── Update finished. "
       "Press Enter to close ──\"; read'")
changed = []
# El de serie es `pkexec pacman -Syu` dentro de fish y NO funciona: pkexec no
# propaga la terminal a un comando interactivo. Ademas ignora el AUR.
if d.get("apps", {}).get("update") != cmd:
    d.setdefault("apps", {})["update"] = cmd; changed.append("apps.update")
# 120 min deja el contador tan obsoleto que parece roto.
if d.get("updates", {}).get("checkInterval") != 30:
    d.setdefault("updates", {})["checkInterval"] = 30; changed.append("checkInterval")
if changed:
    shutil.copy(p, p + ".bak-updates")
    json.dump(d, open(p, "w"), indent=2)
    print("   [ok] " + ", ".join(changed))
else:
    print("   [skip] ya configurado")
PY

echo "== 15. Limite de concurrencia del generador de miniaturas =="
# EL MAS IMPORTANTE. end-4 lanza un `magick` por archivo sin tope; con cientos de
# wallpapers eso agota la RAM, el OOM killer mata `qs` (oom_score_adj=200) y cae
# la sesion entera en bucle. Paso el 2026-09-07 en la HP: 5 logins y reinicio.
python3 - <<'PY'
import os, shutil
p = os.path.expanduser(
    "~/.config/quickshell/ii/scripts/thumbnails/generate-thumbnails-magick.sh")
if not os.path.isfile(p):
    print("   [skip] falta el script"); raise SystemExit
s = open(p).read()
if "MAGICK_MEMORY_LIMIT" in s:
    print("   [skip] ya parcheado"); raise SystemExit
old = """        for f in "$TARGET"/*; do
            [ -f "$f" ] || continue
            generate_thumbnail "$f" &
        done
        wait"""
new = """        # Un trabajo por nucleo. Sin tope, N wallpapers = N procesos `magick`, y
        # como ImageMagick se autoconfigura para poder usar TODA la RAM, el OOM
        # killer se lleva a quickshell y con el la sesion entera.
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
    print("   [FALLO] patron no encontrado - revisar a mano")
else:
    shutil.copy(p, p + ".bak-oom")
    open(p, "w").write(s.replace(old, new, 1))
    print("   [ok] concurrencia acotada a nproc (respaldo .bak-oom)")
PY

echo
echo "== Recordatorios =="
echo "  · Los binds de custom/keybinds.lua SOLO se cargan al ARRANCAR Hyprland."
echo "    'hyprctl reload' no los toma: hay que reiniciar la sesión."
echo "  · Mantén la sesión 'hyprland-uwsm' en SDDM (no la simple)."
echo "  · Limpia ~/.cache/yay después de instalar: la compilación deja ~75 GB."
echo "  · Prompt de 2 líneas: se ajusta en ~/.config/starship.toml si molesta."
echo "Listo."
