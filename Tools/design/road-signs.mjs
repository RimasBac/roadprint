#!/usr/bin/env node
// Road-sign templates (ROA-49): writes Design/road-signs/*.svg, signs.json, previews and contact sheets.
// Usage: node road-signs.mjs [--only usa]
// Each template is a shield or plate drawn in a 64-unit-high viewBox, without the number. The number's
// box is computed from the field shape so the text keeps 4 units from every edge, and checked again
// for every sample ref before anything is written.
import { writeFileSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { renderSvg } from './render.mjs';
import { loadFont } from './ttf.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const OUT = join(here, '../../Design/road-signs');
const PREV = join(OUT, 'previews');
mkdirSync(PREV, { recursive: true });
const FONT = loadFont(join(here, 'fonts/BarlowCondensed-700.ttf'));
const CAP = FONT.capHeight / FONT.unitsPerEm; // 0.70
const H = 64, MARGIN = 4, MIN_SCALE = 0.7;
const tokens = JSON.parse(readFileSync(join(here, '../../Design/tokens.json'), 'utf8')).color;

// Our chosen sRGB values for a road-sign feel, not official specifications (board, 2026-11-10).
const PAL = {
  interstateBlue: '#003f87', interstateRed: '#bf2033', white: '#ffffff', black: '#111111',
  green: '#00703c', motorwayBlue: '#0079c1', yellow: '#ffd200', ausGreen: '#00693c', ausGold: '#ffc82e',
  // The board's greens give 4.3:1 (#00703c / yellow) and 4.4:1 (#00693c / gold), under the 4.5:1 bar.
  // These are the nearest darker greens that pass; the white-text E-road keeps #00703c.
  ukARoadGreen: '#006b39', ausGreenText: '#00663a',
  genericFill: tokens.land.$value, genericEdge: tokens.textSecondary.$value, genericText: tokens.text.$value,
};

const r2 = v => (Math.round(v * 100) / 100).toString();

// ---- shapes: right half as cubic segments from the top centre to the bottom centre, mirrored ------
// seg: ['L', x, y] or ['C', x1, y1, x2, y2, x, y]
function fullPath(start, half, cx, sx = 1) {
  const X = x => Math.round(cx + (x - 32) * sx); // every point lands on the 1-unit grid
  const pts = [[X(start[0]), start[1]]];
  const segs = half.map(s => s[0] === 'L' ? ['L', X(s[1]), s[2]] : ['C', X(s[1]), s[2], X(s[3]), s[4], X(s[5]), s[6]]);
  // mirror: walk back up the left side
  const mir = x => 2 * cx - x;
  const back = [];
  const ends = [pts[0], ...segs.map(s => [s[s.length - 2], s[s.length - 1]])];
  const last = ends[ends.length - 1];
  if (Math.abs(last[0] - cx) > 0.01) back.push(['L', mir(last[0]), last[1]]);
  for (let i = segs.length - 1; i >= 0; i--) {
    const s = segs[i], from = ends[i];
    if (s[0] === 'L') back.push(['L', mir(from[0]), from[1]]);
    else back.push(['C', mir(s[3]), s[4], mir(s[1]), s[2], mir(from[0]), from[1]]);
  }
  const all = [...segs, ...back];
  const d = `M${r2(pts[0][0])} ${r2(pts[0][1])}` + all.map(s => s[0] === 'L' ? `L${r2(s[1])} ${r2(s[2])}` : `C${s.slice(1).map(r2).join(' ')}`).join('') + 'Z';
  // polygon for checks
  const poly = [pts[0]];
  let cur = pts[0];
  for (const s of all) {
    if (s[0] === 'L') { cur = [s[1], s[2]]; poly.push(cur); continue; }
    for (let t = 1; t <= 24; t++) {
      const u = t / 24, a = (1 - u) ** 3, b = 3 * (1 - u) ** 2 * u, c = 3 * (1 - u) * u * u, e = u ** 3;
      poly.push([a * cur[0] + b * s[1] + c * s[3] + e * s[5], a * cur[1] + b * s[2] + c * s[4] + e * s[6]]);
    }
    cur = [s[5], s[6]];
  }
  return { d, poly };
}

const rectPoly = (x, y, w, h) => [[x, y], [x + w, y], [x + w, y + h], [x, y + h]];

// ---- geometry checks -------------------------------------------------------------------------------
function inside(poly, [x, y]) {
  let c = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i], [xj, yj] = poly[j];
    if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) c = !c;
  }
  return c;
}
function edgeDist(poly, [x, y]) {
  let m = Infinity;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [ax, ay] = poly[j], [bx, by] = poly[i], dx = bx - ax, dy = by - ay;
    const t = Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy || 1)));
    m = Math.min(m, Math.hypot(x - ax - t * dx, y - ay - t * dy));
  }
  return m;
}
/** Smallest clearance between the rectangle and the field edge (negative if outside). */
function clearance(field, x0, y0, x1, y1) {
  let m = Math.min(y0 - field.top, field.bottom - y1);
  for (let k = 0; k <= 20; k++) {
    const u = k / 20;
    for (const p of [[x0 + u * (x1 - x0), y0], [x0 + u * (x1 - x0), y1], [x0, y0 + u * (y1 - y0)], [x1, y0 + u * (y1 - y0)]]) {
      m = Math.min(m, inside(field.poly, p) ? edgeDist(field.poly, p) : -edgeDist(field.poly, p));
    }
  }
  return m;
}
/** Widest centred text box for the cap band [capTop, baseline] that keeps MARGIN clearance. */
function fitWidth(field, cx, capTop, baseline) {
  let lo = 0, hi = 2 * H;
  for (let i = 0; i < 40; i++) {
    const w = (lo + hi) / 2;
    if (clearance(field, cx - w / 2, capTop, cx + w / 2, baseline) >= MARGIN) lo = w; else hi = w;
  }
  return Math.floor(lo * 2) / 2;
}

// ---- layered drawing -------------------------------------------------------------------------------
// A shield = the field path S with uniform outside rings drawn as round-joined strokes (outermost first).
function rings(d, list) { // list: [{color, width}] outermost first; width = distance outside S
  return list.map(r => `<path d="${d}" fill="${r.color}" stroke="${r.color}" stroke-width="${r2(2 * r.width)}" stroke-linejoin="round"/>`).join('');
}
function letters(word, cx, baseline, cap, color, tracking = 0) {
  const size = cap / CAP, tr = tracking * FONT.unitsPerEm / size;
  const w = FONT.measure(word, tr) * size / FONT.unitsPerEm;
  return `<path id="lettering" d="${FONT.pathData(word, cx - w / 2, baseline, size, tr, 1)}" fill="${color}"/>`;
}

// ---- templates -------------------------------------------------------------------------------------
const T = {};
const KEY = 2; // keyline width

// US Interstate (MUTCD M1-1): concave top arcs meeting at a centre crest, red band with INTERSTATE,
// white divider, blue field. White border 3, dark keyline 2 outside so it holds on paper.
const IS_START = [32, 6];
const IS_HALF = [['C', 40, 11, 50, 11, 58, 8], ['L', 58, 20], ['C', 60, 40, 51, 53, 32, 59]];
function interstate(id, w, { small = false } = {}) {
  const cx = w / 2, sx = (cx - 5.2) / 26.8;
  const S = fullPath(IS_START, IS_HALF, cx, sx);
  const bandBottom = small ? 15 : 20, divider = 2;
  // the side is the vertical segment x = 58 from the corner (58, 8) down to y = 20
  const top = fullPath(IS_START, [IS_HALF[0], ['L', 58, bandBottom]], cx, sx);
  const band = top.d; // closes along y = bandBottom
  const wr = Math.round(26 * sx) + 2; // the divider runs 2 units into the white border
  let body = rings(S.d, [{ color: PAL.black, width: 5 }, { color: PAL.white, width: 3 }]);
  body += `<path d="${S.d}" fill="${PAL.interstateBlue}"/><path d="${band}" fill="${PAL.interstateRed}"/>`;
  body += `<rect x="${r2(cx - wr)}" y="${bandBottom}" width="${r2(2 * wr)}" height="${divider}" fill="${PAL.white}"/>`;
  if (!small) body += letters('INTERSTATE', cx, 17.6, 5.6, PAL.white, 0.25);
  const capTop = small ? 21.5 : 26.5, cap = small ? 22 : 20;
  return {
    id, w, body, kind: 'shield', textColor: PAL.white, fieldColor: PAL.interstateBlue, outerColor: PAL.black,
    field: { poly: S.poly, top: bandBottom + divider, bottom: H }, cx, capTop, cap,
    description: `US Interstate shield${w > 64 ? ', 3 digits' : ''}${small ? ', plain band for heights under 40 px' : ''}`,
  };
}

// US Route (MUTCD M1-4): the white shield with ears, a waist and a pointed base. Black keyline 2.5
// with a 2-unit white rim outside it, so the outline reads on dark and on paper.
const US_START = [32, 10];
const US_HALF = [['C', 38, 11, 47, 10, 54, 6], ['C', 57, 4, 60, 6, 60, 10], ['C', 60, 14, 56, 16, 56, 21],
  ['C', 56, 26, 60, 29, 60, 36], ['C', 60, 47, 46, 54, 32, 60]];
function usHighway(id, w) {
  const cx = w / 2, sx = (cx - 4) / 28;
  const S = fullPath(US_START, US_HALF, cx, sx);
  const body = rings(S.d, [{ color: PAL.white, width: 4 }, { color: PAL.black, width: 2 }]) + `<path d="${S.d}" fill="${PAL.white}"/>`;
  return {
    id, w, body, kind: 'shield', textColor: PAL.black, fieldColor: PAL.white, outerColor: PAL.white,
    field: { poly: S.poly, top: 0, bottom: H }, cx, capTop: 24.5, cap: 22,
    description: `US Route shield${w > 64 ? ', 3 digits' : ''}`,
  };
}

const ALL = {
  usInterstate: interstate('usInterstate', 64),
  'usInterstate-wide': interstate('usInterstate-wide', 80),
  'usInterstate-small': interstate('usInterstate-small', 64, { small: true }),
  'usInterstate-wide-small': interstate('usInterstate-wide-small', 80, { small: true }),
  usHighway: usHighway('usHighway', 64),
  'usHighway-wide': usHighway('usHighway-wide', 80),
};
const SAMPLES = {
  usInterstate: ['5', '80'], 'usInterstate-wide': ['405'], 'usInterstate-small': ['5', '80'], 'usInterstate-wide-small': ['405'],
  usHighway: ['1', '50'], 'usHighway-wide': ['101'],
};
const USA = Object.keys(ALL);

// Canada (Trans-Canada style): white shield, green top, black number, black keyline + white rim.
// No maple leaf or provincial crest.
const CA_START = [32, 5];
const CA_HALF = [['L', 57, 5], ['L', 57, 34], ['C', 57, 50, 46, 56, 32, 60]];
function canada(id, w) {
  const cx = w / 2, sx = (cx - 7) / 25;
  const S = fullPath(CA_START, CA_HALF, cx, sx);
  const top = fullPath(CA_START, [['L', 57, 5], ['L', 57, 22]], cx, sx);
  const body = rings(S.d, [{ color: PAL.white, width: 4 }, { color: PAL.black, width: 2 }]) +
    `<path d="${S.d}" fill="${PAL.white}"/><path d="${top.d}" fill="${PAL.green}"/>`;
  return {
    id, w, body, kind: 'shield', textColor: PAL.black, fieldColor: PAL.white, outerColor: PAL.white,
    field: { poly: S.poly, top: 22, bottom: H }, cx, capTop: 27, cap: 22,
    description: `Canadian highway shield (Trans-Canada style)${w > 64 ? ', 3 digits' : ''}`,
  };
}

// Rectangular plates: 44 units high, centred. layers = [{color, inset, r}] outermost first; the last is the field.
function plate(id, w, layers, textColor, description, { cap = 22 } = {}) {
  const y0 = 10, h = 44;
  const body = layers.map(l => `<rect x="${r2(l.inset)}" y="${r2(y0 + l.inset)}" width="${r2(w - 2 * l.inset)}" height="${r2(h - 2 * l.inset)}" rx="${r2(l.r)}" fill="${l.color}"/>`).join('');
  const f = layers[layers.length - 1];
  const fx = f.inset, fy = y0 + f.inset, fw = w - 2 * f.inset, fh = h - 2 * f.inset;
  return {
    id, w, body, kind: 'plate', textColor, fieldColor: f.color, outerColor: layers[0].color, prefixed: true,
    field: { poly: rectPoly(fx, fy, fw, fh), top: fy, bottom: fy + fh }, cx: w / 2, capTop: 32 - cap / 2, cap, description,
  };
}

// Australia national highway: green shield, gold border, NATIONAL lettering, gold number.
const AU_START = [32, 5];
const AU_HALF = [['C', 42, 5, 52, 7, 58, 10], ['L', 58, 32], ['C', 58, 47, 46, 55, 32, 59]];
function ausShield(id, { small = false } = {}) {
  const w = 64, cx = 32;
  const S = fullPath(AU_START, AU_HALF, cx);
  let body = rings(S.d, [{ color: PAL.ausGreenText, width: 5 }, { color: PAL.ausGold, width: 3 }]) + `<path d="${S.d}" fill="${PAL.ausGreenText}"/>`;
  if (!small) body += letters('NATIONAL', cx, 15.5, 5.6, PAL.ausGold, 0.3);
  return {
    id, w, body, kind: 'shield', textColor: PAL.ausGold, fieldColor: PAL.ausGreenText, outerColor: PAL.ausGreenText,
    field: { poly: S.poly, top: small ? 0 : 17.5, bottom: H }, cx, capTop: small ? 19 : 23, cap: 22,
    description: `Australian national highway shield${small ? ', without lettering for heights under 40 px' : ''}`,
  };
}

Object.assign(ALL, {
  canadaHighway: canada('canadaHighway', 64),
  'canadaHighway-wide': canada('canadaHighway-wide', 80),
  // E-road (Vienna Convention E-road sign): green plate, white border just inside a green rim.
  eRoad: plate('eRoad', 80, [{ color: PAL.green, inset: 0, r: 6 }, { color: PAL.white, inset: 2, r: 4 }, { color: PAL.green, inset: 4, r: 2 }], PAL.white, 'European E-road sign'),
  // UK route patches (TSRGD): white border at the edge, small corner radius.
  ukMotorway: plate('ukMotorway', 76, [{ color: PAL.white, inset: 0, r: 3 }, { color: PAL.motorwayBlue, inset: 2, r: 2 }], PAL.white, 'UK motorway route patch'),
  ukARoad: plate('ukARoad', 76, [{ color: PAL.white, inset: 0, r: 3 }, { color: PAL.ukARoadGreen, inset: 2, r: 2 }], PAL.yellow, 'UK primary A-road route patch'),
  // Australia alphanumeric route marker (AS 1742.2): squarer, round corners, gold border.
  australia: plate('australia', 66, [{ color: PAL.ausGreenText, inset: 0, r: 9 }, { color: PAL.ausGold, inset: 2, r: 7 }, { color: PAL.ausGreenText, inset: 4, r: 5 }], PAL.ausGold, 'Australian alphanumeric route marker'),
  'australia-shield': ausShield('australia-shield'),
  'australia-shield-small': ausShield('australia-shield-small', { small: true }),
  // Generic: app palette only (tokens.json): land fill, secondary-text edge, text colour.
  generic: plate('generic', 76, [{ color: PAL.genericEdge, inset: 0, r: 10 }, { color: PAL.genericFill, inset: 2, r: 8 }], PAL.genericText, 'Neutral sign in the app palette'),
});
Object.assign(SAMPLES, {
  canadaHighway: ['1', '17'], 'canadaHighway-wide': ['401'], eRoad: ['E4', 'E40', 'E105'], ukMotorway: ['M1', 'M25', 'A1(M)'],
  ukARoad: ['A1', 'A303'], australia: ['A1', 'M31'], 'australia-shield': ['1', '95'], 'australia-shield-small': ['1', '95'], generic: ['7', 'N7', 'A380'],
});

// network id -> how the app picks a template for a ref
const NETWORKS = {
  usInterstate: { accept: '^[0-9]{1,3}$', wide: 'usInterstate-wide', wideAbove: 2, small: 'usInterstate-small', wideSmall: 'usInterstate-wide-small', smallBelow: 40 },
  usHighway: { accept: '^[0-9]{1,3}$', wide: 'usHighway-wide', wideAbove: 2 },
  canadaHighway: { accept: '^[0-9]{1,3}[A-Z]?$', wide: 'canadaHighway-wide', wideAbove: 2 },
  eRoad: { accept: '^E[0-9]{1,3}$' },
  ukMotorway: { accept: '^(M[0-9]{1,3}|A[0-9]{1,4}\\(M\\))$' },
  ukARoad: { accept: '^A[0-9]{1,4}$' },
  australia: { accept: '^([ABCM][0-9]{1,3}|[0-9]{1,3})$', variants: [{ match: '^[0-9]{1,3}$', template: 'australia-shield', small: 'australia-shield-small', smallBelow: 40 }] },
  generic: { accept: '^[A-Z0-9()-]{1,5}$' },
};

// ---- text layout (the rule the app follows) ---------------------------------------------------------
function layout(t, ref) {
  const size = t.cap / CAP, w = FONT.measure(ref) * size / FONT.unitsPerEm;
  const scale = Math.min(1, t.textBox.width / w);
  const s = size * scale, cap = t.cap * scale, tw = w * scale;
  const capTop = t.textBox.y + (t.textBox.height - cap) / 2; // centred in the box when scaled
  return { size: s, scale, x0: t.cx - tw / 2, x1: t.cx + tw / 2, capTop, baseline: capTop + cap, cap };
}

// ---- contrast ---------------------------------------------------------------------------------------
function lum(hex) {
  const c = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16) / 255).map(v => v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}
const contrast = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };

// ---- build -----------------------------------------------------------------------------------------
const report = [];
for (const t of Object.values(ALL)) {
  const baseline = t.capTop + t.cap;
  const width = fitWidth(t.field, t.cx, t.capTop, baseline);
  t.textBox = { x: r2(t.cx - width / 2) * 1, y: t.capTop, width, height: t.cap };
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${t.w} ${H}" width="${t.w}" height="${H}"><title>RoadPrint road sign: ${t.description}</title>${t.body}</svg>\n`;
  t.svg = svg;
  writeFileSync(join(OUT, `${t.id}.svg`), svg);
  for (const ref of SAMPLES[t.id]) {
    const L = layout(t, ref);
    const c = clearance(t.field, L.x0, L.capTop, L.x1, L.baseline);
    report.push({ id: t.id, ref, scale: +L.scale.toFixed(2), clearance: +c.toFixed(1), cap32: +(L.cap * 32 / H).toFixed(1), cap48: +(L.cap * 48 / H).toFixed(1), ok: c >= MARGIN - 0.05 && L.scale >= MIN_SCALE });
  }
  // 1-unit grid: every coordinate outside the outlined lettering is a whole number
  const offGrid = t.body.replace(/<path id="lettering"[^>]*\/>/g, '').match(/\d+\.\d+/g);
  if (offGrid) { console.error(`${t.id}: off-grid values ${offGrid.slice(0, 6).join(', ')}`); process.exitCode = 1; }
  t.contrast = +contrast(t.textColor, t.fieldColor).toFixed(1);
  t.bytes = Buffer.byteLength(svg);
}
console.table(report);
console.table(Object.values(ALL).map(t => ({ id: t.id, bytes: t.bytes, contrast: t.contrast, textBox: JSON.stringify(t.textBox) })));
if (report.some(r => !r.ok)) { console.error('fit check failed'); process.exitCode = 1; }

// ---- template selection (README "Drawing the number", step 1) and the 32 px legibility bar ---------
/** The template the app draws for `ref` on `network` at a sign height of `px`. */
function pick(network, ref, px) {
  const n = NETWORKS[network];
  if (!new RegExp(n.accept).test(ref)) return 'generic';
  let r = { template: network, ...n };
  for (const v of n.variants ?? []) if (new RegExp(v.match).test(ref)) { r = { accept: n.accept, ...v }; break; }
  const wide = r.wide && ref.length > r.wideAbove;
  if (r.smallBelow && px < r.smallBelow) return (wide ? r.wideSmall : r.small) ?? (wide ? r.wide : r.template);
  return wide ? r.wide : r.template;
}
const NET_SAMPLES = {
  usInterstate: ['5', '80', '405'], usHighway: ['1', '50', '101'], canadaHighway: ['1', '17', '401'], eRoad: ['E4', 'E40', 'E105'],
  ukMotorway: ['M1', 'M25', 'A1(M)'], ukARoad: ['A1', 'A303'], australia: ['A1', 'M31', '1', '95'], generic: ['7', 'N7', 'A380'],
};
const MIN_CAP32 = 11; // board: digits at least 11 px tall when the sign is 32 px high
const picks = [];
for (const [net, refs] of Object.entries(NET_SAMPLES)) for (const ref of refs) {
  const row = { network: net, ref };
  for (const px of [32, 48]) {
    const id = pick(net, ref, px), L = layout(ALL[id], ref);
    row[`template${px}`] = id; row[`cap${px}`] = +(L.cap * px / H).toFixed(1);
  }
  row.ok = row.cap32 >= MIN_CAP32 - 0.05 && (net !== 'australia' || /^[0-9]+$/.test(ref) === row.template32.startsWith('australia-shield'));
  picks.push(row);
}
console.table(picks);
if (picks.some(r => !r.ok)) { console.error('32 px legibility / selection check failed'); process.exitCode = 1; }

// ---- signs.json ------------------------------------------------------------------------------------
const palName = hex => Object.keys(PAL).find(k => PAL[k] === hex);
function maxChars(t) {
  const size = t.cap / CAP, fits = str => FONT.measure(str) * size * MIN_SCALE / FONT.unitsPerEm <= t.textBox.width;
  let n = 1; while (n < 8 && fits((t.prefixed ? 'M' : '') + '8'.repeat(n + (t.prefixed ? 0 : 1)))) n++;
  return n;
}
const json = {
  $schema: './signs.schema.json', version: 1, viewBoxHeight: H,
  font: 'Barlow Condensed', fontWeight: 700, minScale: MIN_SCALE, margin: MARGIN,
  palette: PAL,
  networks: {}, templates: {},
};
for (const [id, n] of Object.entries(NETWORKS)) json.networks[id] = { template: id, ...n };
for (const t of Object.values(ALL)) {
  json.templates[t.id] = {
    file: `${t.id}.svg`, viewBox: [0, 0, t.w, H], description: t.description,
    textBox: t.textBox, textColor: t.textColor, textColorName: palName(t.textColor),
    font: 'Barlow Condensed', fontWeight: 700, fontSize: +(t.cap / CAP).toFixed(2), baseline: +(t.capTop + t.cap).toFixed(2),
    tracking: 0, minScale: MIN_SCALE, maxChars: maxChars(t),
    display: { show: 'ref', uppercase: true },
    outerColor: t.outerColor, samples: SAMPLES[t.id],
  };
}
// a base template shows refs up to wideAbove chars; longer ones go to the wide file
for (const n of Object.values(json.networks)) if (n.wideAbove) json.templates[n.template].maxChars = Math.min(json.templates[n.template].maxChars, n.wideAbove);
writeFileSync(join(OUT, 'signs.json'), JSON.stringify(json, null, 2) + '\n');

// ---- previews --------------------------------------------------------------------------------------
function signWithText(t, ref) {
  const L = layout(t, ref);
  return t.body + `<path d="${FONT.pathData(ref, L.x0, L.baseline, L.size)}" fill="${t.textColor}"/>`;
}
const place = (t, ref, x, y, px) => [`<g transform="translate(${r2(x)} ${r2(y)}) scale(${(px / H).toFixed(4)})">${signWithText(t, ref)}</g>`, t.w * px / H];
const BGS = [['app dark', '#14161c', '#a6aab4'], ['card', '#1d2029', '#a6aab4'], ['Road Atlas paper', '#f3eadb', '#5b5548']];
const SIZES = [96, 48, 32];
const label = (s, x, y, size, color, weight = 600) => `<text x="${x}" y="${y}" font-family="Inter" font-weight="${weight}" font-size="${size}" fill="${color}">${s}</text>`;

function sheet(ids, file, title) {
  const GAP = 12, PAD = 20, LABEL_W = 230, ROW_H = 150, HEAD = 96;
  // column width per background = widest row
  const rowW = id => SIZES.reduce((a, px) => a + SAMPLES[id].length * (ALL[id].w * px / H + GAP) + 18, 0) + PAD;
  const CELL = Math.ceil(Math.max(...ids.map(rowW)) + PAD);
  const W = LABEL_W + CELL * BGS.length, Hh = HEAD + ROW_H * ids.length + 40;
  const o = [`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${Hh}" width="${W}" height="${Hh}"><rect width="${W}" height="${Hh}" fill="#0b0c10"/>`];
  o.push(label(title, 24, 40, 22, '#f0efec', 700));
  BGS.forEach(([name, col, ink], b) => {
    const x0 = LABEL_W + b * CELL;
    o.push(`<rect x="${x0}" y="56" width="${CELL}" height="${Hh - 56}" fill="${col}"/>`);
    o.push(label(`${name} ${col}`, x0 + PAD, 84, 16, ink));
  });
  ids.forEach((id, r) => {
    const y0 = HEAD + r * ROW_H;
    o.push(label(id, 24, y0 + 64, 17, '#f0efec'));
    o.push(label(`cap @32 px: ${Math.min(...report.filter(q => q.id === id).map(q => q.cap32))} px · contrast ${ALL[id].contrast}:1`, 24, y0 + 88, 12, '#a6aab4', 400));
    BGS.forEach(([, , ink], b) => {
      let x = LABEL_W + b * CELL + PAD;
      for (const px of SIZES) {
        o.push(label(`${px}`, x, y0 + 14, 11, ink, 500));
        for (const ref of SAMPLES[id]) { const [g, w] = place(ALL[id], ref, x, y0 + 22 + (100 - px) / 2, px); o.push(g); x += w + GAP; }
        x += 18;
      }
    });
  });
  o.push('</svg>');
  const { png, width, height } = renderSvg(o.join(''));
  writeFileSync(join(OUT, file), png);
  console.log(`${file} ${width}×${height}`);
}

// per-template strip on app dark at 32/48/96
for (const id of Object.keys(ALL)) {
  const t = ALL[id]; let x = 12; const parts = [];
  for (const px of [32, 48, 96]) for (const ref of SAMPLES[id]) { const [g, w] = place(t, ref, x, 12 + (96 - px) / 2, px); parts.push(g); x += w + 16; }
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${Math.ceil(x)} 120" width="${Math.ceil(x)}" height="120"><rect width="100%" height="100%" fill="#14161c"/>${parts.join('')}</svg>`;
  writeFileSync(join(PREV, `${id}.png`), renderSvg(svg).png);
}
sheet(USA, 'contact-sheet-usa.png', 'RoadPrint road signs: USA · samples at 96 / 48 / 32 px');
sheet(Object.keys(ALL), 'contact-sheet.png', 'RoadPrint road signs · samples at 96 / 48 / 32 px');

// usInterstate 80 at 48 pt (96 px @2x) next to the shield in mockup 1 (also @2x). The mockup is a
// raster reference, so this preview embeds it; the templates themselves never contain images.
{
  const mock = readFileSync(join(here, '../../docs/plan/mockups/1-trip-summary.png')).toString('base64');
  const [g] = place(ALL.usInterstate, '80', 196, 34, 96);
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 320 190" width="320" height="190">` +
    `<rect width="320" height="190" fill="#14161c"/><svg x="20" y="22" width="140" height="140" viewBox="730 1050 140 140">` +
    `<image href="data:image/png;base64,${mock}" width="2600" height="2056"/></svg>${g}` +
    label('mockup 1', 52, 178, 12, '#a6aab4', 500) + label('usInterstate · 48 pt', 190, 178, 12, '#a6aab4', 500) + '</svg>';
  writeFileSync(join(PREV, 'usInterstate-vs-mockup.png'), renderSvg(svg).png);
}
writeFileSync(join(PREV, 'checks.json'), JSON.stringify({ fit: report, selection: picks }, null, 2) + '\n');
export { ALL, SAMPLES, layout, PAL, report, pick, picks };
