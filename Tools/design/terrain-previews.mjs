#!/usr/bin/env node
// Terrain card composition previews (ROA-11). Not production code and not a dataset check.
//
// The relief layer comes from terrain_relief.py: real elevation (AWS Terrain Tiles) box-averaged
// to the ADR 0001 2′ grid and drawn as the 160×160 flat-shaded mesh the app will draw. It is a
// real-elevation STYLE preview, not validation of the ETOPO 2022 bundle (ROA-9). Routes: I-80 uses
// the mockup route and elevation profile; Brenner and Nullarbor use OSRM (OSM) road geometry.
// This file adds the type, ribbon, summit and chips. Every visual value comes from Design/tokens.json.
// Output: Design/cards/terrain/previews/*.png at 1080×1920.
//
// Usage: node terrain-previews.mjs [variant ...]   (python3 with numpy, scipy, pillow on PATH)
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
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
  'i80-terrain': { date: 'Wednesday, November 4, 2026', title: ['Salt Lake City', '→ Sacramento'], number: '649', unit: 'Miles', chips: ['10h 52m', '3 states'], sign: { kind: 'interstate', number: '80' }, summit: { kicker: 'Highest recorded point', value: '7,139 ft', name: 'Donner Summit' }, source: 'real I-80 track; 60-mi gap illustrative' },
  'brenner-terrain': { date: 'Saturday, August 15, 2026', title: ['Innsbruck → Bolzano'], number: '118', unit: 'km', chips: ['1h 25m', '2 countries'], sign: { kind: 'e-road', number: 'E45' }, summit: { kicker: 'Highest recorded point', value: '1,372 m', name: 'Brenner Pass' }, source: 'A13/A22 via OSRM (© OSM)' },
  'brenner-terrain-long-labels': { relief: 'brenner-terrain', date: 'Samstag, 15. August 2026', title: ['Innsbruck → Bozen', 'Bolzano (Südtirol)'], number: '118', unit: 'km', chips: ['1 Std. 25 Min.', '2 Länder'], sign: { kind: 'e-road', number: 'E45' }, summit: { kicker: 'Höchster aufgezeichneter Punkt', value: '1.372 m', name: 'Brennerpass / Passo del Brennero' }, source: 'long/localized labels (German)', guides: true },
  'nullarbor-flat': { date: 'Monday, March 2, 2026', title: ['Norseman → Ceduna'], number: '1,197', unit: 'km', chips: ['12h 40m', '2 states'], sign: { kind: 'generic', number: 'A1' }, summit: { kicker: 'Highest recorded point', value: '254 m' }, source: 'flat landscape, Eyre Hwy via OSRM (© OSM)' },
  'i80-altitude-unavailable': { date: 'Wednesday, November 4, 2026', title: ['Salt Lake City', '→ Sacramento'], number: '649', unit: 'Miles', chips: ['10h 52m', '3 states'], sign: { kind: 'interstate', number: '80' }, flat: true, notice: 'Elevation unavailable', source: 'no usable altitude: flat layout, no summit' },
  'i80-hide-route': { hidden: true, date: 'Wednesday, November 4, 2026', title: ['Salt Lake City', '→ Sacramento'], number: '649', unit: 'Miles', chips: ['10h 52m', '3 states', '7,139 ft high'], sign: { kind: 'interstate', number: '80' }, source: 'places and stats only' },
};

const want = process.argv.slice(2);
function card(name) {
  const cd = CARDS[name], top = v(L.reliefTop), fh = v(L.reliefHeight);
  const parts = [`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}"><rect width="${W}" height="${H}" fill="${C.background.$value}"/>`];
  let info = '';
  if (cd.hidden) {
    const bd = readFileSync(new URL('Design/cards/terrain/terrain-backdrop.svg', ROOT), 'utf8').replace(/<\?xml[^>]*>/, '');
    parts.push(`<g transform="translate(0,${top})" opacity="${v(TT.hiddenRoute.backdropOpacity)}">${bd.replace('<svg', `<svg width="${W}" height="${fh}"`)}</g>`);
    info = 'generic backdrop';
  } else {
    const key = cd.relief ?? name, build = new URL(`Tools/design/build/${key}.relief`, ROOT).pathname;
    if (!want.includes('--reuse') || !existsSync(build + '.json'))
      execFileSync('python3', [new URL('Tools/design/terrain_relief.py', ROOT).pathname, key, ...(cd.flat ? ['--flat'] : [])], { stdio: 'inherit' });
    const rel = JSON.parse(readFileSync(build + '.json'));
    rel.pts.forEach(p => { if (p.sy != null) p.sy -= top; });
    parts.push(`<image id="relief" x="0" y="0" width="${W}" height="${H}" href="data:image/png;base64,${readFileSync(build + '.png').toString('base64')}"/>`);
    parts.push(ribbonSvg(rel.pts, top), endpointsSvg(rel.pts, top));
    if (cd.summit && !cd.flat) parts.push(summitSvg(rel.pts, top, cd.summit));
    if (cd.notice) parts.push(`<g id="notice"><rect x="${v(TT.safeArea.side)}" y="${top + fh - 300}" width="${measure('notice', cd.notice) + 56}" height="60" rx="30" fill="${v(TT.chip.fill)}" stroke="${v(TT.chip.stroke)}" stroke-width="2"/>${textEl('notice', cd.notice, v(TT.safeArea.side) + 28, top + fh - 300 + 39)}</g>`);
    info = cd.flat ? 'no relief' : `k=${rel.k.toFixed(1)}× · ${Math.round(rel.gwKm)}×${Math.round(rel.gdKm)} km`;
  }
  parts.push(headerSvg(cd), statsSvg(cd));
  if (cd.guides) parts.push(safeAreaGuides());
  parts.push(stamp([cd.hidden ? 'STYLE PREVIEW · GENERIC BACKDROP, NO TRIP DATA' : 'STYLE PREVIEW · REAL ELEVATION AT 2′, NOT THE ETOPO BUNDLE', `${cd.source} · ${info}`]));
  parts.push('</svg>');
  const { png: out, width, height } = renderSvg(parts.join('\n'));
  writeFileSync(new URL(`${name}.png`, OUT), out);
  console.log(`${name}.png ${width}×${height}  ${info}`);
}

const names = want.filter(n => !n.startsWith('--'));
for (const n of names.length ? names : Object.keys(CARDS)) card(n);
