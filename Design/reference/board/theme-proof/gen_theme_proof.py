"""Colour proof: the trip summary in the night (dark) and day (light) themes, side by side.

Usage: python gen_theme_proof.py i80-slc-sac-route.json elev.json out_dir
This is a proof of the two palettes and of how the route line is drawn in each. It is not the final
screen design: the real map has state borders and labels, which need the Natural Earth data.
"""
import json, math, sys, pathlib

route_src, elev_src, out = (pathlib.Path(a) for a in sys.argv[1:4])
out.mkdir(parents=True, exist_ok=True)
pts = json.loads(route_src.read_text()); elev = json.loads(elev_src.read_text())
BC, INTER = "Barlow Condensed", "Inter"
PW, PH = 393, 700                                   # one phone panel, in points

THEMES = {
    "night": dict(bg="#14161c", land="#1d2029", card="#1d2029", border="#30353f", text="#f0efec", sec="#a6aab4",
                  route="#ffb547", edge=None, glow=True, accent="#ffb547", btn2="#1d2029", btn2edge=None, ring_fill=0.14),
    "day":   dict(bg="#f5f3ee", land="#e9e5db", card="#ffffff", border="#d3cdc0", text="#16181d", sec="#5d6470",
                  route="#e8830a", edge="#9c4e00", glow=False, accent="#9c4e00", btn2="#ffffff", btn2edge="#d3cdc0", ring_fill=0.16),
}

def simplify(p, tol):
    keep = [False] * len(p); keep[0] = keep[-1] = True; stack = [(0, len(p) - 1)]
    while stack:
        a, b = stack.pop(); (ax, ay), (bx, by) = p[a], p[b]; dx, dy = bx - ax, by - ay; n = math.hypot(dx, dy) or 1e-9
        best, bi = 0.0, -1
        for i in range(a + 1, b):
            d = abs((p[i][0] - ax) * dy - (p[i][1] - ay) * dx) / n
            if d > best: best, bi = d, i
        if best > tol: keep[bi] = True; stack += [(a, bi), (bi, b)]
    return [q for q, f in zip(p, keep) if f]

def smooth(p):
    d = [f"M{p[0][0]:.1f} {p[0][1]:.1f}"]
    for i in range(len(p) - 1):
        p0, p1, p2, p3 = p[max(i - 1, 0)], p[i], p[i + 1], p[min(i + 2, len(p) - 1)]; t = 0.5 / 3
        d.append(f"C{p1[0] + (p2[0] - p0[0]) * t:.1f} {p1[1] + (p2[1] - p0[1]) * t:.1f} "
                 f"{p2[0] - (p3[0] - p1[0]) * t:.1f} {p2[1] - (p3[1] - p1[1]) * t:.1f} {p2[0]:.1f} {p2[1]:.1f}")
    return " ".join(d)

RB = (44, 138, 349, 322)
lat0 = sum(p[0] for p in pts) / len(pts); kx = math.cos(math.radians(lat0))
gx = [p[1] * kx for p in pts]; gy = [-p[0] for p in pts]
sc = min((RB[2] - RB[0]) / (max(gx) - min(gx)), (RB[3] - RB[1]) / (max(gy) - min(gy)))
ox = RB[0] + ((RB[2] - RB[0]) - (max(gx) - min(gx)) * sc) / 2 - min(gx) * sc
oy = RB[1] + ((RB[3] - RB[1]) - (max(gy) - min(gy)) * sc) / 2 - min(gy) * sc
P = lambda la, lo: (lo * kx * sc + ox, -la * sc + oy)
line = simplify([P(a, b) for a, b in pts], 0.5); route_d = smooth(line)
(sx, sy), (ex, ey) = line[0], line[-1]
top = max(elev, key=lambda e: e["ft"]); mx, my = P(top["lat"], top["lon"])
EB = (58, 506, 357, 580)
E = lambda e: (EB[0] + e["d"] / elev[-1]["d"] * (EB[2] - EB[0]), EB[3] - e["ft"] / 8000 * (EB[3] - EB[1]))
el = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in map(E, elev)); ea = el + f" L{EB[2]} {EB[3]} L{EB[0]} {EB[3]} Z"
tx, ty = E(top)

def t(x, y, s, size, fam=INTER, w=400, fill="#000", track=0, anchor="start", op=1.0):
    st = ' font-stretch="condensed"' if fam == BC else ""
    return (f'<text x="{x}" y="{y}" text-anchor="{anchor}" font-family="{fam}" font-weight="{w}"{st} font-size="{size}" '
            f'letter-spacing="{track}" fill="{fill}" fill-opacity="{op}">{s}</text>')

def shield(x, y, h):
    s = h / 100
    return (f'<g transform="translate({x} {y}) scale({s:.4f})">'
            '<path d="M50 3 C62 9 78 10 92 6 C97 22 99 38 96 54 C92 76 74 91 50 98 C26 91 8 76 4 54 C1 38 3 22 8 6 C22 10 38 9 50 3 Z" fill="#ffffff"/>'
            '<path d="M50 9 C62 14 76 15 88 12 C92 26 93 39 91 53 C87 72 71 85 50 92 C29 85 13 72 9 53 C7 39 8 26 12 12 C24 15 38 14 50 9 Z" fill="#003f87"/>'
            '<path d="M12 12 C24 15 38 14 50 9 C62 14 76 15 88 12 C89.6 17.5 90.8 23 91.6 30 L8.4 30 C9.2 23 10.4 17.5 12 12 Z" fill="#bf2033"/>'
            '<path d="M8.4 30 H91.6" stroke="#ffffff" stroke-width="2.4"/>'
            f'<text x="50" y="25" text-anchor="middle" font-family="{INTER}" font-weight="700" font-size="9.5" letter-spacing="0.9" fill="#fff">INTERSTATE</text>'
            f'<text x="50" y="76" text-anchor="middle" font-family="{BC}" font-stretch="condensed" font-weight="700" font-size="50" fill="#fff">80</text></g>')

def panel(name, x0):
    c = THEMES[name]; g = [f'<g transform="translate({x0} 30)">',
        f'<clipPath id="clip-{name}"><rect width="{PW}" height="{PH}" rx="34"/></clipPath>',
        f'<g clip-path="url(#clip-{name})"><rect width="{PW}" height="{PH}" fill="{c["bg"]}"/>']
    g.append(t(20, 54, "Trip complete", 22, INTER, 700, c["text"]))
    g.append(t(20, 77, "Wed, Nov 4 · Utah → Nevada → California", 14, INTER, 400, c["sec"]))
    g.append(f'<circle cx="{PW - 36}" cy="56" r="16" fill="{c["land"]}"/><path d="M{PW - 41} 51 l10 10 m0 -10 l-10 10" stroke="{c["sec"]}" stroke-width="2" stroke-linecap="round"/>')
    g.append(f'<rect y="96" width="{PW}" height="268" fill="{c["land"]}"/>')
    if c["glow"]:
        g.append(f'<path d="{route_d}" fill="none" stroke="{c["route"]}" stroke-opacity="0.45" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" filter="url(#glow)"/>')
    if c["edge"]:
        g.append(f'<path d="{route_d}" fill="none" stroke="{c["edge"]}" stroke-width="5.4" stroke-linecap="round" stroke-linejoin="round"/>')
    g.append(f'<path d="{route_d}" fill="none" stroke="{c["route"]}" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/>')
    ring = c["edge"] or c["route"]
    for x, y in ((sx, sy), (ex, ey)):
        g.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="11" fill="{c["route"]}" fill-opacity="{c["ring_fill"]}" stroke="{ring}" stroke-width="1.5" stroke-dasharray="3 3"/>'
                 f'<circle cx="{x:.1f}" cy="{y:.1f}" r="3.5" fill="{c["route"]}" stroke="{c["land"]}" stroke-width="1.5"/>')
    g.append(t(sx + 8, sy - 20, "Salt Lake City area", 12, INTER, 500, c["sec"], anchor="end"))
    g.append(t(ex - 10, ey + 28, "Sacramento area", 12, INTER, 500, c["sec"]))
    g.append(f'<path d="M{mx - 5:.1f} {my + 15:.1f} L{mx:.1f} {my + 6:.1f} L{mx + 5:.1f} {my + 15:.1f} Z" fill="{c["text"]}"/>')
    g.append(t(mx + 10, my + 16, "Highest point · 7,139 ft", 12, INTER, 600, c["text"]))
    for x, num, lab in ((20, "649", "miles"), (112, "10:52", "hours moving"), (238, "3", "states")):
        g.append(t(x, 412, num, 34, BC, 700, c["text"]))
        g.append(t(x, 431, lab, 13, INTER, 400, c["sec"]))
    g.append(shield(PW - 20 - 46, 386, 48))
    edge = f' stroke="{c["border"]}" stroke-width="1"' if name == "day" else ""
    g.append(f'<rect x="20" y="452" width="{PW - 40}" height="150" rx="20" fill="{c["card"]}"{edge}/>')
    g.append(t(36, 479, "ELEVATION", 12, INTER, 600, c["sec"], track=0.8))
    for v, lab in ((0, "0"), (4000, "4k"), (8000, "8k")):
        y = EB[3] - v / 8000 * (EB[3] - EB[1])
        g.append(f'<path d="M{EB[0]} {y:.1f} H{EB[2]}" stroke="{c["border"]}" stroke-width="0.6"/>')
        g.append(t(EB[0] - 6, y + 4, lab, 11, INTER, 400, c["sec"], anchor="end"))
    g.append(f'<path d="{ea}" fill="url(#el-{name})"/>')
    g.append(f'<path d="{el}" fill="none" stroke="{c["route"]}" stroke-width="2" stroke-linejoin="round"/>')
    g.append(f'<circle cx="{tx:.1f}" cy="{ty:.1f}" r="4" fill="{c["route"]}" stroke="{c["card"]}" stroke-width="1.5"/>')
    g.append(t(tx - 8, ty - 7, "7,139 ft · mile 557", 11, INTER, 500, c["text"], anchor="end"))
    g.append(f'<rect x="20" y="624" width="225" height="50" rx="14" fill="#ffb547"/>')
    g.append(t(132.5, 655, "Share trip card", 17, INTER, 600, "#16181d", anchor="middle"))
    e2 = f' stroke="{c["btn2edge"]}" stroke-width="1"' if c["btn2edge"] else ""
    g.append(f'<rect x="257" y="624" width="116" height="50" rx="14" fill="{c["btn2"]}"{e2}/>')
    g.append(t(315, 655, "Done", 17, INTER, 600, c["text"], anchor="middle"))
    g.append("</g></g>")
    return "\n".join(g)

W, H = PW * 2 + 90, PH + 110
defs = ('<defs><filter id="glow" x="-10%" y="-60%" width="120%" height="220%"><feGaussianBlur stdDeviation="6"/></filter>'
        + "".join(f'<linearGradient id="el-{n}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{c["route"]}" stop-opacity="{0.5 if n == "night" else 0.34}"/>'
                  f'<stop offset="1" stop-color="{c["route"]}" stop-opacity="0"/></linearGradient>' for n, c in THEMES.items()) + "</defs>")
svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}"><rect width="{W}" height="{H}" fill="#3a3d44"/>{defs}'
       + panel("night", 30) + panel("day", PW + 60)
       + t(30 + PW / 2, PH + 68, "Night · a line of light", 18, INTER, 600, "#f0efec", anchor="middle")
       + t(PW + 60 + PW / 2, PH + 68, "Day · a line of ink on the map", 18, INTER, 600, "#f0efec", anchor="middle") + "</svg>")
(out / "theme-proof.svg").write_text(svg, encoding="utf-8")
print("ok", len(svg))
