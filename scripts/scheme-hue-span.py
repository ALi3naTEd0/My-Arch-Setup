import colorsys, json, sys
d = json.load(open(sys.argv[1]))["dark"]
hs = []
for k in ("term1","term2","term3","term4","term5","term6"):
    h = d[k].lstrip("#")
    r,g,b = (int(h[i:i+2],16)/255 for i in (0,2,4))
    hue,_,s = colorsys.rgb_to_hsv(r,g,b)
    if s > 0.05: hs.append(hue*360)
if len(hs) < 2: print(0); raise SystemExit
hs.sort()
gaps = [hs[i+1]-hs[i] for i in range(len(hs)-1)] + [360-hs[-1]+hs[0]]
print(round(360 - max(gaps)))   # circular span occupied by the hues
