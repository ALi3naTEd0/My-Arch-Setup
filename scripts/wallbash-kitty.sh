#!/usr/bin/env bash
# Colors kitty HyDE's wallbash way: pulls 4 dominant colors from the wallpaper
# with k-means and assigns them to the ANSI slots, instead of rotating a fixed
# palette toward a single accent (what end-4 does, leaving everything one hue).
#
# Reuses HyDE's extractor and template, vendored into ~/.local/lib/wallbash/.
#
# Usage:  wallbash-kitty.sh [path-to-wallpaper] [-v|-p|-m]
#         With no argument it takes end-4's current wallpaper.
set -uo pipefail

# Vendored copies first, so nothing depends on HyDE staying installed.
# If they are ever removed, it falls back to HyDE's while those exist.
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
    [ -f "$f" ] || { echo "wallbash-kitty: missing $f" >&2; exit 1; }
done
[ -f "$WALL" ] || { echo "wallbash-kitty: wallpaper not found: $WALL" >&2; exit 1; }

TMPDIR_=$(mktemp -d) || exit 1
trap 'rm -rf "$TMPDIR_"' EXIT

# ImageMagick configures itself to be allowed ALL of the machine's RAM. On a
# 7.5 GB box that means a single `magick` can starve the system: on 2026-09-07
# wallbash's kmeans triggered the OOM killer on the HP, which killed quickshell
# (oom_score_adj=200) and brought the whole session down in a loop. With a low
# ceiling, IM spills to disk instead of blowing up.
export MAGICK_MEMORY_LIMIT="${MAGICK_MEMORY_LIMIT:-512MiB}"
export MAGICK_MAP_LIMIT="${MAGICK_MAP_LIMIT:-1GiB}"

# Downscaled BEFORE handing it to wallbash. The 4 dominant colors of a 512px
# image are the same as those of a 4K one -- kmeans looks at color distribution,
# not detail -- but it costs orders of magnitude less memory and time. The '>'
# only shrinks, never enlarges; the [0] takes a single frame (animated gif/webp
# would otherwise be expanded whole into RAM).
WORK="$TMPDIR_/wall.png"
if ! magick "$WALL[0]" -alpha off -resize '512x512>' "$WORK" 2>/dev/null; then
    echo "wallbash-kitty: downscale failed, using the original" >&2
    cp "$WALL" "$WORK"
fi

# wallbash.sh writes <base>.dcol and cleans up its own temporaries.
# -d forces dark mode. Without it wallbash uses "auto": with a light wallpaper
# it inverts the palette (light background, dark text), and since we force the
# background dark below, the result is dark text on dark background: unreadable.
bash "$WALLBASH" -d "${PROFILE[@]}" "$WORK" "$TMPDIR_/wall" >/dev/null 2>&1
DCOL="$TMPDIR_/wall.dcol"
[ -s "$DCOL" ] || { echo "wallbash-kitty: no colors were generated" >&2; exit 1; }

# shellcheck disable=SC1090
source "$DCOL"

# wallbash uses pry1 (the darkest dominant) as the background as-is. On
# mid-tone wallpapers that gives a background too light and the text smears.
# The hue is kept but the value is pinned to something usable.
BG_MAX_V="${BG_MAX_V:-0.16}"   # if the background exceeds this, darken it
BG_TARGET_V="${BG_TARGET_V:-0.11}"
dcol_pry1=$(python3 - "$dcol_pry1" "$BG_MAX_V" "$BG_TARGET_V" <<'PY'
import colorsys, sys
hexv, vmax, vtgt = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
r, g, b = (int(hexv[i:i+2], 16) / 255 for i in (0, 2, 4))
h, s, v = colorsys.rgb_to_hsv(r, g, b)
if v > vmax:
    v = vtgt
    s = min(1.0, s * 1.15)   # compensate the washout from lowering brightness
r, g, b = colorsys.hsv_to_rgb(h, s, v)
print("%02X%02X%02X" % (round(r*255), round(g*255), round(b*255)))
PY
)
dcol_pry1_rgba="rgba($((16#${dcol_pry1:0:2})),$((16#${dcol_pry1:2:2})),$((16#${dcol_pry1:4:2})),\1)"

# Since the background always ends up dark, the text has to end up light. With
# a light wallpaper wallbash decides the opposite and would leave dark text on a
# dark background: unreadable. So txt1..txt4 are lifted.
for n in 1 2 3 4; do
    var="dcol_txt$n"; val="${!var:-}"
    [ -z "$val" ] && continue
    newval=$(python3 - "$val" <<'PY'
import colorsys, sys
h_ = sys.argv[1]
r, g, b = (int(h_[i:i+2], 16) / 255 for i in (0, 2, 4))
h, s, v = colorsys.rgb_to_hsv(r, g, b)
if v < 0.75:            # too dark to read against a dark background
    v, s = 0.90, min(s, 0.12)
r, g, b = colorsys.hsv_to_rgb(h, s, v)
print("%02X%02X%02X" % (round(r*255), round(g*255), round(b*255)))
PY
)
    printf -v "$var" '%s' "$newval"
    printf -v "${var}_rgba" 'rgba(%d,%d,%d,\1)' \
        "$((16#${newval:0:2}))" "$((16#${newval:2:2}))" "$((16#${newval:4:2}))"
done

# The first line of the template is the output path, not content.
TMP="$OUT.tmp.$$"
tail -n +2 "$TEMPLATE" > "$TMP"

# Replace <wallbash_XXX> with the value of $dcol_XXX
while IFS= read -r slot; do
    var="dcol_${slot}"
    val="${!var:-}"
    [ -n "$val" ] && sed -i "s|<wallbash_${slot}>|${val}|g" "$TMP"
done < <(grep -ohE '<wallbash_[a-z0-9]+>' "$TMP" | tr -d '<>' | sed 's/^wallbash_//' | sort -u)

if grep -q '<wallbash_' "$TMP"; then
    echo "wallbash-kitty: unresolved slots remain:" >&2
    grep -ohE '<wallbash_[a-z0-9]+>' "$TMP" | sort -u | sed 's/^/  /' >&2
    rm -f "$TMP"; exit 1
fi

mv "$TMP" "$OUT"

# end-4 emits sequences.txt (its own palette) to EVERY open /dev/pts from
# apply_anyterm. That arrives after kitty has loaded kitty.conf and overrides
# the live colors. To stop them fighting, we rewrite sequences.txt with this
# same palette: whichever wins the race, the colors are identical.
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
echo "wallbash-kitty: $OUT updated from $(basename "$WALL")"
