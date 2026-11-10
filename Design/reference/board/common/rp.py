"""Shared helpers for the RoadPrint design references: the repo's places.rpgeo reader, geometry, SVG bits."""
import math

# ---------------------------------------------------------------- places.rpgeo (Tools/places/FORMAT.md, version 1)
def read_rpgeo(path, bbox):
    """Return features whose bounding box touches bbox = (minLon, minLat, maxLon, maxLat).
    Each: dict(kind 0 country / 1 region, code, name, parent, rings [[(lon, lat), ...], ...])."""
    b = open(path, "rb").read()
    assert b[:4] == b"RPGE" and b[4] == 1, "unknown places.rpgeo version"
    pos = 5

    def var():
        nonlocal pos
        v = 0; shift = 0
        while True:
            c = b[pos]; pos += 1
            v |= (c & 0x7F) << shift
            if c < 0x80: return v
            shift += 7

    def zz():
        v = var()
        return -((v + 1) >> 1) if v & 1 else v >> 1

    strings = []
    for _ in range(var()):
        n = var(); strings.append(b[pos:pos + n].decode("utf-8")); pos += n
    out = []
    for _ in range(var()):
        kind = b[pos]; pos += 1
        code, name, parent = strings[var()], strings[var()], strings[var()]
        minx, miny = zz() / 1e5, zz() / 1e5
        maxx, maxy = minx + var() / 1e5, miny + var() / 1e5
        hit = not (maxx < bbox[0] or minx > bbox[2] or maxy < bbox[1] or miny > bbox[3])
        rings = []
        for _ in range(var()):
            n = var(); x = y = 0; ring = []
            for _ in range(n):
                x += zz(); y += zz()
                if hit: ring.append((x / 1e5, y / 1e5))
            if hit: rings.append(ring)
        if hit:
            out.append(dict(kind=kind, code=code, name=name, parent=parent, rings=rings))
    return out

# ---------------------------------------------------------------- geometry
def simplify(p, tol):
    """Douglas-Peucker (iterative)."""
    if len(p) < 3: return list(p)
    keep = [False] * len(p); keep[0] = keep[-1] = True; stack = [(0, len(p) - 1)]
    while stack:
        a, b = stack.pop(); (ax, ay), (bx, by) = p[a], p[b]; dx, dy = bx - ax, by - ay; n = math.hypot(dx, dy) or 1e-9
        best, bi = 0.0, -1
        for i in range(a + 1, b):
            d = abs((p[i][0] - ax) * dy - (p[i][1] - ay) * dx) / n
            if d > best: best, bi = d, i
        if best > tol: keep[bi] = True; stack += [(a, bi), (bi, b)]
    return [q for q, f in zip(p, keep) if f]

def simplify_ring(ring, tol):
    """Douglas-Peucker for a closed ring: split at the point farthest from the first one, simplify both halves."""
    if len(ring) < 4: return list(ring)
    x0, y0 = ring[0]
    k = max(range(len(ring)), key=lambda i: (ring[i][0] - x0) ** 2 + (ring[i][1] - y0) ** 2)
    a = simplify(ring[:k + 1], tol); b = simplify(ring[k:] + [ring[0]], tol)
    return a[:-1] + b[:-1]

def smooth_path(p):
    """Catmull-Rom through the points as cubic Beziers."""
    if len(p) < 3: return "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in p)
    d = [f"M{p[0][0]:.1f} {p[0][1]:.1f}"]
    for i in range(len(p) - 1):
        p0, p1, p2, p3 = p[max(i - 1, 0)], p[i], p[i + 1], p[min(i + 2, len(p) - 1)]; t = 0.5 / 3
        d.append(f"C{p1[0] + (p2[0] - p0[0]) * t:.1f} {p1[1] + (p2[1] - p0[1]) * t:.1f} "
                 f"{p2[0] - (p3[0] - p1[0]) * t:.1f} {p2[1] - (p3[1] - p1[1]) * t:.1f} {p2[0]:.1f} {p2[1]:.1f}")
    return " ".join(d)

def clip_ring(ring, rect):
    """Sutherland-Hodgman clip of a closed ring to rect = (x0, y0, x1, y1)."""
    x0, y0, x1, y1 = rect
    def clip(pts, inside, cut):
        res = []
        for i in range(len(pts)):
            a, b = pts[i - 1], pts[i]; ia, ib = inside(a), inside(b)
            if ia and ib: res.append(b)
            elif ia and not ib: res.append(cut(a, b))
            elif not ia and ib: res.append(cut(a, b)); res.append(b)
        return res
    def cx(v): return lambda a, b: (v, a[1] + (b[1] - a[1]) * (v - a[0]) / ((b[0] - a[0]) or 1e-12))
    def cy(v): return lambda a, b: (a[0] + (b[0] - a[0]) * (v - a[1]) / ((b[1] - a[1]) or 1e-12), v)
    p = ring
    for inside, cut in ((lambda q: q[0] >= x0, cx(x0)), (lambda q: q[0] <= x1, cx(x1)),
                        (lambda q: q[1] >= y0, cy(y0)), (lambda q: q[1] <= y1, cy(y1))):
        if not p: break
        p = clip(p, inside, cut)
    return p

def area_centroid(ring):
    a = cx = cy = 0.0
    for i in range(len(ring)):
        (x0, y0), (x1, y1) = ring[i - 1], ring[i]; c = x0 * y1 - x1 * y0
        a += c; cx += (x0 + x1) * c; cy += (y0 + y1) * c
    a /= 2
    if abs(a) < 1e-9: return 0.0, (ring[0] if ring else (0, 0))
    return abs(a), (cx / (6 * a), cy / (6 * a))

def inside(pt, ring):
    x, y = pt; r = False
    for i in range(len(ring)):
        (x0, y0), (x1, y1) = ring[i - 1], ring[i]
        if (y0 > y) != (y1 > y) and x < (x1 - x0) * (y - y0) / ((y1 - y0) or 1e-12) + x0: r = not r
    return r

def dist_to_line(pt, line):
    x, y = pt; best = 1e18
    for i in range(len(line) - 1):
        (ax, ay), (bx, by) = line[i], line[i + 1]; dx, dy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / ((dx * dx + dy * dy) or 1e-12)))
        best = min(best, math.hypot(x - ax - t * dx, y - ay - t * dy))
    return best

def ring_path(ring):
    return "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in ring) + " Z"

# ---------------------------------------------------------------- svg bits
BC, INTER = "Barlow Condensed", "Inter"

def text(x, y, s, size, fam=INTER, w=600, fill="#f0efec", track=0, anchor="start", op=1.0):
    st = ' font-stretch="condensed"' if fam == BC else ""
    return (f'<text x="{x:.1f}" y="{y:.1f}" text-anchor="{anchor}" font-family="{fam}" font-weight="{w}"{st} '
            f'font-size="{size}" letter-spacing="{track}" fill="{fill}" fill-opacity="{op}">{s}</text>')

def interstate_shield(x, y, h, ref):
    s = h / 100
    return (f'<g transform="translate({x:.1f} {y:.1f}) scale({s:.4f})">'
            '<path d="M50 3 C62 9 78 10 92 6 C97 22 99 38 96 54 C92 76 74 91 50 98 C26 91 8 76 4 54 C1 38 3 22 8 6 C22 10 38 9 50 3 Z" fill="#ffffff"/>'
            '<path d="M50 9 C62 14 76 15 88 12 C92 26 93 39 91 53 C87 72 71 85 50 92 C29 85 13 72 9 53 C7 39 8 26 12 12 C24 15 38 14 50 9 Z" fill="#003f87"/>'
            '<path d="M12 12 C24 15 38 14 50 9 C62 14 76 15 88 12 C89.6 17.5 90.8 23 91.6 30 L8.4 30 C9.2 23 10.4 17.5 12 12 Z" fill="#bf2033"/>'
            '<path d="M8.4 30 H91.6" stroke="#ffffff" stroke-width="2.4"/>'
            f'<text x="50" y="25" text-anchor="middle" font-family="{INTER}" font-weight="700" font-size="9.5" letter-spacing="0.9" fill="#fff">INTERSTATE</text>'
            f'<text x="50" y="76" text-anchor="middle" font-family="{BC}" font-stretch="condensed" font-weight="700" font-size="50" fill="#fff">{ref}</text></g>')
