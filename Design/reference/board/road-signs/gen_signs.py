"""RoadPrint road-sign templates (board reference for ROA-49).

Usage: python gen_signs.py out_dir
Writes one SVG per template (no number: the app draws the ref as live text), signs.json,
and contact-sheet.svg (templates + sample refs at 96/48/32 px on three backgrounds).
All templates share a 64-unit-high viewBox. Shields fill the height; rectangular signs are
44 units high and centred, so both kinds carry the same visual weight next to a number.
"""
import json, re, sys, pathlib

out = pathlib.Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)

PAL = {  # our chosen sRGB values for a road-sign feel, not official specifications
    "interstateBlue": "#003f87", "interstateRed": "#bf2033", "white": "#ffffff", "black": "#111111",
    "green": "#00703c", "motorwayBlue": "#0079c1", "yellow": "#ffd200",
    "ausGreen": "#00693c", "ausGold": "#ffc82e",
    "genericFill": "#1d2029", "genericEdge": "#a6aab4", "genericText": "#f0efec",
}
H = 64

def tf(d, sx, sy, dx=0.0, dy=0.0):
    """Scale/translate an absolute M/L/C/Z path (coordinates come in x y pairs)."""
    i = 0
    def num(m):
        nonlocal i
        v = float(m.group(0)); r = v * (sx if i % 2 == 0 else sy) + (dx if i % 2 == 0 else dy); i += 1
        return f"{r:.2f}".rstrip("0").rstrip(".")
    return re.sub(r"-?\d+(?:\.\d+)?", num, d)

def about(d, k, cx=50.0, cy=50.0):
    """Scale a 100-box path about a centre: a cheap inset for outlines."""
    return tf(d, k, k, cx * (1 - k), cy * (1 - k))

# ---- shapes designed in a 100x100 box -------------------------------------------------
IS_OUTER = "M50 3 C62 9 78 10 92 6 C97 22 99 38 96 54 C92 76 74 91 50 98 C26 91 8 76 4 54 C1 38 3 22 8 6 C22 10 38 9 50 3 Z"
IS_INNER = "M50 9 C62 14 76 15 88 12 C92 26 93 39 91 53 C87 72 71 85 50 92 C29 85 13 72 9 53 C7 39 8 26 12 12 C24 15 38 14 50 9 Z"
IS_BAND = "M12 12 C24 15 38 14 50 9 C62 14 76 15 88 12 C89.6 17.5 90.8 23 91.6 30 L8.4 30 C9.2 23 10.4 17.5 12 12 Z"
US_SHIELD = ("M50 4 C45 9 37 11 28 8 C23 6 18 6 14 9 C9 15 6 21 5 29 C4 38 8 45 10 53 C12 65 19 76 31 84 "
             "C39 89 46 93 50 97 C54 93 61 89 69 84 C81 76 88 65 90 53 C92 45 96 38 95 29 C94 21 91 15 86 9 "
             "C82 6 77 6 72 8 C63 11 55 9 50 4 Z")
CA_SHIELD = "M9 5 C22 9 36 9 50 5 C64 9 78 9 91 5 L91 52 C91 74 73 90 50 97 C27 90 9 74 9 52 Z"

# "INTERSTATE" as single-stroke letters on a 3x5 grid (it is texture at these sizes, not text)
LET = {"I": "M1.5 0 V5", "N": "M0 5 V0 L3 5 V0", "T": "M0 0 H3 M1.5 0 V5", "E": "M3 0 H0 V5 H3 M0 2.5 H2.4",
       "R": "M0 5 V0 H2 L3 1 V1.6 L2 2.6 H0 M1.8 2.6 L3 5", "S": "M3 0.7 L2.3 0 H0.7 L0 0.7 V1.8 L0.7 2.5 H2.3 L3 3.2 V4.3 L2.3 5 H0.7 L0 4.3",
       "A": "M0 5 L1.5 0 L3 5 M0.6 3.3 H2.4"}

def lettering(word, cx, top, cap, gap=0.9):
    k = cap / 5; adv = 3 * k + gap; x0 = cx - (len(word) * adv - gap) / 2
    def place(d, ox):
        o = []; toks = re.findall(r"[MLHV]|-?\d+(?:\.\d+)?", d); i = 0
        while i < len(toks):
            c = toks[i]; i += 1
            if c in "ML":
                o.append(f"{c}{ox + float(toks[i]) * k:.2f} {top + float(toks[i + 1]) * k:.2f}"); i += 2
            elif c == "H":
                o.append(f"H{ox + float(toks[i]) * k:.2f}"); i += 1
            elif c == "V":
                o.append(f"V{top + float(toks[i]) * k:.2f}"); i += 1
        return " ".join(o)
    return " ".join(place(LET[ch], x0 + n * adv) for n, ch in enumerate(word))

def svg(w, title, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {H}" width="{w}" height="{H}">'
            f"<title>{title}</title>{body}</svg>\n")

def interstate(w, band_text=True):
    sx, sy = w / 100, H / 100
    b = (f'<path d="{tf(IS_OUTER, sx, sy)}" fill="{PAL["white"]}"/><path d="{tf(IS_INNER, sx, sy)}" fill="{PAL["interstateBlue"]}"/>'
         f'<path d="{tf(IS_BAND, sx, sy)}" fill="{PAL["interstateRed"]}"/>'
         f'<path d="M{8.4 * sx:.2f} {30 * sy:.2f} H{91.6 * sx:.2f}" stroke="{PAL["white"]}" stroke-width="1.6"/>')
    if band_text:
        b += (f'<path d="{lettering("INTERSTATE", w / 2, 10.4, 5.0, 0.95 * sx / 0.64)}" fill="none" stroke="{PAL["white"]}" '
              f'stroke-width="0.95" stroke-linecap="round" stroke-linejoin="round"/>')
    return b

def us_highway(w=64):
    s = w / 100
    return (f'<path d="{tf(US_SHIELD, s, H / 100)}" fill="{PAL["black"]}"/>'
            f'<path d="{tf(about(US_SHIELD, 0.9), s, H / 100)}" fill="{PAL["white"]}"/>')

def canada(w=60):
    sx, sy = w / 100, H / 100
    return (f'<path d="{tf(CA_SHIELD, sx, sy)}" fill="{PAL["white"]}"/>'
            f'<path d="{tf(about(CA_SHIELD, 0.9), sx, sy)}" fill="{PAL["green"]}"/>'
            f'<path d="M{15 * sx:.2f} 17 H{85 * sx:.2f}" stroke="{PAL["white"]}" stroke-width="2"/>')

def plate(w, fill, edge, ring=2.5, r=6):
    """Rectangular sign: 44 high, centred in the 64-high box, with an inset edge line."""
    y0, h = 10, 44
    return (f'<rect x="0" y="{y0}" width="{w}" height="{h}" rx="{r}" fill="{fill}"/>'
            f'<rect x="{ring}" y="{y0 + ring}" width="{w - 2 * ring}" height="{h - 2 * ring}" rx="{r - ring + 0.5}" fill="none" stroke="{edge}" stroke-width="2"/>')

# id -> (width, body, text spec, sample refs, description)
T = {
    "usInterstate":       (64, interstate(64),        dict(cx=32, cy=40.5, w=40, size=28, color="white"), ["5", "80"], "US interstate shield"),
    "usInterstate-wide":  (80, interstate(80),        dict(cx=40, cy=40.5, w=54, size=28, color="white"), ["405", "495"], "US interstate shield, 3 digits"),
    "usInterstate-small": (64, interstate(64, False), dict(cx=32, cy=40.5, w=40, size=28, color="white"), ["80"], "US interstate shield for heights under 40 px (plain band)"),
    "usHighway":          (64, us_highway(),          dict(cx=32, cy=35.5, w=40, size=29, color="black"), ["1", "50", "101"], "US route shield"),
    "canadaHighway":      (60, canada(),              dict(cx=30, cy=38.5, w=38, size=27, color="white"), ["1", "401"], "Generic Canadian highway shield"),
    "eRoad":              (88, plate(88, PAL["green"], PAL["white"]),        dict(cx=44, cy=32, w=70, size=29, color="white"), ["E4", "E40", "E105"], "European E-road"),
    "ukMotorway":         (88, plate(88, PAL["motorwayBlue"], PAL["white"]), dict(cx=44, cy=32, w=70, size=29, color="white"), ["M1", "M25"], "UK motorway"),
    "ukARoad":            (88, plate(88, PAL["green"], PAL["white"]),        dict(cx=44, cy=32, w=70, size=29, color="yellow"), ["A1", "A303"], "UK A-road"),
    "australia":          (88, plate(88, PAL["ausGreen"], PAL["ausGold"]),   dict(cx=44, cy=32, w=70, size=29, color="ausGold"), ["A1", "M31"], "Australian alphanumeric route"),
    "generic":            (88, plate(88, PAL["genericFill"], PAL["genericEdge"]), dict(cx=44, cy=32, w=70, size=29, color="genericText"), ["7", "N7", "A380"], "Neutral sign for everywhere else"),
}
CAP = 0.708          # Barlow Condensed Bold cap height / font size (measured with the preview renderer)
ADV = 0.47           # average advance per character / font size, used only to pick the fit scale
MIN_SCALE = 0.7

signs = {"$schema": "./signs.schema.json", "version": 1, "viewBoxHeight": H, "font": "Barlow Condensed", "fontWeight": 700,
         "palette": PAL, "templates": {}}
for sid, (w, body, tx, refs, desc) in T.items():
    (out / f"{sid}.svg").write_text(svg(w, f"RoadPrint road sign: {desc}", body), encoding="utf-8")
    signs["templates"][sid] = {
        "file": f"{sid}.svg", "viewBox": [0, 0, w, H], "description": desc,
        "textBox": {"x": tx["cx"] - tx["w"] / 2, "y": round(tx["cy"] - tx["size"] * CAP / 2, 2), "width": tx["w"], "height": round(tx["size"] * CAP, 2)},
        "fontSize": tx["size"], "baseline": round(tx["cy"] + tx["size"] * CAP / 2, 2), "tracking": 0,
        "minScale": MIN_SCALE, "textColor": PAL[tx["color"]], "samples": refs,
    }
signs["templates"]["usInterstate"].update(wideAbove=2, wide="usInterstate-wide", small="usInterstate-small", smallBelow=40)
signs["templates"]["usInterstate-wide"].update(small=None)
(out / "signs.json").write_text(json.dumps(signs, indent=2) + "\n", encoding="utf-8")

# ---- contact sheet -------------------------------------------------------------------
def sign(sid, ref, x, y, px):
    """One sign with its number at display height px, top-left at (x, y). Returns (svg, width)."""
    w, body, tx, _, _ = T[sid]; k = px / H; t = signs["templates"][sid]
    scale = max(MIN_SCALE, min(1.0, tx["w"] / (len(ref) * ADV * tx["size"])))
    size = tx["size"] * scale
    base = tx["cy"] + size * CAP / 2
    g = (f'<g transform="translate({x:.1f} {y:.1f}) scale({k:.4f})">{body}'
         f'<text x="{tx["cx"]}" y="{base:.2f}" text-anchor="middle" font-family="Barlow Condensed" font-stretch="condensed" '
         f'font-weight="700" font-size="{size:.2f}" fill="{t["textColor"]}">{ref}</text></g>')
    return g, w * k

BGS = [("app dark", "#14161c", "#a6aab4"), ("card", "#1d2029", "#a6aab4"), ("Road Atlas paper", "#f3eadb", "#5b5548")]
rows = [s for s in T]
LABEL_W, CELL_W, ROW_H, HEAD = 250, 500, 128, 70
SW, SH = LABEL_W + CELL_W * len(BGS), HEAD + ROW_H * len(rows)
cs = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SW} {SH}" width="{SW}" height="{SH}">',
      f'<rect width="{SW}" height="{SH}" fill="#0b0c10"/>']
for b, (name, col, ink) in enumerate(BGS):
    x0 = LABEL_W + b * CELL_W
    cs.append(f'<rect x="{x0}" y="0" width="{CELL_W}" height="{SH}" fill="{col}"/>')
    cs.append(f'<text x="{x0 + 24}" y="42" font-family="Inter" font-weight="600" font-size="20" fill="{ink}">{name} · 96 / 48 / 32 px</text>')
for r, sid in enumerate(rows):
    y0 = HEAD + r * ROW_H
    cs.append(f'<text x="24" y="{y0 + ROW_H / 2 + 7}" font-family="Inter" font-weight="600" font-size="19" fill="#f0efec">{sid}</text>')
    refs = T[sid][3]
    for b in range(len(BGS)):
        x = LABEL_W + b * CELL_W + 24
        for n, px in enumerate((96, 48, 32)):
            for ref in ([refs[min(n, len(refs) - 1)]] if px == 96 else refs):
                g, wpx = sign(sid, ref, x, y0 + (ROW_H - px) / 2, px)
                cs.append(g); x += wpx + 14
            x += 18
cs.append("</svg>")
(out / "contact-sheet.svg").write_text("\n".join(cs), encoding="utf-8")
sizes = {f.name: f.stat().st_size for f in sorted(out.glob("*.svg")) if f.name != "contact-sheet.svg"}
print(sizes)
