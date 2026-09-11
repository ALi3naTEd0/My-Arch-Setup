import json, sys
from materialyoucolor.hct import Hct
from materialyoucolor.utils.math_utils import difference_degrees, sanitize_degrees_double, rotation_direction

def hex_to_argb(h):
    h = h.lstrip('#')
    return (0xFF << 24) | (int(h[0:2],16) << 16) | (int(h[2:4],16) << 8) | int(h[4:6],16)

def harmonize(design, source, threshold, harmony):
    f = Hct.from_int(design); t = Hct.from_int(source)
    d = difference_degrees(f.hue, t.hue)
    rot = min(d * harmony, threshold)
    return sanitize_degrees_double(f.hue + rot * rotation_direction(f.hue, t.hue))

base = json.load(open('/home/x/.config/quickshell/ii/scripts/colors/terminal/scheme-base.json'))['dark']
# the accent actually in use: primary from the generated scss
prim = None
for line in open('/home/x/.local/state/quickshell/user/generated/material_colors.scss'):
    if line.startswith('$primary:'):
        prim = line.split(':')[1].strip().rstrip(';')
src = hex_to_argb(prim)
print(f"accent $primary = {prim}  (hue {Hct.from_int(src).hue:.0f})\n")

names = {1:'red',2:'green',3:'yellow',4:'blue',5:'magenta',6:'cyan'}
combos = [(0.6,100),(0.4,60),(0.25,30),(0.15,20),(0.0,0)]
print(f"{'':9}" + "".join(f"h={h} t={t:<3}".rjust(14) for h,t in combos))
for i,n in names.items():
    orig = Hct.from_int(hex_to_argb(base[f'term{i}'])).hue
    row = f"{n:<7}{orig:>4.0f}"
    for h,t in combos:
        row += f"{harmonize(hex_to_argb(base[f'term{i}']), src, t, h):>14.0f}"
    print(row)
