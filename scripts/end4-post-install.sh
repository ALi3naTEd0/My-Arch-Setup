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

echo
echo "== Recordatorios =="
echo "  · Los binds de custom/keybinds.lua SOLO se cargan al ARRANCAR Hyprland."
echo "    'hyprctl reload' no los toma: hay que reiniciar la sesión."
echo "  · Mantén la sesión 'hyprland-uwsm' en SDDM (no la simple)."
echo "  · Limpia ~/.cache/yay después de instalar: la compilación deja ~75 GB."
echo "  · Prompt de 2 líneas: se ajusta en ~/.config/starship.toml si molesta."
echo "Listo."
