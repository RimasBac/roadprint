#!/usr/bin/env python3
"""Terrain card relief layer for design previews (ROA-11). Not production code, not dataset validation.

Mirrors the ADR 0001 pipeline so the preview never shows more than the app can draw:
  real elevation (AWS Terrain Tiles, Terrarium) -> box-averaged to the 2' grid the app bundles
  -> mesh -> per-triangle colour (Natural Earth land cover graded for dark, snow, x hillshade x
  occlusion, haze, edge fade, route light) -> flat triangles painted far-to-near, like SwiftUI Canvas.
  --places frames two city centre points instead of the route (hide-route card): no route, no light.
Writes build/<name>.relief.png (1080x1920, RGB) and build/<name>.relief.json (projected route).

Usage: python3 terrain_relief.py <name> [--flat | --places]   (needs numpy, scipy, pillow; Linux design tool only)
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
MESH = 240            # ADR 0001 says 'initially 160x160'; 160 shows a 7 px triangle staircase at 1080 wide. Proposed: 240 (CTO to confirm)
CELL = 2 / 60         # ADR 0001 grid spacing, degrees
MIN_FOOTPRINT = 100e3 # ADR 0001 minimum terrain footprint, metres
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


def grid2min(lon0, lat0, lon1, lat1):
    """Mean elevation per 2' cell (what the ETOPO-derived bundle stores), on the global 2' lattice."""
    i0, i1 = math.floor((lon0 + 180) / CELL) - 2, math.ceil((lon1 + 180) / CELL) + 2
    j0, j1 = math.floor((90 - lat1) / CELL) - 2, math.ceil((90 - lat0) / CELL) + 2
    lons = -180 + (np.arange(i0, i1) + 0.5) * CELL
    lats = 90 - (np.arange(j0, j1) + 0.5) * CELL
    z = 7
    m = Mosaic(lons[0] - CELL, lats[-1] - CELL, lons[-1] + CELL, lats[0] + CELL, z)
    cpx = CELL / 360 * 2 ** z * 256
    latc = (lats[0] + lats[-1]) / 2
    box = ndimage.uniform_filter(m.a, size=(max(1, round(cpx / math.cos(latc * math.pi / 180))), max(1, round(cpx))), mode='nearest')
    LO, LA = np.meshgrid(lons, lats)
    g = m.sample(LO.ravel(), LA.ravel(), box).reshape(LA.shape)
    return g, lons[0], lats[0]   # row 0 = north


def sample_grid(g, glon0, glat0, lon, lat):
    """Bicubic resample of the 2' grid (mesh vertices)."""
    return ndimage.map_coordinates(g, [(glat0 - lat) / CELL, (lon - glon0) / CELL], order=3, mode='nearest')


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
        _LC = np.asarray(Image.open(p).convert('RGB'), np.float32)
    r, c = (90 - np.asarray(lat)) / CELL - 0.5, (np.asarray(lon) + 180) / CELL - 0.5
    return np.stack([ndimage.map_coordinates(_LC[..., q], [r, c], order=1, mode='nearest') for q in range(3)], -1)


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


# ---------- scene ----------
def render(name, flat=False, places=False):
    key = name.split('-')[0]
    route = [[lo, la, None] for lo, la in PLACES[key]] if places else ROUTES[key]()
    lon = np.array([p[0] for p in route]); lat = np.array([p[1] for p in route])
    lat0, lon0 = (lat.min() + lat.max()) / 2, (lon.min() + lon.max()) / 2
    kx = math.cos(math.radians(lat0)) * M_PER_DEG
    fwd = lambda lo, la: ((np.asarray(lo) - lon0) * kx, (np.asarray(la) - lat0) * M_PER_DEG)
    inv = lambda x, y: (np.asarray(x) / kx + lon0, np.asarray(y) / M_PER_DEG + lat0)
    rx, ry = fwd(lon, lat)

    el = math.radians(v(TT['camera']['elevationDeg']))
    pad = v(TT['hiddenRoute']['framePadding']) if places else v(L['routePadding'])
    top, fh = v(L['reliefTop']), v(L['reliefHeight'])
    depth_px = fh * v(L['reliefDepthFill'])
    rw = max(np.ptp(rx) * (1 + 2 * pad), MIN_FOOTPRINT)
    rd = max(np.ptp(ry) * (1 + 2 * pad), MIN_FOOTPRINT)
    s = min(W / rw, depth_px / (rd * math.sin(el)))          # px per metre
    # Footprint: the full card width, and deeper than the route so far ridges fade into haze.
    gw = W / s
    gd = depth_px / (s * math.sin(el)) * 1.5
    cx, cy = (rx.min() + rx.max()) / 2, (ry.min() + ry.max()) / 2
    x0, y0 = cx - gw / 2, cy - gd * 0.4                     # route sits in the near half
    near_y = top + fh - v(L['reliefFadeBottom']) * 0.1      # screen y of the near edge at hBase

    # mesh
    mx = x0 + np.linspace(0, gw, MESH); my = y0 + np.linspace(0, gd, MESH)
    MX, MY = np.meshgrid(mx, my)                             # row 0 = near (south)
    MLON, MLAT = inv(MX, MY)
    g, glon0, glat0 = grid2min(MLON.min(), MLAT.min(), MLON.max(), MLAT.max())
    h = sample_grid(g, glon0, glat0, MLON.ravel(), MLAT.ravel()).reshape(MX.shape)
    water = (h <= 0) & (not flat)   # flat layout has no DEM: plain land plane
    h = np.maximum(h, 0)
    land = h[~water] if (~water).any() else h.ravel()
    p_lo, p_hi = np.percentile(land, 2), np.percentile(land, 99.5)
    span = max(p_hi - p_lo, v(TT['land']['minSpanMeters']))
    ex = TT['camera']['exaggeration']
    k = 0.0 if flat else float(np.clip(v(ex['targetReliefRatio']) * gw / (span * math.cos(el)), v(ex['min']), v(ex['max'])))
    hbase = p_lo

    def project(x, y, z):
        return (np.asarray(x) - x0) * s, near_y - ((np.asarray(y) - y0) * math.sin(el) + (np.asarray(z) - hbase) * k * math.cos(el)) * s

    SX, SY = project(MX, MY, h)

    # ---- per-triangle colour (what RoadPrintCore would emit as colour indices) ----
    hs = TT['hillshade']
    az, alt = math.radians(v(hs['lightAzimuthDeg'])), math.radians(v(hs['lightAltitudeDeg']))
    Lv = np.array([math.sin(az) * math.cos(alt), math.cos(az) * math.cos(alt), math.sin(alt)])
    oc = TT['occlusion']
    blur = ndimage.uniform_filter(h, size=2 * v(oc['radiusCells']) + 1, mode='nearest')
    occ = np.clip(1 + v(oc['strength']) * (h - blur) / span, v(oc['min']), v(oc['max']))
    raw = landcover(MLON, MLAT)
    # Water: below sea level in the DEM, or Natural Earth's white water/no-data (lakes) at low height.
    water = water | ((raw.min(-1) > 250) & (h < 2000))
    base_rgb = grade(raw)
    sn = TT['snow']
    snow = 0 if flat else smoothstep(v(sn['startMeters']), v(sn['fullMeters']), h)[..., None] * v(sn['opacity'])
    base_rgb = base_rgb * (1 - snow) + hexrgb(v(sn['color'])) * snow
    water_rgb = hexrgb(v(TT['water']['color'])); coast_rgb = hexrgb(v(TT['water']['edge']))
    # world-space fades (fractions of footprint)
    ef = TT['edgeFade']
    u = (MX - x0) / gw; w_ = (MY - y0) / gd
    fade = smoothstep(0, v(ef['side']), u) * smoothstep(0, v(ef['side']), 1 - u) * smoothstep(0, v(ef['near']), w_) * smoothstep(0, v(ef['far']), 1 - w_)
    hz = TT['haze']; haze_rgb = hexrgb(v(hz['color']))
    haze = v(hz['farOpacity']) * np.clip(w_, 0, 1) ** v(hz['curve'])
    # route light: distance from each vertex to the route (metres), gaussian falloff
    rl = TT['routeLight']
    rpts = np.column_stack([rx, ry])
    seg = np.linspace(0, 1, 6)[:, None, None]
    rpts = (rpts[:-1][None] * (1 - seg) + rpts[1:][None] * seg).reshape(-1, 2)
    dist, _ = cKDTree(rpts).query(np.column_stack([MX.ravel(), MY.ravel()]))
    sigma = v(rl['radius']) / s
    light = (v(rl['intensity']) * np.exp(-0.5 * (dist / sigma) ** 2)).reshape(MX.shape) * (0 if places else 1)
    light_rgb = hexrgb(v(rl['color']))

    # Smooth vertex normals; each triangle takes the mean of its three vertex shades. Still one flat
    # colour per triangle (Canvas), but neighbours no longer alternate light/dark along the diagonal.
    gy_, gx_ = np.gradient(h * k, gd / (MESH - 1), gw / (MESH - 1))
    nrm = np.stack([-gx_, -gy_, np.ones_like(h)], -1); nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    vsh = np.minimum(v(hs['max']), v(hs['ambient']) + v(hs['diffuse']) * np.maximum(0, nrm @ Lv))
    s1 = (vsh[:-1, :-1] + vsh[:-1, 1:] + vsh[1:, 1:]) / 3     # sw, se, ne
    s2 = (vsh[:-1, :-1] + vsh[1:, 1:] + vsh[1:, :-1]) / 3     # sw, ne, nw
    avg = lambda f: (f[:-1, :-1] + f[:-1, 1:] + f[1:, 1:] + f[1:, :-1]) / 4
    q_base = avg(base_rgb); q_occ = avg(occ)[..., None]; q_fade = avg(fade)[..., None]
    q_haze = avg(haze)[..., None]; q_light = avg(light)[..., None]
    q_water = avg(water.astype(float))[..., None]
    q_coast = (q_water > 0) & (q_water < 1)
    if flat:
        s1 = s2 = np.ones_like(s1)
        q_occ = np.ones_like(q_occ)

    def finish(sh):
        rgb = q_base * sh[..., None] * q_occ
        rgb = np.where(q_water >= 0.5, water_rgb, rgb)
        rgb = np.where(q_coast & (q_water >= 0.5), coast_rgb, rgb)
        rgb = rgb + light_rgb * q_light
        rgb = rgb * (1 - q_haze) + haze_rgb * q_haze
        rgb = rgb * q_fade + BG * (1 - q_fade)
        return np.clip(rgb, 0, 255)
    c1, c2 = finish(s1), finish(s2)

    # ---- paint far -> near (rows of a north-up heightfield), supersampled ----
    img = Image.new('RGB', (W * SS, H * SS), tuple(int(x) for x in BG))
    dr = ImageDraw.Draw(img)
    sx, sy = SX * SS, SY * SS
    for i in range(MESH - 2, -1, -1):
        for j in range(MESH - 1):
            pa, pb, pc, pd = (sx[i, j], sy[i, j]), (sx[i, j + 1], sy[i, j + 1]), (sx[i + 1, j + 1], sy[i + 1, j + 1]), (sx[i + 1, j], sy[i + 1, j])
            # nw-ne-sw first (farther), then sw-se-ne
            f2, f1 = tuple(int(x) for x in c2[i, j]), tuple(int(x) for x in c1[i, j])
            dr.polygon([pa, pc, pd], fill=f2, outline=f2)   # outline closes hairline seams
            dr.polygon([pa, pb, pc], fill=f1, outline=f1)
    img = img.resize((W, H), Image.LANCZOS)

    # ---- route projection and visibility (bounded ray march, like the core's visibility pass) ----
    hfun = lambda x, y: ndimage.map_coordinates(h, [(y - y0) / gd * (MESH - 1), (x - x0) / gw * (MESH - 1)], order=1, mode='nearest')
    bias = v(TT['ribbon']['depthBias']) / (s * math.cos(el))   # screen-px bias -> exaggerated metres
    pts = []
    for (px_, py_, rec), xx, yy in zip(route, rx, ry):
        if places:
            X, Y = project(xx, yy, float(hfun(np.array([xx]), np.array([yy]))[0]))
            pts.append({'sx': float(X), 'sy': float(Y), 'place': True}); continue
        if rec is None:
            pts.append({'sx': float((xx - x0) * s), 'sy': None, 'gap': True, 'elev': None}); continue
        z = hbase if flat else rec
        X, Y = project(xx, yy, z)
        hidden = False
        if not flat:
            # march toward the camera (south, up): terrain above the sight line hides the point
            ts = np.linspace(0, gd * 0.6, 160)[1:]
            ray = z * k + ts * math.tan(el)
            terr = hfun(np.full_like(ts, xx), yy - ts) * k
            hidden = bool(np.any(terr - ray > bias))
        pts.append({'sx': float(X), 'sy': float(Y), 'gap': False, 'hidden': bool(hidden), 'elev': rec})
    os.makedirs(BUILD, exist_ok=True)
    img.save(os.path.join(BUILD, f'{name}.relief.png'))
    info = {'k': k, 'gwKm': gw / 1000, 'gdKm': gd / 1000, 'span': span, 'pts': pts}
    json.dump(info, open(os.path.join(BUILD, f'{name}.relief.json'), 'w'))
    print(f'{name}: k={k:.1f}x footprint {gw/1000:.0f}x{gd/1000:.0f} km span {span:.0f} m, hidden {sum(p.get("hidden", False) for p in pts)}/{len(pts)}')


if __name__ == '__main__':
    render(sys.argv[1], flat='--flat' in sys.argv, places='--places' in sys.argv)
