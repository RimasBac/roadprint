#!/usr/bin/env python3
"""Terrain card relief layer, style 5 (design previews). Not production code, not dataset validation.

A full-screen perspective heightfield: real elevation (AWS Terrain Tiles, Terrarium) at the zoom whose
pixel matches the mesh spacing, Natural Earth I land cover graded for the dark card, golden-hour light
(warm key, cool fill), occlusion, snow, warm route light and horizon haze, painted far-to-near as flat
triangles about 2 px tall. The elevation detail assumes docs/adr/0006 (tiles for the trip's area), not
the 2' bundle of ADR 0001. --places frames two city centre points instead of the route (hide-route
card): no route, no route light. --flat draws the land with no height (no usable altitude).
Writes build/<name>.relief.png (1080x1920, RGB) and build/<name>.relief.json (projected route).

Usage: python3 terrain_relief.py <name> [--flat | --places]   (needs numpy, scipy, pillow)
"""
import io, json, math, os, sys, urllib.request
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.spatial import cKDTree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
CACHE, BUILD = os.path.join(HERE, '.cache'), os.path.join(HERE, 'build')
T = json.load(open(os.path.join(ROOT, 'Design', 'tokens.json')))
TT, C = T['terrain'], T['color']
v = lambda o: o['$value']
W, H = v(TT['export']['width']), v(TT['export']['height'])
L = TT['layout']
CELL = 2 / 60         # land-cover grid spacing (Natural Earth resampled to 2'), degrees
MIN_FOOTPRINT = 60e3  # ADR 0001 said 100 km for the 2' grid; with finer elevation (style 5) 60 km keeps short routes large
R_EARTH = 6371008.8
M_PER_DEG = R_EARTH * math.pi / 180
SS = 2                # supersampling for anti-aliased triangle edges

hexrgb = lambda h: np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], float)
BG = hexrgb(v(C['background']))


# ---------- elevation tiles ----------
def tile(z, x, y):
    p = os.path.join(CACHE, 'terrarium', str(z), str(x), f'{y}.png')
    if not os.path.exists(p):
        os.makedirs(os.path.dirname(p), exist_ok=True)
        url = f'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png'
        with urllib.request.urlopen(url, timeout=60) as r, open(p, 'wb') as f:
            f.write(r.read())
    a = np.asarray(Image.open(p).convert('RGB'), float)
    return a[..., 0] * 256 + a[..., 1] + a[..., 2] / 256 - 32768


def merc(lon, lat, z):
    n = 2 ** z * 256
    lat = np.clip(lat, -85, 85) * math.pi / 180
    return (np.asarray(lon) + 180) / 360 * n, (1 - np.log(np.tan(lat) + 1 / np.cos(lat)) / math.pi) / 2 * n


class Mosaic:
    def __init__(self, lon0, lat0, lon1, lat1, z):
        self.z = z
        (x0, x1), (y1, y0) = merc(np.array([lon0, lon1]), np.array([lat0, lat1]), z)
        tx0, tx1, ty0, ty1 = int(x0 // 256), int(x1 // 256), int(y0 // 256), int(y1 // 256)
        rows = [np.hstack([tile(z, tx, ty) for tx in range(tx0, tx1 + 1)]) for ty in range(ty0, ty1 + 1)]
        self.a, self.ox, self.oy = np.vstack(rows), tx0 * 256, ty0 * 256

    def sample(self, lon, lat, arr=None):
        px, py = merc(lon, lat, self.z)
        return ndimage.map_coordinates(self.a if arr is None else arr, [py - self.oy - 0.5, px - self.ox - 0.5], order=1, mode='nearest')


# ---------- land cover colour ----------
_LC = None


def landcover(lon, lat):
    """Natural Earth I land cover (NE1_LR_LC, public domain) resampled to the 2' grid, RGB 0-255."""
    global _LC
    if _LC is None:
        Image.MAX_IMAGE_PIXELS = None
        p = os.path.join(CACHE, 'ne', 'ne1_2min.png')
        if not os.path.exists(p):
            sys.exit('missing .cache/ne/ne1_2min.png: run Tools/design/fetch_landcover.py first')
        _LC = np.asarray(Image.open(p).convert('RGB'))   # uint8: 175 MB instead of 700 MB as float
    r, c = (90 - np.asarray(lat)) / CELL - 0.5, (np.asarray(lon) + 180) / CELL - 0.5
    return np.stack([ndimage.map_coordinates(_LC[..., q], [r, c], order=1, mode='nearest') for q in range(3)], -1).astype(float)


def grade(rgb):
    """Grade the daylight land-cover tint for the dark card (terrain.landCover tokens)."""
    lc = TT['landCover']
    c = rgb / 255.0
    lum = (c @ np.array([0.299, 0.587, 0.114]))[..., None]
    c = lum + (c - lum) * v(lc['saturation'])
    c = np.clip(c, 0, 1) ** v(lc['gamma']) * v(lc['brightness'])
    return c * 255


# ---------- routes ----------
def densify(pts, step_m):
    out = [pts[0]]
    for a, b in zip(pts, pts[1:]):
        d = math.hypot((b[0] - a[0]) * math.cos(math.radians(a[1])), b[1] - a[1]) * M_PER_DEG
        n = max(1, int(d // step_m))
        for k in range(1, n + 1):
            t = k / n
            out.append([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t])
    return out


def resample(pts, step_m):
    """Even spacing along the line, keeping roughly one point per step."""
    out, acc = [pts[0]], 0.0
    for a, b in zip(pts, pts[1:]):
        acc += math.hypot((b[0] - a[0]) * math.cos(math.radians(a[1])), b[1] - a[1]) * M_PER_DEG
        if acc >= step_m:
            out.append(b); acc = 0.0
    if out[-1] is not pts[-1]:
        out.append(pts[-1])
    return out


def cum_km(pts):
    d = [0.0]
    for a, b in zip(pts, pts[1:]):
        d.append(d[-1] + math.hypot((b[0] - a[0]) * math.cos(math.radians(a[1])), b[1] - a[1]) * M_PER_DEG / 1000)
    return d


def trim_ends(pts, km=8):  # plan §4.2 privacy trim, applied before anything is drawn
    d = cum_km(pts); tot = d[-1]
    return [p for p, x in zip(pts, d) if km <= x <= tot - km]


def recorded_alt(pts):
    """Stand-in for GPS altitude: finer elevation (z10, ~110 m pixels) sampled on the road."""
    lon = np.array([p[0] for p in pts]); lat = np.array([p[1] for p in pts])
    m = Mosaic(lon.min() - .05, lat.min() - .05, lon.max() + .05, lat.max() + .05, 10)
    return m.sample(lon, lat)


def route_i80():
    src = os.path.join(ROOT, 'docs', 'plan', 'mockups', 'source')
    r = json.load(open(os.path.join(src, 'routes.json')))['SLC-SAC']['coords']
    e = json.load(open(os.path.join(src, 'elev.json')))
    pts = resample([list(p[:2]) for p in r], 1500)
    d = np.array(cum_km(pts)) / 1.609344
    ed = np.array([s['d'] for s in e]); ef = np.array([s['ft'] for s in e]) * 0.3048
    alt = np.interp(d, ed, ef)
    # Illustrative recording gap (invalid altitude) across ~60 miles of Nevada.
    return [[p[0], p[1], None if 290 < dd < 350 else float(a)] for p, dd, a in zip(pts, d, alt)]


OSRM_ENDS = {'brenner': '11.392,47.262;11.355,46.498', 'nullarbor': '121.70,-32.20;133.68,-32.13'}


def route_osrm(name, step):
    p = os.path.join(CACHE, 'routes', f'{name}.osrm.json')
    if not os.path.exists(p):   # public OSRM demo server, OSM data (ODbL); preview use only
        os.makedirs(os.path.dirname(p), exist_ok=True)
        url = f'https://router.project-osrm.org/route/v1/driving/{OSRM_ENDS[name]}?overview=full&geometries=geojson'
        with urllib.request.urlopen(url, timeout=60) as r, open(p, 'wb') as f:
            f.write(r.read())
    g = json.load(open(p))['routes'][0]['geometry']['coordinates']
    pts = trim_ends(resample(densify(g, step / 4), step))
    alt = ndimage.uniform_filter1d(recorded_alt(pts), size=9, mode='nearest')   # GPS altitude is smoothed in the core too
    return [[p[0], p[1], float(a)] for p, a in zip(pts, alt)]


PLACES = {  # city centre points (what the card's title already names), never trip points
    'i80': [[-111.891, 40.761], [-121.494, 38.582]],
    'brenner': [[11.393, 47.268], [11.354, 46.498]],
    'nullarbor': [[121.783, -32.198], [133.676, -32.126]],
}

ROUTES = {
    'i80': route_i80,
    'brenner': lambda: route_osrm('brenner', 400),
    'nullarbor': lambda: route_osrm('nullarbor', 2000),
}


# ---------- colour helpers ----------
def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


# ---------- scene (style 5: full-screen perspective relief) ----------
# The land fills the whole card, from the horizon at the top (terrain.layout.horizonY) to below the
# bottom edge. The route is framed in a middle band (routeBandTop..routeBandBottom) so the title above
# it and the number below it sit on open land with no road. The camera looks north; ground depth d runs
# 0 (near, bottom) .. 1 (far, horizon); perspective scale f(d) = 1/(1 + p d).
#
# Detail: elevation comes from Terrarium tiles at the zoom whose pixel matches the mesh spacing (z6-z11),
# drawn as a mesh with about one row per 2.4 screen px, so the land is shaded at screen resolution. This
# is NOT what the 2' offline bundle (ADR 0001) can draw: it needs a finer elevation source (open decision,
# see Design/cards/terrain/README.md "Elevation detail").
MESH_ROWS, MESH_COLS = 820, 700
MAX_TILES = 160


def pick_zoom(lat, metres, lon0, lat0, lon1, lat1):
    """Finest zoom whose pixel is about the mesh spacing, within the tile budget."""
    for z in range(11, 5, -1):
        px = 2 * math.pi * R_EARTH * math.cos(math.radians(lat)) / (256 * 2 ** z)
        (x0, x1), (y1, y0) = merc(np.array([lon0, lon1]), np.array([lat0, lat1]), z)
        n = (int(x1 // 256) - int(x0 // 256) + 1) * (int(y1 // 256) - int(y0 // 256) + 1)
        if px >= metres * 0.6 and n <= MAX_TILES:
            return z, px
    return 6, 2 * math.pi * R_EARTH * math.cos(math.radians(lat)) / (256 * 64)


def render(name, flat=False, places=False):
    key = name.split('-')[0]
    route = [[lo, la, None] for lo, la in PLACES[key]] if places else ROUTES[key]()
    lon = np.array([p[0] for p in route]); lat = np.array([p[1] for p in route])
    lat0, lon0 = (lat.min() + lat.max()) / 2, (lon.min() + lon.max()) / 2
    kx = math.cos(math.radians(lat0)) * M_PER_DEG
    fwd = lambda lo, la: ((np.asarray(lo) - lon0) * kx, (np.asarray(la) - lat0) * M_PER_DEG)
    inv = lambda x, y: (np.asarray(x) / kx + lon0, np.asarray(y) / M_PER_DEG + lat0)
    rx, ry = fwd(lon, lat)

    cam = TT['camera']
    el = math.radians(v(cam['elevationDeg']))
    p = v(cam['perspective'])
    pad = v(TT['hiddenRoute']['framePadding']) if places else v(L['routePadding'])
    side_px = v(TT['safeArea']['side'])
    horizon_y, near_y = v(L['horizonY']), v(L['nearY'])
    band_t, band_b = v(L['routeBandTop']), v(L['routeBandBottom'])
    dpx = near_y - horizon_y
    # screen y <-> ground depth fraction (ground at base height)
    ys_of = lambda d: near_y - dpx * np.log1p(p * np.asarray(d)) / math.log1p(p)
    d_of = lambda y: ((1 + p) ** ((near_y - np.asarray(y, float)) / dpx) - 1) / p
    fsc = lambda d: 1 / (1 + p * np.asarray(d))
    d_lo, d_hi = float(d_of(band_b)), float(d_of(band_t))
    d_mid = float(d_of((band_t + band_b) / 2))
    cx, cy = (rx.min() + rx.max()) / 2, (ry.min() + ry.max()) / 2
    # Ground depth gd (metres from the near edge to the horizon) sets the scale: s = A p / (sin(el) gd)
    # px per metre at the near edge, with A = dpx / ln(1 + p). Grow gd until the route fits the band
    # (depth) and the safe width, and the near edge is at least the minimum footprint wide.
    A = dpx / math.log1p(p)
    gd = max(np.ptp(ry) * (1 + 2 * pad) / (d_hi - d_lo), 1.0)
    for _ in range(12):
        s = A * p / (math.sin(el) * gd)
        y0 = cy - d_mid * gd
        dr = (ry - y0) / gd
        wneed = max(np.max(np.abs(rx - cx) * fsc(dr)) * 2 * (1 + pad) * s, 1e-9)
        grow = max(wneed / (W - 2 * side_px), MIN_FOOTPRINT / (W / s), 1.0)
        if grow < 1.001:
            break
        gd *= grow
    s = A * p / (math.sin(el) * gd)
    y0 = cy - d_mid * gd
    gw = W / s

    # mesh: rows evenly spaced on screen (near edge below the card, far edge at the horizon)
    row_y = np.linspace(near_y + 120, horizon_y, MESH_ROWS)
    row_d = d_of(row_y)
    half = (W / 2 + 60) / (s * fsc(row_d))                   # 60 px bleed past each side
    MX = cx + np.linspace(-1, 1, MESH_COLS)[None, :] * half[:, None]
    MY = np.repeat((y0 + row_d * gd)[:, None], MESH_COLS, 1)  # row 0 = near (south)
    MLON, MLAT = inv(MX, MY)

    # elevation: one Terrarium mosaic at the zoom that matches the mid-depth column spacing
    spacing = 2 * half[MESH_ROWS // 3] / MESH_COLS
    z, px_m = pick_zoom(lat0, spacing, MLON.min(), MLAT.min(), MLON.max(), MLAT.max())
    mos = Mosaic(MLON.min() - 0.05, MLAT.min() - 0.05, MLON.max() + 0.05, MLAT.max() + 0.05, z)
    dem = ndimage.gaussian_filter(np.maximum(mos.a, -50).astype(np.float32), 0.8)          # tame aliasing in far rows
    hgrid = lambda X, Y: mos.sample(*inv(X, Y), dem).reshape(np.shape(X))
    h = hgrid(MX.ravel(), MY.ravel()).reshape(MX.shape)
    water = (h <= 0) & (not flat)
    h = np.maximum(h, 0)
    land = h[~water] if (~water).any() else h.ravel()
    p_lo, p_hi = np.percentile(land, 2), np.percentile(land, 99.5)
    span = max(p_hi - p_lo, v(TT['land']['minSpanMeters']))
    ex = cam['exaggeration']
    k = 0.0 if flat else float(np.clip(v(ex['targetReliefRatio']) * gw / (span * math.cos(el)), v(ex['min']), v(ex['max'])))
    hbase = p_lo

    def project(x, y, zz):
        d = (np.asarray(y) - y0) / gd
        f = fsc(d)
        return W / 2 + (np.asarray(x) - cx) * s * f, ys_of(d) - (np.asarray(zz) - hbase) * k * math.cos(el) * f * s

    SX, SY = project(MX, MY, h)

    # ---- light: normals and occlusion from the mosaic itself (metres), sampled at the vertices ----
    gy_px, gx_px = np.gradient(dem * k)
    dzdx = mos.sample(MLON.ravel(), MLAT.ravel(), gx_px / px_m).reshape(MX.shape)
    # Web Mercator pixels are square on the ground; image rows run south.
    dzdy = -mos.sample(MLON.ravel(), MLAT.ravel(), gy_px / px_m).reshape(MX.shape)
    nrm = np.stack([-dzdx, -dzdy, np.ones_like(h)], -1); nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    hs = TT['hillshade']
    az, alt = math.radians(v(hs['lightAzimuthDeg'])), math.radians(v(hs['lightAltitudeDeg']))
    Lv = np.array([math.sin(az) * math.cos(alt), math.cos(az) * math.cos(alt), math.sin(alt)])
    lam = np.maximum(0, nrm @ Lv)
    oc = TT['occlusion']
    blur = ndimage.gaussian_filter(dem, v(oc['radiusMeters']) / px_m)
    occ_m = mos.sample(MLON.ravel(), MLAT.ravel(), dem - blur).reshape(MX.shape)
    occ = np.clip(1 + v(oc['strength']) * occ_m / span, v(oc['min']), v(oc['max']))
    key_c = hexrgb(v(hs['keyColor'])) / 255
    amb_c = hexrgb(v(hs['ambientColor'])); amb_c = amb_c / amb_c.max()
    light_v = np.minimum(v(hs['max']), v(hs['ambient']) * amb_c + v(hs['diffuse']) * lam[..., None] * key_c)
    if flat:
        light_v = np.ones_like(light_v); occ = np.ones_like(occ)

    # ---- ground colour ----
    raw = landcover(MLON, MLAT)
    water = water | ((raw.min(-1) > 250) & (h < 2000))
    base = grade(raw)
    sn = TT['snow']
    snow = 0 if flat else smoothstep(v(sn['startMeters']), v(sn['fullMeters']), h)[..., None] * v(sn['opacity'])
    base = base * (1 - snow) + hexrgb(v(sn['color'])) * snow
    rgb_v = base * light_v * occ[..., None]
    wq = smoothstep(0.25, 0.75, ndimage.uniform_filter(water.astype(float), 3))[..., None]
    rgb_v = rgb_v * (1 - wq) + hexrgb(v(TT['water']['color'])) * wq
    # route light (warm spill around the visible route), not in hide-route mode
    rl = TT['routeLight']
    if not places:
        rpts = np.column_stack([rx, ry]); seg = np.linspace(0, 1, 6)[:, None, None]
        rpts = (rpts[:-1][None] * (1 - seg) + rpts[1:][None] * seg).reshape(-1, 2)
        dist, _ = cKDTree(rpts).query(np.column_stack([MX.ravel(), MY.ravel()]))
        sig = v(rl['radius']) / (s * fsc((MY.ravel() - y0) / gd))
        rgb_v = rgb_v + hexrgb(v(rl['color'])) * (v(rl['intensity']) * np.exp(-0.5 * (dist / sig) ** 2)).reshape(MX.shape)[..., None]
    # haze toward the horizon, then the far edge melts into the sky
    hz = TT['haze']
    haze = (v(hz['farOpacity']) * np.clip(row_d, 0, 1) ** v(hz['curve']))[:, None, None]
    rgb_v = rgb_v * (1 - haze) + hexrgb(v(hz['color'])) * haze
    sky_c = hexrgb(v(TT['sky']['horizon']))
    far = smoothstep(1 - v(TT['edgeFade']['far']), 1.0, np.clip(row_d, 0, 1))[:, None, None]
    rgb_v = np.clip(rgb_v * (1 - far) + sky_c * far, 0, 255)

    # ---- paint far -> near, two triangles per quad, supersampled ----
    img = Image.new('RGB', (W * SS, H * SS), tuple(int(x) for x in BG))
    dr_ = ImageDraw.Draw(img)
    for yy in range(0, int((horizon_y + 260) * SS)):   # the sky band above the horizon
        t = smoothstep(horizon_y - 260, horizon_y + 40, yy / SS)
        dr_.line([(0, yy), (W * SS, yy)], fill=tuple(int(c) for c in BG + (sky_c - BG) * t))
    tri = lambda f: ((f[:-1, :-1] + f[:-1, 1:] + f[1:, 1:]) / 3, (f[:-1, :-1] + f[1:, 1:] + f[1:, :-1]) / 3)
    c1, c2 = (np.clip(t, 0, 255).astype(np.uint8) for t in tri(rgb_v))
    sx, sy = SX * SS, SY * SS
    for i in range(MESH_ROWS - 2, -1, -1):
        ra, rb = sx[i], sx[i + 1]; ya, yb = sy[i], sy[i + 1]
        if min(ya.min(), yb.min()) > H * SS + 8 or max(ya.max(), yb.max()) < -8:
            continue
        for j in range(MESH_COLS - 1):
            if ra[j + 1] < 0 or ra[j] > W * SS:
                continue
            pa, pb, pc, pd = (ra[j], ya[j]), (ra[j + 1], ya[j + 1]), (rb[j + 1], yb[j + 1]), (rb[j], yb[j])
            f2, f1 = tuple(c2[i, j]), tuple(c1[i, j])
            dr_.polygon([pa, pc, pd], fill=f2, outline=f2)
            dr_.polygon([pa, pb, pc], fill=f1, outline=f1)
    img = img.resize((W, H), Image.LANCZOS)

    # ---- route projection and visibility (bounded ray march toward the camera) ----
    bias = v(TT['ribbon']['depthBias']) / (s * math.cos(el))
    pts = []
    for (_, _, rec), xx, yy in zip(route, rx, ry):
        if places:
            X, Y = project(xx, yy, float(hgrid(np.array([xx]), np.array([yy]))[0]))
            pts.append({'sx': float(X), 'sy': float(Y), 'place': True}); continue
        if rec is None:
            pts.append({'sx': float(project(xx, yy, hbase)[0]), 'sy': None, 'gap': True, 'elev': None}); continue
        zz = hbase if flat else rec
        X, Y = project(xx, yy, zz)
        hidden = False
        if not flat:
            ts = np.linspace(0, gd * 0.5, 200)[1:]
            ray = zz * k + ts * math.tan(el)
            terr = hgrid(np.full_like(ts, xx), yy - ts) * k
            hidden = bool(np.any(terr - ray > bias))
        pts.append({'sx': float(X), 'sy': float(Y), 'gap': False, 'hidden': hidden, 'elev': rec})
    os.makedirs(BUILD, exist_ok=True)
    img.save(os.path.join(BUILD, f'{name}.relief.png'))
    info = {'k': k, 'gwKm': gw / 1000, 'gdKm': gd / 1000, 'span': span, 'zoom': z, 'horizonY': horizon_y, 'pts': pts}
    json.dump(info, open(os.path.join(BUILD, f'{name}.relief.json'), 'w'))
    print(f'{name}: k={k:.1f}x near width {gw/1000:.0f} km, depth {gd/1000:.0f} km, z{z} ({px_m:.0f} m/px), span {span:.0f} m, hidden {sum(q.get("hidden", False) for q in pts)}/{len(pts)}')


if __name__ == '__main__':
    render(sys.argv[1], flat='--flat' in sys.argv, places='--places' in sys.argv)
