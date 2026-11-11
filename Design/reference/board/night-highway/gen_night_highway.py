"""RoadPrint 'Night Highway' share card (the free default), board reference on the real I-80 route.

Usage: python gen_night_highway.py places.rpgeo i80-slc-sac-route.json elev.json out_dir
The map uses the repo's own places.rpgeo (Natural Earth outlines), so borders are real.
"""
import json, math, sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "common"))
import rp

places, route_src, elev_src, out = (pathlib.Path(a) for a in sys.argv[1:5])
out.mkdir(parents=True, exist_ok=True)
pts = json.loads(route_src.read_text())             # [[lat, lon], ...]
elev = json.loads(elev_src.read_text())

W, H = 1080, 1920
L, R = 72, 1008
BG, LAND, BORDER, BORDER2 = "#14161c", "#1d2029", "#30353f", "#454b58"
AMBER, TEXT, SEC = "#ffb547", "#f0efec", "#a6aab4"
MAP_BOTTOM = 1080                                    # the map is drawn down to here, then fades out
RB = (130, 380, 950, 850)                            # the route is fitted into this box

# ---------------------------------------------------------------- projection (local equirectangular; the app uses the core's LAEA)
lat0 = sum(p[0] for p in pts) / len(pts); kx = math.cos(math.radians(lat0))
gx = [p[1] * kx for p in pts]; gy = [-p[0] for p in pts]
sc = min((RB[2] - RB[0]) / (max(gx) - min(gx)), (RB[3] - RB[1]) / (max(gy) - min(gy)))
ox = RB[0] + ((RB[2] - RB[0]) - (max(gx) - min(gx)) * sc) / 2 - min(gx) * sc
oy = RB[1] + ((RB[3] - RB[1]) - (max(gy) - min(gy)) * sc) / 2 - min(gy) * sc
P = lambda lat, lon: (lon * kx * sc + ox, -lat * sc + oy)
inv = lambda x, y: (-(y - oy) / sc, (x - ox) / sc / kx)   # -> lat, lon

line = rp.simplify([P(a, b) for a, b in pts], 1.2)
route_d = rp.smooth_path(line)
(sx, sy), (ex, ey) = line[0], line[-1]
top = max(elev, key=lambda e: e["ft"]); mx, my = P(top["lat"], top["lon"])

# ---------------------------------------------------------------- map: land, borders, labels
view = (-40, -40, W + 40, MAP_BOTTOM + 40)
la1, lo0 = inv(view[0], view[1]); la0, lo1 = inv(view[2], view[3])
feats = rp.read_rpgeo(places, (lo0, la0, lo1, la1))
land, region_lines, country_lines, labels = [], [], [], []
route_countries = set()
for f in feats:
    f["px"] = []
    for ring in f["rings"]:
        pr = rp.clip_ring([P(lat, lon) for lon, lat in ring], view)
        if len(pr) >= 3:
            pr = rp.simplify_ring(pr, 0.8)
            if len(pr) >= 3: f["px"].append(pr)
regions = [f for f in feats if f["kind"] == 1 and f["px"]]
countries = [f for f in feats if f["kind"] == 0 and f["px"]]
with_regions = {f["parent"] for f in regions}
for f in countries:
    d = " ".join(rp.ring_path(r) for r in f["px"])
    if f["code"] not in with_regions: land.append(d)
    country_lines.append(d)
for f in regions:
    d = " ".join(rp.ring_path(r) for r in f["px"])
    land.append(d); region_lines.append(d)
    big = max(f["px"], key=lambda r: rp.area_centroid(r)[0])
    vis = rp.clip_ring(big, (0, 230, W, 980))
    if len(vis) < 3: continue
    area, c = rp.area_centroid(vis)
    crossed = any(rp.inside(q, big) for q in line[::3])
    if crossed: route_countries.add(f["parent"])
    if area < 16000: continue
    labels.append(dict(code=f["code"].split("-")[-1], c=c, ring=vis, crossed=crossed, area=area))

def place(lb, taken):
    """Label position: the visible centroid, pushed away from the route and from other labels."""
    cands = [lb["c"]] + [(lb["c"][0] + math.cos(a) * r, lb["c"][1] + math.sin(a) * r)
                         for r in range(30, 241, 30) for a in [i * math.pi / 4 for i in range(8)]]
    for q in cands:
        if not (110 < q[0] < W - 110 and 350 < q[1] < 950): continue
        if not rp.inside(q, lb["ring"]): continue
        if rp.dist_to_line(q, line) < 95: continue
        if any(math.hypot(q[0] - t[0], q[1] - t[1]) < 170 for t in taken): continue
        return q
    return None

placed, taken = [], [(sx - 120, sy - 60), (ex + 100, ey + 66), (mx + 150, my + 50)]   # keep clear of the place and summit labels
for lb in sorted(labels, key=lambda l: (not l["crossed"], -l["area"])):
    q = place(lb, taken)
    if q: placed.append((lb, q)); taken.append(q)

# ---------------------------------------------------------------- the card
def chip(x, y, label, h=72):
    w = 34 * 0.56 * len(label) + 60
    return (f'<rect x="{x}" y="{y}" width="{w:.0f}" height="{h}" rx="{h / 2}" fill="{LAND}" stroke="{BORDER}" stroke-width="2"/>'
            + rp.text(x + w / 2, y + h / 2 + 12, label, 34, rp.INTER, 500, TEXT, anchor="middle"), w)

g = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">',
     "<title>RoadPrint Night Highway card - I-80 reference</title>",
     "<defs>"
     '<filter id="g1" x="-20%" y="-80%" width="140%" height="260%"><feGaussianBlur stdDeviation="46"/></filter>'
     '<filter id="g2" x="-20%" y="-80%" width="140%" height="260%"><feGaussianBlur stdDeviation="20"/></filter>'
     '<filter id="g3" x="-20%" y="-80%" width="140%" height="260%"><feGaussianBlur stdDeviation="7"/></filter>'
     f'<linearGradient id="fadeTop" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{BG}"/><stop offset="1" stop-color="{BG}" stop-opacity="0"/></linearGradient>'
     f'<linearGradient id="fadeBottom" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{BG}" stop-opacity="0"/><stop offset="1" stop-color="{BG}"/></linearGradient>'
     f'<clipPath id="mapclip"><rect width="{W}" height="{MAP_BOTTOM}"/></clipPath>'
     "</defs>",
     f'<rect width="{W}" height="{H}" fill="{BG}"/>',
     '<g clip-path="url(#mapclip)">',
     f'<path d="{" ".join(land)}" fill="{LAND}" fill-rule="evenodd"/>',
     f'<path d="{" ".join(region_lines)}" fill="none" stroke="{BORDER}" stroke-width="2" stroke-linejoin="round"/>',
     f'<path d="{" ".join(country_lines)}" fill="none" stroke="{BORDER2}" stroke-width="3" stroke-linejoin="round"/>']
for lb, (x, y) in placed:
    g.append(rp.text(x, y + 13, lb["code"], 38, rp.INTER, 600, SEC, track=9, anchor="middle", op=0.42 if lb["crossed"] else 0.22))
g += ["</g>",
      f'<rect width="{W}" height="300" fill="url(#fadeTop)"/>',
      f'<rect y="{MAP_BOTTOM - 240}" width="{W}" height="240" fill="url(#fadeBottom)"/>']

# route: light spilled on the ground, a soft halo, a tight halo, then the core
g += [f'<path d="{route_d}" fill="none" stroke="{AMBER}" stroke-opacity="0.16" stroke-width="90" stroke-linecap="round" stroke-linejoin="round" filter="url(#g1)"/>',
      f'<path d="{route_d}" fill="none" stroke="{AMBER}" stroke-opacity="0.38" stroke-width="40" stroke-linecap="round" stroke-linejoin="round" filter="url(#g2)"/>',
      f'<path d="{route_d}" fill="none" stroke="{AMBER}" stroke-opacity="0.70" stroke-width="20" stroke-linecap="round" stroke-linejoin="round" filter="url(#g3)"/>',
      f'<path d="{route_d}" fill="none" stroke="{AMBER}" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>',
      f'<path d="{route_d}" fill="none" stroke="#ffe1a0" stroke-opacity="0.85" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>']
for x, y in ((sx, sy), (ex, ey)):
    g.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="30" fill="{AMBER}" fill-opacity="0.13" stroke="{AMBER}" stroke-width="3" stroke-dasharray="5 7" stroke-linecap="round"/>'
             f'<circle cx="{x:.1f}" cy="{y:.1f}" r="9" fill="{BG}"/><circle cx="{x:.1f}" cy="{y:.1f}" r="6" fill="{AMBER}"/>')
g.append(rp.text(sx + 30, sy - 50, "SALT LAKE CITY AREA", 22, rp.INTER, 600, TEXT, track=2.5, anchor="end", op=0.85))
g.append(rp.text(ex - 30, ey + 72, "SACRAMENTO AREA", 22, rp.INTER, 600, TEXT, track=2.5, op=0.85))
g.append(f'<path d="M{mx - 13:.1f} {my + 40:.1f} L{mx:.1f} {my + 18:.1f} L{mx + 13:.1f} {my + 40:.1f} Z" fill="{TEXT}"/>')
g.append(rp.text(mx + 26, my + 40, "Donner Summit", 28, rp.INTER, 700, TEXT))
g.append(rp.text(mx + 26, my + 72, "7,139 ft", 24, rp.INTER, 500, SEC))

# header
g.append(rp.text(L + 2, 268, "ROADPRINT", 27, rp.INTER, 700, AMBER, track=11))

# the brag
g.append(rp.text(L - 9, 1240, "649", 300, rp.BC, 700, TEXT, track=-2))
g.append(rp.text(L + 408, 1240, "MILES", 78, rp.BC, 700, AMBER, track=3))
g.append(rp.text(L + 2, 1312, "Utah → California  ·  Nov 4", 42, rp.INTER, 600, TEXT))

# road sign and chips
g.append(rp.interstate_shield(L, 1348, 88, "80"))
x = L + 88 + 22
for label in ("10h 52m", "3 states"):
    s, w = chip(x, 1356, label); g.append(s); x += w + 16

# badge (only when one was earned)
bx, by = L + 40, 1496
hexp = " ".join(f"{bx + 38 * math.cos(math.radians(a)):.1f},{by + 38 * math.sin(math.radians(a)):.1f}" for a in range(-90, 270, 60))
g.append(f'<polygon points="{hexp}" fill="{AMBER}" fill-opacity="0.12" stroke="{AMBER}" stroke-width="4" stroke-linejoin="round"/>')
g.append(f'<path d="M{bx - 20} {by + 12} L{bx - 7} {by - 8} L{bx + 1} {by + 3} L{bx + 8} {by - 5} L{bx + 20} {by + 12} Z" fill="{AMBER}"/>')
g.append(rp.text(bx + 62, by - 8, "NEW BADGE", 20, rp.INTER, 600, AMBER, track=3))
g.append(rp.text(bx + 62, by + 28, "Donner Pass conquered", 36, rp.INTER, 600, TEXT))

# watermark (free cards)
g.append(rp.text(W / 2, 1590, "MADE WITH ROADPRINT", 22, rp.INTER, 600, SEC, track=5, anchor="middle", op=0.75))
g.append("</svg>")
svg = "\n".join(g)
(out / "night-highway-i80.svg").write_text(svg, encoding="utf-8")
guides = svg.replace("</svg>", f'<rect x="{L}" y="220" width="{R - L}" height="{H - 540}" fill="none" stroke="#4fd1ff" stroke-width="2" stroke-dasharray="14 10"/></svg>')
(out / "night-highway-i80-guides.svg").write_text(guides, encoding="utf-8")
print(len(feats), "features;", len(placed), "labels:", [l["code"] for l, _ in placed], ";", len(svg), "bytes")
