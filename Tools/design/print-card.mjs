#!/usr/bin/env node
// Print share card (ROA-57): writes Design/cards/print/*.svg, previews and the contact sheet.
// Usage: node print-card.mjs
// Built from the board's v2 reference (Design/reference/board/print-card/gen_print.py). Every visual
// number comes from Design/tokens.json `print.*`. Text stays live <text> (the app fills it); the
// generator measures it with the same renderer and fails if anything leaves the safe area or collides.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { Resvg } from '@resvg/resvg-js';
import { renderSvg, fontOptions } from './render.mjs';

const ROOT = new URL('../../', import.meta.url);
const OUT = new URL('Design/cards/print/', ROOT), PREV = new URL('previews/', OUT);
mkdirSync(PREV, { recursive: true });
const TOK = JSON.parse(readFileSync(new URL('Design/tokens.json', ROOT)));

// ---- tokens ----------------------------------------------------------------------------------------
function get(path) {
  const v = path.split('.').reduce((o, k) => o[k], TOK);
  return resolve(v && typeof v === 'object' && '$value' in v ? v.$value : v);
}
function resolve(v) {
  if (typeof v === 'string') { const m = v.match(/^\{(.+)\}$/); return m ? get(m[1]) : v; }
  if (v && typeof v === 'object' && !Array.isArray(v)) {
    if ('$value' in v) return resolve(v.$value);
    return Object.fromEntries(Object.entries(v).filter(([k]) => !k.startsWith('$')).map(([k, x]) => [k, resolve(x)]));
  }
  return v;
}
const P = k => get(`print.${k}`), Lk = k => P(`layout.${k}`), TY = k => P(`type.${k}`);
const W = P('export.width'), H = P('export.height');
const SAFE = { top: P('safeArea.top'), bottom: P('safeArea.bottom'), side: P('safeArea.side') };
const L = SAFE.side, R = W - SAFE.side;
const C = { route: get('color.route'), text: get('color.text'), secondary: get('color.textSecondary'), ink: P('color.ink'), muted: P('color.muted'), bg: get('color.background') };

// ---- text measuring (same renderer and fonts as the previews) --------------------------------------
const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
const cased = (style, s) => style.case === 'upper' ? s.toLocaleUpperCase('de-DE').replace(/ß/g, 'SS') : s;
function textEl(style, s, x, y, { anchor = 'start', size = style.size, op = 1, id } = {}) {
  const st = style.family.startsWith('Barlow') ? ' font-stretch="condensed"' : '';
  return `<text${id ? ` id="${id}"` : ''} x="${f1(x)}" y="${f1(y)}"${anchor !== 'start' ? ` text-anchor="${anchor}"` : ''} font-family="${style.family}" font-weight="${style.weight}"${st} font-size="${f1(size)}"${style.tracking ? ` letter-spacing="${style.tracking}"` : ''} fill="${style.color}"${op < 1 ? ` fill-opacity="${op}"` : ''}>${esc(cased(style, s))}</text>`;
}
const mcache = new Map();
/** Ink box of the text at x=0, baseline 0: {x, w, top, bottom}. */
function ink(style, s, size = style.size) {
  const key = JSON.stringify([style, s, size]);
  if (!mcache.has(key)) {
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="4000" height="1000">${textEl(style, s, 100, 600, { size })}</svg>`;
    const b = new Resvg(svg, { font: fontOptions() }).getBBox();
    mcache.set(key, b ? { x: b.x - 100, w: b.width, top: b.y - 600, bottom: b.y + b.height - 600 } : { x: 0, w: 0, top: 0, bottom: 0 });
  }
  return mcache.get(key);
}
const f1 = v => (Math.round(v * 10) / 10).toString();

/** Fit text into maxW: full size, then down to fitMinScale, then ellipsis at that size. */
function fit(style, s, maxW) {
  const min = Lk('fitMinScale');
  if (ink(style, s).w <= maxW) return { s, size: style.size };
  const k = maxW / ink(style, s).w;
  if (k >= min) return { s, size: Math.floor(style.size * k * 10) / 10 };
  const size = style.size * min;
  let t = s;
  while (t.length > 1 && ink(style, t.trimEnd() + '…', size).w > maxW) t = t.slice(0, -1);
  return { s: t.trimEnd() + '…', size, ellipsis: true };
}

// ---- geometry --------------------------------------------------------------------------------------
function simplify(p, tol) {
  const keep = p.map(() => false); keep[0] = keep[p.length - 1] = true;
  const st = [[0, p.length - 1]];
  while (st.length) {
    const [a, b] = st.pop(), [ax, ay] = p[a], [bx, by] = p[b], dx = bx - ax, dy = by - ay, n = Math.hypot(dx, dy) || 1e-9;
    let best = 0, bi = -1;
    for (let i = a + 1; i < b; i++) { const d = Math.abs((p[i][0] - ax) * dy - (p[i][1] - ay) * dx) / n; if (d > best) { best = d; bi = i; } }
    if (best > tol) { keep[bi] = true; st.push([a, bi], [bi, b]); }
  }
  return p.filter((_, i) => keep[i]);
}
/** Catmull-Rom through the points as cubic Béziers. */
function smooth(p) {
  if (p.length < 3) return 'M' + p.map(q => `${f1(q[0])} ${f1(q[1])}`).join(' L');
  const d = [`M${f1(p[0][0])} ${f1(p[0][1])}`], t = 0.5 / 3;
  for (let i = 0; i < p.length - 1; i++) {
    const p0 = p[Math.max(i - 1, 0)], p1 = p[i], p2 = p[i + 1], p3 = p[Math.min(i + 2, p.length - 1)];
    d.push(`C${f1(p1[0] + (p2[0] - p0[0]) * t)} ${f1(p1[1] + (p2[1] - p0[1]) * t)} ${f1(p2[0] - (p3[0] - p1[0]) * t)} ${f1(p2[1] - (p3[1] - p1[1]) * t)} ${f1(p2[0])} ${f1(p2[1])}`);
  }
  return d.join(' ');
}
const kmBetween = (a, b) => { const r = Math.PI / 180, x = (b[1] - a[1]) * r * Math.cos((a[0] + b[0]) / 2 * r), y = (b[0] - a[0]) * r; return Math.hypot(x, y) * 6371; };

// ---- trips -----------------------------------------------------------------------------------------
// Points are [lat, lon, altMetres|null, gap] where gap=true starts a recording gap before this point.
const fx = JSON.parse(readFileSync(new URL('Tools/design/fixtures/print-routes.json', ROOT)));
const i80pts = JSON.parse(readFileSync(new URL('RoadPrintCore/Tests/RoadPrintCoreTests/Fixtures/i80-slc-sac-route.json', ROOT)));
const i80elev = JSON.parse(readFileSync(new URL('docs/plan/mockups/source/elev.json', ROOT)));
function withAlt(pts, elev) { // altitude along distance from the mockup's profile (feet → metres)
  let d = 0; return pts.map((p, i) => {
    if (i) d += kmBetween(pts[i - 1], p) / 1.609344;
    const j = Math.max(1, elev.findIndex(e => e.d >= d)), a = elev[j - 1], b = elev[j] ?? a, u = b.d > a.d ? (d - a.d) / (b.d - a.d) : 0;
    return [p[0], p[1], (a.ft + (b.ft - a.ft) * Math.min(1, Math.max(0, u))) * 0.3048, false, d];
  });
}
const I80 = withAlt(i80pts, i80elev);
const osm = k => fx[k].map(([lon, lat, alt]) => [lat, lon, alt, false]);
const BRENNER = osm('brenner'), NULLARBOR = osm('nullarbor');
function firstKm(pts, km) { let d = 0; const o = [pts[0]]; for (let i = 1; i < pts.length && d < km; i++) { d += kmBetween(pts[i - 1], pts[i]); o.push(pts[i]); } return o; }
function withGap(pts, fromMi, toMi) { // drop the points in the gap, mark the first point after it
  const o = []; let open = false;
  for (const p of pts) { if (p[4] > fromMi && p[4] < toMi) { open = true; continue; } o.push(open ? [p[0], p[1], p[2], true, p[4]] : p); open = false; }
  return o;
}
const PLACES = { i80: [[40.761, -111.891], [38.582, -121.494]], brenner: [[47.268, 11.393], [46.498, 11.354]] };

const US = { locale: 'en-US', unit: 'MILES', labels: ['MOVING TIME', 'STATES', 'CAREER MILES'] };
const DE = { locale: 'de-DE', unit: 'KM', labels: ['FAHRZEIT', 'LÄNDER', 'KARRIERE-KM'] };
const EN_KM = { locale: 'en-AU', unit: 'KM', labels: ['MOVING TIME', 'STATES', 'CAREER KM'] };
const num = (loc, v) => new Intl.NumberFormat(loc.locale, { maximumFractionDigits: 0 }).format(v);

const BASE = {
  i80: { pts: I80, title: ['Utah', 'California'], date: 'Wednesday, November 4', ends: ['Salt Lake City area', 'Sacramento area'], sign: ['interstate', '80'], loc: US, dist: 649, stats: ['10h 52m', '3', 1284961], summitUnit: 'ft' },
  brenner: { pts: BRENNER, title: ['Tyrol', 'South Tyrol'], date: 'Saturday, August 15', ends: ['Innsbruck area', 'Bolzano area'], sign: ['eRoad', 'E45'], loc: { ...EN_KM, labels: ['MOVING TIME', 'COUNTRIES', 'CAREER KM'] }, dist: 118, stats: ['1h 25m', '2', 412880], summitUnit: 'm' },
  nullarbor: { pts: NULLARBOR, title: ['Western Australia', 'South Australia'], date: 'Monday, March 2', ends: ['Norseman area', 'Ceduna area'], sign: ['australia', 'A1'], loc: EN_KM, dist: 1197, stats: ['12h 40m', '2', 2066120], summitUnit: 'm' },
};
const CASES = {
  i80: { ...BASE.i80, main: true },
  brenner: { ...BASE.brenner, main: true },
  nullarbor: { ...BASE.nullarbor, main: true },
  'short-12km': { ...BASE.brenner, pts: firstKm(BRENNER, 12), title: ['Innsbruck', 'Patsch'], ends: ['Innsbruck area', 'Patsch area'], dist: 12, stats: ['0h 14m', '1', 412880], note: '12 km, one region: the title shows the two area names' },
  'recording-gap': { ...BASE.i80, pts: withGap(I80, 290, 350), note: 'No points for 60 miles in Nevada: dotted, textSecondary, in the route and the strip' },
  'no-altitude': { ...BASE.i80, pts: I80.map(p => [p[0], p[1], null, p[3]]), note: 'No altitude: no strip, no highest point; the route box grows into the space' },
  'no-career': { ...BASE.i80, stats: ['10h 52m', '3', null], highest: true, note: 'No career distance entered: the third stat becomes the highest point' },
  'no-career-no-altitude': { ...BASE.i80, pts: I80.map(p => [p[0], p[1], null, p[3]]), stats: ['10h 52m', '3', null], note: 'No career and no altitude: two columns' },
  'long-names': { ...BASE.i80, title: ['North Salt Lake', 'West Sacramento'], ends: ['North Salt Lake area', 'West Sacramento area'], note: 'Too long for one line: two lines at full size' },
  'longer-names': { ...BASE.brenner, title: ['Bezirk Innsbruck-Land', 'Autonome Provinz Bozen – Südtirol'], ends: ['Innsbruck-Land area', 'Bozen – Südtirol area'], note: 'Second line too long at 80 %: ellipsis' },
  'km-de_DE': { ...BASE.nullarbor, loc: DE, title: ['Westaustralien', 'Südaustralien'], date: 'Montag, 2. März', ends: ['Region Norseman', 'Region Ceduna'], stats: ['12 Std. 40 Min.', '2', 2066120], summitLabel: 'HÖCHSTER PUNKT', kicker: 'HÖHENPROFIL', note: 'Kilometres, de_DE numbers and German labels' },
  'hide-route': { ...BASE.i80, hidden: true, note: 'Hide route: the two places only, framed on their city centres, no strip' },
};

// ---- road signs: drawn from the production templates (Design/road-signs) ---------------------------
const SIGNS = JSON.parse(readFileSync(new URL('Design/road-signs/signs.json', ROOT)));
function sign(kind, ref, x, y, h) { // right-aligned at x
  const net = { interstate: 'usInterstate', eRoad: 'eRoad', australia: 'australia' }[kind];
  const id = ref.length > (SIGNS.networks[net].wideAbove ?? 9) ? SIGNS.networks[net].wide : net;
  const t = SIGNS.templates[id], body = readFileSync(new URL(`Design/road-signs/${t.file}`, ROOT), 'utf8').replace(/^[\s\S]*?<\/title>/, '').replace(/<\/svg>\s*$/, '');
  const style = { family: 'Barlow Condensed', weight: 700, size: t.fontSize, tracking: 0, color: t.textColor };
  const k = Math.min(1, t.textBox.width / ink(style, ref).w), s = h / 64, w = t.viewBox[2] * s;
  const cap = 0.7 * t.fontSize * k, base = t.textBox.y + (t.textBox.height + cap) / 2;
  const g = `<g id="road-sign" transform="translate(${f1(x - w)} ${y}) scale(${(s).toFixed(4)})">${body}${textEl(style, ref, t.textBox.x + t.textBox.width / 2, base, { anchor: 'middle', size: t.fontSize * k })}</g>`;
  return { g, box: [x - w, y, x, y + h] };
}

// ---- the card --------------------------------------------------------------------------------------
function build(cd) {
  const loc = cd.loc, boxes = []; // [x0, y0, x1, y1, name] of every text and mark, for the checks
  const add = (name, b) => { boxes.push([...b, name]); return b; };
  const textBox = (style, s, x, y, anchor = 'start', size = style.size) => {
    const m = ink(style, cased(style, s), size), x0 = anchor === 'end' ? x - m.w - m.x : anchor === 'middle' ? x - m.w / 2 : x + m.x;
    return [x0, y + m.top, x0 + m.w, y + m.bottom];
  };
  const art = [], over = [];
  // header
  const wm = TY('wordmark');
  art.push(textEl(wm, 'RoadPrint', L + 2, Lk('wordmarkBaseline'), { id: 'wordmark' }));
  add('wordmark', textBox(wm, 'RoadPrint', L + 2, Lk('wordmarkBaseline')));
  const sg = sign(cd.sign[0], cd.sign[1], R, Lk('signTop'), Lk('signHeight'));
  art.push(sg.g); add('sign', sg.box);
  // title: one line "A → B" if it fits left of the sign, else two lines (A →, then B), then 80 %, then ellipsis
  const ti = TY('title'), aw = Lk('titleArrowWidth'), ag = Lk('titleArrowGap');
  const maxW1 = sg.box[0] - Lk('titleSignGap') - L;
  const [A, B] = cd.title.map(s => cased(ti, s));
  // one line "A → B" if it fits left of the sign; else "A" then "→ B" on line 2, both at one size:
  // full, then down to 80 %, then an ellipsis at 80 %
  const arrow = (x, y, size) => {
    const k = size / ti.size, my = y - 34 * k, len = aw * k, hd = 16 * k;
    art.push(`<path class="title-arrow" d="M${f1(x)} ${f1(my)} h${f1(len)} m${f1(-hd - 1)} ${f1(-hd)} l${f1(hd + 1)} ${f1(hd)} l${f1(-hd - 1)} ${f1(hd)}" fill="none" stroke="${C.route}" stroke-width="${f1(Lk('titleArrowStroke') * k)}" stroke-linecap="round" stroke-linejoin="round"/>`);
    const hs = Lk('titleArrowStroke') * k / 2; // round caps reach half a stroke past the path
    add('arrow', [x - hs, my - hd - hs, x + len + hs, my + hd + hs]);
    return x + len + ag * k;
  };
  // every line starts with its ink exactly on the safe edge (no optical overhang)
  const atL = (st, s) => L - ink(st, s).x;
  let y = Lk('titleBaseline');
  if (ink(ti, A).w + ink(ti, B).w + aw + 2 * ag <= maxW1) {
    const x0 = atL(ti, A);
    art.push(textEl(ti, A, x0, y, { id: 'title' })); const b0 = add('title', textBox(ti, A, x0, y));
    const bx = arrow(b0[2] + ag, y, ti.size);
    art.push(textEl(ti, B, bx, y, { id: 'title-2' })); add('title', textBox(ti, B, bx, y));
  } else {
    const w1 = maxW1, w2 = R - L - aw - ag, size = Math.min(fit(ti, A, w1).size, fit(ti, B, w2).size), st = { ...ti, size };
    const clip = (s, w) => { if (ink(st, s).w <= w) return s; let t = s; while (t.length > 1 && ink(st, t + '…').w > w) t = t.slice(0, -1).trimEnd(); return t + '…'; };
    const a = clip(A, w1), bb = clip(B, w2 - ag * size / ti.size);
    const x0 = atL(st, a);
    art.push(textEl(st, a, x0, y, { id: 'title' })); add('title', textBox(st, a, x0, y));
    y += Lk('titleLineHeight') * size / ti.size;
    const bx = arrow(L + Lk('titleArrowStroke') * size / ti.size / 2, y, size);
    art.push(textEl(st, bb, bx, y, { id: 'title-2' })); add('title', textBox(st, bb, bx, y));
  }
  const dt = TY('date'), dateY = y + Lk('dateGap');
  art.push(textEl(dt, cd.date, L + 2, dateY, { id: 'date' })); add('date', textBox(dt, cd.date, L + 2, dateY));

  // route box: wide, or tall when that draws the route larger
  const hasAlt = !cd.hidden && cd.pts.some(p => p[2] != null);
  const top = Math.max(Lk('routeBoxTop'), dateY + Lk('routeTopGap'));
  const bottom = hasAlt ? Lk('routeBoxBottom') : Lk('routeBottomNoElevation');
  const src = cd.hidden ? PLACES.i80 : cd.pts;
  const lat0 = src.reduce((a, p) => a + p[0], 0) / src.length, kx = Math.cos(lat0 * Math.PI / 180);
  const gx = src.map(p => p[1] * kx), gy = src.map(p => -p[0]);
  const ext = [Math.min(...gx), Math.max(...gx), Math.min(...gy), Math.max(...gy)], gw = ext[1] - ext[0] || 1e-9, gh = ext[3] - ext[2] || 1e-9;
  const wide = [Lk('routeBoxLeft'), top, Lk('routeBoxRight'), bottom];
  const tw = Lk('routeBoxTallWidth'), th = Math.min(Lk('routeBoxTallHeight'), bottom - top), tcy = (top + bottom) / 2;
  const tall = [W / 2 - tw / 2, tcy - th / 2, W / 2 + tw / 2, tcy + th / 2];
  const scaleIn = b => Math.min((b[2] - b[0]) / gw, (b[3] - b[1]) / gh);
  const RB = cd.hidden ? [wide[0] + 120, wide[1] + 60, wide[2] - 120, wide[3] - 60] : scaleIn(tall) > scaleIn(wide) * 1.05 ? tall : wide;
  const sc = scaleIn(RB), ox = RB[0] + ((RB[2] - RB[0]) - gw * sc) / 2 - ext[0] * sc, oy = RB[1] + ((RB[3] - RB[1]) - gh * sc) / 2 - ext[2] * sc;
  const proj = p => [p[1] * kx * sc + ox, -p[0] * sc + oy];
  const rd = [];
  let summit = null, start, end, routeXY = null;
  const rt = P('route'), rg = P('ring');
  if (!cd.hidden) {
    // split at recording gaps; each run is simplified and smoothed on its own
    const runs = [[]];
    cd.pts.forEach(p => { if (p[3] && runs.at(-1).length) runs.push([]); runs.at(-1).push(p); });
    const paths = runs.map(r => smooth(simplify(r.map(proj), rt.simplifyTolerance))).join(' ');
    const gaps = runs.slice(1).map((r, i) => [proj(runs[i].at(-1)), proj(r[0])]);
    const lj = 'stroke-linecap="round" stroke-linejoin="round"';
    rd.push(`<path id="route-glow" d="${paths}" fill="none" stroke="${C.route}" stroke-opacity="${rt.glow.opacity}" stroke-width="${rt.glow.width}" ${lj} filter="url(#glow)"/>`);
    art.push(`<path id="route-casing" d="${paths}" fill="none" stroke="${rt.casing.color}" stroke-opacity="${rt.casing.opacity}" stroke-width="${rt.casing.width}" ${lj}/>`);
    for (const [a, b] of gaps) art.push(`<path class="route-gap" d="M${f1(a[0])} ${f1(a[1])} L${f1(b[0])} ${f1(b[1])}" stroke="${rt.gap.color}" stroke-width="${rt.gap.width}" stroke-dasharray="0 ${rt.gap.spacing}" stroke-linecap="round"/>`);
    art.push(`<path id="route" d="${paths}" fill="none" stroke="${rt.core.color}" stroke-width="${rt.core.width}" ${lj}/>`);
    start = proj(cd.pts[0]); end = proj(cd.pts.at(-1));
    const sp = cd.pts.filter(p => p[2] != null);
    if (sp.length) summit = sp.reduce((a, p) => p[2] > a[2] ? p : a);
    routeXY = cd.pts.map(proj);
    cd.pts.forEach(p => { const q = proj(p); add('route', [q[0] - rt.core.width / 2, q[1] - rt.core.width / 2, q[0] + rt.core.width / 2, q[1] + rt.core.width / 2]); });
  } else {
    start = proj(PLACES.i80[0]); end = proj(PLACES.i80[1]);
    art.push(`<path id="places-connector" d="M${f1(start[0])} ${f1(start[1])} L${f1(end[0])} ${f1(end[1])}" stroke="${C.secondary}" stroke-opacity="${rt.hiddenConnector.opacity}" stroke-width="${rt.gap.width}" stroke-dasharray="0 ${rt.gap.spacing}" stroke-linecap="round"/>`);
  }
  const ring = ([x, y], id) => `<g id="${id}"><circle cx="${f1(x)}" cy="${f1(y)}" r="${rg.radius}" fill="${C.route}" fill-opacity="${rg.fillOpacity}"/><circle cx="${f1(x)}" cy="${f1(y)}" r="${rg.radius}" fill="none" stroke="${C.route}" stroke-width="${rg.strokeWidth}" stroke-dasharray="${rg.dash} ${rg.dashGap}" stroke-linecap="round"/><circle cx="${f1(x)}" cy="${f1(y)}" r="${rg.dotHaloRadius}" fill="${C.ink}" fill-opacity="${rg.dotHaloOpacity}"/><circle cx="${f1(x)}" cy="${f1(y)}" r="${rg.dotRadius}" fill="${C.text}"/></g>`;
  art.push(ring(start, 'start'), ring(end, 'end'));
  const rr = rg.radius + rg.strokeWidth / 2;
  add('ring', [start[0] - rr, start[1] - rr, start[0] + rr, start[1] + rr]); add('ring', [end[0] - rr, end[1] - rr, end[0] + rr, end[1] + rr]);
  if (summit && hasAlt) {
    const [mx, my] = proj(summit), sm = P('summit');
    art.push(`<circle id="highest-point" cx="${f1(mx)}" cy="${f1(my)}" r="${sm.radius}" fill="${C.text}" stroke="${C.ink}" stroke-opacity="${sm.strokeOpacity}" stroke-width="${sm.strokeWidth}"/>`);
    add('summit', [mx - sm.radius, my - sm.radius, mx + sm.radius, my + sm.radius]);
  }

  // elevation strip
  const fmtAlt = m => cd.summitUnit === 'ft' ? `${num(loc, m / 0.3048)} FT` : `${num(loc, m)} M`;
  if (hasAlt) {
    const et = Lk('elevationTop'), eb = Lk('elevationBaseline'), ev = P('elevation');
    const kt = TY('kicker'), kick = cd.kicker ?? 'Elevation';
    art.push(textEl(kt, kick, L + 2, et - Lk('elevationKickerGap'), { id: 'elevation-kicker' })); add('kicker', textBox(kt, kick, L + 2, et - Lk('elevationKickerGap')));
    let d = 0; const ds = cd.pts.map((p, i) => (d += i ? kmBetween(cd.pts[i - 1], p) : 0));
    const flip = end[0] < start[0], amax = summit[2], amin = 0, E = (i) => [flip ? R - ds[i] / d * (R - L) : L + ds[i] / d * (R - L), eb - (cd.pts[i][2] - amin) / (amax - amin) * (eb - et)];
    const runs = [[]]; cd.pts.forEach((p, i) => { if (p[3] && runs.at(-1).length) runs.push([]); if (p[2] != null) runs.at(-1).push(E(i)); });
    const line = runs.map(r => 'M' + simplify(r, P('elevation.simplifyTolerance')).map(q => `${f1(q[0])} ${f1(q[1])}`).join(' L')).join(' ');
    const area = runs.map(r => { const s = simplify(r, P('elevation.simplifyTolerance')); return 'M' + s.map(q => `${f1(q[0])} ${f1(q[1])}`).join(' L') + ` L${f1(s.at(-1)[0])} ${eb} L${f1(s[0][0])} ${eb} Z`; }).join(' ');
    over.push(`<path id="elevation-fill" d="${area}" fill="url(#elev)"/>`); // above the shadow, so the shadow never greys it
    art.push(`<path d="${line}" fill="none" stroke="${C.ink}" stroke-opacity="${ev.casingOpacity}" stroke-width="${ev.casingWidth}" stroke-linejoin="round"/>`);
    for (let i = 1; i < runs.length; i++) { const a = runs[i - 1].at(-1), b = runs[i][0]; art.push(`<path class="elevation-gap" d="M${f1(a[0])} ${f1(a[1])} L${f1(b[0])} ${f1(b[1])}" stroke="${rt.gap.color}" stroke-width="${rt.gap.width * 0.7}" stroke-dasharray="0 ${rt.gap.spacing * 0.75}" stroke-linecap="round"/>`); }
    art.push(`<path id="elevation" d="${line}" fill="none" stroke="${C.route}" stroke-width="${ev.lineWidth}" stroke-linejoin="round" stroke-linecap="round"/>`);
    const si = cd.pts.indexOf(summit), [tx, ty] = E(si), sm = P('summit');
    art.push(`<circle id="elevation-highest" cx="${f1(tx)}" cy="${f1(ty)}" r="${sm.stripRadius}" fill="${C.text}" stroke="${C.ink}" stroke-opacity="${sm.stripStrokeOpacity}" stroke-width="${sm.stripStrokeWidth}"/>`);
    const st = TY('summitLabel'), lab = `${cd.summitLabel ?? 'Highest point'} · ${fmtAlt(amax)}`, gap = Lk('summitLabelGap');
    const kb = boxes.find(x => x[4] === 'kicker');
    const cands = [[tx - gap, ty - 16, 'end'], [tx + gap, ty - 16, 'start'], [tx + gap, ty + 8, 'start'], [tx - gap, ty + 8, 'end']];
    let pk = cands.map(([x, y, an]) => [x, y, an, textBox(st, lab, x, y, an)]).find(([, , , bb]) => bb[0] >= L && bb[2] <= R && !(bb[0] < kb[2] + 14 && bb[2] > kb[0] - 14 && bb[1] < kb[3] + 6 && bb[3] > kb[1] - 6));
    pk ??= [tx - gap, ty - 16, 'end', textBox(st, lab, tx - gap, ty - 16, 'end')];
    art.push(textEl(st, lab, pk[0], pk[1], { anchor: pk[2], id: 'highest-label' })); add('summit label', pk[3]);
  }

  // area labels: try 8 spots around each ring, keep the first that clears everything placed so far
  const al = TY('areaLabel'), off = Lk('areaLabelOffset'), clr = Lk('labelClearance');
  const hits = (b, list) => list.some(o => b[0] < o[2] + clr && b[2] > o[0] - clr && b[1] < o[3] + clr && b[3] > o[1] - clr);
  const fixed = boxes.filter(b => b[4] !== 'route' && b[4] !== 'ring').slice();
  const routeBoxes = boxes.filter(b => b[4] === 'route');
  [[start, cd.ends[0], 'start-label'], [end, cd.ends[1], 'end-label']].forEach(([[x, y], name, id], k) => {
    const f = fit(al, cased(al, name), Lk('areaLabelMaxWidth')), st = { ...al, size: f.size };
    const m = ink(st, f.s), h = m.bottom - m.top;
    const spots = [[x + off, y + h / 2, 'start'], [x - off, y + h / 2, 'end'], [x, y - off, 'middle'], [x, y + off + h, 'middle'], [x + off * 0.8, y - off * 0.8, 'start'], [x - off * 0.8, y - off * 0.8, 'end'], [x + off * 0.8, y + off * 0.8 + h, 'start'], [x - off * 0.8, y + off * 0.8 + h, 'end']];
    // prefer pointing outward from the other end
    const other = k ? start : end, outward = x < other[0] ? [1, 0, 5, 7, 2, 3, 4, 6] : [0, 1, 4, 6, 2, 3, 5, 7];
    const others = boxes.filter(b => b[4] !== 'route');
    let pick = null;
    for (const i of outward) {
      let [lx, ly, an] = spots[i], b = textBox(st, f.s, lx, ly, an);
      const shift = b[0] < L ? L - b[0] : b[2] > R ? R - b[2] : 0; // slide along the edge, never past it
      if (shift) { lx += shift; b = [b[0] + shift, b[1], b[2] + shift, b[3]]; }
      if (b[1] < SAFE.top) continue;
      if (!hits(b, others) && !hits(b, routeBoxes)) { pick = [lx, ly, an, b]; break; }
    }
    if (!pick) { const [lx, ly, an] = spots[outward[0]]; pick = [lx, ly, an, textBox(st, f.s, lx, ly, an)]; }
    art.push(textEl(st, f.s, pick[0], pick[1], { anchor: pick[2], op: 0.9, id }));
    add('area label', pick[3]);
  });
  void fixed;

  // the big number and unit
  const nt = TY('number'), ut = TY('unit'), nstr = num(loc, cd.dist);
  let ns = nt.size, us = ut.size;
  const full = () => ink({ ...nt, size: ns }, nstr).w + Lk('unitGap') * ns / nt.size + ink({ ...ut, size: us }, loc.unit).w;
  while (full() > R - L && ns > nt.size * Lk('numberMinScale')) { ns -= 4; us = ut.size * ns / nt.size; }
  const nx = L - ink({ ...nt, size: ns }, nstr).x, nb = Lk('numberBaseline');
  art.push(textEl({ ...nt, size: ns }, nstr, nx, nb, { id: 'distance' })); const nbx = add('number', textBox({ ...nt, size: ns }, nstr, nx, nb));
  const ux = nbx[2] + Lk('unitGap') * ns / nt.size;
  art.push(textEl({ ...ut, size: us }, loc.unit, ux, nb, { id: 'distance-unit' })); add('unit', textBox({ ...ut, size: us }, loc.unit, ux, nb));

  // stats: moving time, regions, then career distance, else the highest point, else nothing
  const hl = P('hairline'), sl = TY('statLabel'), sv = TY('statValue');
  const cols = [[loc.labels[0], cd.stats[0]], [loc.labels[1], cd.stats[1]]];
  if (cd.stats[2] != null) cols.push([loc.labels[2], num(loc, cd.stats[2])]);
  else if (hasAlt) cols.push([cd.summitLabel ?? 'HIGHEST POINT', fmtAlt(summit[2]).toLowerCase()]);
  const cw = (R - L) / cols.length;
  art.push(`<path d="M${L} ${Lk('statsRule')} H${R}" stroke="${C.text}" stroke-opacity="${hl.opacity}" stroke-width="${hl.width}"/>`);
  cols.forEach(([label, value], i) => {
    const x = L + 2 + i * cw;
    if (i) art.push(`<path d="M${f1(x - Lk('statsDividerInset'))} ${Lk('statsDividerTop')} V${Lk('statsDividerBottom')}" stroke="${C.text}" stroke-opacity="${hl.opacity}" stroke-width="${hl.width}"/>`);
    const lf = fit(sl, cased(sl, label), cw - Lk('statsDividerInset') - 8), vf = fit(sv, value, cw - Lk('statsDividerInset') - 8);
    art.push(textEl({ ...sl, size: lf.size }, lf.s, x, Lk('statsLabelBaseline'), { id: `stat-${i + 1}-label` })); add('stat', textBox({ ...sl, size: lf.size }, lf.s, x, Lk('statsLabelBaseline')));
    art.push(textEl({ ...sv, size: vf.size }, vf.s, x, Lk('statsValueBaseline'), { id: `stat-${i + 1}-value` })); add('stat', textBox({ ...sv, size: vf.size }, vf.s, x, Lk('statsValueBaseline')));
  });

  // filters: route glow and the one soft shadow (wide + tight blur merged)
  const sh = P('shadow'), ev = P('elevation');
  const ink3 = [1, 3, 5].map(i => (parseInt(C.ink.slice(i, i + 2), 16) / 255).toFixed(3));
  const defs = `<defs><filter id="glow" x="-10%" y="-60%" width="120%" height="220%"><feGaussianBlur stdDeviation="${rt.glow.blur}"/></filter>` +
    `<filter id="shade" color-interpolation-filters="sRGB" filterUnits="userSpaceOnUse" x="0" y="0" width="${W}" height="${H}"><feColorMatrix in="SourceAlpha" type="matrix" values="0 0 0 0 ${ink3[0]}  0 0 0 0 ${ink3[1]}  0 0 0 0 ${ink3[2]}  0 0 0 1 0" result="a"/>` +
    `<feGaussianBlur in="a" stdDeviation="${sh.blur}" result="w"/><feOffset in="w" dy="${sh.offsetY}" result="wo"/><feComponentTransfer in="wo" result="wide"><feFuncA type="linear" slope="${sh.opacity}"/></feComponentTransfer>` +
    `<feMorphology in="a" operator="dilate" radius="${sh.tightSpread}" result="ad"/><feGaussianBlur in="ad" stdDeviation="${sh.tightBlur}" result="t"/><feOffset in="t" dy="${sh.tightOffsetY}" result="to"/><feComponentTransfer in="to" result="tight"><feFuncA type="linear" slope="${sh.tightOpacity}"/></feComponentTransfer>` +
    `<feMerge><feMergeNode in="wide"/><feMergeNode in="tight"/></feMerge></filter>` +
    `<linearGradient id="elev" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${C.route}" stop-opacity="${ev.fillTopOpacity}"/><stop offset="1" stop-color="${C.route}" stop-opacity="${ev.fillBottomOpacity}"/></linearGradient></defs>`;
  return { defs, glow: rd.join('') + over.join(''), art: art.join('\n'), boxes, RB, hasAlt, routeXY };
}

function svgOf(cd, b, { background = '', guides = false, title, hideText = false } = {}) {
  const art = hideText ? b.art.replace(/<text /g, '<text visibility="hidden" ') : b.art;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">` +
    `<title>${title ?? 'RoadPrint Print card (transparent overlay)'}</title>${b.defs}${background}` +
    `<defs><g id="art">\n${b.art}\n</g></defs><use href="#art" filter="url(#shade)"/>\n${b.glow}\n` +
    (hideText ? `<g>${art}</g>` : `<use href="#art"/>`) + (guides ? guideSvg(b) : '') + '</svg>\n';
}
function guideSvg(b) {
  return `<g id="guides" fill="none" stroke-width="2"><rect x="${L}" y="${SAFE.top}" width="${R - L}" height="${H - SAFE.top - SAFE.bottom}" stroke="#4fd1ff" stroke-dasharray="14 10"/>` +
    `<rect x="${f1(b.RB[0])}" y="${f1(b.RB[1])}" width="${f1(b.RB[2] - b.RB[0])}" height="${f1(b.RB[3] - b.RB[1])}" stroke="#ff5fa2" stroke-dasharray="6 8"/></g>`;
}

// ---- checks: safe area and collisions ----------------------------------------------------------------
function check(name, b) {
  const errs = [];
  for (const x of b.boxes) {
    if (x[0] < L - 0.5 || x[2] > R + 0.5 || x[1] < SAFE.top || x[3] > H - SAFE.bottom) errs.push(`${x[4]} outside safe area [${x.slice(0, 4).map(Math.round)}]`);
  }
  // no exceptions: the number and the title obey the same 72 px edge as everything else
  const labels = b.boxes.filter(x => /label|title|date|wordmark|kicker|sign|arrow/.test(x[4]));
  const marks = b.boxes.filter(x => /route|ring|summit$/.test(x[4]));
  for (const a of labels) for (const m of marks) if (a[0] < m[2] && a[2] > m[0] && a[1] < m[3] && a[3] > m[1]) { errs.push(`${a[4]} touches ${m[4]}`); break; }
  for (let i = 0; i < labels.length; i++) for (let j = i + 1; j < labels.length; j++) {
    const a = labels[i], c = labels[j];
    if (a[0] < c[2] && a[2] > c[0] && a[1] < c[3] && a[3] > c[1]) errs.push(`${a[4]} overlaps ${c[4]} [${a.slice(0,4).map(Math.round)}]/[${c.slice(0,4).map(Math.round)}]`);
  }
  const uniq = [...new Set(errs)];
  console.log(`${name.padEnd(22)} ${uniq.length ? 'FAIL ' + uniq.join('; ') : 'ok'}`);
  return uniq.length === 0;
}

// ---- preview backgrounds: checkerboard, app dark, and two photographs ------------------------------
/** A photo as a full-bleed background (cover). cropX = left edge of the crop in source px. */
function photo(file, w, h, cropX) {
  const b64 = readFileSync(new URL(`Tools/design/fixtures/photos/${file}`, ROOT)).toString('base64');
  const k = Math.max(W / w, H / h), x = cropX == null ? (W - w * k) / 2 : -cropX * k, y = (H - h * k) / 2;
  return `<image id="photo" x="${f1(x)}" y="${f1(y)}" width="${f1(w * k)}" height="${f1(h * k)}" href="data:image/jpeg;base64,${b64}"/>`;
}
const BG = {
  transparent: `<defs><pattern id="chk" width="40" height="40" patternUnits="userSpaceOnUse"><rect width="40" height="40" fill="#cfd2d6"/><rect width="20" height="20" fill="#f4f5f6"/><rect x="20" y="20" width="20" height="20" fill="#f4f5f6"/></pattern></defs><rect width="${W}" height="${H}" fill="url(#chk)"/>`,
  dark: `<rect width="${W}" height="${H}" fill="${C.bg}"/>`,
  // Photographs (preview only, never in the card SVGs). Provenance: Tools/design/fixtures/photos/README.md
  sky: photo('bright-sky-cc0.jpg', 1280, 1920),       // CC0, Trixia Lao via Wikimedia Commons
  night: photo('night-moab-pd.jpg', 1920, 1015, 1000), // public domain, Arches National Park (NPS)
};

// ---- contrast on the bright photo -------------------------------------------------------------------
const lin = c => (c /= 255) <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
const lumPx = (px, i) => 0.2126 * lin(px[i]) + 0.7152 * lin(px[i + 1]) + 0.0722 * lin(px[i + 2]);
const lumHex = h => 0.2126 * lin(parseInt(h.slice(1, 3), 16)) + 0.7152 * lin(parseInt(h.slice(3, 5), 16)) + 0.0722 * lin(parseInt(h.slice(5, 7), 16));
/** Glyph-local text contrast on a photo, with the soft shadow (WCAG 2 contrast formula).
 *  1. Render the card on the photo with every <text> hidden: photo + shadow + glow = the local background.
 *  2. Render a coverage mask: the same <text> elements in white on black, no shadow, same antialiasing.
 *  3. Antialiasing policy: a pixel with coverage >= GLYPH_CORE is glyph; its text colour is the fill
 *     (fill-opacity composited over the pixel behind it). Pixels with coverage < GLYPH_CORE are edge blends
 *     of text and background and are not counted as glyph. The surround is every pixel with coverage
 *     < 0.02 within SURROUND px of a glyph pixel: what the eye sees right next to the stroke.
 *  4. For every glyph pixel: contrast(text, background under it); for every surround pixel:
 *     contrast(text, that pixel). The text passes when at least PASS_SHARE of both sets are >= MIN_CONTRAST.
 *  The road sign is excluded: it carries its own opaque panel. */
const GLYPH_CORE = 0.75, SURROUND = 3, MIN_CONTRAST = 3, PASS_SHARE = 0.98;
const TEXT_RE = /<text(?: id="([^"]+)")?[^>]*? fill="([^"]+)"(?: fill-opacity="([\d.]+)")?>([^<]*)<\/text>/g;
function contrastReport(cd, b, bg) {
  const back = renderSvg(svgOf(cd, b, { background: BG[bg], hideText: true })).pixels;
  const s0 = b.art.indexOf('<g id="road-sign"'), s1 = b.art.indexOf('</text></g>', s0) + '</text></g>'.length; // the sign ends with its number
  const artTop = s0 < 0 ? b.art : b.art.slice(0, s0) + b.art.slice(s1);
  const texts = [...artTop.matchAll(TEXT_RE)];
  // one coverage mask for all text (text boxes never overlap: the layout check guarantees it)
  const mask = renderSvg(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}"><rect width="${W}" height="${H}" fill="#000"/>` +
    texts.map(([el, , fill]) => el.replace(` fill="${fill}"`, ' fill="#ffffff"').replace(/ fill-opacity="[\d.]+"/, '')).join('') + '</svg>').pixels;
  const cov = i => mask[i * 4] / 255;
  const rows = [];
  for (const m of texts) {
    const [el, id, fill, op = 1, s] = m;
    const bb = new Resvg(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">${el}</svg>`, { font: fontOptions() }).getBBox();
    if (!bb) continue;
    const x0 = Math.max(0, Math.floor(bb.x) - 1), y0 = Math.max(0, Math.floor(bb.y) - 1), x1 = Math.min(W - 1, Math.ceil(bb.x + bb.width) + 1), y1 = Math.min(H - 1, Math.ceil(bb.y + bb.height) + 1);
    const fr = [1, 3, 5].map(j => parseInt(fill.slice(j, j + 2), 16));
    const textLum = i => { // fill over the pixel behind it, in sRGB like the renderer
      const c = fr.map((v, j) => v * +op + back[i * 4 + j] * (1 - +op));
      return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2]);
    };
    const cr = (a, c) => (Math.max(a, c) + 0.05) / (Math.min(a, c) + 0.05);
    const under = [], around = [];
    let tl = 0, nt = 0;
    for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) { const i = y * W + x; if (cov(i) >= GLYPH_CORE) { const t = textLum(i); tl += t; nt++; under.push(cr(t, lumPx(back, i * 4))); } }
    const tMean = tl / nt;
    for (let y = Math.max(0, y0 - SURROUND); y <= Math.min(H - 1, y1 + SURROUND); y++) for (let x = Math.max(0, x0 - SURROUND); x <= Math.min(W - 1, x1 + SURROUND); x++) {
      const i = y * W + x; if (cov(i) >= 0.02) continue;
      let near = false;
      for (let dy = -SURROUND; dy <= SURROUND && !near; dy++) for (let dx = -SURROUND; dx <= SURROUND; dx++) {
        const xx = x + dx, yy = y + dy; if (xx < 0 || yy < 0 || xx >= W || yy >= H || dx * dx + dy * dy > SURROUND * SURROUND) continue;
        if (cov(yy * W + xx) >= GLYPH_CORE) { near = true; break; }
      }
      if (near) around.push(cr(tMean, lumPx(back, i * 4)));
    }
    const q = (a, p) => { const v = a.slice().sort((x, y) => x - y); return +v[Math.min(v.length - 1, Math.floor(v.length * p))].toFixed(2); };
    const share = a => +(a.filter(v => v >= MIN_CONTRAST).length / a.length).toFixed(3);
    const row = { id: id ?? '', text: s.slice(0, 26), glyphPx: under.length, surroundPx: around.length,
      underMin: q(under, 0), underP02: q(under, 0.02), underShare3: share(under),
      surroundMin: q(around, 0), surroundP02: q(around, 0.02), surroundShare3: share(around) };
    row.pass = row.underShare3 >= PASS_SHARE && row.surroundShare3 >= PASS_SHARE;
    rows.push(row);
  }
  return rows;
}
/** Route visibility on the bright photo: contrast between the amber core and the ring of pixels just outside the casing. */
function routeReport(cd, b, bg = 'sky') {
  const px = renderSvg(svgOf(cd, b, { background: BG[bg] })).pixels;
  const xy = b.routeXY; if (!xy) return null;
  const core = lumHex(C.route), out = [];
  const ends = [xy[0], xy.at(-1)];
  for (let i = 1; i < xy.length; i++) {
    if (ends.some(e => Math.hypot(xy[i][0] - e[0], xy[i][1] - e[1]) < 45)) continue; // under the rings
    const [x0, y0] = xy[i], [ax, ay] = xy[Math.max(0, i - 4)], [bx, by] = xy[Math.min(xy.length - 1, i + 4)]; const dx = bx - ax, dy = by - ay, n = Math.hypot(dx, dy) || 1;
    for (const s of [-1, 1]) { let m = 1; for (const o of [8, 10, 12, 14]) { const qx = Math.round(x0 + (-dy / n) * s * o), qy = Math.round(y0 + (dx / n) * s * o); if (qx >= 0 && qy >= 0 && qx < W && qy < H) m = Math.min(m, lumPx(px, (qy * W + qx) * 4)); } out.push(m); }
  }
  out.sort((a, c) => a - c);
  const cr = l => (Math.max(core, l) + 0.05) / (Math.min(core, l) + 0.05);
  return { samples: out.length, p5Contrast: +cr(out[Math.floor(out.length * 0.95)]).toFixed(2), medianContrast: +cr(out[Math.floor(out.length / 2)]).toFixed(2), shareAtLeast3: +(out.filter(l => cr(l) >= 3).length / out.length).toFixed(3) };
}

// ---- build everything ------------------------------------------------------------------------------
let ok = true; const built = {};
for (const [name, cd] of Object.entries(CASES)) { built[name] = build(cd); ok = check(name, built[name]) && ok; }
writeFileSync(new URL('print-card.svg', OUT), svgOf(CASES.i80, built.i80, { title: 'RoadPrint Print card: transparent overlay, I-80 sample. Text is live placeholder text the app fills' }));
writeFileSync(new URL('print-card-hide-route.svg', OUT), svgOf(CASES['hide-route'], built['hide-route'], { title: 'RoadPrint Print card, hide route: places and stats only' }));
const png = (name, svg, width) => { const r = renderSvg(svg, width); writeFileSync(new URL(name, PREV), r.png); return r; };
const thumbs = [];
for (const route of ['i80', 'brenner', 'nullarbor']) for (const bg of ['transparent', 'dark', 'sky', 'night']) {
  const svg = svgOf(CASES[route], built[route], { background: BG[bg] });
  png(`${route}-${bg}.png`, svg, 540); thumbs.push([`${route} · ${bg}`, svg]);
}
const edge = [];
for (const [name, cd] of Object.entries(CASES)) if (!cd.main) {
  const svg = svgOf(cd, built[name], { background: BG.dark, guides: true });
  png(`${name}.png`, svg, 540); edge.push([name, svg, cd.note]);
}
png('i80-guides.png', svgOf(CASES.i80, built.i80, { background: BG.dark, guides: true }), 540);

const report = { method: { glyphCore: GLYPH_CORE, surroundPx: SURROUND, minContrast: MIN_CONTRAST, passShare: PASS_SHARE,
  note: 'Glyph-local WCAG contrast on photographs with the soft shadow; see contrastReport() in Tools/design/print-card.mjs' },
  text: {}, route: {} };
const fails = [];
for (const route of ['i80', 'brenner', 'nullarbor', 'longer-names']) for (const bg of ['sky', 'night']) {
  const key = `${route}-${bg}`, rows = contrastReport(CASES[route], built[route], bg);
  report.text[key] = rows; report.route[key] = routeReport(CASES[route], built[route], bg);
  for (const r of rows) if (!r.pass) fails.push(`${key}: "${r.text}" glyph ${r.underShare3}, surround ${r.surroundShare3} at >= ${MIN_CONTRAST}:1`);
  console.log(key.padEnd(20), rows.every(r => r.pass) ? 'text ok' : 'text FAIL', 'worst surroundP02', Math.min(...rows.map(r => r.surroundP02)), 'route', JSON.stringify(report.route[key]));
}
report.pass = fails.length === 0;
writeFileSync(new URL('checks.json', PREV), JSON.stringify(report, null, 1) + '\n');
if (fails.length) { console.error('contrast check failed:\n  ' + fails.join('\n  ')); ok = false; }

// ---- contact sheet ---------------------------------------------------------------------------------
// Top: I-80 (the USA case) on the four backgrounds at 50 % (540×960). Below: every preview at 25 %
// (270×480, share-sheet size), one route per row, then the edge cases.
{
  const gap = 22, lab = 50, cols = 8, tw = 270, th = 480, bw = 540, bh = 960;
  const SW = cols * tw + (cols + 1) * gap;
  const big = thumbs.filter(([n]) => n.startsWith('i80'));
  const small = [...thumbs.map(([n, s]) => [n, s, '']), ...edge.map(([n, s, note]) => [n, s, note])];
  const bigGap = (SW - 4 * bw) / 5, y1 = 120, y2 = y1 + bh + lab + 70;
  const rows = Math.ceil(small.length / cols), SH = y2 + 40 + rows * (th + lab + gap) + gap;
  const o = [`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${SW} ${SH}" width="${SW}" height="${SH}"><rect width="${SW}" height="${SH}" fill="#0b0c10"/>`,
    `<text x="${gap}" y="52" font-family="Inter" font-weight="700" font-size="30" fill="#f0efec">RoadPrint Print card (ROA-57) · I-80 Utah → California first</text>`,
    `<text x="${gap}" y="88" font-family="Inter" font-weight="500" font-size="18" fill="#a6aab4">Row 1: I-80 at 50 % on transparent, app dark #14161c, bright sky, night. Below: every preview at 25 % (270×480, share-sheet size).</text>`];
  const tile = (n, s, note, x, y, w, h, fs) => {
    o.push(`<image x="${x}" y="${y}" width="${w}" height="${h}" href="data:image/png;base64,${renderSvg(s, w).png.toString('base64')}"/>`);
    o.push(`<text x="${x}" y="${y + h + fs + 6}" font-family="Inter" font-weight="600" font-size="${fs}" fill="#f0efec">${esc(n)}</text>`);
    if (note) o.push(`<text x="${x}" y="${y + h + 40}" font-family="Inter" font-weight="400" font-size="11" fill="#a6aab4">${esc(note.slice(0, 48))}</text>`);
  };
  big.forEach(([n, s], i) => tile(n, s, '', bigGap + i * (bw + bigGap), y1, bw, bh, 20));
  o.push(`<text x="${gap}" y="${y2 + 10}" font-family="Inter" font-weight="700" font-size="22" fill="#f0efec">At 25 %: I-80, Brenner, Nullarbor on the four backgrounds, then edge cases with safe area (blue) and route box (pink)</text>`);
  small.forEach(([n, s, note], i) => {
    tile(n, s, note, gap + (i % cols) * (tw + gap), y2 + 40 + Math.floor(i / cols) * (th + lab + gap), tw, th, 15);
  });
  o.push('</svg>');
  writeFileSync(new URL('contact-sheet.png', PREV), renderSvg(o.join('')).png);
  console.log('contact-sheet.png', SW, SH);
}
if (!ok) { console.error('layout check failed'); process.exitCode = 1; }
