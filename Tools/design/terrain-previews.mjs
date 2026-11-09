#!/usr/bin/env node
// Terrain card composition previews (ROA-11). Not production code and not a dataset check.
//
// Relief here is SYNTHETIC: a procedural heightfield shaped to look like each region, then
// box-filtered to the ADR 0001 grid spacing (2 arc-minutes) so it never shows more detail than
// the bundled ETOPO grid can. Routes: I-80 uses the real mockup route and elevation profile;
// Brenner and Nullarbor use hand-placed town waypoints. Every visual value comes from
// Design/tokens.json. Output: Design/cards/terrain/previews/*.png at 1080×1920.
//
// Usage: node terrain-previews.mjs [variant ...]
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { deflateSync } from 'node:zlib';
import { Resvg } from '@resvg/resvg-js';
import { renderSvg, fontOptions } from './render.mjs';

const ROOT = new URL('../../', import.meta.url);
const T = JSON.parse(readFileSync(new URL('Design/tokens.json', ROOT)));
const OUT = new URL('Design/cards/terrain/previews/', ROOT);
mkdirSync(OUT, { recursive: true });

// ---------- token helpers ----------
const C = T.color, TT = T.terrain, L = TT.layout;
const v = o => o.$value;
const W = v(TT.export.width), H = v(TT.export.height);
const hex = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
const ref = s => (typeof s === 'string' && s.startsWith('{') ? s.slice(1, -1).split('.').reduce((o, k) => o[k], T).$value : s);
const typeStyle = k => { const t = v(TT.type[k]); return { ...t, color: ref(t.color) }; };
const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
const lerp = (a, b, t) => a + (b - a) * t;
const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };

// ---------- text ----------
function textAttrs(k, extra = '') {
  const s = typeStyle(k);
  const stretch = s.family.includes('Condensed') ? ' font-stretch="condensed"' : '';
  return `font-family="${s.family}"${stretch} font-weight="${s.weight}" font-size="${s.size}" letter-spacing="${s.tracking}" fill="${s.color}" ${extra}`;
}
const cased = (k, str) => (typeStyle(k).case === 'upper' ? str.toLocaleUpperCase('de') : str);
// Inter carries the arrow; Barlow Condensed lacks it and resvg would fall back for the whole run.
// resvg falls back for a whole <text> when one glyph is missing, so the arrow gets its own element.
function textEl(k, str, x, y, extra = '') {
  const s = cased(k, str);
  if (!s.includes('→') || !typeStyle(k).family.includes('Condensed')) return `<text x="${x}" y="${y}" ${textAttrs(k, extra)}>${esc(s)}</text>`;
  const parts = s.split(/(→)/);
  let cx = Number(x), out = `<g ${extra}>`;
  for (const p of parts) {
    if (!p) continue;
    if (p === '→') { const sz = typeStyle(k).size; out += `<text x="${cx.toFixed(1)}" y="${y}" font-family="Inter" font-weight="500" font-size="${sz * 0.8}" fill="${typeStyle(k).color}">→</text>`; cx += sz * 0.8 * 0.95; }
    else { out += `<text x="${cx.toFixed(1)}" y="${y}" ${textAttrs(k)} xml:space="preserve">${esc(p)}</text>`; cx += advance(k, p); }
  }
  return out + '</g>';
}
function inkWidth(svgText) {
  const bb = new Resvg(`<svg xmlns="http://www.w3.org/2000/svg" width="3000" height="400">${svgText}</svg>`, { font: fontOptions() }).getBBox();
  return bb ? bb.width : 0;
}
// advance incl. spaces: ink("|s|") − ink("||")
function advance(k, s) { return inkWidth(`<text x="0" y="300" ${textAttrs(k)} xml:space="preserve">|${esc(s)}|</text>`) - inkWidth(`<text x="0" y="300" ${textAttrs(k)}>||</text>`); }
function measure(k, str) { return inkWidth(textEl(k, str, 0, 300)); }

// ---------- noise ----------
function hash(ix, iy, seed) { let h = (ix * 374761393 + iy * 668265263 + seed * 2147483647) | 0; h = Math.imul(h ^ (h >>> 13), 1274126177); return ((h ^ (h >>> 16)) >>> 0) / 4294967295; }
function vnoise(x, y, seed) {
  const ix = Math.floor(x), iy = Math.floor(y), fx = x - ix, fy = y - iy;
  const u = fx * fx * (3 - 2 * fx), w = fy * fy * (3 - 2 * fy);
  return lerp(lerp(hash(ix, iy, seed), hash(ix + 1, iy, seed), u), lerp(hash(ix, iy + 1, seed), hash(ix + 1, iy + 1, seed), u), w);
}
function fbm(x, y, seed, oct = 5) { let a = 0.5, f = 1, s = 0, n = 0; for (let i = 0; i < oct; i++) { s += a * vnoise(x * f, y * f, seed + i * 17); n += a; a *= 0.5; f *= 2.03; } return s / n; }
function ridged(x, y, seed, oct = 5) { let a = 0.5, f = 1, s = 0, n = 0; for (let i = 0; i < oct; i++) { const r = 1 - Math.abs(vnoise(x * f, y * f, seed + i * 31) * 2 - 1); s += a * r * r; n += a; a *= 0.5; f *= 2.1; } return s / n; }

// ---------- geometry ----------
const R = 6371008.8, DEG = Math.PI / 180;
function makeProj(lat0, lon0) {
  const kx = R * DEG * Math.cos(lat0 * DEG), ky = R * DEG;
  return { fwd: (lon, lat) => [(lon - lon0) * kx, (lat - lat0) * ky], inv: (x, y) => [lon0 + x / kx, lat0 + y / ky] };
}
function distToPolyline(px, py, pts) {
  let best = Infinity, bi = 0, bt = 0;
  for (let i = 0; i < pts.length - 1; i++) {
    const [ax, ay] = pts[i], [bx, by] = pts[i + 1];
    const dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy || 1;
    const t = clamp(((px - ax) * dx + (py - ay) * dy) / l2, 0, 1);
    const d = Math.hypot(px - ax - t * dx, py - ay - t * dy);
    if (d < best) { best = d; bi = i; bt = t; }
  }
  return { d: best, i: bi, t: bt };
}
function densify(pts, step) { // pts: [[lon,lat,elev]] linear in lon/lat, ok for previews
  const out = [];
  for (let i = 0; i < pts.length - 1; i++) {
    const [a, b] = [pts[i], pts[i + 1]];
    const n = Math.max(1, Math.ceil(Math.hypot((b[0] - a[0]) * Math.cos(a[1] * DEG), b[1] - a[1]) * 111 / step));
    for (let k = 0; k < n; k++) { const t = k / n; out.push([lerp(a[0], b[0], t), lerp(a[1], b[1], t), a[2] == null || b[2] == null ? null : lerp(a[2], b[2], t)]); }
  }
  out.push(pts[pts.length - 1]);
  return out;
}
function cumKm(pts) { const d = [0]; for (let i = 1; i < pts.length; i++) d.push(d[i - 1] + Math.hypot((pts[i][0] - pts[i - 1][0]) * Math.cos(pts[i][1] * DEG), pts[i][1] - pts[i - 1][1]) * 111.195); return d; }
function trimEnds(pts, km = 8) { const d = cumKm(pts), tot = d[d.length - 1]; return pts.filter((_, i) => d[i] >= km && d[i] <= tot - km); }

// ---------- routes ----------
function routeI80() {
  const src = new URL('docs/plan/mockups/source/', ROOT);
  const r = JSON.parse(readFileSync(new URL('routes.json', src)))['SLC-SAC'].coords;
  const e = JSON.parse(readFileSync(new URL('elev.json', src)));
  const pts = [];
  let d = 0;
  for (let i = 0; i < r.length; i++) {
    if (i) d += Math.hypot((r[i][0] - r[i - 1][0]) * Math.cos(r[i][1] * DEG), r[i][1] - r[i - 1][1]) * 111.195 / 1.609344;
    let j = e.findIndex(s => s.d >= d); if (j < 1) j = j === 0 ? 1 : e.length - 1;
    const t = clamp((d - e[j - 1].d) / (e[j].d - e[j - 1].d), 0, 1);
    const elev = lerp(e[j - 1].ft, e[j].ft, t) * 0.3048;
    if (!pts.length || d - pts[pts.length - 1][3] > 1.2) pts.push([r[i][0], r[i][1], elev, d]);
  }
  // Illustrative recording gap (invalid altitude) across ~22 miles of Nevada.
  return pts.map(p => [p[0], p[1], p[3] > 290 && p[3] < 350 ? null : p[2]]);
}
const BRENNER = [ // Innsbruck → Bolzano (A13/A22), hand-placed; elevations in m
  [11.392, 47.262, 575], [11.400, 47.235, 640], [11.404, 47.205, 790], [11.433, 47.165, 900], [11.452, 47.128, 990],
  [11.468, 47.090, 1045], [11.482, 47.055, 1160], [11.503, 47.012, 1340], [11.508, 47.003, 1372], [11.470, 46.960, 1180],
  [11.432, 46.898, 950], [11.500, 46.840, 850], [11.610, 46.790, 750], [11.655, 46.715, 560], [11.575, 46.640, 520],
  [11.530, 46.600, 470], [11.450, 46.540, 330], [11.355, 46.498, 265],
];
const NULLARBOR = [ // Norseman → Ceduna (Eyre Highway), hand-placed; elevations in m
  [121.78, -32.20, 280], [122.60, -32.30, 240], [123.62, -32.35, 200], [124.60, -32.30, 120], [125.49, -32.27, 90],
  [126.10, -32.04, 95], [126.60, -31.95, 90], [127.02, -31.90, 30], [127.60, -31.85, 40], [128.30, -31.75, 60],
  [128.88, -31.68, 85], [129.00, -31.64, 95], [129.90, -31.55, 100], [130.90, -31.45, 95], [131.84, -31.48, 80],
  [132.40, -31.70, 60], [133.01, -31.93, 40], [133.68, -32.13, 15],
];

// ---------- synthetic terrain (metres), evaluated at lon/lat ----------
const TERRAIN = {
  i80(lon, lat, ctx) {
    const sierra = 2300 * Math.exp(-(((lon + 120.25) / 0.55) ** 2)) * (0.75 + 0.5 * fbm(lon * 3, lat * 3, 11));
    const valley = smooth(-121.5, -120.9, lon);                         // Central Valley floor to the west
    const basin = lerp(1250, 1500, fbm(lon * 0.8, lat * 0.8, 3));
    const ranges = 950 * Math.pow(ridged(lon * 1.4, lat * 0.9, 5, 3), 1.6) * smooth(-120.2, -119.6, lon); // N–S ranges
    const wasatch = 1300 * Math.exp(-(((lon + 111.55) / 0.35) ** 2)) * (0.7 + 0.6 * fbm(lon * 4, lat * 4, 9));
    let h = lerp(15 + 60 * fbm(lon * 3, lat * 3, 2), Math.max(basin + ranges, 0), valley) + sierra * smooth(-121.6, -120.8, lon) + wasatch;
    const near = ctx.near(lon, lat);                                     // road follows valleys and passes
    if (near.elev != null) h = lerp(near.elev - 40, h, smooth(4000, 22000, near.d));
    return h;
  },
  i80Water(lon, lat) { return ((lon + 112.55) / 0.42) ** 2 + ((lat - 41.22) / 0.42) ** 2 < 1; }, // Great Salt Lake, flat
  i80WaterLevel: 1280,
  brenner(lon, lat, ctx) {
    const peaks = 1500 + 1700 * ridged(lon * 2.6, lat * 3.2, 21, 3) + 400 * fbm(lon * 6, lat * 6, 4, 2);
    const inn = Math.abs(lat - (47.268 + 0.04 * (lon - 11.39))) * 111000;  // Inn valley, W–E
    const adige = distToPolyline(lon * 76000, lat * 111000, [[11.15 * 76000, 46.70 * 111000], [11.355 * 76000, 46.498 * 111000], [11.20 * 76000, 46.20 * 111000]]).d;
    const near = ctx.near(lon, lat);
    const floorInn = 560 + 30 * fbm(lon * 30, lat * 30, 8), floorAdige = 250;
    let h = peaks;
    h = lerp(floorInn, h, smooth(1500, 9000, inn));
    h = lerp(floorAdige, h, smooth(1500, 8000, adige));
    if (near.elev != null) h = lerp(near.elev - 30, h, smooth(1500, 8500, near.d));
    return h;
  },
  nullarbor(lon, lat, ctx) {
    const near = ctx.near(lon, lat);
    const coast = ctx.coast(lon);
    const inland = (coast - lat) * -111000;                              // metres north of the coast
    let h = 60 + 120 * smooth(0, 300000, inland) + 25 * fbm(lon * 2, lat * 2, 6) + 8 * fbm(lon * 12, lat * 12, 7);
    if (lon > 126.3 && lon < 128.6) h = lerp(h, 25, 1 - smooth(4000, 20000, inland));   // Roe Plain below the escarpment
    if (near.elev != null) h = lerp(near.elev, h, smooth(1000, 6000, near.d));
    return h;
  },
  nullarborWater(lon, lat, ctx) { return lat < ctx.coast(lon); },
  nullarborWaterLevel: 0,
};
const nullarborCoast = lon => { // south coast, roughly following the highway 15–60 km south
  const p = NULLARBOR.map(q => [q[0], q[1]]);
  let j = p.findIndex(q => q[0] >= lon); if (j < 1) j = j === 0 ? 1 : p.length - 1;
  const lat = lerp(p[j - 1][1], p[j][1], clamp((lon - p[j - 1][0]) / (p[j][0] - p[j - 1][0]), 0, 1));
  const off = lon < 124.8 ? 0.9 - (lon - 121.78) * 0.15 : lon > 129.4 && lon < 131.4 ? 0.06 : lon > 126.3 && lon < 128.9 ? 0.22 : 0.3;
  return lat - Math.max(off, 0.05) - 0.03 * Math.sin(lon * 7);
};

// ---------- scene ----------
function buildScene(route, kind) {
  const lats = route.map(p => p[1]), lons = route.map(p => p[0]);
  const lat0 = (Math.min(...lats) + Math.max(...lats)) / 2, lon0 = (Math.min(...lons) + Math.max(...lons)) / 2;
  const proj = makeProj(lat0, lon0);
  const xy = route.map(p => proj.fwd(p[0], p[1]));
  const xs = xy.map(p => p[0]), ys = xy.map(p => p[1]);
  const pad = v(L.routePadding), el = v(TT.camera.elevationDeg) * DEG;
  const fw = W, fh = v(L.reliefHeight), depthBudget = fh * v(L.reliefDepthFill);
  const rw = Math.max(Math.max(...xs) - Math.min(...xs), 1) * (1 + 2 * pad), rd = Math.max(Math.max(...ys) - Math.min(...ys), 1) * (1 + 2 * pad);
  let s = Math.min(fw / Math.max(rw, 100000), depthBudget / (Math.max(rd, 100000) * Math.sin(el)));
  const gw = fw / s, gd = depthBudget / (s * Math.sin(el));
  const cx = (Math.min(...xs) + Math.max(...xs)) / 2, cy = (Math.min(...ys) + Math.max(...ys)) / 2;
  const x0 = cx - gw / 2, y0 = cy - gd / 2;

  // 2′ grid cells covering the footprint, each the mean of 4×4 synthetic subsamples (band limit).
  const cellLat = 2 / 60, cellLon = cellLat;
  const [lonA, latA] = proj.inv(x0, y0), [lonB, latB] = proj.inv(x0 + gw, y0 + gd);
  const gc = Math.ceil((lonB - lonA) / cellLon) + 3, gr = Math.ceil((latB - latA) / cellLat) + 3;
  const rxy = route.map(p => [p[0] * 76000, p[1] * 111000]);
  const ctx = {
    nearRaw(lon, lat) { const n = distToPolyline(lon * 76000, lat * 111000, rxy); const a = route[n.i], b = route[n.i + 1]; return { d: n.d, elev: a[2] == null || b[2] == null ? (a[2] ?? b[2]) : lerp(a[2], b[2], n.t) }; },
    coast: nullarborCoast,
  };
  const fn = TERRAIN[kind], wfn = TERRAIN[kind + 'Water'], wl = TERRAIN[kind + 'WaterLevel'] ?? 0;
  const grid = new Float32Array(gc * gr), wet = new Float32Array(gc * gr);
  for (let r = 0; r < gr; r++) for (let c = 0; c < gc; c++) {
    let sum = 0, wsum = 0;
    const cellNear = ctx.nearRaw(lonA + (c - 0.5) * cellLon, latA + (r - 0.5) * cellLat);
    ctx.near = () => cellNear;                                 // one route lookup per 2′ cell
    for (let a = 0; a < 4; a++) for (let b = 0; b < 4; b++) {
      const lon = lonA + (c - 1 + (b + 0.5) / 4) * cellLon, lat = latA + (r - 1 + (a + 0.5) / 4) * cellLat;
      const w = wfn ? wfn(lon, lat, ctx) : false;
      if (w) wsum++; else sum += fn(lon, lat, ctx);
    }
    const land = 16 - wsum;
    wet[r * gc + c] = wsum / 16;
    grid[r * gc + c] = land >= 8 ? sum / land : wl;          // land wins ties (ADR)
  }
  // Catmull-Rom sample of the 2′ grid, as a fine raster for shading.
  const cr = (p0, p1, p2, p3, t) => p1 + 0.5 * t * (p2 - p0 + t * (2 * p0 - 5 * p1 + 4 * p2 - p3 + t * (3 * (p1 - p2) + p3 - p0)));
  const g = (r, c) => grid[clamp(r, 0, gr - 1) * gc + clamp(c, 0, gc - 1)];
  function sampleGrid(lon, lat) {
    const fc = (lon - lonA) / cellLon + 1 - 0.5, frr = (lat - latA) / cellLat + 1 - 0.5;
    const c = Math.floor(fc), r = Math.floor(frr), tc = fc - c, tr = frr - r;
    const row = k => cr(g(r + k, c - 1), g(r + k, c), g(r + k, c + 1), g(r + k, c + 2), tc);
    return cr(row(-1), row(0), row(1), row(2), tr);
  }
  function sampleWet(lon, lat) {
    const fc = (lon - lonA) / cellLon + 0.5, frr = (lat - latA) / cellLat + 0.5;
    const c = Math.floor(fc), r = Math.floor(frr), tc = fc - c, tr = frr - r;
    const q = (rr, cc) => wet[clamp(rr, 0, gr - 1) * gc + clamp(cc, 0, gc - 1)];
    return lerp(lerp(q(r, c), q(r, c + 1), tc), lerp(q(r + 1, c), q(r + 1, c + 1), tc), tr);
  }
  const FN = 520, FD = Math.round(FN * gd / gw) | 0 || 1;
  const fine = new Float32Array(FN * FD), fwet = new Uint8Array(FN * FD);
  for (let j = 0; j < FD; j++) for (let i = 0; i < FN; i++) {
    const [lon, lat] = proj.inv(x0 + (i + 0.5) / FN * gw, y0 + (j + 0.5) / FD * gd);
    const w = sampleWet(lon, lat) > 0.5;
    fwet[j * FN + i] = w ? 1 : 0;
    fine[j * FN + i] = w ? wl : sampleGrid(lon, lat);
  }
  return { proj, x0, y0, gw, gd, s, el, FN, FD, fine, fwet, xy, cellKm: cellLat * 111.2 };
}

function renderRelief(scene, route, opts = {}) {
  const { x0, y0, gw, gd, s, el, FN, FD, fine, fwet } = scene;
  const fh = v(L.reliefHeight);
  const land = [...fine].filter((_, i) => !fwet[i]).sort((a, b) => a - b);
  const p5 = land[Math.floor(land.length * 0.05)] ?? 0, p99 = land[Math.floor(land.length * 0.99)] ?? 1;
  const span = Math.max(p99 - p5, v(TT.land.minSpanMeters));
  const ex = TT.camera.exaggeration;
  const k = opts.flat ? 0 : clamp(v(ex.targetReliefRatio) * gw / (span * Math.cos(el)), v(ex.min), v(ex.max));
  const dxm = gw / FN, dym = gd / FD;
  // hillshade on the fine raster (with exaggeration, like the core will)
  const hs = TT.hillshade, az = v(hs.lightAzimuthDeg) * DEG, alt = v(hs.lightAltitudeDeg) * DEG;
  const Lx = Math.sin(az) * Math.cos(alt), Ly = Math.cos(az) * Math.cos(alt), Lz = Math.sin(alt);
  const shade = new Float32Array(FN * FD);
  const ke = Math.max(k, 1);
  for (let j = 0; j < FD; j++) for (let i = 0; i < FN; i++) {
    const f = (ii, jj) => fine[clamp(jj, 0, FD - 1) * FN + clamp(ii, 0, FN - 1)];
    const gx = (f(i + 1, j) - f(i - 1, j)) * ke / (2 * dxm), gy = (f(i, j + 1) - f(i, j - 1)) * ke / (2 * dym);
    const n = Math.hypot(gx, gy, 1);
    const d = Math.max(0, (-gx * Lx - gy * Ly + Lz) / n);
    shade[j * FN + i] = Math.min(v(hs.max), v(hs.ambient) + v(hs.diffuse) * d);
  }
  const stops = v(TT.land.ramp).map(st => ({ p: st.position, c: hex(st.color) }));
  const ramp = t => { for (let i = 1; i < stops.length; i++) if (t <= stops[i].p) { const u = (t - stops[i - 1].p) / (stops[i].p - stops[i - 1].p); return stops[i].c.map((x, q) => lerp(stops[i - 1].c[q], x, u)); } return stops[stops.length - 1].c; };
  const water = hex(v(TT.land.water)), edge = hex(v(TT.land.waterEdge)), haze = hex(v(TT.haze.color)), hazeA = v(TT.haze.farOpacity);
  const bg = hex(C.background.$value);
  const px = new Uint8Array(W * fh * 4);
  for (let i = 0; i < W * fh; i++) { px[i * 4] = bg[0]; px[i * 4 + 1] = bg[1]; px[i * 4 + 2] = bg[2]; px[i * 4 + 3] = 255; }
  // screen mapping: sy = base - (dy*sin(el) + (h - hBase)*k*cos(el)) * s
  const hBase = p5;
  const base = fh - v(L.reliefFadeBottom) * 0.4;     // near edge sits inside the bottom fade
  const steps = Math.ceil(gd * Math.sin(el) * s * 2);
  const horizon = new Float32Array(W * (steps + 1));
  const sampleF = (arr, fi, fj) => { const i = clamp(Math.floor(fi), 0, FN - 2), j = clamp(Math.floor(fj), 0, FD - 2), u = clamp(fi - i, 0, 1), w = clamp(fj - j, 0, 1); return lerp(lerp(arr[j * FN + i], arr[j * FN + i + 1], u), lerp(arr[(j + 1) * FN + i], arr[(j + 1) * FN + i + 1], u), w); };
  for (let col = 0; col < W; col++) {
    const fi = (col + 0.5) / W * FN - 0.5;
    let ybuf = fh, prevRgb = null, prevSt = -2;
    for (let st = 0; st <= steps; st++) {
      horizon[col * (steps + 1) + st] = ybuf;
      const dy = st / steps * gd, fj = dy / gd * FD - 0.5;
      const iw = fwet[clamp(Math.round(fj), 0, FD - 1) * FN + clamp(Math.round(fi), 0, FN - 1)];
      const h = sampleF(fine, fi, fj);
      const top = base - (dy * Math.sin(el) + (h - hBase) * k * Math.cos(el)) * s;
      if (top < ybuf && st === 0) { ybuf = top; continue; }   // near-edge skirt stays background
      if (top < ybuf) {
        let rgb;
        if (iw) {
          const nearLand = [[1, 0], [-1, 0], [0, 1], [0, -1]].some(([a, b]) => !fwet[clamp(Math.round(fj) + b, 0, FD - 1) * FN + clamp(Math.round(fi) + a, 0, FN - 1)]);
          rgb = nearLand ? edge : water;
        } else {
          const t = clamp((h - p5) / span, 0, 1), sh = opts.flat ? 1 : sampleF(shade, fi, fj);
          rgb = ramp(t).map(x => x * sh);
        }
        const hz = hazeA * (st / steps);
        rgb = rgb.map((x, q) => lerp(x, haze[q], hz));
        // Blend down to the previous sample's colour so steep, exaggerated slopes don't streak.
        const from = prevRgb && prevSt === st - 1 ? prevRgb : rgb, y0p = Math.floor(top), y1p = Math.ceil(ybuf);
        for (let y = Math.max(0, y0p); y < Math.min(fh, y1p); y++) {
          const u = y1p > y0p ? (y - y0p) / (y1p - y0p) : 0, o = (y * W + col) * 4;
          px[o] = lerp(rgb[0], from[0], u); px[o + 1] = lerp(rgb[1], from[1], u); px[o + 2] = lerp(rgb[2], from[2], u);
        }
        ybuf = top; prevRgb = rgb; prevSt = st;
      }
    }
  }
  // project the ribbon at recorded altitude and classify visibility
  const bias = v(TT.ribbon.depthBias);
  const pts = route.map((p0, i) => {
    let p = p0;
    const [x, y] = scene.xy[i];
    const sx = (x - x0) * s, dy = y - y0;
    const z = opts.flat ? hBase : p[2];   // flat layout ignores altitude entirely
    if (z == null) return { sx, sy: null, gap: true, elev: null };
    if (opts.flat) p = [p[0], p[1], 0];
    const sy = base - (dy * Math.sin(el) + (z - hBase) * k * Math.cos(el)) * s;
    const col = clamp(Math.round(sx), 0, W - 1), st = clamp(Math.floor(dy / gd * steps), 0, steps);
    const hidden = sy > horizon[col * (steps + 1) + st] + bias;
    return { sx, sy, hidden, gap: false, elev: p[2] };
  });
  return { px, pts, k, span, p5, p99 };
}

// ---------- PNG ----------
const CRC = new Uint32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
const crc32 = b => { let c = 0xffffffff; for (const x of b) c = CRC[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
function png(rgba, w, h) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) { raw[y * (w * 4 + 1)] = 0; Buffer.from(rgba.buffer, rgba.byteOffset + y * w * 4, w * 4).copy(raw, y * (w * 4 + 1) + 1); }
  const chunk = (t, d) => { const len = Buffer.alloc(4); len.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc32(td)); return Buffer.concat([len, td, c]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', deflateSync(raw, { level: 6 })), chunk('IEND', Buffer.alloc(0))]);
}

// ---------- SVG overlay ----------
const RB = TT.ribbon;
function ribbonSvg(pts, top) {
  const segs = { vis: [], hid: [], gap: [] };
  let cur = null, kind = null;
  const pt = p => `${p.sx.toFixed(1)},${(p.sy + top).toFixed(1)}`;
  for (let i = 0; i < pts.length; i++) {
    const p = pts[i];
    if (p.gap) { // link last valid point to next valid point with a straight dotted segment
      if (cur) { segs[kind].push(cur); cur = null; }
      continue;
    }
    const k = p.hidden ? 'hid' : 'vis';
    if (i > 0 && pts[i - 1].gap) { const prev = pts.slice(0, i).reverse().find(q => !q.gap); if (prev) segs.gap.push([pt(prev), pt(p)]); }
    if (kind !== k && cur) { cur.push(pt(p)); segs[kind].push(cur); cur = null; }
    if (!cur) { cur = i > 0 && !pts[i - 1].gap ? [pt(pts[i - 1])] : []; kind = k; }
    cur.push(pt(p));
  }
  if (cur) segs[kind].push(cur);
  const d = list => list.filter(s => s.length > 1).map(s => 'M' + s.join('L')).join('');
  const glow = v(RB.glow);
  const oc = RB.occluded, gp = RB.gap;
  return `
  <defs>${glow.map((g, i) => `<filter id="ribbon-glow-${i}" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="${g.radius}"/></filter>`).join('')}</defs>
  <g id="ribbon" fill="none" stroke-linejoin="round" stroke-linecap="round">
    <path id="ribbon-occluded" d="${d(segs.hid)}" stroke="${v(oc.color)}" stroke-opacity="${v(oc.opacity)}" stroke-width="${v(oc.width)}" stroke-dasharray="${v(oc.dash).dashArray.join(' ')}" stroke-linecap="${v(oc.dash).lineCap}"/>
    <path id="ribbon-gap" d="${d(segs.gap)}" stroke="${v(gp.color)}" stroke-opacity="${v(gp.opacity)}" stroke-width="${v(gp.width)}" stroke-dasharray="${v(gp.dash).dashArray.join(' ')}" stroke-linecap="${v(gp.dash).lineCap}"/>
    ${glow.map((g, i) => `<path id="ribbon-glow-${i}-path" d="${d(segs.vis)}" stroke="${g.color}" stroke-opacity="${g.opacity}" stroke-width="${g.width}" filter="url(#ribbon-glow-${i})"/>`).join('')}
    <path id="ribbon-casing" d="${d(segs.vis)}" stroke="${v(RB.casing.color)}" stroke-opacity="${v(RB.casing.opacity)}" stroke-width="${v(RB.casing.width)}"/>
    <path id="ribbon-visible" d="${d(segs.vis)}" stroke="${v(RB.color)}" stroke-width="${v(RB.width)}"/>
  </g>`;
}
function endpointsSvg(pts, top) {
  const e = RB.endpoint, valid = pts.filter(p => !p.gap);
  const c = p => `<circle cx="${p.sx.toFixed(1)}" cy="${(p.sy + top).toFixed(1)}" r="${v(e.radius)}" fill="${v(e.color)}" fill-opacity="${v(e.fillOpacity)}" stroke="${v(e.color)}" stroke-width="${v(e.stroke)}"/>`;
  return `<g id="route-ends">${c(valid[0])}${c(valid[valid.length - 1])}</g>`;
}
function summitSvg(pts, top, label) {
  const S = TT.summit, valid = pts.filter(p => !p.gap);
  const p = valid.reduce((a, b) => (b.elev > a.elev ? b : a));
  const mx = p.sx, my = p.sy + top;
  const lead = v(S.leader.length), lx = mx;
  const lab = S.label, gap = v(lab.gapToLeader), lg = v(lab.lineGap);
  const kS = typeStyle('summitKicker'), vS = typeStyle('summitValue'), nS = typeStyle('summitName');
  const lines = [['summitKicker', label.kicker, kS.size], ['summitValue', label.value, vS.size * 0.8]];
  if (label.name) lines.push(['summitName', label.name, nS.size]);
  const widths = lines.map(([k, s]) => measure(k, s));
  const bw = Math.max(...widths), bh = lines.reduce((a, l) => a + l[2], 0) + lg * (lines.length - 1);
  const side = v(TT.safeArea.side), pp = v(lab.platePadding), mr = v(S.marker.radius);
  // Candidate placements: above/below × open side/other side, then longer leaders. The plate must
  // stay inside the relief frame and safe area and must not cover the ribbon.
  const ribbon = pts.filter(q => !q.gap).map(q => [q.sx, q.sy + top]);
  const frameTop = top + 20, frameBot = top + v(L.reliefHeight) - v(L.reliefFadeBottom) * 0.5;
  const open = mx < W / 2 ? 1 : -1;
  let best = null;
  for (const mult of [1, 1.5, 2])
    for (const dir of [-1, 1])
      for (const sideSign of [open, -open]) {
        if (best) break;
        const ly = my + dir * lead * mult;
        const tx = sideSign > 0 ? lx + gap : lx - gap - bw;
        const box = dir < 0 ? [tx - pp, ly - bh - pp, tx + bw + pp, ly + pp] : [tx - pp, ly - pp, tx + bw + pp, ly + bh + pp];
        if (box[0] < side - pp || box[2] > W - side + pp || box[1] < frameTop || box[3] > frameBot) continue;
        if (ribbon.some(([x, y]) => x > box[0] - 6 && x < box[2] + 6 && y > box[1] - 6 && y < box[3] + 6)) continue;
        best = { tx, ly, dir, box };
      }
  if (!best) { const ly = my - lead; const tx = clamp(open > 0 ? lx + gap : lx - gap - bw, side, W - side - bw); best = { tx, ly, dir: -1, box: [tx - pp, ly - bh - pp, tx + bw + pp, ly + pp] }; }
  const { tx, dir, box } = best, leaderEnd = best.ly;
  let y = box[1] + pp + lines[0][2];
  const out = [`<g id="summit">`,
    `<rect id="summit-plate" x="${box[0].toFixed(1)}" y="${box[1].toFixed(1)}" width="${(bw + 2 * pp).toFixed(1)}" height="${(bh + 2 * pp).toFixed(1)}" rx="${v(lab.plateRadius)}" fill="${C.background.$value}" fill-opacity="${v(lab.plateOpacity)}"/>`,
    `<line id="summit-leader" x1="${lx}" y1="${my + dir * mr}" x2="${lx}" y2="${leaderEnd}" stroke="${v(S.leader.color)}" stroke-opacity="${v(S.leader.opacity)}" stroke-width="${v(S.leader.width)}"/>`,
    `<circle id="summit-marker" cx="${mx.toFixed(1)}" cy="${my.toFixed(1)}" r="${v(S.marker.radius) + v(S.marker.ring)}" fill="${C.background.$value}"/>`,
    `<circle cx="${mx.toFixed(1)}" cy="${my.toFixed(1)}" r="${v(S.marker.radius)}" fill="${v(S.marker.fill)}"/>`];
  lines.forEach(([k, s, hgt], i) => { if (i) y += hgt + lg; out.push(textEl(k, s, tx.toFixed(1), y.toFixed(1), `id="summit-${['kicker', 'value', 'name'][i]}"`)); });
  out.push('</g>');
  return out.join('');
}
function roadSign(sign, x, y) {
  const z = v(L.roadSignSize);
  if (!sign) return '';
  if (sign.kind === 'interstate') return `<g id="road-sign" transform="translate(${x},${y})">
    <path d="M6 6 Q${z / 2} 0 ${z - 6} 6 Q${z} ${z * 0.5} ${z / 2} ${z} Q0 ${z * 0.5} 6 6Z" fill="#1f4aa8" stroke="#f0efec" stroke-width="3"/>
    <path d="M6 6 Q${z / 2} 0 ${z - 6} 6 L${z - 3} ${z * 0.26} L3 ${z * 0.26}Z" fill="#c8202f"/>
    <text x="${z / 2}" y="${z * 0.72}" text-anchor="middle" font-family="Barlow Condensed" font-stretch="condensed" font-weight="700" font-size="34" fill="#ffffff">${sign.number}</text></g>`;
  if (sign.kind === 'e-road') return `<g id="road-sign" transform="translate(${x},${y + 12})">
    <rect width="${z + 16}" height="${z - 24}" rx="6" fill="#00843d" stroke="#ffffff" stroke-width="3"/>
    <text x="${(z + 16) / 2}" y="${z * 0.5}" text-anchor="middle" font-family="Barlow Condensed" font-stretch="condensed" font-weight="700" font-size="34" fill="#ffffff">${sign.number}</text></g>`;
  return `<g id="road-sign" transform="translate(${x},${y + 8})">
    <rect width="${z}" height="${z - 16}" rx="8" fill="none" stroke="${C.textSecondary.$value}" stroke-width="3"/>
    <text x="${z / 2}" y="${z * 0.53}" text-anchor="middle" font-family="Barlow Condensed" font-stretch="condensed" font-weight="700" font-size="34" fill="${C.text.$value}">${sign.number}</text></g>`;
}
function headerSvg(card) {
  const side = v(TT.safeArea.side), out = [textEl('kicker', card.date, side, v(L.kickerBaseline), 'id="kicker-date"')];
  card.title.slice(0, v(L.titleMaxLines)).forEach((line, i) => out.push(textEl('title', line, side, v(L.titleBaseline) + i * v(L.titleLineHeight), `id="title-line-${i + 1}"`)));
  return out.join('');
}
function statsSvg(card) {
  const side = v(TT.safeArea.side), nb = v(L.numberBaseline);
  const nw = measure('number', card.number);
  const out = [textEl('number', card.number, side, nb, 'id="stat-number"'), textEl('unit', card.unit, side + nw + v(L.unitGap), nb, 'id="stat-unit"')];
  let x = side; const y = v(L.chipTop), ch = v(L.chipHeight);
  if (card.sign) { out.push(roadSign(card.sign, x, y)); x += v(L.roadSignSize) + (card.sign.kind === 'e-road' ? 16 : 0) + v(L.chipGap); }
  for (const c of card.chips) {
    const tw = measure('chip', c), cw = tw + 2 * v(L.chipPaddingX);
    out.push(`<rect x="${x}" y="${y}" width="${cw.toFixed(1)}" height="${ch}" rx="${v(L.chipRadius)}" fill="${v(TT.chip.fill)}" stroke="${v(TT.chip.stroke)}" stroke-width="${v(TT.chip.strokeWidth)}"/>`);
    out.push(textEl('chip', c, (x + v(L.chipPaddingX)).toFixed(1), y + ch / 2 + typeStyle('chip').size * 0.36));
    x += cw + v(L.chipGap);
  }
  return out.join('');
}
function fadesSvg(top) {
  const fh = v(L.reliefHeight), bg = C.background.$value, ft = v(L.reliefFadeTop), fb = v(L.reliefFadeBottom);
  return `<defs><linearGradient id="fade-top" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${bg}"/><stop offset="1" stop-color="${bg}" stop-opacity="0"/></linearGradient>
  <linearGradient id="fade-bottom" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${bg}" stop-opacity="0"/><stop offset="1" stop-color="${bg}"/></linearGradient></defs>
  <rect id="relief-fade-top" x="0" y="${top}" width="${W}" height="${ft}" fill="url(#fade-top)"/>
  <rect id="relief-fade-bottom" x="0" y="${top + fh - fb}" width="${W}" height="${fb}" fill="url(#fade-bottom)"/>`;
}
function stamp(text) { // preview-only provenance stamp, never part of the card
  const [a, b] = text;
  return `<g id="preview-stamp"><rect x="0" y="${H - 96}" width="${W}" height="96" fill="#000" fill-opacity="0.6"/>
  <text x="${W / 2}" y="${H - 56}" text-anchor="middle" font-family="Inter" font-weight="600" font-size="22" letter-spacing="2" fill="#a6aab4">${esc(a)}</text>
  <text x="${W / 2}" y="${H - 24}" text-anchor="middle" font-family="Inter" font-weight="400" font-size="22" fill="#a6aab4">${esc(b)}</text></g>`;
}
function safeAreaGuides() {
  const sa = TT.safeArea, side = v(sa.side);
  return `<g id="safe-area" fill="none" stroke="#ff4d8d" stroke-width="2" stroke-dasharray="8 8" opacity="0.8">
  <rect x="${side}" y="${v(sa.top)}" width="${W - 2 * side}" height="${H - v(sa.top) - v(sa.bottom)}"/></g>`;
}

// ---------- cards ----------
const CARDS = {
  'i80-terrain': { route: routeI80, kind: 'i80', date: 'Wednesday, November 4, 2026', title: ['Salt Lake City', '→ Sacramento'], number: '649', unit: 'Miles', chips: ['10h 52m', '3 states'], sign: { kind: 'interstate', number: '80' }, summit: { kicker: 'Highest recorded point', value: '7,139 ft', name: 'Donner Summit' }, source: 'real I-80 track; 60-mi gap illustrative' },
  'brenner-terrain': { route: () => trimEnds(densify(BRENNER, 1)), kind: 'brenner', date: 'Saturday, August 15, 2026', title: ['Innsbruck → Bolzano'], number: '118', unit: 'km', chips: ['1h 25m', '2 countries'], sign: { kind: 'e-road', number: 'E45' }, summit: { kicker: 'Highest recorded point', value: '1,372 m', name: 'Brenner Pass' }, source: 'route: hand-placed waypoints' },
  'brenner-terrain-long-labels': { route: () => trimEnds(densify(BRENNER, 1)), kind: 'brenner', date: 'Samstag, 15. August 2026', title: ['Innsbruck → Bozen', 'Bolzano (Südtirol)'], number: '118', unit: 'km', chips: ['1 Std. 25 Min.', '2 Länder'], sign: { kind: 'e-road', number: 'E45' }, summit: { kicker: 'Höchster aufgezeichneter Punkt', value: '1.372 m', name: 'Brennerpass / Passo del Brennero' }, source: 'long/localized labels (German)', guides: true },
  'nullarbor-flat': { route: () => trimEnds(densify(NULLARBOR, 2)), kind: 'nullarbor', date: 'Monday, March 2, 2026', title: ['Norseman → Ceduna'], number: '1,197', unit: 'km', chips: ['12h 40m', '2 states'], sign: { kind: 'generic', number: 'A1' }, summit: { kicker: 'Highest recorded point', value: '254 m' }, source: 'flat landscape case, hand-placed route' },
  'i80-altitude-unavailable': { route: routeI80, kind: 'i80', date: 'Wednesday, November 4, 2026', title: ['Salt Lake City', '→ Sacramento'], number: '649', unit: 'Miles', chips: ['10h 52m', '3 states'], sign: { kind: 'interstate', number: '80' }, flat: true, notice: 'Elevation unavailable', source: 'no usable altitude: flat layout, no summit' },
  'i80-hide-route': { hidden: true, date: 'Wednesday, November 4, 2026', title: ['Salt Lake City', '→ Sacramento'], number: '649', unit: 'Miles', chips: ['10h 52m', '3 states', '7,139 ft high'], sign: { kind: 'interstate', number: '80' }, source: 'places and stats only' },
};

function card(name) {
  const cd = CARDS[name], top = v(L.reliefTop), fh = v(L.reliefHeight);
  const parts = [`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}"><rect width="${W}" height="${H}" fill="${C.background.$value}"/>`];
  let info = '';
  if (cd.hidden) {
    const bd = readFileSync(new URL('Design/cards/terrain/terrain-backdrop.svg', ROOT), 'utf8').replace(/<\?xml[^>]*>/, '');
    parts.push(`<g transform="translate(0,${top})" opacity="${v(TT.hiddenRoute.backdropOpacity)}">${bd.replace('<svg', `<svg width="${W}" height="${fh}"`)}</g>`);
    info = 'generic backdrop';
  } else {
    const route = cd.route();
    const scene = buildScene(route, cd.kind);
    const rel = renderRelief(scene, route, { flat: cd.flat });
    if (cd.flat) { // flat layout: plain land plane, no DEM shading or heights
      const land = hex(C.land.$value);
      for (let i = 0; i < rel.px.length; i += 4) if (rel.px[i] !== hex(C.background.$value)[0] || rel.px[i + 1] !== hex(C.background.$value)[1]) { rel.px[i] = land[0]; rel.px[i + 1] = land[1]; rel.px[i + 2] = land[2]; }
    }
    parts.push(`<image id="relief" x="0" y="${top}" width="${W}" height="${fh}" href="data:image/png;base64,${png(rel.px, W, fh).toString('base64')}"/>`);
    parts.push(fadesSvg(top));
    parts.push(ribbonSvg(rel.pts, top), endpointsSvg(rel.pts, top));
    if (cd.summit && !cd.flat) parts.push(summitSvg(rel.pts, top, cd.summit));
    if (cd.notice) parts.push(`<g id="notice"><rect x="${v(TT.safeArea.side)}" y="${top + fh - 300}" width="${measure('notice', cd.notice) + 56}" height="60" rx="30" fill="${v(TT.chip.fill)}" stroke="${v(TT.chip.stroke)}" stroke-width="2"/>${textEl('notice', cd.notice, v(TT.safeArea.side) + 28, top + fh - 300 + 39)}</g>`);
    info = cd.flat ? 'flat' : `k=${rel.k.toFixed(1)}× · ${Math.round(scene.gw / 1000)}×${Math.round(scene.gd / 1000)} km`;
  }
  parts.push(headerSvg(cd), statsSvg(cd));
  if (cd.guides) parts.push(safeAreaGuides());
  parts.push(stamp(['COMPOSITION PREVIEW · SYNTHETIC RELIEF, NOT ETOPO DATA', `${cd.source} · ${info}`]));
  parts.push('</svg>');
  const { png: out, width, height } = renderSvg(parts.join('\n'));
  writeFileSync(new URL(`${name}.png`, OUT), out);
  console.log(`${name}.png ${width}×${height}  ${info}`);
}

const want = process.argv.slice(2);
for (const n of want.length ? want : Object.keys(CARDS)) card(n);
