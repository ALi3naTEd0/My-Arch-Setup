#!/usr/bin/env bash
# Colorea kitty al estilo wallbash de HyDE: extrae 4 colores dominantes del
# wallpaper con k-means y les asigna los slots ANSI, en vez de rotar una paleta
# fija hacia un único acento (que es lo que hace end-4 y deja todo de un tono).
#
# Reutiliza el extractor de HyDE (~/.local/lib/hyde/wallbash.sh) y su plantilla
# (~/HyDE/Configs/.local/share/wallbash/theme/kitty.dcol), que siguen instalados.
#
# Uso:  wallbash-kitty.sh [ruta-al-wallpaper] [-v|-p|-m]
#       Sin argumento toma el wallpaper actual de end-4.
set -uo pipefail

# Copias propias primero, para no depender de que HyDE siga instalado.
# Si algun dia las borras, cae de vuelta a las de HyDE mientras existan.
WALLBASH="$HOME/.local/lib/wallbash/wallbash.sh"
TEMPLATE="$HOME/.local/lib/wallbash/kitty.dcol"
[ -f "$WALLBASH" ] || WALLBASH="$HOME/.local/lib/hyde/wallbash.sh"
[ -f "$TEMPLATE" ] || TEMPLATE="$HOME/HyDE/Configs/.local/share/wallbash/theme/kitty.dcol"
STATE="$HOME/.local/state/quickshell/user/generated/wallpaper/path.txt"
OUT="$HOME/.config/kitty/wallbash-theme.conf"

PROFILE=()
WALL=""
for a in "$@"; do
    case "$a" in
        -v|--vibrant|-p|--pastel|-m|--mono) PROFILE=("$a") ;;
        *) WALL="$a" ;;
    esac
done
[ -z "$WALL" ] && WALL=$(cat "$STATE" 2>/dev/null)

for f in "$WALLBASH" "$TEMPLATE"; do
    [ -f "$f" ] || { echo "wallbash-kitty: falta $f" >&2; exit 1; }
done
[ -f "$WALL" ] || { echo "wallbash-kitty: wallpaper no encontrado: $WALL" >&2; exit 1; }

TMPDIR_=$(mktemp -d) || exit 1
trap 'rm -rf "$TMPDIR_"' EXIT

# ImageMagick se autoconfigura para poder usar TODA la RAM del equipo. En una
# maquina de 7.5 GB eso significa que un solo `magick` puede dejar al sistema
# sin memoria: el 2026-09-07 en la HP el kmeans de wallbash disparo el OOM
# killer, que mato a quickshell (oom_score_adj=200) y tumbo la sesion entera en
# bucle. Con un techo bajo, IM usa disco en vez de reventar.
export MAGICK_MEMORY_LIMIT="${MAGICK_MEMORY_LIMIT:-512MiB}"
export MAGICK_MAP_LIMIT="${MAGICK_MAP_LIMIT:-1GiB}"

# Se reduce ANTES de pasarsela a wallbash. Los 4 colores dominantes de una
# imagen de 512px son los mismos que los de una 4K -- el kmeans mira la
# distribucion de color, no el detalle -- pero cuesta ordenes de magnitud menos
# memoria y tiempo. El '>' solo encoge, nunca agranda; el [0] toma un unico
# fotograma (gif/webp animados, que si no se expanden enteros en RAM).
WORK="$TMPDIR_/wall.png"
if ! magick "$WALL[0]" -alpha off -resize '512x512>' "$WORK" 2>/dev/null; then
    echo "wallbash-kitty: no se pudo reducir, se usa el original" >&2
    cp "$WALL" "$WORK"
fi

# wallbash.sh escribe <base>.dcol y borra sus temporales
# -d fuerza modo oscuro. Sin esto, wallbash usa "auto": con un wallpaper claro
# invierte la paleta (fondo claro, texto oscuro), y como abajo forzamos el fondo
# a oscuro el resultado es texto oscuro sobre fondo oscuro: ilegible.
bash "$WALLBASH" -d "${PROFILE[@]}" "$WORK" "$TMPDIR_/wall" >/dev/null 2>&1
DCOL="$TMPDIR_/wall.dcol"
[ -s "$DCOL" ] || { echo "wallbash-kitty: no se generaron colores" >&2; exit 1; }

# shellcheck disable=SC1090
source "$DCOL"

# wallbash usa pry1 (el dominante mas oscuro) como fondo tal cual. En wallpapers
# de tono medio eso da un fondo demasiado claro y el texto se empasta. Se conserva
# el matiz pero se fija la luminosidad a un valor usable.
BG_MAX_V="${BG_MAX_V:-0.16}"   # si el fondo supera esto, se oscurece
BG_TARGET_V="${BG_TARGET_V:-0.11}"
dcol_pry1=$(python3 - "$dcol_pry1" "$BG_MAX_V" "$BG_TARGET_V" <<'PY'
import colorsys, sys
hexv, vmax, vtgt = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
r, g, b = (int(hexv[i:i+2], 16) / 255 for i in (0, 2, 4))
h, s, v = colorsys.rgb_to_hsv(r, g, b)
if v > vmax:
    v = vtgt
    s = min(1.0, s * 1.15)   # compensa el lavado al bajar el brillo
r, g, b = colorsys.hsv_to_rgb(h, s, v)
print("%02X%02X%02X" % (round(r*255), round(g*255), round(b*255)))
PY
)
dcol_pry1_rgba="rgba($((16#${dcol_pry1:0:2})),$((16#${dcol_pry1:2:2})),$((16#${dcol_pry1:4:2})),\1)"

# Como el fondo siempre queda oscuro, el texto tiene que quedar claro. Con un
# wallpaper claro wallbash decide lo contrario (fondo claro, texto oscuro) y
# quedaria texto oscuro sobre fondo oscuro: ilegible. Se sube txt1..txt4.
for n in 1 2 3 4; do
    var="dcol_txt$n"; val="${!var:-}"
    [ -z "$val" ] && continue
    newval=$(python3 - "$val" <<'PY'
import colorsys, sys
h_ = sys.argv[1]
r, g, b = (int(h_[i:i+2], 16) / 255 for i in (0, 2, 4))
h, s, v = colorsys.rgb_to_hsv(r, g, b)
if v < 0.75:            # demasiado oscuro para leerse sobre fondo oscuro
    v, s = 0.90, min(s, 0.12)
r, g, b = colorsys.hsv_to_rgb(h, s, v)
print("%02X%02X%02X" % (round(r*255), round(g*255), round(b*255)))
PY
)
    printf -v "$var" '%s' "$newval"
    printf -v "${var}_rgba" 'rgba(%d,%d,%d,\1)' \
        "$((16#${newval:0:2}))" "$((16#${newval:2:2}))" "$((16#${newval:4:2}))"
done

# La primera línea de la plantilla es la ruta de salida, no contenido.
TMP="$OUT.tmp.$$"
tail -n +2 "$TEMPLATE" > "$TMP"

# Sustituye <wallbash_XXX> por el valor de $dcol_XXX
while IFS= read -r slot; do
    var="dcol_${slot}"
    val="${!var:-}"
    [ -n "$val" ] && sed -i "s|<wallbash_${slot}>|${val}|g" "$TMP"
done < <(grep -ohE '<wallbash_[a-z0-9]+>' "$TMP" | tr -d '<>' | sed 's/^wallbash_//' | sort -u)

if grep -q '<wallbash_' "$TMP"; then
    echo "wallbash-kitty: quedaron slots sin resolver:" >&2
    grep -ohE '<wallbash_[a-z0-9]+>' "$TMP" | sort -u | sed 's/^/  /' >&2
    rm -f "$TMP"; exit 1
fi

mv "$TMP" "$OUT"

# end-4 emite sequences.txt (su propia paleta) a TODAS las /dev/pts abiertas desde
# apply_anyterm. Eso llega despues de que kitty cargue kitty.conf y sobreescribe
# los colores en vivo. Para que no se pisen, reescribimos sequences.txt con esta
# misma paleta: gane quien gane el orden, los colores son los mismos.
SEQ="$HOME/.local/state/quickshell/user/generated/terminal/sequences.txt"
if [ -f "$SEQ" ]; then
    seqtmp="$SEQ.tmp.$$"
    { for i in $(seq 0 15); do
        hex=$(grep -m1 "^color${i}[[:space:]]" "$OUT" | awk '{print $2}')
        [ -n "$hex" ] && printf '\033]4;%d;%s\033\\' "$i" "$hex"
      done
      bg=$(grep -m1 '^background[[:space:]]' "$OUT" | awk '{print $2}')
      fg=$(grep -m1 '^foreground[[:space:]]' "$OUT" | awk '{print $2}')
      [ -n "$fg" ] && printf '\033]10;%s\033\\' "$fg"
      [ -n "$bg" ] && printf '\033]11;%s\033\\' "$bg"
      [ -n "$fg" ] && printf '\033]12;%s\033\\' "$fg"
    } > "$seqtmp" && mv "$seqtmp" "$SEQ"
fi

pids=$(pgrep -x kitty) && [ -n "$pids" ] && kill -SIGUSR1 $pids
echo "wallbash-kitty: $OUT actualizado desde $(basename "$WALL")"
