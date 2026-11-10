"""RoadPrint 'Print' share card, v2: a transparent overlay built from the real I-80 fixture.

Usage: python gen_print.py i80-slc-sac-route.json elev.json out_dir
Writes print-overlay.svg (the card, transparent) and preview-*.svg (the card on test backgrounds).
"""
import json, math, sys, pathlib

route_src, elev_src, out = (pathlib.Path(a) for a in sys.argv[1:4])
out.mkdir(parents=True, exist_ok=True)
pts = json.loads(route_src.read_text())            # [[lat, lon], ...]
elev = json.loads(elev_src.read_text())            # [{d (mi), lon, lat, ft}, ...]

W, H = 1080, 1920
SAFE = dict(top=220, bottom=320, side=72)
L, R = SAFE["side"], W - SAFE["side"]              # 72 .. 1008
AMBER, TEXT, MUTED, INK = "#ffb547", "#f0efec", "#e4e5e8", "#0b0c10"
BC, INTER = "Barlow Condensed", "Inter"

# ---------------------------------------------------------------- geometry helpers
def simplify(p, tol):
    keep = [False] * len(p); keep[0] = keep[-1] = True
    stack = [(0, len(p) - 1)]
    while stack:
        a, b = stack.pop()
        (ax, ay), (bx, by) = p[a], p[b]
        dx, dy = bx - ax, by - ay
        n = math.hypot(dx, dy) or 1e-9
        best, bi = 0.0, -1
        for i in range(a + 1, b):
            d = abs((p[i][0] - ax) * dy - (p[i][1] - ay) * dx) / n
            if d > best: best, bi = d, i
        if best > tol:
            keep[bi] = True; stack += [(a, bi), (bi, b)]
    return [q for q, f in zip(p, keep) if f]

def smooth_path(p):
    """Catmull-Rom through the points as cubic Beziers: a drawn line, not a polyline."""
    if len(p) < 3:
        return "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in p)
    d = [f"M{p[0][0]:.1f} {p[0][1]:.1f}"]
    for i in range(len(p) - 1):
        p0, p1, p2, p3 = p[max(i - 1, 0)], p[i], p[i + 1], p[min(i + 2, len(p) - 1)]
        t = 0.5 / 3
        c1 = (p1[0] + (p2[0] - p0[0]) * t, p1[1] + (p2[1] - p0[1]) * t)
        c2 = (p2[0] - (p3[0] - p1[0]) * t, p2[1] - (p3[1] - p1[1]) * t)
        d.append(f"C{c1[0]:.1f} {c1[1]:.1f} {c2[0]:.1f} {c2[1]:.1f} {p2[0]:.1f} {p2[1]:.1f}")
    return " ".join(d)

# ---------------------------------------------------------------- route (hero)
RB = (118, 480, 962, 830)                           # route box: x0, y0, x1, y1
lat0 = sum(p[0] for p in pts) / len(pts)
kx = math.cos(math.radians(lat0))
gx = [p[1] * kx for p in pts]; gy = [-p[0] for p in pts]
sc = min((RB[2] - RB[0]) / (max(gx) - min(gx)), (RB[3] - RB[1]) / (max(gy) - min(gy)))
offx = RB[0] + ((RB[2] - RB[0]) - (max(gx) - min(gx)) * sc) / 2 - min(gx) * sc
offy = RB[1] + ((RB[3] - RB[1]) - (max(gy) - min(gy)) * sc) / 2 - min(gy) * sc
P = lambda lat, lon: (lon * kx * sc + offx, -lat * sc + offy)
line = simplify([P(a, b) for a, b in pts], 1.2)
route_d = smooth_path(line)
(sx, sy), (ex, ey) = line[0], line[-1]              # start = Salt Lake City (east), end = Sacramento (west)
top = max(elev, key=lambda e: e["ft"])
mx, my = P(top["lat"], top["lon"])

# ---------------------------------------------------------------- elevation strip
EB = (L, 955, R, 1105)                              # x0, top, x1, baseline
dmax = elev[-1]["d"]; fmax = top["ft"]
E = lambda e: (EB[0] + e["d"] / dmax * (EB[2] - EB[0]), EB[3] - e["ft"] / fmax * (EB[3] - EB[1]))
ep = [E(e) for e in elev]
elev_line = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in ep)
elev_area = elev_line + f" L{EB[2]} {EB[3]} L{EB[0]} {EB[3]} Z"
tx, ty = E(top)

# ---------------------------------------------------------------- text helpers
def t(x, y, s, size, family=INTER, weight=600, fill=TEXT, track=0, anchor="start", op=1.0, halo=0.0):
    st = ' font-stretch="condensed"' if family == BC else ""
    hl = ""   # legibility comes from the soft shadow layer under the whole card, not from outlines
    return (f'<text x="{x:.1f}" y="{y:.1f}" text-anchor="{anchor}" font-family="{family}" font-weight="{weight}"{st} '
            f'font-size="{size}" letter-spacing="{track}" fill="{fill}" fill-opacity="{op}"{hl}>{s}</text>')

def shield(x, y, h, ref):
    """US interstate shield, drawn in a 100x100 box and scaled to height h. Number is live text."""
    s = h / 100
    outer = "M50 3 C62 9 78 10 92 6 C97 22 99 38 96 54 C92 76 74 91 50 98 C26 91 8 76 4 54 C1 38 3 22 8 6 C22 10 38 9 50 3 Z"
    inner = "M50 9 C62 14 76 15 88 12 C92 26 93 39 91 53 C87 72 71 85 50 92 C29 85 13 72 9 53 C7 39 8 26 12 12 C24 15 38 14 50 9 Z"
    band = "M12 12 C24 15 38 14 50 9 C62 14 76 15 88 12 C89.6 17.5 90.8 23 91.6 29 L8.4 29 C9.2 23 10.4 17.5 12 12 Z"
    return (f'<g transform="translate({x:.1f} {y:.1f}) scale({s:.4f})">'
            f'<path d="{outer}" fill="#ffffff"/><path d="{inner}" fill="#003f87"/><path d="{band}" fill="#bf2033"/>'
            f'<path d="M8.4 29 H91.6" stroke="#ffffff" stroke-width="2.4"/>'
            f'<text x="50" y="24.5" text-anchor="middle" font-family="{INTER}" font-weight="700" font-size="9.5" '
            f'letter-spacing="0.9" fill="#ffffff">INTERSTATE</text>'
            f'<text x="50" y="74" text-anchor="middle" font-family="{BC}" font-stretch="condensed" font-weight="700" '
            f'font-size="50" fill="#ffffff">{ref}</text></g>')

def area_ring(x, y):
    return (f'<circle cx="{x:.1f}" cy="{y:.1f}" r="30" fill="{AMBER}" fill-opacity="0.14"/>'
            f'<circle cx="{x:.1f}" cy="{y:.1f}" r="30" fill="none" stroke="{AMBER}" stroke-width="3" stroke-dasharray="5 7" stroke-linecap="round"/>'
            f'<circle cx="{x:.1f}" cy="{y:.1f}" r="11" fill="{INK}" fill-opacity="0.55"/>'
            f'<circle cx="{x:.1f}" cy="{y:.1f}" r="8" fill="{TEXT}"/>')

# ---------------------------------------------------------------- the card
def card(background=""):
    g = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">',
         "<title>RoadPrint Print card (transparent overlay) - I-80 reference, v2</title>",
         '<defs>'
         '<filter id="glow" x="-10%" y="-60%" width="120%" height="220%"><feGaussianBlur stdDeviation="16"/></filter>'
         f'<filter id="shade" filterUnits="userSpaceOnUse" x="0" y="0" width="{W}" height="{H}">'
         '<feColorMatrix type="matrix" values="0 0 0 0 0.03  0 0 0 0 0.035  0 0 0 0 0.05  0 0 0 0.62 0"/>'
         '<feGaussianBlur stdDeviation="9"/></filter>'
         f'<linearGradient id="elev" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{AMBER}" stop-opacity="0.50"/>'
         f'<stop offset="1" stop-color="{AMBER}" stop-opacity="0"/></linearGradient>'
         '</defs>', background]
    head = len(g)

    # header: wordmark, title, date; the road sign balances it on the right
    g.append(t(L + 2, 268, "ROADPRINT", 27, INTER, 700, AMBER, track=11, halo=4))
    g.append(t(L - 4, 366, "UTAH", 96, BC, 700, TEXT, track=1.5, halo=6))
    ax = L + 174 + 24
    g.append(f'<path d="M{ax} 332 h50 m-17 -16 l17 16 l-17 16" fill="none" stroke="{AMBER}" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/>')
    g.append(t(ax + 50 + 22, 366, "CALIFORNIA", 96, BC, 700, TEXT, track=1.5, halo=6))
    g.append(t(L + 2, 420, "Wednesday, November 4", 31, INTER, 500, MUTED, halo=4))
    g.append(shield(R - 128, 240, 132, "80"))

    # route: soft glow, dark casing for bright photos, amber core
    glow = (f'<path d="{route_d}" fill="none" stroke="{AMBER}" stroke-opacity="0.55" stroke-width="30" stroke-linecap="round" stroke-linejoin="round" filter="url(#glow)"/>')
    g.append(f'<path d="{route_d}" fill="none" stroke="{INK}" stroke-opacity="0.30" stroke-width="17" stroke-linecap="round" stroke-linejoin="round"/>')
    g.append(f'<path d="{route_d}" fill="none" stroke="{AMBER}" stroke-width="11" stroke-linecap="round" stroke-linejoin="round"/>')
    g.append(area_ring(sx, sy)); g.append(area_ring(ex, ey))
    g.append(t(sx + 30, sy - 52, "SALT LAKE CITY AREA", 22, INTER, 600, TEXT, track=2.5, anchor="end", op=0.9, halo=4))
    g.append(t(ex + 48, ey + 14, "SACRAMENTO AREA", 22, INTER, 600, TEXT, track=2.5, anchor="start", op=0.9, halo=4))
    # highest point on the route
    g.append(f'<circle cx="{mx:.1f}" cy="{my:.1f}" r="10" fill="{TEXT}" stroke="{INK}" stroke-opacity="0.55" stroke-width="3.5"/>')

    # elevation strip
    g.append(t(L + 2, EB[1] - 34, "ELEVATION", 22, INTER, 600, MUTED, track=4, halo=4))
    g.append(f'<path d="{elev_area}" fill="url(#elev)"/>')
    g.append(f'<path d="{elev_line}" fill="none" stroke="{INK}" stroke-opacity="0.30" stroke-width="9" stroke-linejoin="round"/>')
    g.append(f'<path d="{elev_line}" fill="none" stroke="{AMBER}" stroke-width="4.5" stroke-linejoin="round" stroke-linecap="round"/>')
    g.append(f'<circle cx="{tx:.1f}" cy="{ty:.1f}" r="9" fill="{TEXT}" stroke="{INK}" stroke-opacity="0.5" stroke-width="3"/>')
    g.append(t(tx - 22, ty - 16, "HIGHEST POINT · 7,139 FT", 22, INTER, 600, TEXT, track=2.5, anchor="end", halo=4))

    # the brag: one huge number
    g.append(t(L - 11, 1412, "649", 360, BC, 700, TEXT, track=-2, halo=8))
    g.append(t(L + 486, 1412, "MILES", 84, BC, 700, AMBER, track=3, halo=5))

    # supporting stats: label over value, hairline dividers
    cols = [(L + 2, "MOVING TIME", "10h 52m"), (L + 314, "STATES", "3"), (L + 626, "CAREER MILES", "1,284,961")]
    g.append(f'<path d="M{L} 1456 H{R}" stroke="{TEXT}" stroke-opacity="0.28" stroke-width="2"/>')
    for i, (x, label, value) in enumerate(cols):
        if i:
            g.append(f'<path d="M{x - 30} 1484 V1576" stroke="{TEXT}" stroke-opacity="0.28" stroke-width="2"/>')
        g.append(t(x, 1502, label, 21, INTER, 600, MUTED, track=3.5, halo=4))
        g.append(t(x, 1572, value, 66, BC, 600, TEXT, track=0.5, halo=5))
    pre, art = "\n".join(x for x in g[:head] if x), "\n".join(g[head:])
    return (f'{pre}\n{glow}\n<defs><g id="art">\n{art}\n</g></defs>\n'
            '<use href="#art" y="3" filter="url(#shade)"/>\n<use href="#art"/>\n</svg>')

# ---------------------------------------------------------------- test backgrounds (previews only)
night = f'<rect width="{W}" height="{H}" fill="#14161c"/>'
dusk = (f'<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1b2748"/><stop offset="0.38" stop-color="#6a4a6e"/>'
        f'<stop offset="0.56" stop-color="#e08a4f"/><stop offset="0.66" stop-color="#ffd08a"/></linearGradient>'
        f'<radialGradient id="sun" cx="0.62" cy="0.655" r="0.32"><stop offset="0" stop-color="#fff3cf" stop-opacity="0.95"/><stop offset="1" stop-color="#ffd08a" stop-opacity="0"/></radialGradient>'
        f'<linearGradient id="road" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3b3640"/><stop offset="1" stop-color="#17171c"/></linearGradient></defs>'
        f'<rect width="{W}" height="{H}" fill="url(#sky)"/><rect width="{W}" height="{H}" fill="url(#sun)"/>'
        f'<path d="M0 1240 L140 1150 L260 1205 L420 1090 L560 1190 L700 1120 L860 1215 L1000 1140 L1080 1190 V1300 H0 Z" fill="#4a3a52"/>'
        f'<path d="M0 1290 L200 1215 L380 1265 L600 1200 L820 1262 L1080 1225 V1340 H0 Z" fill="#33293c"/>'
        f'<rect y="1300" width="{W}" height="{H - 1300}" fill="#221d27"/>'
        f'<path d="M500 1300 L580 1300 L1000 {H} L80 {H} Z" fill="url(#road)"/>'
        f'<path d="M539 1310 L541 1310 L560 1500 L520 1500 Z M515 1600 L565 1600 L585 {H} L495 {H} Z" fill="#f2d48a" fill-opacity="0.75"/>')
day = (f'<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5aa4e6"/><stop offset="0.6" stop-color="#cfe6f7"/></linearGradient></defs>'
       f'<rect width="{W}" height="{H}" fill="url(#sky)"/>'
       f'<path d="M0 1180 L180 1040 L330 1130 L520 960 L700 1120 L860 1030 L1080 1160 V1300 H0 Z" fill="#8fa7b8"/>'
       f'<path d="M430 1012 L520 960 L600 1030 L540 1020 L500 1050 Z" fill="#f4f8fb"/>'
       f'<path d="M0 1260 L260 1190 L520 1240 L800 1180 L1080 1230 V1340 H0 Z" fill="#6f8f6a"/>'
       f'<rect y="1320" width="{W}" height="{H - 1320}" fill="#c9b27a"/>'
       f'<path d="M505 1320 L575 1320 L980 {H} L100 {H} Z" fill="#55565a"/>')
guides = (f'<rect x="{L}" y="{SAFE["top"]}" width="{R - L}" height="{H - SAFE["top"] - SAFE["bottom"]}" fill="none" stroke="#4fd1ff" stroke-width="2" stroke-dasharray="14 10"/>'
          f'<rect x="{RB[0]}" y="{RB[1]}" width="{RB[2] - RB[0]}" height="{RB[3] - RB[1]}" fill="none" stroke="#ff5fa2" stroke-width="2" stroke-dasharray="6 8"/>')

for name, bg in (("print-overlay", ""), ("preview-night", night), ("preview-dusk", dusk), ("preview-day", day), ("preview-guides", night + guides)):
    (out / f"{name}.svg").write_text(card(bg), encoding="utf-8")
print(len(line), "route points;", (out / "print-overlay.svg").stat().st_size, "bytes")
