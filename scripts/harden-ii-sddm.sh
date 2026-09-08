#!/usr/bin/env bash
# Endurece la regla NOPASSWD que instala ii-sddm-theme.
#
# EL PROBLEMA
#   setup.sh crea /etc/sudoers.d/sddm-theme-$USER con:
#       $USER ALL=(ALL) NOPASSWD: /home/$USER/.config/ii-sddm-theme/sddm-theme-apply.sh
#   y copia ese script como el usuario, así que queda escribible por él.
#   Cualquier proceso corriendo como $USER puede reescribirlo y obtener root
#   sin contraseña. El objetivo de una regla NOPASSWD nunca debe ser escribible
#   por el usuario al que se le concede.
#
# LA SOLUCIÓN
#   El *código* que corre como root pasa a /usr/local/bin, propiedad de root.
#   Los *datos* que lee (Colors.qml, Settings.qml, generados por matugen) se
#   quedan en el home del usuario: matugen corre como él y tiene que poder
#   escribirlos. Eso es inherente al diseño y no es escalada a root — lo peor
#   que permite es influir en el QML que dibuja el greeter, que corre como el
#   usuario 'sddm', no como root.
#
# Idempotente. Correr DESPUÉS de setup.sh:  sudo ./harden-ii-sddm.sh
set -euo pipefail

THEME="ii-sddm-theme"
REAL_USER="${SUDO_USER:-$USER}"
USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

SRC_DIR="$USER_HOME/.config/$THEME"
OLD_SCRIPT="$SRC_DIR/sddm-theme-apply.sh"
NEW_SCRIPT="/usr/local/bin/sddm-theme-apply.sh"
SUDOERS="/etc/sudoers.d/sddm-theme-$REAL_USER"
MATUGEN_CONF="$USER_HOME/.config/matugen/config.toml"

[ "$(id -u)" -eq 0 ] || { echo "Corre con sudo." >&2; exit 1; }

# --- 1. El script a /usr/local/bin, de root ---
if [ -f "$OLD_SCRIPT" ]; then
    install -o root -g root -m 755 "$OLD_SCRIPT" "$NEW_SCRIPT"
    echo "[ok] copiado a $NEW_SCRIPT (root:root 755)"
elif [ -f "$NEW_SCRIPT" ]; then
    echo "[skip] $NEW_SCRIPT ya existe"
else
    echo "[ERROR] no encuentro $OLD_SCRIPT — ¿corriste setup.sh?" >&2; exit 1
fi

# --- 2. Fijar SCRIPT_DIR ---
# El original lo deriva de BASH_SOURCE; desde /usr/local/bin apuntaría ahí y no
# encontraría Colors.qml ni ii-sddm.conf. Se fija al directorio de datos.
if grep -q 'SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE\[0\]}")" && pwd)"' "$NEW_SCRIPT"; then
    sed -i 's|SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE\[0\]}")" \&\& pwd)"|SCRIPT_DIR="$USER_HOME/.config/ii-sddm-theme"  # fijado: el script vive en /usr/local/bin|' "$NEW_SCRIPT"
    echo "[ok] SCRIPT_DIR fijado al directorio de datos"
else
    grep -q 'fijado: el script vive' "$NEW_SCRIPT" \
        && echo "[skip] SCRIPT_DIR ya estaba fijado" \
        || { echo "[ERROR] no reconozco la línea de SCRIPT_DIR — revisar a mano" >&2; exit 1; }
fi

# --- 3. Sudoers apuntando al binario de root ---
tmp="$(mktemp)"
printf '%s ALL=(ALL) NOPASSWD: %s\n' "$REAL_USER" "$NEW_SCRIPT" > "$tmp"
if ! visudo -c -f "$tmp" >/dev/null 2>&1; then
    echo "[ERROR] regla de sudoers inválida, no se toca nada" >&2; rm -f "$tmp"; exit 1
fi
install -o root -g root -m 0440 "$tmp" "$SUDOERS"
rm -f "$tmp"
echo "[ok] $SUDOERS -> $NEW_SCRIPT"

# --- 4. El post_hook de matugen al binario nuevo ---
if [ -f "$MATUGEN_CONF" ] && grep -q "\.config/$THEME/sddm-theme-apply\.sh" "$MATUGEN_CONF"; then
    cp "$MATUGEN_CONF" "$MATUGEN_CONF.bak-harden"
    sed -i "s|sudo [^ ]*\.config/$THEME/sddm-theme-apply\.sh|sudo $NEW_SCRIPT|g" "$MATUGEN_CONF"
    chown "$REAL_USER":"$REAL_USER" "$MATUGEN_CONF"
    echo "[ok] post_hook de matugen actualizado (respaldo en config.toml.bak-harden)"
else
    echo "[skip] matugen no referencia la ruta vieja"
fi

# --- 5. Fuera el script viejo, para que no quede una copia obsoleta ---
if [ -f "$OLD_SCRIPT" ]; then
    rm -f "$OLD_SCRIPT"
    echo "[ok] eliminado $OLD_SCRIPT (los datos .qml/.conf se quedan)"
fi

echo
echo "=== Verificación ==="
ls -l "$NEW_SCRIPT"
echo -n "sudoers: "; cat "$SUDOERS"
echo -n "escribible por $REAL_USER? "
sudo -u "$REAL_USER" test -w "$NEW_SCRIPT" && echo "SÍ - MAL" || echo "no - correcto"
